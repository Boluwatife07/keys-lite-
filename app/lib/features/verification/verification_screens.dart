import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

const kVerifyIntro = 'We need to verify your home address using your bank card. Your card will not be charged. Please ensure that your home address and billing address are exactly the same.';

/// Where the verification flow returns to when it finishes.
void _exitVerification(BuildContext context, String? from) {
  if (from == 'onboarding') {
    context.go('/onboarding/invite');
  } else {
    context.go('/home');
  }
}

/// AVW-08.1: shown when an unverified resident tries a restricted action.
/// Call it when the API answers VERIFICATION_REQUIRED.
Future<void> showVerifySheet(BuildContext context) => showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/images/verify_identification.png', width: 120),
          const SizedBox(height: 12),
          Text('Verify your home address', style: KText.headingSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('In order to perform this action, kindly verify your home address using your bank card. Your card will not be charged.',
              textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          LinkText('How does address verification protect me?', onTap: () {
            Navigator.pop(c);
            context.push('/verify/why');
          }),
          const SizedBox(height: 16),
          KeysButton('Verify', onPressed: () {
            Navigator.pop(c);
            context.push('/verify');
          }),
        ]),
      ),
    );

/// Maps an API error to the verify sheet when needed. Returns true if handled.
bool handleVerificationRequired(BuildContext context, Object e) {
  if (e is ApiException && e.code == 'VERIFICATION_REQUIRED') {
    showVerifySheet(context);
    return true;
  }
  return false;
}

/// AVW-01: choose a method. Under review shows the review screen instead (AVW-05.4).
class VerifyMethodScreen extends StatefulWidget {
  const VerifyMethodScreen({super.key, this.from});
  final String? from;
  @override
  State<VerifyMethodScreen> createState() => _VerifyMethodScreenState();
}

class _VerifyMethodScreenState extends State<VerifyMethodScreen> with Busy {
  Map<String, dynamic>? _state;
  VerifyMethod? _method;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.api.get('/verification');
    if (!mounted) return;
    if (r['status'] == 'under_review') {
      context.pushReplacement('/verify/review', extra: {'case': r['reviewCase'], 'from': widget.from});
      return;
    }
    if (r['status'] == 'verified') {
      context.pushReplacement('/verify/success', extra: widget.from);
      return;
    }
    setState(() => _state = r);
  }

  List<VerifyMethod> get _methods => [
        VerifyMethod.card,
        if (isIOS) VerifyMethod.applePay,
        if (isAndroid) VerifyMethod.googlePay,
      ];

  String _label(VerifyMethod m) => switch (m) {
        VerifyMethod.card => 'Verify with Bank card',
        VerifyMethod.applePay => 'Verify with Apple Pay',
        VerifyMethod.googlePay => 'Verify with Google Pay',
      };

  IconData _icon(VerifyMethod m) => switch (m) {
        VerifyMethod.card => PhosphorIconsRegular.creditCard,
        VerifyMethod.applePay => PhosphorIconsFill.appleLogo,
        VerifyMethod.googlePay => PhosphorIconsBold.googleLogo,
      };

  Future<void> _verify() async {
    final m = _method!;
    if (m == VerifyMethod.card) {
      context.push('/verify/card', extra: {'from': widget.from, 'home': _state!['homeAddress']});
      return;
    }
    final d = context.deps;
    await run(() async {
      final pm = await d.cards.walletPaymentMethod(m);
      if (pm == null) {
        // AVW-03.2: sheet cancelled, back on this screen with no error.
        await d.api.post('/verification/cancelled', {'method': m.api});
        return;
      }
      final r = await d.api.post('/verification/check', {'method': m.api, 'paymentMethodId': pm});
      if (mounted) _showResult(context, r, widget.from);
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeysScaffold(
      header: const KeysHeader(),
      body: _state == null
          ? const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Intro(overline: 'Verify address', title: 'Verify your home address.', body: kVerifyIntro),
              const SizedBox(height: 24),
              for (final m in _methods) ...[
                OptionTile(
                  leading: Icon(_icon(m), color: KColors.textPrimary),
                  title: _label(m),
                  selected: _method == m,
                  onTap: () => setState(() => _method = m),
                ),
                const SizedBox(height: 12),
              ],
              Text('*Ensure this card address is same as your home address. You will not be charged for this action.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              const SizedBox(height: 8),
              LinkText('How does address verification protect me?', onTap: () => context.push('/verify/why')),
            ]),
      // AVW-01.2: inactive until a method is chosen.
      bottom: KeysButton('Verify', loading: busy, onPressed: _method == null ? null : _verify),
    );
  }
}

