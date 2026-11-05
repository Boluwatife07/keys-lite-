import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/models.dart';
import 'package:keys_lite/features/auth/auth_screens.dart';
import 'package:keys_lite/features/entry/entry_screens.dart';
import 'package:keys_lite/features/onboarding/community_screens.dart';
import 'package:keys_lite/features/onboarding/profile_screens.dart';
import '../harness.dart';
import 'catalog.dart';

Map<String, dynamic> card(String name, {String type = 'street', int? residents, int committee = 8}) => {
      'id': 'id-$name',
      'type': type,
      'typeLabel': {'street': 'STREET COMMUNITY', 'development': 'DEVELOPMENT', 'building': 'BUILDING'}[type],
      'name': name,
      'code': 'BLLEDN',
      'residents': ?residents,
      if (residents != null) 'committeeMembers': committee,
    };

Map<String, dynamic> onboardingMe(String step) => Harness.me(step: step);

void main() {
  // splash_screens
  shot('choose_how_to_use_keys', () => const ChooseAccountScreen());
  shot('intro_1', () => const IntroCarousel());
  // account_setup
  shot('email_empty', () => const EmailScreen());
  shot('email_filled', () => const EmailScreen(), act: (t, h) async {
    await t.enterText(find.byType(TextField).first, 'amyduncan@gmail.com');
  });
  shot('verify_email_empty', () => const VerifyCodeScreen(email: 'amyduncan@gmail.com', purpose: 'signup'));
  shot('create_account_empty', () => const CreateAccountScreen(ticket: 't'));
  shot('login_password', () => const PasswordLoginScreen(email: 'amyduncan@gmail.com', firstName: 'Amy'));
  shot('forgot_password', () => const ForgotPasswordScreen(email: 'amyduncan@gmail.com'));
  shot('new_password_empty', () => const NewPasswordScreen(ticket: 't'));
  shot('password_reset_done', () => const PasswordResetDoneScreen());
  // home address
  shot('home_address_default', () => const AddressScreen(), me: onboardingMe('address'));
  shot('home_address_suggestions', () => const AddressScreen(), me: onboardingMe('address'), setup: (h) {
    h.fake.on('GET /addresses/autocomplete', (_, _) => {
          'suggestions': [
            for (final n in ['10', '11', '12', '13', '14']) {'placeId': 'p$n', 'primary': '$n James Street, London', 'secondary': 'London, SE10 9PH'},
          ],
        });
  }, act: (t, h) async {
    await t.enterText(find.byKey(const Key('address-field')), '1 James');
    await t.pump(const Duration(milliseconds: 400));
  });
  // community matching
  shot('match_street_found', () => MatchScreen(result: MatchResult({'kind': 'single', 'communities': [card('Bellenden Road', residents: 863)]})), me: onboardingMe('community'));
  shot('match_development_found', () => MatchScreen(result: MatchResult({'kind': 'single', 'communities': [card('New Keys Capital', type: 'development', residents: 1584, committee: 12)]})), me: onboardingMe('community'));
  shot('match_not_eligible', () => MatchScreen(result: MatchResult({'kind': 'code_mismatch', 'communities': [card('Bellenden Road', residents: 863)]})), me: onboardingMe('community'));
  shot('pick_community', () => MatchScreen(result: MatchResult({
        'kind': 'multiple',
        'communities': [
          card('Morden Wharf Road', residents: 698),
          card('Morden Wharf', type: 'development', residents: 1584, committee: 24),
          card('Enderby Wharf', type: 'development'),
          card('Enderby Place', type: 'development', residents: 503, committee: 12),
        ],
      })), me: onboardingMe('community'));
  shot('area_not_on_keys', () => MatchScreen(result: MatchResult({'kind': 'none', 'communities': [], 'street': 'Dreadnought Walk'})), me: onboardingMe('community'));
  shot('area_kind', () => const AreaKindScreen(), me: onboardingMe('community'));
  shot('confirm_street', () => const ConfirmStreetScreen(), me: onboardingMe('community'));
  shot('development_name', () => const DevelopmentNameScreen(), me: onboardingMe('community'));
  shot('similar_developments', () => SimilarDevelopmentsScreen(name: 'New Keys', similar: [
        {...card('New Capital Keys', type: 'development', residents: 612, committee: 5), 'distanceKm': 0.4},
        {...card('New Keys Ct', type: 'development'), 'distanceKm': 0.6},
      ]), me: onboardingMe('community'));
  shot('join_development', () => const JoinDevelopmentScreen(developmentId: 'd1'), me: onboardingMe('community'), setup: (h) {
    h.fake.on('GET /onboarding/development/d1/join-preview', (_, _) => {
          'development': card('New Keys Capital', type: 'development'),
          'yourStreet': 'John Street',
          'streets': ['Dreadnought Walk', 'Dowell Street', 'Victoria Parade'],
        });
  });
  shot('shape_development', () => const ShapeDevelopmentScreen(name: 'New Keys Capital'), me: onboardingMe('community'), setup: (h) {
    h.fake.on('GET /onboarding/development/connected-streets', (_, _) => {
          'max': 5,
          'yourStreet': {'name': 'Dreadnought Walk', 'town': 'London'},
          'streets': [
            for (final s in ['Dowells Street', 'Victoria Parade', 'Thames St', 'Norway St', 'Wood Wharf']) {'name': s, 'town': 'London', 'key': '${s.toLowerCase()}|london'},
          ],
        });
  });
  shot('home_type', () => const HomeTypeScreen(), me: onboardingMe('home_type'));
  shot('pick_building', () => PickBuildingScreen(buildings: [
        {'id': 'b1', 'name': 'Linden Court', 'residents': 21},
        {'id': 'b2', 'name': 'Building 02', 'residents': 184},
        {'id': 'b3', 'name': 'Building 03', 'residents': 752},
        {'id': 'b4', 'name': 'Building 04', 'residents': 503},
      ]), me: onboardingMe('home_type'));
  shot('name_building', () => const NameBuildingScreen(), me: onboardingMe('home_type'));
  shot('street_live', () => const CommunityLiveScreen(screen: 'pioneer_live', name: 'Bellenden Road'), me: onboardingMe('profile'));
  shot('welcome_to_street', () => const CommunityLiveScreen(screen: 'welcome', name: 'Bellenden Road'), me: onboardingMe('profile'));
  shot('building_live', () => const CommunityLiveScreen(screen: 'pioneer_live', name: 'Linden Court', building: true), me: onboardingMe('profile'));
  // profile, verify, invite
  shot('profile_setup', () => const ProfileSetupScreen(), me: onboardingMe('profile'), setup: (h) {
    h.fake.on('GET /onboarding/defaults', (_, _) => {'bio': 'Hi neighbors! I am new to the area and excited to meet people nearby.'});
  });
  shot('verify_prompt', () => const VerifyPromptScreen(), me: onboardingMe('verify'));
  shot('invite', () => const InviteScreen(), me: onboardingMe('invite'), setup: (h) {
    h.fake.on('GET /communities/mine/invite', (_, _) => {'link': 'keys.modernwharf/f=4058391', 'message': "Hey! I'm using the Keys app to stay connected to our community. Download it and join us!"});
  });
}
