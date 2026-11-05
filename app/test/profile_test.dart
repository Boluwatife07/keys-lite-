import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/profile/profile_screens.dart';
import 'package:keys_lite/features/profile/settings_screens.dart';
import 'package:keys_lite/widgets/widgets.dart';
import 'package:keys_lite/core/services.dart';
import 'package:keys_lite/theme/theme_controller.dart';
import 'package:keys_lite/theme/tokens.dart';
import 'harness.dart';

Map<String, dynamic> profile({bool blocked = false, bool muted = false}) => {
      'id': 'u2', 'name': 'Jules Winnfield', 'firstName': 'Jules', 'photoUrl': null, 'verified': true, 'role': 'Committee Chair',
      'bio': 'Hi neighbours', 'community': 'Maple Road', 'joinedAt': '2026-06-02T10:00:00Z', 'isMe': false,
      'isMuted': muted, 'isBlocked': blocked, 'shareLink': 'https://keys.app/profile/u2',
    };

void main() {
  testWidgets('Settings > Display: one switch on; dark mode recolours the app and is saved', (t) async {
    final h = Harness();
    await h.pump(t, const SettingsScreen());
    expect(find.text('Manage your app theme here'), findsOneWidget);
    await t.tap(find.text('Display'));
    await t.pumpAndSettle();
    final switches = find.byType(KSwitch);
    expect(switches, findsNWidgets(3));
    bool on(int i) => t.widget<KSwitch>(switches.at(i)).value;
    expect([on(0), on(1), on(2)], [true, false, false]); // Light is the default
    await t.tap(find.text('Dark mode'));
    await t.pumpAndSettle();
    expect([on(0), on(1), on(2)], [false, true, false]);
    expect(KColors.isDark, isTrue);
    expect(t.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, KPalette.dark.surfaceDefault);
    expect((h.deps.store as MemoryStore).theme, 'dark');
    // Tapping the switch that is on keeps it on.
    await t.tap(switches.at(1));
    await t.pumpAndSettle();
    expect(KColors.isDark, isTrue);
    await t.tap(find.text('Use device default settings'));
    await t.pumpAndSettle();
    expect(h.deps.theme.choice, ThemeChoice.system);
    expect(KColors.isDark, isFalse); // the test device is light
    await t.tap(find.text('Light mode'));
    await t.pumpAndSettle();
    expect((h.deps.store as MemoryStore).theme, 'light');
  });

  testWidgets('PRF-02 other profile: role, joined, Chat and the actions', (t) async {
    final h = Harness();
    h.fake.on('GET /users/u2', (_, _) => profile());
    await h.pump(t, const OtherProfileScreen(id: 'u2'));
    expect(find.text('Committee Chair'), findsOneWidget);
    expect(find.text('Joined June 2026'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    for (final a in ['Share profile', 'Mute Jules', 'Block Jules', 'Report Jules']) {
      expect(find.text(a), findsOneWidget);
    }
  });

  testWidgets('PRF-04.1 mute asks first, then "You muted" with Undo', (t) async {
    final h = Harness();
    var muted = false;
    h.fake.on('GET /users/u2', (_, _) => profile(muted: muted));
    h.fake.on('POST /users/u2/mute', (_, _) {
      muted = true;
      return {'message': 'You muted Jules Winnfield'};
    });
    await h.pump(t, const OtherProfileScreen(id: 'u2'));
    await t.tap(find.text('Mute Jules'));
    await t.pumpAndSettle();
    expect(find.textContaining("You won't receive any posts, messages notification from them for the next 30 days."), findsOneWidget);
    await t.tap(find.text('Yes, mute'));
    await t.pumpAndSettle();
    expect(find.text('You muted Jules Winnfield'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Unmute Jules'), findsOneWidget);
  });

  testWidgets('PRF-05.2 blocked profile shows Unblock and no actions', (t) async {
    final h = Harness();
    h.fake.on('GET /users/u2', (_, _) => profile(blocked: true));
    await h.pump(t, const OtherProfileScreen(id: 'u2'));
    expect(find.text('Unblock'), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Mute Jules'), findsNothing);
  });

  testWidgets('PRF-03.3 outsider sees not available', (t) async {
    final h = Harness();
    h.fake.on('GET /users/u9', (_, _) => throw Exception());
    h.fake.routes.remove('GET /users/u9');
    await h.pump(t, const OtherProfileScreen(id: 'u9'));
    expect(find.text('Not available'), findsOneWidget);
  });

  testWidgets('PRF-12 settings shows Phase 1 rows only', (t) async {
    final h = Harness();
    await h.pump(t, const SettingsScreen());
    for (final r in ['Your account', 'Notification', 'Privacy and Safety', 'Display', 'Terms & Conditions']) {
      expect(find.text(r), findsOneWidget);
    }
    for (final r in ['Address book', 'My payment method', 'Security', 'Language & Region']) {
      expect(find.text(r), findsNothing);
    }
  });

  testWidgets('PRF-13.5 empty blocked list', (t) async {
    final h = Harness();
    h.fake.on('GET /me/blocked', (_, _) => {'accounts': []});
    await h.pump(t, const PeopleListScreen(blocked: true));
    expect(find.text('No blocked accounts'), findsOneWidget);
    expect(find.text("Blocked accounts won't show up in your feed, inbox, or activity."), findsOneWidget);
  });

  testWidgets('PRF-14.2 newsletter starts off', (t) async {
    final h = Harness();
    h.fake.on('GET /me/notification-prefs', (_, _) => {'prefs': {'likes': true, 'comments': true, 'mentions': true, 'polls': true, 'updates': true, 'committee': true, 'chat': true, 'events': true, 'clubs': true, 'newsletter': false}});
    await h.pump(t, const NotificationSettingsScreen());
    await t.scrollUntilVisible(find.text('Newsletter'), 200);
    expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Newsletter')).value, isFalse);
  });

  testWidgets('PRF-15.3 new passwords must match', (t) async {
    final h = Harness();
    await h.pump(t, const PasswordScreen(create: false));
    final f = find.byType(TextField);
    await t.enterText(f.at(0), 'Keys2026!');
    await t.enterText(f.at(1), 'New2026!x');
    await t.enterText(f.at(2), 'New2026!y');
    await t.pump();
    await t.tap(find.widgetWithText(KeysButton, 'Change password'));
    await t.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(h.fake.called('PUT /me/password'), isFalse);
  });

  testWidgets('PRF-11 change address lists what happens and blocks when needed', (t) async {
    final h = Harness();
    h.fake.on('GET /me/exit-check', (_, _) => {'blockers': [{'code': 'CLUB_PRESIDENT', 'message': 'You are the President of Runners. Transfer ownership or close the club first.'}], 'warnings': [{'code': 'UNVERIFIED', 'message': 'Your profile will be unverified until you verify your new address.'}]});
    await h.pump(t, const ChangeAddressScreen());
    expect(find.text('Your profile will be unverified until you verify your new address.'), findsOneWidget);
    expect(find.textContaining('President of Runners'), findsOneWidget);
    expect(buttonEnabled(t, 'Proceed to change address'), isFalse);
  });
}