void _showResult(BuildContext context, Map<String, dynamic> r, String? from) async {
  if (r['result'] == 'pass') {
    await context.session.refresh();
    if (context.mounted) context.pushReplacement('/verify/success', extra: from);
  } else {
    context.pushReplacement('/verify/mismatch', extra: {...r, 'from': from});
  }
}

/// AVW-02: bank card form. Card details go to Stripe on the device; the
/// billing address checked is the Keys home address.
class CardFormScreen extends StatefulWidget {
  const CardFormScreen({super.key, this.from, required this.homeAddress});
  final String? from;
  final String homeAddress;
  @override
  State<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends State<CardFormScreen> with Busy {
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();
  late final _billing = TextEditingController(text: widget.homeAddress);
  final Map<String, String?> _err = {};

  static bool luhn(String n) {
    var sum = 0;
    var alt = false;
    for (var i = n.length - 1; i >= 0; i--) {
      var d = int.parse(n[i]);
      if (alt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      alt = !alt;
    }
    return n.length >= 12 && sum % 10 == 0;
  }

  bool _validate() {
    final n = _number.text.replaceAll(' ', '');
    final exp = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(_expiry.text);
    String? expErr;
    if (exp == null || int.parse(exp[1]!) < 1 || int.parse(exp[1]!) > 12) {
      expErr = 'Enter a valid expiry date';
    } else {
      final now = DateTime.now();
      final end = DateTime(2000 + int.parse(exp[2]!), int.parse(exp[1]!) + 1);
      if (!end.isAfter(now)) expErr = 'This card has expired';
    }
    setState(() {
      _err['number'] = luhn(n) ? null : 'Enter a valid card number';
      _err['expiry'] = expErr;
      _err['cvc'] = RegExp(r'^\d{3,4}$').hasMatch(_cvc.text) ? null : 'Enter a valid CVV';
    });
    return _err.values.every((e) => e == null);
  }

  Future<void> _verify() async {
    if (!_validate()) return;
    final d = context.deps;
    await run(() async {
      final pm = await d.cards.cardPaymentMethod(CardDetails(number: _number.text.replaceAll(' ', ''), expiry: _expiry.text, cvc: _cvc.text));
      final r = await d.api.post('/verification/check', {'method': 'card', 'paymentMethodId': pm});
      if (mounted) _showResult(context, r, widget.from);
    });
  }

  @override
  Widget build(BuildContext context) {
    void changed(_) => setState(() {});
    return KeysScaffold(
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Intro(overline: 'Verify address', title: 'Verify with Bank card'),
        const SizedBox(height: 24),
        KeysTextField(
          label: 'Card number',
          controller: _number,
          hint: '1234 5678 9012 3456',
          keyboardType: TextInputType.number,
          error: _err['number'],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(19), _CardNumberFormatter()],
          onChanged: changed,
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: KeysTextField(label: 'Expiry date', controller: _expiry, hint: 'MM/YY', keyboardType: TextInputType.number, error: _err['expiry'], inputFormatters: [_ExpiryFormatter()], onChanged: changed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KeysTextField(label: 'CVV', controller: _cvc, hint: '123', obscure: true, keyboardType: TextInputType.number, error: _err['cvc'], inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)], onChanged: changed),
          ),
        ]),
        const SizedBox(height: 16),
        KeysTextField(label: 'Billing address', controller: _billing, enabled: false, maxLines: 2),
        const SizedBox(height: 8),
        Text('*Ensure this card is associated with your address.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
      ]),
      bottom: KeysButton('Verify', loading: busy, onPressed: _number.text.isEmpty || _expiry.text.isEmpty || _cvc.text.isEmpty ? null : _verify),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    final digits = n.text.replaceAll(' ', '');
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(digits[i]);
    }
    return TextEditingValue(text: b.toString(), selection: TextSelection.collapsed(offset: b.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    var d = n.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 4) d = d.substring(0, 4);
    final t = d.length > 2 ? '${d.substring(0, 2)}/${d.substring(2)}' : d;
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// AVW-02.3
class VerifySuccessScreen extends StatelessWidget {
  const VerifySuccessScreen({super.key, this.from});
  final String? from;
  @override
  Widget build(BuildContext context) => KeysScaffold(
        body: Column(children: [
          const SizedBox(height: 120),
          const CircleAvatar(radius: 40, backgroundColor: KColors.success, child: Icon(PhosphorIconsRegular.check, color: Colors.white, size: 44)),
          const SizedBox(height: 24),
          const Intro(center: true, title: 'Successful', body: 'Congratulations, your account has been verified.'),
        ]),
        bottom: KeysButton('Continue', onPressed: () => _exitVerification(context, from)),
      );
}

/// AVW-04: the check failed. Try again or contest.
class VerifyMismatchScreen extends StatelessWidget {
  const VerifyMismatchScreen({super.key, required this.result});
  final Map<String, dynamic> result;

  String get _method {
    final brand = (result['brand'] as String? ?? 'card');
    final b = brand.isEmpty ? 'Card' : brand[0].toUpperCase() + brand.substring(1);
    final via = switch (result['method']) { 'apple_pay' => ' (Apple Pay)', 'google_pay' => ' (Google Pay)', _ => '' };
    return '$b •••• ${result['last4']}$via';
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value, style: KText.paragraphMediumLarge),
          ]),
        );
    return KeysScaffold(
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: CircleAvatar(radius: 32, backgroundColor: Color(0xFFFDECEA), child: Icon(PhosphorIconsRegular.x, color: KColors.error, size: 36))),
        const SizedBox(height: 20),
        const Intro(center: true, title: "We couldn't verify your address", body: 'The address linked to your card does not match your home address on Keys.'),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            row('Method used', _method),
            const Divider(height: 1, color: KColors.borderDefault),
            row('Address on Keys', result['homeAddress'] ?? ''),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Contesting this decision will send your case to Keys for manual review. Your account will remain unverified during this time.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
      ]),
      bottom: ButtonStack([
        KeysButton('Try again', onPressed: () => context.pushReplacement('/verify', extra: result['from'])),
        KeysButton('Contest this decision', variant: ButtonVariant.secondary, onPressed: () => context.pushReplacement('/verify/contest', extra: result['from'])),
      ]),
    );
  }
}

