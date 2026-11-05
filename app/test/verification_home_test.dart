import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/features/home/home_shell.dart';
import 'package:keys_lite/features/home/learning_tour.dart';
import 'package:keys_lite/features/verification/verification_screens.dart';
import 'harness.dart';

void main() {
  Map<String, dynamic> unverified() => {'status': 'unverified', 'homeAddress': '12 Maple Road, London SE1 7AA', 'reviewCase': null, 'acceptedDocuments': []};

  testWidgets('AVW-01.1 methods by device: card always, Apple Pay on iOS only', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final h = Harness();
    h.fake.on('GET /verification', (_, __) => unverified());
    await h.pump(t, const VerifyMethodScreen());
    expect(find.text('Verify with Bank card'), findsOneWidget);
    expect(find.text('Verify with Apple Pay'), findsOneWidget);
    expect(find.text('Verify with Google Pay'), findsNothing);
    expect(buttonEnabled(t, 'Verify'), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await t.pumpWidget(const SizedBox());
    final h2 = Harness();
    h2.fake.on('GET /verification', (_, __) => unverified());
    await h2.pump(t, const VerifyMethodScreen());
    expect(find.text('Verify with Google Pay'), findsOneWidget);
    expect(find.text('Verify with Apple Pay'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AVW-05.4 under review opens the review screen instead', (t) async {
    final h = Harness();
    h.fake.on('GET /verification', (_, __) => {
          'status': 'under_review',
          'reviewCase': {'ref': 'KYS-2026-11-0001', 'documentName': 'bill.pdf', 'submittedAt': '2026-11-05T10:00:00Z', 'estimate': 'Est. 1-2 business days'},
        });
    await h.pump(t, const VerifyMethodScreen());
    expect(find.text('Your documents are under review'), findsOneWidget);
    expect(find.text('Ref: KYS-2026-11-0001'), findsOneWidget);
    expect(find.text('Est. 1-2 business days'), findsOneWidget);
  });

  testWidgets('AVW-02 / AVW-04 card check fails -> mismatch with method and address; pass -> success', (t) async {
    final h = Harness();
    h.fake.on('POST /verification/check', (b, _) {
      final fail = (b['paymentMethodId'] as String).contains('_fail_');
      return {'result': fail ? 'fail' : 'pass', 'method': 'card', 'brand': 'visa', 'last4': fail ? '0002' : '4242', 'homeAddress': '12 Maple Road, London SE1 7AA'};
    });
    await h.pump(t, const CardFormScreen(homeAddress: '12 Maple Road, London SE1 7AA'));
    final f = find.byType(TextField);
    await t.enterText(f.at(0), '4000000000000002');
    await t.enterText(f.at(1), '1230');
    await t.enterText(f.at(2), '123');
    await t.pump();
    await t.tap(find.text('Verify'));
    await t.pumpAndSettle();
    expect(find.text("We couldn't verify your address"), findsOneWidget);
    expect(find.text('Visa •••• 0002'), findsOneWidget);
    expect(find.text('12 Maple Road, London SE1 7AA'), findsOneWidget);
    expect(find.textContaining('Contesting this decision will send your case to Keys for manual review'), findsOneWidget);
    expect(find.text('Contest this decision'), findsOneWidget);
  });

  testWidgets('card form validates number and expiry before calling Stripe', (t) async {
    final h = Harness();
    await h.pump(t, const CardFormScreen(homeAddress: 'x'));
    final f = find.byType(TextField);
    await t.enterText(f.at(0), '4242424242424241');
    await t.enterText(f.at(1), '1320');
    await t.enterText(f.at(2), '1');
    await t.pump();
    await t.tap(find.text('Verify'));
    await t.pumpAndSettle();
    expect(find.text('Enter a valid card number'), findsOneWidget);
    expect(find.text('Enter a valid expiry date'), findsOneWidget);
    expect(find.text('Enter a valid CVV'), findsOneWidget);
    expect(h.fake.called('POST /verification/check'), isFalse);
  });

  testWidgets('AVW-05 contest: 10 MB limit and accepted types checked before upload', (t) async {
    final h = Harness();
    await h.pump(t, const ContestScreen());
    expect(find.text('Utility bill'), findsOneWidget);
    h.media.document = fakePng(10 * 1024 * 1024 + 1);
    await t.tap(find.text('Tap to upload document'));
    await t.pumpAndSettle();
    expect(find.text('The file you selected is too large. Please choose a file of 10 MB or less.'), findsOneWidget);
    expect(buttonEnabled(t, 'Submit for review'), isFalse);
  });

  testWidgets('AVW-08.1 VERIFICATION_REQUIRED shows the verify sheet', (t) async {
    final h = Harness();
    late BuildContext ctx;
    await h.pump(t, Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    }));
    expect(handleVerificationRequired(ctx, ApiException(403, 'VERIFICATION_REQUIRED', 'x')), isTrue);
    await t.pumpAndSettle();
    expect(find.text('Verify your home address'), findsOneWidget);
    expect(handleVerificationRequired(ctx, ApiException(400, 'OTHER', 'x')), isFalse);
  });

  testWidgets('ONB-25 then LRN-01: welcome prompt first, then the 8-step tour; Back, Next and Skip', (t) async {
    final h = Harness();
    h.fake.on('GET /onboarding/welcome-post', (_, __) => {'community': 'Maple Road', 'text': "Hi neighbours! I'm Amy", 'audience': 'everyone'});
    h.fake.on('POST /onboarding/welcome-prompt/done', (_, __) => {'ok': true});
    h.fake.on('POST /learning/done', (_, __) => {'ok': true});
    await h.pump(t, const HomeShell(), meJson: Harness.me(welcome: true, learning: true));
    expect(find.text('Welcome to Maple Road'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /onboarding/welcome-prompt/done'), isTrue);

    expect(find.text('Step 1 of 8'), findsOneWidget);
    expect(find.text("Share what's on your mind"), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Step 2 of 8'), findsOneWidget);
    expect(find.textContaining('News'), findsNothing); // LRN-02.2
    await t.tap(find.text('Back'));
    await t.pumpAndSettle();
    expect(find.text('Step 1 of 8'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
    }
    expect(find.text('Your Profile'), findsOneWidget);
    await t.tap(find.text('Finish'));
    await t.pumpAndSettle();
    expect(find.text('Step 8 of 8'), findsNothing);
    expect(h.fake.lastBody('POST /learning/done')['outcome'], 'completed');
  });

  test('LRN-02 copy has no later-phase items', () {
    final all = kTourSteps.map((s) => '${s.title} ${s.body}').join(' ');
    expect(all.contains('scheduled posts'), isFalse);
    expect(all.contains('budget'), isFalse);
    expect(kTourSteps.length, 8);
  });
}
