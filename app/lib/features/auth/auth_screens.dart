import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/flow.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

Future<void> openLegal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

/// ONB-05 / ONB-06: email entry and social sign-in.
class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});
  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> with Busy {
  final _email = TextEditingController();
  String? _error;

  Future<void> _continue() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() => _error = null);
    await run(() async {
      final r = await context.api.post('/auth/email/start', {'email': email});
      if (!mounted) return;
      if (r['status'] == 'existing') {
        context.push('/auth/password', extra: {'email': email, 'firstName': r['firstName']});
      } else {
        context.push('/auth/verify', extra: {'email': email, 'purpose': 'signup'});
      }
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong.'));
  }

  Future<void> _social(SocialProvider p) async {
    final d = context.deps;
    await run(() async {
      final res = await d.social.signIn(p);
      if (res == null) return; // ONB-06.4: cancelled, stay here with no error
      final r = await d.api.post('/auth/social', {'provider': p.name, 'idToken': res.idToken, 'firstName': res.firstName, 'lastName': res.lastName});
      await d.session.signIn(r['token']);
      if (mounted) await goToCurrentStep(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = KText.paragraphSmall.copyWith(color: KColors.textLink);
    return KeysScaffold(
      header: const _LogoNav(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        const Intro(
          title: 'Get closer with your neighbourhood.',
          body: 'Connect with your neighbours, access local services, manage your clubs and events all in one place. Enter your email to get started.',
        ),
        const SizedBox(height: 28),
        KeysTextField(
          label: 'Email address',
          controller: _email,
          hint: 'name@example.com',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          error: _error,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 28),
        // ONB-05.1: inactive until an email is typed.
        KeysButton('Continue', loading: busy, onPressed: _email.text.trim().isEmpty ? null : _continue),
        const SizedBox(height: 32),
        Row(children: [
          const Expanded(child: Divider(color: KColors.borderDefault)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: KText.paragraphMediumSmall)),
          const Expanded(child: Divider(color: KColors.borderDefault)),
        ]),
        const SizedBox(height: 32),
        KeysButton('Continue with Apple', variant: ButtonVariant.outline, icon: const Icon(PhosphorIconsFill.appleLogo, size: 24, color: KColors.textPrimary), onPressed: busy ? null : () => _social(SocialProvider.apple)),
        const SizedBox(height: 16),
        KeysButton('Continue with Google', variant: ButtonVariant.outline, icon: const GoogleMark(), onPressed: busy ? null : () => _social(SocialProvider.google)),
        const SizedBox(height: 32),
        // ONB-05.5: consent line with links to the current documents.
        Center(
          child: Text.rich(
            TextSpan(style: KText.paragraphSmall, children: [
              const TextSpan(text: 'By continuing you agree to our '),
              TextSpan(text: 'Terms of Use', style: linkStyle, recognizer: TapGestureRecognizer()..onTap = () => openLegal(AppConfig.termsUrl)),
              const TextSpan(text: ' and '),
              TextSpan(text: 'Privacy Policy', style: linkStyle, recognizer: TapGestureRecognizer()..onTap = () => openLegal(AppConfig.privacyUrl)),
            ]),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

class _LogoNav extends StatelessWidget {
  const _LogoNav();
  @override
  Widget build(BuildContext context) => Container(
        height: 60,
        alignment: Alignment.center,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: KColors.borderDefault))),
        child: const KeysLogo(height: 28),
      );
}

/// ONB-07 (sign-up) and ONB-10.2 (password reset): six-digit code with a
/// 60-second resend timer.
class VerifyCodeScreen extends StatefulWidget {
  const VerifyCodeScreen({super.key, required this.email, required this.purpose});
  final String email;
  final String purpose; // signup | reset
  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> with Busy {
  final _code = TextEditingController();
  String? _error;
  int _left = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) t.cancel();
      if (mounted) setState(() => _left = _left - 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify(String code) async {
    await run(() async {
      final path = widget.purpose == 'signup' ? '/auth/email/verify' : '/auth/password/verify';
      final r = await context.api.post(path, {'email': widget.email, 'code': code});
      if (!mounted) return;
      if (widget.purpose == 'signup') {
        context.pushReplacement('/auth/details', extra: {'ticket': r['ticket']});
      } else {
        context.pushReplacement('/auth/forgot/new', extra: {'ticket': r['ticket']});
      }
    }, onError: (e) {
      // ONB-07.4: show the error and clear the boxes.
      _code.clear();
      setState(() => _error = e is ApiException ? e.message : 'Something went wrong.');
    });
  }

  Future<void> _resend() async {
    await run(() async {
      await context.api.post('/auth/code/resend', {'email': widget.email, 'purpose': widget.purpose});
      _code.clear();
      setState(() => _error = null);
      _startTimer();
      if (mounted) showToast(context, 'A new code has been sent');
    });
  }

  @override
  Widget build(BuildContext context) {
    final signup = widget.purpose == 'signup';
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(signup ? 'Verify email address' : 'Check your email', style: KText.headingSmall),
        const SizedBox(height: 12),
        Text('Enter the 6-digit verification code sent to', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
        Text(widget.email, style: KText.paragraphMedium),
        const SizedBox(height: 32),
        CodeInput(controller: _code, error: _error, onCompleted: _verify),
        const SizedBox(height: 20),
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text("Didn't receive a code?  ", style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            _left > 0
                ? Text('Resend code in ${_left}s', style: KText.paragraphMedium)
                : LinkText('Resend code', onTap: busy ? null : _resend),
          ]),
        ),
        const SizedBox(height: 28),
        ValueListenableBuilder(
          valueListenable: _code,
          builder: (_, v, _) => KeysButton('Continue', loading: busy, onPressed: v.text.length == 6 ? () => _verify(v.text) : null),
        ),
      ]),
    );
  }
}

/// ONB-08: legal name and password.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, required this.ticket});
  final String ticket;
  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> with Busy {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final Map<String, String?> _errors = {};

  bool get _valid => _first.text.trim().isNotEmpty && _last.text.trim().isNotEmpty && PasswordRules.ok(_pw.text) && _pw2.text.isNotEmpty;

  Future<void> _submit() async {
    final e = <String, String?>{
      'firstName': _first.text.trim().isEmpty ? 'Add a first name' : null,
      'lastName': _last.text.trim().isEmpty ? 'Add a last name' : null,
      'confirmPassword': _pw.text != _pw2.text ? 'Passwords do not match' : null,
    };
    setState(() => _errors
      ..clear()
      ..addAll(e));
    if (e.values.any((v) => v != null) || !PasswordRules.ok(_pw.text)) return;
    final d = context.deps;
    await run(() async {
      final r = await d.api.post('/auth/signup', {
        'ticket': widget.ticket,
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'password': _pw.text,
        'confirmPassword': _pw2.text,
      });
      await d.session.signIn(r['token']);
      if (mounted) await goToCurrentStep(context);
    }, onError: (err) {
      if (err is ApiException && err.field != null) {
        setState(() => _errors[err.field!] = err.message);
      } else {
        showToast(context, err is ApiException ? err.message : 'Something went wrong.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    void changed(_) => setState(() {});
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Intro(overline: 'Account setup', title: "Let's get to know you", body: 'Use your legal name. It is shown to your neighbours and cannot be changed later.'),
        const SizedBox(height: 24),
        KeysTextField(label: 'First name', controller: _first, textCapitalization: TextCapitalization.words, error: _errors['firstName'], onChanged: changed, autofillHints: const [AutofillHints.givenName]),
        const SizedBox(height: 16),
        KeysTextField(label: 'Last name', controller: _last, textCapitalization: TextCapitalization.words, error: _errors['lastName'], onChanged: changed, autofillHints: const [AutofillHints.familyName]),
        const SizedBox(height: 16),
        KeysTextField(label: 'Password', controller: _pw, obscure: true, onChanged: changed, autofillHints: const [AutofillHints.newPassword]),
        PasswordRules(password: _pw.text),
        const SizedBox(height: 16),
        KeysTextField(label: 'Confirm password', controller: _pw2, obscure: true, error: _errors['confirmPassword'], onChanged: changed),
      ]),
      bottom: KeysButton('Continue', loading: busy, onPressed: _valid ? _submit : null),
    );
  }
}

/// ONB-09: "Welcome, [first name]" password login.
class PasswordLoginScreen extends StatefulWidget {
  const PasswordLoginScreen({super.key, required this.email, required this.firstName});
  final String email;
  final String firstName;
  @override
  State<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<PasswordLoginScreen> with Busy {
  final _pw = TextEditingController();
  String? _error;

  Future<void> _login() async {
    final d = context.deps;
    await run(() async {
      final r = await d.api.post('/auth/login', {'email': widget.email, 'password': _pw.text});
      await d.session.signIn(r['token']);
      if (!mounted) return;
      if (r['reactivated'] == true) showToast(context, 'Welcome back. Your account has been reactivated.');
      await goToCurrentStep(context);
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong.'));
  }

  @override
  Widget build(BuildContext context) {
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Welcome, ${widget.firstName}', style: KText.headingSmall),
        const SizedBox(height: 8),
        Text.rich(TextSpan(style: KText.paragraphMedium.copyWith(color: KColors.textSecondary), children: [
          const TextSpan(text: 'Signing in as '),
          TextSpan(text: widget.email, style: KText.paragraphMedium),
        ])),
        const SizedBox(height: 24),
        KeysTextField(label: 'Password', controller: _pw, obscure: true, error: _error, autofocus: true, onChanged: (_) => setState(() => _error = null), autofillHints: const [AutofillHints.password]),
        Align(
          alignment: Alignment.centerRight,
          child: LinkText('Forgot password?', onTap: () => context.push('/auth/forgot', extra: {'email': widget.email})),
        ),
        const SizedBox(height: 16),
        KeysButton('Log in', loading: busy, onPressed: _pw.text.isEmpty ? null : _login),
      ]),
    );
  }
}

/// ONB-10.1
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email});
  final String? email;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> with Busy {
  late final _email = TextEditingController(text: widget.email);
  String? _error;

  Future<void> _send() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) return setState(() => _error = 'Enter a valid email address');
    await run(() async {
      await context.api.post('/auth/password/forgot', {'email': email});
      if (mounted) context.push('/auth/verify', extra: {'email': email, 'purpose': 'reset'});
    });
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        header: const KeysHeader(),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(title: 'Forgot your password?', body: "No worries. Enter your email below and we'll send you a code to reset your password"),
          const SizedBox(height: 24),
          KeysTextField(label: 'Email address', controller: _email, keyboardType: TextInputType.emailAddress, error: _error, onChanged: (_) => setState(() => _error = null)),
          const SizedBox(height: 24),
          KeysButton('Send reset code', loading: busy, onPressed: _email.text.trim().isEmpty ? null : _send),
        ]),
      );
}

