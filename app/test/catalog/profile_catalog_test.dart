import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/profile/profile_screens.dart';
import 'package:keys_lite/features/profile/settings_screens.dart';
import '../harness.dart';
import 'catalog.dart';

Map<String, dynamic> person(String id, String name, {bool me = false}) => {
      'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': !me, 'role': me ? null : 'Committee Chair',
      'bio': 'Hi neighbors! I am new to the area and excited to meet people nearby.', 'community': 'Maple Road', 'joinedAt': '2026-06-02T10:00:00Z', 'isMe': me,
      'isMuted': false, 'isBlocked': false, 'shareLink': 'https://keys.app/profile/$id',
    };

void main() {
  shot('settings_overview', () => const SettingsScreen());
  shot('settings_display', () => const DisplayScreen());
  shot('settings_account', () => const AccountScreen());
  shot('settings_notifications', () => const NotificationSettingsScreen(), setup: (h) {
    h.fake.on('GET /me/notification-prefs', (_, _) => {'prefs': {'likes': true, 'comments': true, 'mentions': true, 'polls': true, 'updates': true, 'committee': true, 'chat': true, 'events': true, 'clubs': true, 'newsletter': false}});
  });
  shot('settings_privacy', () => const PrivacyScreen());
  shot('my_profile', () => const MyProfileScreen(), setup: (h) {
    h.fake.on('GET /users/u1', (_, _) => person('u1', 'Amy Duncan', me: true));
    h.fake.on('GET /users/u1/posts', (_, _) => {'posts': [], 'total': 0, 'nextCursor': null});
  });
  shot('other_profile', () => const OtherProfileScreen(id: 'u2'), setup: (h) => h.fake.on('GET /users/u2', (_, _) => person('u2', 'Ella White')));
  shot('edit_profile', () => const EditProfileScreen());
  shot('change_email', () => const ChangeEmailScreen());
  shot('mute_confirm', () => const OtherProfileScreen(id: 'u2'), setup: (h) => h.fake.on('GET /users/u2', (_, _) => person('u2', 'Ella White')), act: (t, h) async {
    await t.tap(find.text('Mute Ella'));
    await t.pumpAndSettle();
  });
  shot('block_confirm', () => const OtherProfileScreen(id: 'u2'), setup: (h) => h.fake.on('GET /users/u2', (_, _) => person('u2', 'Ella White')), act: (t, h) async {
    await t.tap(find.text('Block Ella'));
    await t.pumpAndSettle();
  });
  shot('bio_sheet', () => const EditProfileScreen(), act: (t, h) async {
    await t.tap(find.text('Bio'));
    await t.pumpAndSettle();
  });
}
