import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/core/models.dart';
import 'package:keys_lite/features/onboarding/community_screens.dart';
import 'package:keys_lite/features/onboarding/profile_screens.dart';
import 'harness.dart';

Map<String, dynamic> card(String name, {String type = 'street', int? residents}) => {
      'id': 'id-$name',
      'type': type,
      'typeLabel': type == 'street' ? 'STREET COMMUNITY' : 'DEVELOPMENT',
      'name': name,
      'code': 'ABCDEF',
      if (residents != null) 'residents': residents,
      if (residents != null) 'committeeMembers': 12,
    };

void main() {
  testWidgets('ONB-11.3 typed address that was not picked from suggestions is refused', (t) async {
    final h = Harness();
    h.fake.on('GET /addresses/autocomplete', (_, _) => {'suggestions': []});
    await h.pump(t, const AddressScreen(), meJson: Harness.me(step: 'address'));
    await t.enterText(find.byKey(const Key('address-field')), '1 Nowhere');
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Address not found. Please use a valid address.'), findsOneWidget);
  });

  testWidgets('ONB-11.2 / ONB-12.2 picking a suggestion; invalid code shown under the code field', (t) async {
    final h = Harness();
    h.fake.on('GET /addresses/autocomplete', (_, _) => {'suggestions': [{'placeId': 'p1', 'primary': '12 Maple Road', 'secondary': 'London SE1 7AA'}]});
    h.fake.on('POST /onboarding/address', (b, _) => b['communityCode'] == 'ZZZZZZ'
        ? ApiException(400, 'INVALID_COMMUNITY_CODE', 'Invalid community code. Please check and try again.', {'field': 'communityCode'})
        : {'match': {'kind': 'none', 'communities': []}});
    await h.pump(t, const AddressScreen(), meJson: Harness.me(step: 'address'));
    await t.enterText(find.byKey(const Key('address-field')), '12 Map');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    await t.tap(find.text('12 Maple Road'));
    await t.enterText(find.byKey(const Key('code-field-community')), 'ZZZZZZ');
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Invalid community code. Please check and try again.'), findsOneWidget);
    // Clear the code and continue with the address only.
    await t.enterText(find.byKey(const Key('code-field-community')), '');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text("Your area isn't on Keys yet"), findsOneWidget);
    expect(find.text('No one has set up a community for Maple Road yet.'), findsOneWidget);
    expect(h.fake.lastBody('POST /onboarding/address').containsKey('communityCode'), isFalse);
  });

  testWidgets('ONB-13.1 single match: card, counts hidden under 500, join -> home type', (t) async {
    final h = Harness();
    h.fake.on('POST /onboarding/join', (_, _) => {'onboardingStep': 'home_type'});
    await h.pump(t, MatchScreen(result: MatchResult({'kind': 'single', 'communities': [card('Bellenden Road')]})), meJson: Harness.me(step: 'community'));
    expect(find.text('We found your community'), findsOneWidget);
    expect(find.text('STREET COMMUNITY'), findsOneWidget);
    expect(find.textContaining('residents'), findsNothing);
    await t.tap(find.text('Join community'));
    await t.pumpAndSettle();
    expect(find.text('What type of home do you live in?'), findsOneWidget);
  });

  testWidgets('ONB-13.4 counts show above 500', (t) async {
    final h = Harness();
    await h.pump(t, MatchScreen(result: MatchResult({'kind': 'single', 'communities': [card('New Keys Capital', type: 'development', residents: 1584)]})), meJson: Harness.me(step: 'community'));
    expect(find.text('1,584 residents'), findsOneWidget);
    expect(find.text('12 committee'), findsOneWidget);
  });

  testWidgets('ONB-13.4 similar developments hide counts at 500 or fewer', (t) async {
    final h = Harness();
    await h.pump(t, SimilarDevelopmentsScreen(name: 'New Keys', similar: [
      {...card('New Keys Capital', type: 'development'), 'distanceKm': 1.2},
      {...card('New Keys East', type: 'development', residents: 640), 'distanceKm': 3.4},
    ]), meJson: Harness.me(step: 'community'));
    expect(find.text('1.2km away'), findsOneWidget);
    expect(find.text('640 residents'), findsOneWidget);
    expect(find.text('12 committee members'), findsOneWidget);
    expect(find.text('3.4km away'), findsOneWidget);
    expect(find.textContaining('residents'), findsOneWidget);
  });

  testWidgets('ONB-13.4 building list hides counts at 500 or fewer', (t) async {
    final h = Harness();
    await h.pump(t, const PickBuildingScreen(buildings: [
      {'id': 'b1', 'name': 'Linden House'},
      {'id': 'b2', 'name': 'Oak Tower', 'residents': 512},
    ]), meJson: Harness.me(step: 'home_type'));
    expect(find.text('Linden House'), findsOneWidget);
    expect(find.text('512 residents'), findsOneWidget);
    expect(find.textContaining('0 residents'), findsNothing);
  });

  testWidgets('ONB-13.2 multiple: join inactive until one is picked; not listed -> area type', (t) async {
    final h = Harness();
    await h.pump(t, MatchScreen(result: MatchResult({'kind': 'multiple', 'communities': [card('Maple Road'), card('New Keys Capital', type: 'development')]})), meJson: Harness.me(step: 'community'));
    expect(find.text('Pick your community'), findsOneWidget);
    expect(buttonEnabled(t, 'Join community'), isFalse);
    await t.tap(find.text('New Keys Capital'));
    await t.pump();
    expect(buttonEnabled(t, 'Join community'), isTrue);
    await t.tap(find.text('My community is not listed'));
    await t.pumpAndSettle();
    expect(find.text('What kind of area do you live in?'), findsOneWidget);
    // ONB-14.2: Proceed inactive until a type is selected.
    expect(buttonEnabled(t, 'Proceed'), isFalse);
    await t.tap(find.text('Residential street'));
    await t.pump();
    expect(buttonEnabled(t, 'Proceed'), isTrue);
  });

  testWidgets('ONB-12.4 code not eligible -> proceed with my address', (t) async {
    final h = Harness();
    h.fake.on('POST /onboarding/match', (_, _) => {'match': {'kind': 'none', 'communities': []}});
    await h.pump(t, MatchScreen(result: MatchResult({'kind': 'code_ineligible', 'codedName': 'Bellenden Road', 'communities': [card('Bellenden Road')]})), meJson: Harness.me(step: 'community'));
    expect(find.text("You're not eligible for this community"), findsOneWidget);
    await t.tap(find.text('Proceed with my address'));
    await t.pumpAndSettle();
    expect(find.text("Your area isn't on Keys yet"), findsOneWidget);
  });

  testWidgets('ONB-15.3 street already created by a neighbour -> offered to join it', (t) async {
    final h = Harness();
    h.fake.on('POST /onboarding/street', (_, _) => ApiException(409, 'STREET_COMMUNITY_EXISTS', 'exists', {'community': card('Maple Road')}));
    await h.pump(t, const ConfirmStreetScreen(), meJson: Harness.me(step: 'community'));
    expect(find.text('Confirm your street'), findsOneWidget);
    expect(find.text('Maple Road'), findsOneWidget);
    await t.tap(find.text('Create community'));
    await t.pumpAndSettle();
    expect(find.text('We found your community'), findsOneWidget);
  });

  testWidgets('ONB-20.2 shape development: max 5 streets', (t) async {
    final h = Harness();
    h.fake.on('GET /onboarding/development/connected-streets', (_, _) => {
          'yourStreet': {'name': 'Elm Street', 'town': 'London'},
          'max': 5,
          'streets': [for (final n in ['A', 'B', 'C', 'D', 'E', 'F']) {'key': n, 'name': '$n Road', 'town': 'London', 'hasStreetCommunity': n == 'A'}],
        });
    h.fake.on('POST /onboarding/development', (_, _) => {'onboardingStep': 'home_type'});
    await h.pump(t, const ShapeDevelopmentScreen(name: 'Elm Park'), meJson: Harness.me(step: 'community'));
    expect(find.text('Only streets directly connected to your street are shown.'), findsOneWidget);
    for (final n in ['A', 'B', 'C', 'D', 'E']) {
      await t.tap(find.byTooltip('Add $n Road'));
      await t.pump();
    }
    expect(find.text('Maximum of 5 streets can be linked'), findsOneWidget);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, PhosphorIconsRegular.plusCircle)).onPressed, isNull);
    await t.tap(find.text('Create development'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /onboarding/development')['streetKeys'], ['A', 'B', 'C', 'D', 'E']);
  });

  testWidgets('ONB-17.3 duplicate building name shows the server error', (t) async {
    final h = Harness();
    h.fake.on('POST /onboarding/building', (b, _) => ApiException(409, 'BUILDING_EXISTS', '"${b['name']}" already exists on this street. Choose a different name.', {'field': 'name'}));
    await h.pump(t, const NameBuildingScreen(), meJson: Harness.me(step: 'home_type'));
    expect(buttonEnabled(t, 'Create building'), isFalse);
    await t.enterText(find.byType(TextField), 'Linden House');
    await t.pump();
    await t.tap(find.text('Create building'));
    await t.pumpAndSettle();
    expect(find.text('"Linden House" already exists on this street. Choose a different name.'), findsOneWidget);
  });

  testWidgets('ONB-22 profile: photo required, too-large error, safety tick, preset bio n/160', (t) async {
    final h = Harness();
    h.fake.on('GET /onboarding/defaults', (_, _) => {'bio': 'Hi neighbours!'});
    await h.pump(t, const ProfileSetupScreen(), meJson: Harness.me(step: 'profile'));
    expect(find.text('Hi neighbours!'), findsOneWidget);
    expect(find.text('14/160'), findsOneWidget);
    expect(buttonEnabled(t, 'Continue'), isFalse);
    h.media.photo = fakePng(15 * 1024 * 1024 + 1);
    await t.tap(find.bySemanticsLabel('Add profile picture'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose from library'));
    await t.pumpAndSettle();
    expect(find.text('The image you selected is too large. Please choose a different image.'), findsOneWidget);
    await t.tap(find.byKey(const Key('safety-checkbox')));
    await t.pump();
    expect(buttonEnabled(t, 'Continue'), isFalse); // still no photo
    await t.tap(find.text('Keys safety guidelines'));
    await t.pumpAndSettle();
    expect(find.text('Stay safe when interacting online'), findsOneWidget);
  });

  testWidgets('ONB-24 invite: copy shows "Link copied", share uses the phone share sheet', (t) async {
    final h = Harness();
    h.fake.on('GET /communities/mine/invite', (_, _) => {'link': 'https://keys.app/c/MAPLE1', 'message': "Hey! I'm using the Keys app to stay connected to our community. Download it and join us! https://keys.app/c/MAPLE1"});
    await h.pump(t, const InviteScreen());
    await t.tap(find.byTooltip('Copy link'));
    await t.pump();
    expect(find.text('Link copied'), findsOneWidget);
    expect(h.sharer.copied.single, 'https://keys.app/c/MAPLE1');
    await t.tap(find.text('Tap to share'));
    await t.pumpAndSettle();
    expect(h.sharer.shared.single, startsWith("Hey! I'm using the Keys app"));
    expect(find.text('Continue'), findsOneWidget);
  });
}
