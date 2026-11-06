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

class _VerifyMethodScreenState extends State<VerifyMethodScreen> with Busy, _CardForm {
  Map<String, dynamic>? _state;
  VerifyMethod? _method;
  @override
  String get homeAddress => _state?['homeAddress'] ?? '';
  @override
  String? get from => widget.from;

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


  Future<void> _verify() async {
    final m = _method!;
    if (m == VerifyMethod.card) return _verifyCard();
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

  Widget _mark(VerifyMethod m) => switch (m) {
        VerifyMethod.card => Icon(PhosphorIconsFill.creditCard, size: 32, color: KColors.textPrimary),
        VerifyMethod.applePay => PathMark.applePay(),
        VerifyMethod.googlePay => PathMark.googlePay(),
      };

  Widget _cell(VerifyMethod m) => Semantics(
        button: true,
        selected: _method == m,
        label: _label(m),
        child: Material(
          color: KColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _method = m),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: SizedBox(
                height: 40,
                child: Row(children: [
                  KRadio(selected: _method == m),
                  const SizedBox(width: 12),
                  Expanded(child: ExcludeSemantics(child: Text(_label(m), style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500)))),
                  const SizedBox(width: 12),
                  _mark(m),
                ]),
              ),
            ),
          ),
        ),
      );

  // Figma 1300:186350: card number, expiry + CVV, read-only billing address.
  Widget _cardForm() {
    void changed(_) => setState(() {});
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KeysTextField(
          label: 'Card number',
          controller: _number,
          hint: '1234 5678 9012 3456',
          prefixIcon: PhosphorIconsRegular.creditCard,
          keyboardType: TextInputType.number,
          error: _err['number'],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(19), _CardNumberFormatter()],
          onChanged: changed,
        ),
        const SizedBox(height: 32),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: KeysTextField(label: 'Expiry date', controller: _expiry, hint: 'MM/YY', keyboardType: TextInputType.number, error: _err['expiry'], inputFormatters: [_ExpiryFormatter()], onChanged: changed)),
          const SizedBox(width: 16),
          Expanded(child: KeysTextField(label: 'CVV', controller: _cvc, hint: '123', keyboardType: TextInputType.number, error: _err['cvc'], inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)], onChanged: changed)),
        ]),
        const SizedBox(height: 32),
        SizedBox(height: 20, child: OverflowBox(maxHeight: 24, alignment: Alignment.bottomLeft, child: Text('Billing address', style: KText.paragraphMediumLarge))),
        const SizedBox(height: 8),
        // AVW-02: the billing address checked is the Keys home address.
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 144),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            color: KColors.surfaceDefault,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KColors.palette.brightness == Brightness.dark ? KColors.borderDefault : const Color(0xFFDDDDDD), width: 2),
          ),
          child: Text(homeAddress.split(RegExp(r',\s*')).join('\n'), style: KText.paragraphLarge),
        ),
        const SizedBox(height: 12),
        Text('*Ensure this card is associated with your address.', style: KText.paragraphSmall),
      ]),
    );
  }

  void _close() => Navigator.of(context).canPop() ? context.pop() : _exitVerification(context, widget.from);

  // Figma 1300:186409 / 186244 / 186350: a sheet over the page that opened it.
  @override
  Widget build(BuildContext context) {
    final st = _state;
    final ready = _method != null && (_method != VerifyMethod.card || _cardFilled);
    return KeysSheetPage(
      title: 'Verify address',
      onClose: _close,
      bottom: KeysButton('Verify', loading: busy, onPressed: ready ? _verify : null),
      child: st == null
          ? const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('*Ensure this card address is same as your home address.You will not be charged for this action.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              const SizedBox(height: 16),
              for (final m in _methods) ...[
                _cell(m),
                if (m == VerifyMethod.card && _method == VerifyMethod.card) _cardForm(),
                const SizedBox(height: 12),
              ],
            ]),
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

/// Card number, expiry and CVV checks shared by the sheet and the card page.
mixin _CardForm<T extends StatefulWidget> on State<T>, Busy<T> {
  String get homeAddress;
  String? get from;
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();
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

  bool get _cardFilled => _number.text.isNotEmpty && _expiry.text.isNotEmpty && _cvc.text.isNotEmpty;

  Future<void> _verifyCard() async {
    if (!_validate()) return;
    final d = context.deps;
    await run(() async {
      final pm = await d.cards.cardPaymentMethod(CardDetails(number: _number.text.replaceAll(' ', ''), expiry: _expiry.text, cvc: _cvc.text));
      final r = await d.api.post('/verification/check', {'method': 'card', 'paymentMethodId': pm});
      if (mounted) _showResult(context, r, from);
    });
  }
}

class _CardFormScreenState extends State<CardFormScreen> with Busy, _CardForm {
  @override
  String get homeAddress => widget.homeAddress;
  @override
  String? get from => widget.from;
  late final _billing = TextEditingController(text: widget.homeAddress);

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
      bottom: KeysButton('Verify', loading: busy, onPressed: _cardFilled ? _verifyCard : null),
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
  // Figma 1300:186332.
  @override
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        fill: true,
        header: KeysHeader(onBack: () => _exitVerification(context, from)),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('YOU’RE ALMOST DONE', style: KText.overline),
          const SizedBox(height: 12),
          Text('Verify your home address.', style: KText.headingSmall),
          const SizedBox(height: 36),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SuccessMark(),
                const SizedBox(height: 28),
                Text('Successful', textAlign: TextAlign.center, style: KText.headingSmall),
                const SizedBox(height: 8),
                Text('Congratulations, your account\nhas been verified.', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              ]),
            ),
          ),
        ]),
        bottom: KeysButton('Proceed', onPressed: () => _exitVerification(context, from)),
      );
}

