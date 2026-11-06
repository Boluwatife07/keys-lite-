import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/home/home_shell.dart';
import 'package:keys_lite/features/updates/update_detail.dart';
import 'package:keys_lite/features/updates/update_form.dart';
import '../harness.dart';
import 'catalog.dart';

Map<String, dynamic> person(String id, String name, {String? role}) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': role};

Map<String, dynamic> update(String id, String title, String details, String day, List<String> locs, {bool muted = false, bool seen = true, int fresh = 0, String status = 'live'}) => {
      'id': id, 'title': title, 'details': details, 'author': person('u2', 'Jules Winnifred', role: 'Chair'), 'date': '2026-03-${day}T09:00:00Z',
      'locations': locs.join(', '), 'locationNames': locs, 'audience': 'sub', 'images': [], 'imageMedia': [], 'documentId': null,
      'additionalCount': fresh, 'newAdditional': fresh, 'pinned': false, 'muted': muted, 'seen': seen, 'status': status, 'isMine': false,
      'canResolve': false, 'chatId': null, 'editedAt': null, 'shareLink': 'https://keys.app/update/$id',
      'resolvedAt': status == 'resolved' ? '2026-03-11T14:20:00Z' : null,
    };

final list = [
  update('a', 'Road Maintenance on Riverwalk Street', 'Attention residents! The council will be carrying out road maintenance on Riverwalk Street. Expect temporary lane closures and noise during this period.', '11', ['Morden Street']),
  update('b', 'Power Outage on Greenfield Avenue', 'The electricity supply on Greenfield Avenue will be temporarily shut down for maintenance from 10:00 AM to 2:00 PM. Please plan ahead.', '12', ['Gladstone House', 'Orchid house', 'Thames Street', 'Telecom', 'Pier Road'], muted: true),
  update('c', 'Water Supply Interruption on Oakridge Lane', 'Due to pipeline repairs, water service on Oakridge Lane will be unavailable from midnight until 6:00 AM tomorrow. Kindly store enough water.', '13', ['Modern Wharf'], seen: false, fresh: 4),
];

void home(Harness h) {
  h.fake.on('GET /feed', (_, _) => {'posts': [], 'nextCursor': null});
  h.fake.on('GET /calendar/upcoming', (_, _) => {'items': []});
  h.fake.on('GET /updates', (_, _) => {'updates': list, 'hasResolved': true, 'canCreate': true, 'unseen': 3});
  h.fake.on('GET /chats', (_, _) => {'chats': [], 'unread': 2});
}

void main() {
  shot('updates_list', () => const HomeShell(), setup: home, act: (t, h) async {
    await t.tap(find.text('Updates').first);
    await t.pumpAndSettle();
  });
  shot('update_detail', () => const UpdateDetailScreen(id: 'a'), setup: (h) {
    h.fake.on('GET /updates/a', (_, _) => {'update': {...list[0], 'title': 'Temporary road closure for maintenance purpose.', 'locationNames': ['Morden Street', 'Orchid House', 'Thames Street', 'Gladstone House', 'Telecom'], 'document': null, 'additional': [], 'canAddAdditional': false, 'chat': null}});
  });
  shot('update_create', () => const UpdateFormScreen());
}
