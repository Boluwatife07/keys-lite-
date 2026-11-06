import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/calendar/calendar.dart';
import 'package:keys_lite/features/clubs/club_detail.dart';
import 'package:keys_lite/features/events/event_detail.dart';
import 'package:keys_lite/features/events/event_form.dart';
import 'package:keys_lite/features/home/home_shell.dart';
import '../events_test.dart' show card, detail;
import '../clubs_test.dart' show club, clubPage, person;
import 'catalog.dart';

void shell(dynamic h) {
  h.fake.on('GET /feed', (_, _) => {'posts': [], 'nextCursor': null});
  h.fake.on('GET /calendar/upcoming', (_, _) => {'items': []});
  h.fake.on('GET /updates', (_, _) => {'updates': [], 'unseen': 0});
  h.fake.on('GET /chats', (_, _) => {'chats': [], 'unread': 0});
  h.fake.on('GET /events/cancelled-popups', (_, _) => {'popups': []});
  h.fake.on('GET /events/rating-prompts', (_, _) => {'prompts': []});
  h.fake.on('GET /events/templates', (_, _) => {
        'templates': [
          {'id': 'wine', 'name': 'Wine tasting', 'category': 'residential', 'image': 'template_wine.jpg', 'data': {'description': 'Join fellow wine lovers for an evening of discovery, conversation, and good taste. Sample a curated selection of reds, whites, and rosés.'}, 'personal': false},
          {'id': 'football', 'name': 'Football tournament', 'category': 'residential', 'image': 'template_football.jpg', 'data': {'description': 'A weekend of friendly matches for every age.'}, 'personal': false},
        ],
        'personal': [],
      });
  h.fake.on('GET /events/discover', (_, _) => {'trending': [], 'tags': ['All', 'Music', 'Culture', 'Networking', 'Food & Drink'], 'happeningSoon': [], 'templates': []});
  h.fake.on('GET /events/mine', (_, _) => {'events': []});
  h.fake.on('GET /clubs/home', (_, _) => {'myClubs': [], 'announcements': [], 'templates': []});
  h.fake.on('GET /clubs/templates', (_, _) => {'templates': [{'id': 'baking', 'label': 'Baking', 'name': 'Sweet Treats', 'category': 'Food & Drink', 'memberLimit': 30, 'image': 'club_baking.jpg', 'description': 'Home bakers'}]});
  h.fake.on('GET /clubs/discover', (_, _) => {'categories': ['All', 'Lifestyle', 'Sports'], 'clubs': []});
}

void main() {
  shot('events_discover', () => const HomeShell(), setup: shell, act: (t, h) async {
    await t.tap(find.text('Events'));
    await t.pumpAndSettle();
  });
  shot('events_mine', () => const HomeShell(), setup: shell, act: (t, h) async {
    await t.tap(find.text('Events'));
    await t.pumpAndSettle();
    await t.tap(find.text('My events'));
    await t.pumpAndSettle();
  });
  shot('event_detail', () => const EventDetailScreen(id: 'e1'), setup: (h) {
    h.fake.on('GET /events/e1', (_, _) => {'event': detail(card('e1', 'Skill Share Workshop', going: 12), volunteers: true, volunteerState: 'open')});
  });
  shot('event_create', () => const EventFormScreen(category: 'residential'));
  shot('clubs_home', () => const HomeShell(), setup: shell, act: (t, h) async {
    await t.tap(find.text('Clubs'));
    await t.pumpAndSettle();
  });
  shot('clubs_home_filled', () => const HomeShell(), setup: (h) {
    shell(h);
    h.fake.on('GET /clubs/home', (_, _) => {
          'myClubs': [club('k1', 'The Book Clock', role: 'president'), club('k2', 'Sewing Club', role: 'member'), club('k3', 'Gameboys', role: 'member')],
          'announcements': [
            {
              'id': 'a1', 'kind': 'post', 'author': {'id': 'u2', 'name': 'Jules Winnfield', 'firstName': 'Jules', 'photoUrl': null, 'verified': true, 'role': null},
              'text': 'Amy Duncan brought in the collection of yarns donated to the club by her factory today. We would be giving them away in our next meetup.',
              'mentions': [], 'attachment': 'none', 'photos': [], 'poll': null, 'likeCount': 4, 'commentCount': 0, 'likedByMe': false, 'isMine': false,
              'createdAt': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(), 'editedAt': null, 'shareLink': 'https://keys.app/post/a1',
              'club': {'id': 'k9', 'name': 'Cozy Crochet Cottage', 'audience': 'all'},
            },
          ],
          'templates': [],
        });
  }, act: (t, h) async {
    await t.tap(find.text('Clubs'));
    await t.pumpAndSettle();
  });
  shot('clubs_discover', () => const HomeShell(), setup: (h) {
    shell(h);
    h.fake.on('GET /clubs/discover', (_, _) => {
          'categories': ['All', 'Lifestyle', 'Sports'],
          'clubs': [
            {...club('k1', 'Blues United FC Fans'), 'membersPreview': [person('m1', 'Ana Lee'), person('m2', 'Bo Chan'), person('m3', 'Cy Diaz')], 'description': 'Blues United FC Fans is the official community fan club for supporters of Chelsea FC and other blue-clad European teams. From match-day watch parties to five-a-side games.', 'othersText': '+164 others are in this club'},
            {...club('k2', 'Unplug & Connect'), 'membersPreview': [person('m1', 'Ana Lee'), person('m2', 'Bo Chan'), person('m3', 'Cy Diaz')], 'category': 'Lifestyle', 'description': 'Unplug & Connect is a wellness-focused community designed to help residents disconnect from screens and reconnect with life. From guided walks to device-free evenings.', 'othersText': '+164 others are in this club'},
          ],
        });
  }, act: (t, h) async {
    await t.tap(find.text('Clubs'));
    await t.pumpAndSettle();
    await t.tap(find.text('Discover'));
    await t.pumpAndSettle();
  });
  shot('club_detail', () => const ClubDetailScreen(id: 'k1'), setup: (h) => clubPage(h, club('k1', 'Blues United FC Fans'), hidden: true));
  shot('calendar', () => const CalendarScreen(), setup: (h) {
    final now = DateTime.now();
    h.fake.on('GET /calendar', (_, _) => {
          'items': [
            {'type': 'event', 'color': '#1C8C86', 'id': 'e1', 'title': 'Movie night', 'subtitle': '6:00pm - 9:00pm • 1 Maple Road', 'at': now.toUtc().toIso8601String(), 'time': '6:00pm', 'open': {'type': 'event', 'id': 'e1'}},
            {'type': 'update', 'color': '#D92D20', 'id': 'u1', 'title': 'Bins tomorrow', 'subtitle': 'Put them out', 'at': now.toUtc().toIso8601String(), 'time': '9:00am', 'open': {'type': 'update', 'id': 'u1'}},
          ],
          'today': '',
        });
    h.fake.on('GET /calendar/nearest', (_, _) => {'item': null});
  });
}