/// AVW-04: the check failed. Try again or contest.
class VerifyMismatchScreen extends StatelessWidget {
  const VerifyMismatchScreen({super.key, required this.result});
  final Map<String, dynamic> result;


  String get _card {
    final brand = (result['brand'] as String? ?? 'card');
    final b = brand.isEmpty ? 'Card' : brand[0].toUpperCase() + brand.substring(1);
    return '$b •••• ${result['last4']}';
  }

  // Figma 1768:17781: a sheet with the failed mark and what was compared.
  @override
  Widget build(BuildContext context) {
    final label = KText.paragraphSmall.copyWith(fontWeight: FontWeight.w500, height: 1, color: KColors.textSecondary);
    final wallet = switch (result['method']) { 'apple_pay' => PathMark.applePay(), 'google_pay' => PathMark.googlePay(), _ => null };
    return KeysSheetPage(
      onClose: () => _exitVerification(context, result['from']),
      contentPadding: const EdgeInsets.all(20),
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        KeysButton('Contest this decision', onPressed: () => context.pushReplacement('/verify/contest', extra: result['from'])),
        const SizedBox(height: 12),
        KeysButton('Try again', variant: ButtonVariant.secondary, onPressed: () => context.pushReplacement('/verify', extra: result['from'])),
        const SizedBox(height: 12),
        Text('Contesting this decision will send your case to Keys for manual review. Your account will remain unverified during this time.',
            textAlign: TextAlign.center, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
      ]),
      child: Column(children: [
        const FailMark(),
        const SizedBox(height: 28),
        Text("We couldn't verify your address", textAlign: TextAlign.center, style: KText.headingSmall),
        const SizedBox(height: 8),
        Text('The address associated with your payment method does not match the address on your Keys account.', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Method used', style: label),
            const SizedBox(height: 8),
            Row(children: [if (wallet != null) ...[wallet, const SizedBox(width: 8)], Expanded(child: Text(_card, style: KText.paragraphLarge))]),
            Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Container(height: 1, color: KColors.borderDefault)),
            Text('Address on Keys', style: label),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(PhosphorIconsRegular.houseLine, size: 20, color: KColors.iconDefault)),
              const SizedBox(width: 8),
              Expanded(child: Text(result['homeAddress'] ?? '', style: KText.paragraphLarge)),
            ]),
          ]),
        ),
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

  // Figma 1768:17890 (empty) and 1768:17930 (file chosen).
  @override
  Widget build(BuildContext context) => KeysScaffold(
        header: const KeysHeader(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(
            small: true,
            overline: 'Contest verification',
            title: 'Upload a supporting document',
            body: 'Provide a government or utility document displaying your full name and current residential address as registered with Keys.',
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(16), border: Border.all(color: KColors.borderDefault)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Accepted documents', style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500, color: KColors.textSecondary)),
              const SizedBox(height: 12),
              for (final d in docs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [Icon(PhosphorIconsFill.checkCircle, size: 20, color: const Color(0xFF008080)), const SizedBox(width: 8), Text(d, style: KText.paragraphMedium)]),
                ),
              const SizedBox(height: 8),
              Text('* Documents must be dated within the last 3 months, except tenancy agreements.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ]),
          ),
          const SizedBox(height: 20),
          Material(
            color: KColors.surfaceDefault,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(16),
              child: DashedBox(
                color: _error != null ? KColors.error : KColors.textSecondary,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  child: _file == null
                      ? Column(children: [
                          Icon(PhosphorIconsRegular.cloudArrowUp, size: 32, color: KColors.textSecondary),
                          const SizedBox(height: 8),
                          Text('Tap to upload document', style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('Supports PDF, JPG, PNG up to 10MB', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                        ])
                      : Row(children: [
                          Icon(PhosphorIconsRegular.fileText, color: KColors.iconDefault),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_file!.name, style: KText.paragraphMediumLarge, overflow: TextOverflow.ellipsis)),
                          Text('${(_file!.size / 1024 / 1024).toStringAsFixed(1)} MB', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                        ]),
                ),
              ),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: FieldHint(_error!)),
        ]),
        bottom: Column(mainAxisSize: MainAxisSize.min, children: [
          KeysButton('Submit for review', loading: busy, onPressed: _file == null ? null : _submit),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(PhosphorIconsRegular.lock, size: 16, color: KColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(child: Text('Your documents are encrypted and securely stored.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
          ]),
          const SizedBox(height: 8),
        ]),
      );
}