/// ONB-10.3 / ONB-10.4
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.ticket});
  final String ticket;
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> with Busy {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _error;

  Future<void> _reset() async {
    if (_pw.text != _pw2.text) return setState(() => _error = 'Passwords do not match');
    await run(() async {
      await context.api.post('/auth/password/reset', {'ticket': widget.ticket, 'password': _pw.text, 'confirmPassword': _pw2.text});
      if (mounted) context.go('/auth/forgot/done');
    });
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        header: const KeysHeader(),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(title: 'Set a new password', body: 'Enter your new password'),
          const SizedBox(height: 24),
          KeysTextField(label: 'New password', controller: _pw, obscure: true, onChanged: (_) => setState(() {})),
          PasswordRules(password: _pw.text),
          const SizedBox(height: 16),
          KeysTextField(label: 'Confirm new password', controller: _pw2, obscure: true, error: _error, onChanged: (_) => setState(() => _error = null)),
        ]),
        bottom: KeysButton('Reset password', loading: busy, onPressed: PasswordRules.ok(_pw.text) && _pw2.text.isNotEmpty ? _reset : null),
      );
}

class PasswordResetDoneScreen extends StatelessWidget {
  const PasswordResetDoneScreen({super.key});
  @override
  Widget build(BuildContext context) => KeysScaffold(
        body: Column(children: [
          const SizedBox(height: 120),
          const CircleAvatar(radius: 36, backgroundColor: KColors.success, child: Icon(PhosphorIconsRegular.check, color: Colors.white, size: 40)),
          const SizedBox(height: 24),
          const Intro(center: true, title: 'Password reset', body: 'Your password has been changed. For your security, you have been signed out on all devices.'),
        ]),
        bottom: KeysButton('Proceed to log in', onPressed: () => context.go('/auth/email')),
      );
}

