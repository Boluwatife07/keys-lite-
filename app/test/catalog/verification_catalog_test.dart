import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/verification/verification_screens.dart';
import 'catalog.dart';

Map<String, dynamic> unverified() => {
      'status': 'unverified',
      'homeAddress': '12 Maple Road, London SE1 7AA',
      'reviewCase': null,
      'acceptedDocuments': ['Utility bill (last 3 months)', 'Council tax bill', 'Bank statement', 'Tenancy agreement'],
    };

void ios(void Function() body) => body();
const iOS = TargetPlatform.iOS;

void main() {
  ios(() {
    shot('avw_method_default', () => const VerifyMethodScreen(), platform: iOS, setup: (h) => h.fake.on('GET /verification', (_, _) => unverified()));
    shot('avw_method_apple_selected', () => const VerifyMethodScreen(), platform: iOS, setup: (h) => h.fake.on('GET /verification', (_, _) => unverified()), act: (t, h) async {
      await t.tap(find.text('Verify with Apple Pay'));
    });
    shot('avw_method_card_selected', () => const VerifyMethodScreen(), platform: iOS, setup: (h) => h.fake.on('GET /verification', (_, _) => unverified()), act: (t, h) async {
      await t.tap(find.text('Verify with Bank card'));
      await t.pumpAndSettle();
      final f = find.byType(TextField);
      await t.enterText(f.at(0), '1234567890123456');
      await t.enterText(f.at(1), '1125');
      await t.enterText(f.at(2), '123');
    });
    shot('avw_card_form', () => const CardFormScreen(homeAddress: '12 Maple Road, London SE1 7AA'));
    shot('avw_success', () => const VerifySuccessScreen());
    shot('avw_mismatch', () => const VerifyMismatchScreen(result: {'result': 'fail', 'method': 'card', 'brand': 'visa', 'last4': '0002', 'homeAddress': '12 Maple Road, London SE1 7AA'}));
    shot('avw_contest', () => const ContestScreen(), setup: (h) => h.fake.on('GET /verification', (_, _) => unverified()));
    shot('avw_under_review', () => const UnderReviewScreen(reviewCase: {'ref': 'KYS-2026-11-0001', 'documentName': 'council_tax_bill.pdf', 'submittedAt': '2026-11-05T10:00:00Z', 'estimate': 'Est. 1-2 business days'}));
    shot('avw_explainer', () => const VerifyExplainerScreen());
  });
}