/// AVW-05.3 / AVW-05.4: documents under review.
class UnderReviewScreen extends StatelessWidget {
  const UnderReviewScreen({super.key, required this.reviewCase, this.from});
  final Map<String, dynamic> reviewCase;
  final String? from;

  // Figma 1768:17827: a full-height card over the page with a 3-step timeline.
  @override
  Widget build(BuildContext context) {
    final submitted = DateTime.tryParse(reviewCase['submittedAt'] ?? '')?.toLocal();
    final small = KText.paragraphSmall.copyWith(color: KColors.textSecondary);
    void close() => _exitVerification(context, from);
    Widget step(Widget icon, String title, String? sub) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: SizedBox.square(dimension: 20, child: icon)),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500)),
                if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: small)],
              ]),
            ),
          ),
        ]);
    Widget line(Color c) => Padding(padding: const EdgeInsets.only(left: 9.5), child: Container(width: 1, height: 8, color: c));
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Container(
                height: 56,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.borderDefault))),
                child: Row(children: [
                  Semantics(button: true, label: 'Close', child: InkResponse(radius: 20, onTap: close, child: SizedBox.square(dimension: 40, child: Icon(PhosphorIconsRegular.x, size: 22, color: KColors.iconDefault)))),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(color: KColors.brandSubtle, shape: BoxShape.circle),
                      child: Icon(PhosphorIconsRegular.clockCountdown, size: 80, color: KColors.textPrimary),
                    ),
                    const SizedBox(height: 28),
                    Text('Your documents are under review', textAlign: TextAlign.center, style: KText.headingSmall),
                    const SizedBox(height: 12),
                    Text('Keys will review your documents within 2 business days and notify you of the outcome via mail.',
                        textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: KColors.borderDefault, width: 1.5)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        step(const Icon(PhosphorIconsFill.checkCircle, size: 20, color: Color(0xFF008080)), 'Document submitted', submitted == null ? null : DateFormat('d MMMM, y').format(submitted)),
                        line(const Color(0xFF008080)),
                        step(Icon(PhosphorIconsRegular.clockCountdown, size: 20, color: KColors.textPrimary), 'Keys review in progress', reviewCase['estimate'] ?? 'Est. 1-2 business days'),
                        line(KColors.iconDisabled),
                        step(Icon(PhosphorIconsRegular.circle, size: 20, color: KColors.iconDisabled), 'Outcome notification', null),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    Align(alignment: Alignment.centerLeft, child: Text('Submitted Document', style: small)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: KColors.surfaceSubtle, shape: BoxShape.circle),
                          child: const Icon(PhosphorIconsFill.filePdf, size: 24, color: Color(0xFFDE1135)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(reviewCase['documentName'] ?? '', style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text([if ((reviewCase['documentName'] ?? '').toString().toLowerCase().endsWith('.pdf')) 'PDF Document', 'Ref: ${reviewCase['ref']}'].join('  •  '), style: small),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 20), child: KeysButton('Close', onPressed: close)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// AVW-07: why verification matters.
class VerifyExplainerScreen extends StatelessWidget {
  const VerifyExplainerScreen({super.key});
  // Figma 3173:176333: hero illustration, then three illustrated sections.
  @override
  Widget build(BuildContext context) {
    final body = KText.paragraphLarge;
    Widget section(String image, String title, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipOval(child: Image.asset(image, width: 125, height: 125, fit: BoxFit.cover)),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, height: 28 / 20, color: KColors.textPrimary)),
            const SizedBox(height: 8),
            Text(text, style: body),
          ]),
        );
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      padding: EdgeInsets.zero,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.asset('assets/images/verify_hero.jpg', width: double.infinity, height: 320, fit: BoxFit.cover),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How does address verification protect me and my community?', style: KText.headingSmall),
            const SizedBox(height: 24),
            Text(
              'Address verification is a simple, one-time step that creates a secure, members-only environment based on trust, allowing residents to connect and strengthen their community. Here’s how this benefits you and your community:',
              style: body,
            ),
            const SizedBox(height: 24),
            section('assets/images/verify_benefit_1.png', 'Genuine Connections',
                'Verification ensures that every profile belongs to a legitimate resident, keeping out outsiders and fake accounts from your neighborhood spaces, clubs, and events. This means you’ll interact with real neighbors, not strangers pretending to be part of your community.'),
            const SizedBox(height: 24),
            section('assets/images/verify_benefit_2.png', 'Security and safety',
                'By confirming where members live, we significantly reduce impersonation and fraud, keeping your local discussions, interactions, services, and projects safe from malicious actors.'),
            const SizedBox(height: 24),
            section('assets/images/verify_benefit_3.png', 'Community Trust',
                'When everyone is verified, it encourages collaboration on projects, sharing recommendations, and builds confidence in meeting others in your development.'),
            const SizedBox(height: 24),
            Text('Note: Your payment information is only used for address verification. We don’t charge your card or store your payment details.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}
