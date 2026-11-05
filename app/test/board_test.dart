import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/community/board_screens.dart';
import 'package:keys_lite/features/community/community_tab.dart';
import 'package:keys_lite/features/community/proposals.dart';
import 'harness.dart';

Map<String, dynamic> person(String id, String name, {String? role}) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': role};

Map<String, dynamic> community({Map<String, dynamic>? board, String? role, bool committee = false}) => {
      'community': {'id': 'c1', 'name': 'Maple Road', 'type': 'street', 'code': 'MAPLE1', 'location': 'Street | London, SE1, UK'},
      'board': board,
      'me': {'role': role, 'isCommittee': committee, 'isChampion': false, 'isChair': role == 'Chair'},
      'proposalsTab': committee,
      'announcements': board == null
          ? []
          : [
              {'id': 'a1', 'type': 'board_exit', 'label': 'Board exit', 'text': 'Tobias Jurgen has exited the committee board, relieving their role as the Events Lead.', 'reason': 'Moving away', 'subject': person('u9', 'Tobias Jurgen')},
            ],
      'tierUp': null,
      'shareLink': 'https://keys.app/c/MAPLE1',
    };

Map<String, dynamic> board({bool voting = true, Map<String, dynamic>? mySeat}) => {
      'id': 'b1', 'tier': 1, 'committeeCount': 5, 'championCount': 0, 'votingAvailable': voting, 'preview': [],
      'seats': [
        {'id': 's1', 'kind': 'preset', 'role': 'Chair', 'occupant': person('u1', 'Amy Duncan', role: 'Chair'), 'status': 'you'},
        {'id': 's2', 'kind': 'preset', 'role': 'Treasurer', 'occupant': person('u2', 'Eric Pires', role: 'Treasurer'), 'status': 'occupied'},
        {'id': 's3', 'kind': 'preset', 'role': 'Events Lead', 'occupant': null, 'status': 'unoccupied'},
      ],
      'counts': {'all': 2, 'members': 2, 'champions': 0},
      'myApplication': null,
      'mySeat': mySeat,
      'canManageSeats': mySeat?['role'] == 'Chair',
    };

