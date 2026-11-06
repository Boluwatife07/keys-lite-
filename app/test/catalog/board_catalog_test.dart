import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/community/board_screens.dart';
import 'package:keys_lite/features/home/home_shell.dart';
import 'catalog.dart';

Map<String, dynamic> person(String id, String name, {String? role}) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': role};

final seats = [
  ('Chair', 'Amy Duncan'), ('Vice-Chair', 'Ashley White'), ('Treasurer', 'Eric Pires'), ('Secretary', 'Brianna Roy'),
  ('Projects Lead', 'Ajani Kimathi'), ('Events Lead', 'Nadine Sahs'), ('Clubs Lead', 'Tobias Jurgen'), ('Communications Lead', 'Alan Everett'),
];

Map<String, dynamic> board() => {
      'id': 'b1', 'tier': 1, 'committeeCount': 8, 'championCount': 0, 'votingAvailable': true,
      'preview': [for (final (i, s) in seats.indexed) person('u$i', s.$2, role: s.$1)],
      'seats': [for (final (i, s) in seats.indexed) {'id': 's$i', 'kind': 'preset', 'role': s.$1, 'occupant': person('u$i', s.$2, role: s.$1), 'status': i == 0 ? 'you' : 'occupied'}],
      'counts': {'all': 8, 'members': 8, 'champions': 0},
      'myApplication': null, 'mySeat': {'id': 's0', 'role': 'Chair'}, 'canManageSeats': true,
    };

Map<String, dynamic> community() => {
      'community': {'id': 'c1', 'name': 'Modern Wharf', 'type': 'development', 'code': 'MAPLE1', 'location': 'Development | Greenwich, SE10, UK'},
      'board': board(),
      'me': {'role': 'Chair', 'isCommittee': true, 'isChampion': false, 'isChair': true},
      'proposalsTab': true, 'announcements': [], 'tierUp': null, 'shareLink': 'https://keys.app/c/MAPLE1',
    };

void main() {
  shot('community_tab', () => const HomeShell(), setup: (h) {
    h.fake.on('GET /community', (_, _) => community());
    h.fake.on('GET /feed', (_, _) => {'posts': [], 'nextCursor': null});
    h.fake.on('GET /calendar/upcoming', (_, _) => {'items': []});
    h.fake.on('GET /updates', (_, _) => {'updates': [], 'unseen': 0});
    h.fake.on('GET /chats', (_, _) => {'chats': [], 'unread': 0});
  }, act: (t, h) async {
    await t.tap(find.text('Community'));
    await t.pumpAndSettle();
  });
  shot('committee_board', () => const BoardScreen(), setup: (h) => h.fake.on('GET /board', (_, _) => board()));
  shot('join_leadership', () => const JoinBoardScreen(create: true), setup: (h) {
    h.fake.on('GET /board/roles', (_, _) => {'roles': [{'role': 'Chair', 'about': ['Leads committee meetings'], 'available': true}]});
  }, act: (t, h) async {
    await t.tap(find.text('I pledge to be an active member of the committee'));
    await t.pump();
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
  });
}