/// New Apple/Google account: confirm the legal name (no password needed).
class ConfirmNameScreen extends StatefulWidget {
  const ConfirmNameScreen({super.key});
  @override
  State<ConfirmNameScreen> createState() => _ConfirmNameScreenState();
}

class _ConfirmNameScreenState extends State<ConfirmNameScreen> with Busy {
  late final me = context.session.me;
  late final _first = TextEditingController(text: me?.firstName);
  late final _last = TextEditingController(text: me?.lastName);
  final Map<String, String?> _errors = {};

  Future<void> _go() async {
    await run(() async {
      await context.api.post('/onboarding/account', {'firstName': _first.text.trim(), 'lastName': _last.text.trim()});
      if (mounted) await goToCurrentStep(context);
    }, onError: (e) {
      if (e is ApiException && e.field != null) setState(() => _errors[e.field!] = e.message);
    });
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        header: KeysHeader(onBack: () async {
          await context.session.logout();
          if (context.mounted) context.go('/auth/email');
        }),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(overline: 'Account setup', title: "Let's get to know you", body: 'Use your legal name. It is shown to your neighbours and cannot be changed later.'),
          const SizedBox(height: 24),
          KeysTextField(label: 'First name', controller: _first, error: _errors['firstName'], textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          KeysTextField(label: 'Last name', controller: _last, error: _errors['lastName'], textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {})),
        ]),
        bottom: KeysButton('Continue', loading: busy, onPressed: _first.text.trim().isEmpty || _last.text.trim().isEmpty ? null : _go),
      );
}
