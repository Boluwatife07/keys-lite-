import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:keys_lite/features/community/board_screens.dart';
import 'package:keys_lite/features/community/proposals.dart';
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
  Map<String, dynamic> prop(String id, String type, String who, String creator, {String? reason, String? role, String? to, int days = 1, bool vote = true, String status = 'pending', Map<String, dynamic>? results, Map<String, dynamic>? answers}) => {
        'id': id, 'type': type, 'typeLabel': {'join': 'Join board', 'reassign': 'Reassign role', 'remove': 'Remove Member'}[type], 'status': status,
        'outcomeNote': null, 'subject': person('s$id', who, role: type == 'join' ? null : 'Vice Chair'), 'creator': person('c$id', creator), 'role': role, 'proposedRole': to,
        'reason': reason, 'closesAt': DateTime.now().add(Duration(days: days, minutes: 30)).toIso8601String(), 'createdAt': DateTime(2026, 3, 5, 9, 20).toIso8601String(),
        'category': 'Committee board', 'myVote': results == null ? null : 'yes', 'canVote': vote, 'answers': answers, 'results': results,
      };
  final list = [
    prop('1', 'join', 'Ashley White', 'Ashley White', role: 'Vice-Chair'),
    prop('2', 'reassign', 'Tobias Jurgen', 'Brianna Roy', reason: 'Haven seen him work on the budget to the recreational park, I am certain Tobias would be a great feat for our finances.', role: 'Project lead', to: 'Treasurer', days: 4),
    prop('3', 'remove', 'Nardine Sahas', 'Jules Winnfield', reason: 'Nardine has been absolutely inactive in all physical activities the committee has organized. The last time she came was in May.', role: 'Events Lead', days: 5),
  ];
  shot('proposals_list', () => const Scaffold(body: SafeArea(child: ProposalsList())), setup: (h) => h.fake.on('GET /board/proposals', (_, _) => {'proposals': list}));
  const removeReason = "Ashley has been inactive in all the committee activities; She declines most deliverables assigned to her and doesn't deliver on the few she accepts.";
  shot('proposal_vote', () => const ProposalDetailScreen(id: 'r1'), setup: (h) => h.fake.on('GET /board/proposals/r1', (_, _) => {'proposal': prop('r1', 'remove', 'Ashley White', 'Alan Everette', reason: removeReason, role: 'Project lead', days: 0)}));
  final results = {
        'proposal': prop('r1', 'remove', 'Ashley White', 'Alan Everette', reason: removeReason, role: 'Project lead', days: 0, vote: false, status: 'approved', results: {
          'yes': 3, 'no': 1, 'yesPercent': 75, 'noPercent': 25, 'eligible': 6,
          'voters': [
            {'person': person('v1', 'Jules Winfred'), 'choice': 'yes'}, {'person': person('v2', 'Omari Norris'), 'choice': 'yes'},
            {'person': person('v3', 'Ajani Kimathi'), 'choice': 'yes'}, {'person': person('v4', 'Alan Everett'), 'choice': 'no', 'reason': 'Give her more time'},
          ],
        }),
      };
  shot('proposal_results_bottom', () => const ProposalDetailScreen(id: 'r1'), act: (t, h) async {
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pumpAndSettle();
  }, setup: (h) => h.fake.on('GET /board/proposals/r1', (_, _) => results));
  shot('proposal_results', () => const ProposalDetailScreen(id: 'r1'), setup: (h) => h.fake.on('GET /board/proposals/r1', (_, _) => results));
}