/// AVW-05: upload a supporting document for manual review.
class ContestScreen extends StatefulWidget {
  const ContestScreen({super.key, this.from});
  final String? from;
  @override
  State<ContestScreen> createState() => _ContestScreenState();
}

class _ContestScreenState extends State<ContestScreen> with Busy {
  static const maxBytes = 10 * 1024 * 1024; // design: "up to 10MB" (AVW-Q4 decided)
  static const docs = ['Utility bill', 'Bank statement', 'Council tax letter', 'Tenancy agreement', 'Government-issued letter'];
  PickedFile? _file;
  String? _error;

  Future<void> _pick() async {
    final f = await context.deps.media.pickDocument();
    if (f == null) return;
    if (!['application/pdf', 'image/jpeg', 'image/png'].contains(f.mime)) return setState(() => _error = 'Please upload a PDF, JPG or PNG file.');
    if (f.size > maxBytes) return setState(() => _error = 'The file you selected is too large. Please choose a file of 10 MB or less.');
    setState(() {
      _file = f;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final session = context.session;
    await run(() async {
      final r = await session.api.upload('/verification/contest', bytes: _file!.bytes, filename: _file!.name, mime: _file!.mime);
      await session.refresh();
      if (mounted) context.pushReplacement('/verify/review', extra: {'case': r['reviewCase'], 'from': widget.from});
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong.'));
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        header: const KeysHeader(),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(
            overline: 'Contest decision',
            title: 'Upload a supporting document',
            body: 'Provide a government or utility document displaying your full name and current residential address as registered with Keys.',
          ),
          const SizedBox(height: 20),
          Text('Accepted documents', style: KText.paragraphMediumLarge),
          const SizedBox(height: 8),
          for (final d in docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [const Icon(PhosphorIconsRegular.check, size: 16, color: KColors.success), const SizedBox(width: 8), Text(d, style: KText.paragraphMedium)]),
            ),
          const SizedBox(height: 4),
          Text('* Documents must be dated within the last 3 months, except tenancy agreements.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 20),
          InkWell(
            onTap: _pick,
            borderRadius: BorderRadius.circular(KRadius.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: _error != null ? KColors.error : KColors.borderDefault)),
              child: _file == null
                  ? Column(children: [
                      const Icon(PhosphorIconsRegular.fileArrowUp, size: 32),
                      const SizedBox(height: 8),
                      Text('Tap to upload document', style: KText.paragraphMediumLarge),
                      Text('Supports PDF, JPG, PNG up to 10MB', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                    ])
                  : Row(children: [
                      const Icon(PhosphorIconsRegular.fileText),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_file!.name, style: KText.paragraphMediumLarge, overflow: TextOverflow.ellipsis)),
                      Text('${(_file!.size / 1024 / 1024).toStringAsFixed(1)} MB', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                    ]),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorLine(_error!)),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(PhosphorIconsRegular.lock, size: 14, color: KColors.textSecondary),
            const SizedBox(width: 6),
            Text('Your documents are encrypted and securely stored.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          ]),
        ]),
        bottom: KeysButton('Submit for review', loading: busy, onPressed: _file == null ? null : _submit),
      );
}

/// AVW-05.3 / AVW-05.4: documents under review.
class UnderReviewScreen extends StatelessWidget {
  const UnderReviewScreen({super.key, required this.reviewCase, this.from});
  final Map<String, dynamic> reviewCase;
  final String? from;
  @override
  Widget build(BuildContext context) {
    final submitted = DateTime.tryParse(reviewCase['submittedAt'] ?? '')?.toLocal();
    return KeysScaffold(
      header: KeysHeader(onBack: () => _exitVerification(context, from)),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Intro(overline: 'Verify address', title: 'Your documents are under review'),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Submitted Document', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 4),
            Row(children: [const Icon(PhosphorIconsRegular.fileText, size: 20), const SizedBox(width: 8), Expanded(child: Text(reviewCase['documentName'] ?? '', style: KText.paragraphMediumLarge))]),
            if (submitted != null) ...[const SizedBox(height: 4), Text('Submitted ${DateFormat('d MMM yyyy').format(submitted)}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))],
            const Divider(height: 28, color: KColors.borderDefault),
            Row(children: [
              const Icon(PhosphorIconsRegular.hourglassHigh, size: 18, color: KColors.progressStart),
              const SizedBox(width: 8),
              Expanded(child: Text('Keys review in progress', style: KText.paragraphMediumLarge.copyWith(fontSize: 14))),
              Text(reviewCase['estimate'] ?? 'Est. 1-2 business days', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ]),
            const SizedBox(height: 12),
            Text('Ref: ${reviewCase['ref']}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          ]),
        ),
        const SizedBox(height: 12),
        Text("We'll email you when the review is complete. Your account stays unverified until then.", style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
      ]),
      bottom: KeysButton('Close', onPressed: () => _exitVerification(context, from)),
    );
  }
}

/// AVW-07: why verification matters.
class VerifyExplainerScreen extends StatelessWidget {
  const VerifyExplainerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: KText.headingXSmall),
            const SizedBox(height: 6),
            Text(body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          ]),
        );
    return KeysScaffold(
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How does address verification protect me and my community?', style: KText.headingSmall),
        const SizedBox(height: 12),
        Text(
          'Address verification is a simple, one-time step that creates a secure, members-only environment based on trust, allowing residents to connect and strengthen their community. Here’s how this benefits you and your community:',
          style: KText.paragraphMedium.copyWith(color: KColors.textSecondary),
        ),
        section('Genuine Connections',
            'Verification ensures that every profile belongs to a legitimate resident, keeping out outsiders and fake accounts from your neighborhood spaces, clubs, and events. This means you’ll interact with real neighbors, not strangers pretending to be part of your community.'),
        section('Security and safety', 'By confirming where members live, we significantly reduce impersonation and fraud, keeping your local discussions, interactions, services, and projects safe from malicious actors.'),
        section('Community Trust', 'When everyone is verified, it encourages collaboration on projects, sharing recommendations, and builds confidence in meeting others in your development.'),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
          child: Text('Note: Your payment information is only used for address verification. We don’t charge your card or store your payment details.', style: KText.paragraphSmall),
        ),
      ]),
    );
  }
}