void main() {
  testWidgets('CBM-02.1 no committee: "Take a leap" with Create committee; hidden Phase 2 sections', (t) async {
    final h = Harness();
    h.fake.on('GET /community', (_, _) => community());
    await h.pump(t, const Scaffold(body: CommunityTab()));
    expect(find.text('Take a leap to improve your community'), findsOneWidget);
    expect(find.text('Create committee'), findsOneWidget);
    expect(find.text('Proposals'), findsNothing);
    for (final hidden in ['Budget', 'Resources', 'Communal services']) {
      expect(find.text(hidden), findsNothing);
    }
  });

  testWidgets('CBM-Q2 milestone sheet: "View new residents" marks it seen and opens New members', (t) async {
    final h = Harness();
    h.fake.on('GET /community', (_, _) => {
          ...community(),
          'milestone': {'threshold': 400, 'title': '400 members strong', 'body': "Exciting news! Your community has welcomed 300 new residents. Let's come together to greet them and make them feel at home!", 'newResidents': 300},
        });
    h.fake.on('POST /community/milestone/seen', (_, _) => {'ok': true});
    h.fake.on('GET /community/new-members', (_, _) => {'members': [person('u5', 'Ashley White'), person('u6', 'Brianna Roy')]});
    await h.pump(t, const Scaffold(body: CommunityTab()));
    expect(find.text('400 members strong'), findsOneWidget);
    expect(find.textContaining('welcomed 300 new residents'), findsOneWidget);
    await t.tap(find.text('View new residents'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /community/milestone/seen'), {'threshold': 400});
    expect(h.location, '/community/new-members');
    expect(find.text('New members'), findsOneWidget);
    expect(find.text('Brianna Roy'), findsOneWidget);
  });

  testWidgets('CBM-Q2 closing the milestone sheet marks it seen', (t) async {
    final h = Harness();
    h.fake.on('GET /community', (_, _) => {...community(), 'milestone': {'threshold': 100, 'title': '100 members strong', 'body': 'x', 'newResidents': 100}});
    h.fake.on('POST /community/milestone/seen', (_, _) => {'ok': true});
    await h.pump(t, const Scaffold(body: CommunityTab()));
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('100 members strong'), findsNothing);
    expect(h.fake.lastBody('POST /community/milestone/seen'), {'threshold': 100});
  });

  testWidgets('CBM-01 / CBM-18 committee member sees Hub | Proposals and announcements with View reason', (t) async {
    final h = Harness();
    h.fake.on('GET /community', (_, _) => community(board: board(), role: 'Treasurer', committee: true));
    await h.pump(t, const Scaffold(body: CommunityTab()));
    expect(find.text('Proposals'), findsOneWidget);
    expect(find.text('Board exit'), findsOneWidget);
    expect(find.text('View reason'), findsOneWidget);
    expect(find.text('Reassign to this role'), findsOneWidget);
  });

  testWidgets('CBM-04 join flow: pledge gates, leadership title needed, role about, answers required', (t) async {
    final h = Harness();
    h.fake.on('GET /board/roles', (_, _) => {
          'roles': [
            {'role': 'Chair', 'about': ['Leads committee meetings'], 'available': true},
            {'role': 'Treasurer', 'about': ['Keeps track of money'], 'available': false},
          ],
        });
    h.fake.on('POST /board', (_, _) => {'message': 'Committee board for your community has been created successfully.'});
    await h.pump(t, const JoinBoardScreen(create: true));
    expect(find.text('Welcome to Committee'), findsOneWidget);
    expect(buttonEnabled(t, 'Got it'), isFalse);
    await t.tap(find.text('I pledge to be an active member of the committee'));
    await t.pump();
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes'));
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pump();
    expect(find.text('Add your role title'), findsOneWidget);
    await t.tap(find.text('No'));
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('What role would you like to hold in the committee?'), findsOneWidget);
    expect(find.text('Treasurer'), findsNothing); // taken
    await t.tap(find.text('Chair'));
    await t.pump();
    expect(find.text('About the role'), findsOneWidget);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pump();
    expect(find.text('Tell us what makes you qualified for this role'), findsOneWidget);
    await t.enterText(find.byType(TextField).at(0), 'I run the street WhatsApp');
    await t.enterText(find.byType(TextField).at(1), 'Cleaner streets');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /board'), {'pledge': true, 'hasLeadership': false, 'qualified': 'I run the street WhatsApp', 'aim': 'Cleaner streets', 'role': 'Chair'});
    expect(find.text('Committee board for your community has been created successfully.'), findsOneWidget);
  });

  testWidgets('CBM-13 / CBM-16 board actions: my seat -> reassign/exit; others -> reassign/remove when voting is on', (t) async {
    final h = Harness();
    h.fake.on('GET /board', (_, _) => board(mySeat: {'id': 's1', 'role': 'Chair', 'kind': 'preset'}));
    await h.pump(t, const BoardScreen(), meJson: {...Harness.me(), 'id': 'u1'});
    expect(find.text('Manage seats'), findsOneWidget);
    expect(find.text('Unoccupied'), findsOneWidget);
    await t.tap(find.byTooltip('Actions').first);
    await t.pumpAndSettle();
    expect(find.text('Reassign my role'), findsOneWidget);
    expect(find.text('Exit committee'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Actions').last);
    await t.pumpAndSettle();
    expect(find.text('Reassign member'), findsOneWidget);
    expect(find.text('Remove member'), findsOneWidget);
  });

  testWidgets('CBM-16.4 below 5 members: no reassign or remove', (t) async {
    final h = Harness();
    h.fake.on('GET /board', (_, _) => board(voting: false, mySeat: {'id': 's1', 'role': 'Chair', 'kind': 'preset'}));
    await h.pump(t, const BoardScreen(), meJson: {...Harness.me(), 'id': 'u1'});
    await t.tap(find.byTooltip('Actions').last);
    await t.pumpAndSettle();
    expect(find.text('Remove member'), findsNothing);
    expect(find.text('Reassign member'), findsNothing);
  });

  testWidgets('VOT-01 cards: Vote vs Already voted; VOT-03.2 No asks for a reason', (t) async {
    final h = Harness();
    Map<String, dynamic> p(String id, bool can) => {
          'id': id, 'type': 'remove', 'typeLabel': 'Remove Member', 'status': can ? 'pending' : 'awaiting_approval',
          'subject': person('u3', 'Nardine Sahas'), 'creator': person('u1', 'Jules Winnfield'), 'role': 'Events Lead', 'reason': 'Inactive',
          'closesAt': DateTime.now().add(const Duration(days: 5, hours: 1)).toIso8601String(), 'createdAt': DateTime.now().toIso8601String(),
          'category': 'Committee board', 'myVote': can ? null : 'yes', 'canVote': can,
        };
    h.fake.on('GET /board/proposals', (_, _) => {'proposals': [p('p1', true), p('p2', false)]});
    await h.pump(t, const Scaffold(body: ProposalsList()));
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Vote'), findsOneWidget);
    expect(find.text('Already voted'), findsOneWidget);
    expect(find.text('5days left'), findsNWidgets(2));
  });

  testWidgets('VOT-03.2 No on a removal asks for a reason; results show after voting', (t) async {
    final h = Harness();
    Map<String, dynamic> p(String id, bool can) => {
          'id': id, 'type': 'remove', 'typeLabel': 'Remove Member', 'status': can ? 'pending' : 'awaiting_approval',
          'subject': person('u3', 'Nardine Sahas'), 'creator': person('u1', 'Jules Winnfield'), 'role': 'Events Lead', 'reason': 'Inactive',
          'closesAt': DateTime.now().add(const Duration(days: 5, hours: 1)).toIso8601String(), 'createdAt': DateTime.now().toIso8601String(),
          'category': 'Committee board', 'myVote': can ? null : 'yes', 'canVote': can,
        };
    h.fake.on('GET /board/proposals/p1', (_, _) => {'proposal': p('p1', true)});
    h.fake.on('POST /board/proposals/p1/vote', (b, _) => {'proposal': {...p('p1', false), 'results': {'yes': 1, 'no': 1, 'yesPercent': 50, 'noPercent': 50, 'eligible': 5, 'voters': []}}});
    await h.pump(t, const ProposalDetailScreen(id: 'p1'));
    expect(find.text('Do you approve of this request?'), findsOneWidget);
    await t.tap(find.text('No'));
    await t.pumpAndSettle();
    expect(find.text('Why are you voting no?'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Give them time');
    await t.tap(find.text('Submit vote'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /board/proposals/p1/vote'), {'choice': 'no', 'reason': 'Give them time'});
    expect(find.text('50%'), findsNWidgets(2));
  });

  testWidgets('CBM-11 manage seats: preset locked, deactivate asks first', (t) async {
    final h = Harness();
    h.fake.on('GET /board/manage', (_, _) => {
          'tier': 2, 'tierLabel': 'Tier 2 · up to 400 residents', 'championsLockedReason': null,
          'presetRoles': [{'id': 's1', 'kind': 'preset', 'role': 'Chair', 'active': true, 'occupant': person('u1', 'Amy Duncan'), 'canToggle': false}],
          'additionalSeats': [{'id': 'e1', 'kind': 'extra', 'role': 'Committee Member', 'active': true, 'occupant': null, 'canToggle': true}],
          'championSeats': [],
        });
    h.fake.on('POST /board/seats/e1/deactivate', (_, _) => {'message': 'Seat deactivated.'});
    await h.pump(t, const ManageSeatsScreen());
    expect(find.text("Preset roles (Can't be edited)"), findsOneWidget);
    expect(find.text('Additional Seats · Tier 2 · up to 400 residents'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.textContaining('Residents will no longer be able to apply for this role'), findsOneWidget);
    await t.tap(find.text('Deactivate'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /board/seats/e1/deactivate'), isTrue);
  });
}
