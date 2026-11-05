import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/features/auth/auth_screens.dart';
import 'package:keys_lite/features/entry/entry_screens.dart';
import 'harness.dart';

void main() {
  testWidgets('ONB-02 carousel: four slides, Done goes to the resident/vendor choice and is remembered', (t) async {
    final h = Harness();
    await h.pump(t, const IntroCarousel());
    expect(find.text('Stay informed and never miss a beat'), findsOneWidget);
    for (final title in ['Book services digitally', 'Join resident committees and clubs', 'Contribute to your neighbourhood']) {
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Choose how you will use the Keys app.'), findsOneWidget);
    expect(h.store.seen, isTrue);
    // ONB-04.1: no language picker in Phase 1.
    expect(find.text('English UK'), findsNothing);
  });

  testWidgets('ONB-05 email: inactive when empty, inline error, routes by account state', (t) async {
    final h = Harness();
    h.fake.on('POST /auth/email/start', (b, _) => b['email'] == 'amy@keys.test'
        ? {'status': 'existing', 'firstName': 'Amy', 'hasPassword': true}
        : {'status': 'code_sent', 'resendInSeconds': 60});
    await h.pump(t, const EmailScreen());
    expect(buttonEnabled(t, 'Continue'), isFalse);
    expect(find.text('By continuing you agree to our Terms of Use and Privacy Policy', findRichText: true), findsOneWidget);

    await t.enterText(find.byType(TextField), 'amy@');
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(h.fake.called('POST /auth/email/start'), isFalse);

    await t.enterText(find.byType(TextField), 'Amy@keys.test');
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Welcome, Amy'), findsOneWidget);
    expect(h.fake.lastBody('POST /auth/email/start')['email'], 'amy@keys.test');
  });

  testWidgets('ONB-07 code: wrong code shows the error and clears; resend after 60 s', (t) async {
    final h = Harness();
    h.fake.on('POST /auth/email/verify', (_, __) => ApiException(400, 'INVALID_CODE', 'Invalid verification code. Please check and try again'));
    h.fake.on('POST /auth/code/resend', (_, __) => {'resendInSeconds': 60});
    await h.pump(t, const VerifyCodeScreen(email: 'new@keys.test', purpose: 'signup'));
    expect(find.text('Verify email address'), findsOneWidget);
    expect(find.text('Resend code in 60s'), findsOneWidget);
    await t.enterText(find.byKey(const Key('code-field')), '123456');
    await t.pumpAndSettle();
    expect(find.text('Invalid verification code. Please check and try again'), findsOneWidget);
    final field = t.widget<TextField>(find.byKey(const Key('code-field')));
    expect(field.controller!.text, isEmpty);

    await t.pump(const Duration(seconds: 61));
    expect(find.text('Resend code'), findsOneWidget);
    await t.tap(find.text('Resend code'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /auth/code/resend'), isTrue);
    expect(find.text('Resend code in 60s'), findsOneWidget);
    await t.pump(const Duration(seconds: 61));
  });

  testWidgets('ONB-08 details: rules show live, mismatch error, names required', (t) async {
    final h = Harness();
    await h.pump(t, const CreateAccountScreen(ticket: 't'));
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Amy');
    await t.enterText(fields.at(1), 'Duncan');
    await t.enterText(fields.at(2), 'abc');
    await t.pump();
    expect(buttonEnabled(t, 'Continue'), isFalse);
    await t.enterText(fields.at(2), 'Keys2026!');
    await t.enterText(fields.at(3), 'Keys2026?');
    await t.pump();
    expect(buttonEnabled(t, 'Continue'), isTrue);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(h.fake.called('POST /auth/signup'), isFalse);
  });

  testWidgets('ONB-09.2 wrong password shows "Incorrect password"', (t) async {
    final h = Harness();
    h.fake.on('POST /auth/login', (_, __) => ApiException(400, 'INCORRECT_PASSWORD', 'Incorrect password', {'field': 'password'}));
    await h.pump(t, const PasswordLoginScreen(email: 'amy@keys.test', firstName: 'Amy'));
    expect(find.text('Signing in as amy@keys.test', findRichText: true), findsOneWidget);
    await t.enterText(find.byType(TextField), 'nope');
    await t.pump();
    await t.tap(find.text('Log in'));
    await t.pumpAndSettle();
    expect(find.text('Incorrect password'), findsOneWidget);
  });
}
