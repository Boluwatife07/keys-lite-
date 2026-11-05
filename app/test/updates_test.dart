import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/features/updates/update_detail.dart';
import 'package:keys_lite/features/updates/update_form.dart';
import 'package:keys_lite/features/updates/updates_list.dart';
import 'harness.dart';

Map<String, dynamic> person(String id, String name, {String? role}) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': role};

Map<String, dynamic> update(String id, String title, {bool pinned = false, bool muted = false, bool seen = true, int fresh = 0, bool mine = false, bool canResolve = false, String status = 'live', String? chatId}) => {
      'id': id,
      'title': title,
      'details': 'Attention residents! The council will be carrying out road maintenance.',
      'author': person('u2', 'Jules Winnifred', role: 'Chair'),
      'date': '2026-03-11T09:00:00Z',
      'locations': 'Maple Road, Oak Avenue',
      'locationNames': ['Maple Road', 'Oak Avenue'],
      'audience': 'sub',
      'images': [],
      'imageMedia': [],
      'documentId': null,
      'additionalCount': fresh,
      'newAdditional': fresh,
      'pinned': pinned,
      'muted': muted,
      'seen': seen,
      'status': status,
      'isMine': mine,
      'canResolve': canResolve,
      'chatId': chatId,
      'editedAt': null,
      'shareLink': 'https://keys.app/update/$id',
    };

Map<String, dynamic> detail(Map<String, dynamic> u, {bool canAdd = false, Map<String, dynamic>? document, Map<String, dynamic>? chat, List additional = const []}) =>
    {'update': {...u, 'document': document, 'additional': additional, 'canAddAdditional': canAdd, 'chat': chat}};

void main() {
  testWidgets('UPD-01 empty state copy; committee gets the create button', (t) async {
    final h = Harness();
    h.fake.on('GET /updates', (_, _) => {'updates': [], 'hasResolved': false, 'canCreate': true});
    await h.pump(t, const Scaffold(body: UpdatesTab()));
    expect(find.text('No updates yet'), findsOneWidget);
    expect(find.text('Urgent information posted by the Committee members will be shown here'), findsOneWidget);
    expect(find.byTooltip('Create update'), findsOneWidget);
  });

  testWidgets('UPD-01 resident: no create button; pinned and muted marks; new additional updates; search', (t) async {
    final h = Harness();
    h.fake.on('GET /updates', (_, _) => {
          'updates': [
            update('a', 'Road Maintenance on Riverwalk', pinned: true),
            update('b', 'Power Outage on Greenfield', muted: true),
            update('c', 'Water Supply Interruption', seen: false, fresh: 4),
          ],
          'hasResolved': true,
          'canCreate': false,
        });
    var unseen = -1;
    await h.pump(t, Scaffold(body: UpdatesTab(onUnseen: (n) => unseen = n)));
    expect(find.byTooltip('Create update'), findsNothing);
    expect(find.byIcon(PhosphorIconsFill.pushPin), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.speakerSimpleSlash), findsOneWidget);
    expect(find.text('+4 new additional updates'), findsOneWidget);
    expect(unseen, 1);
    expect(find.text('View resolved updates'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'power');
    await t.pumpAndSettle();
    expect(find.text('Power Outage on Greenfield'), findsOneWidget);
    expect(find.text('Road Maintenance on Riverwalk'), findsNothing);
    await t.enterText(find.byType(TextField), 'zzz');
    await t.pumpAndSettle();
    expect(find.text('No results found'), findsOneWidget);
    expect(find.text('Try another keyword.'), findsOneWidget);
  });

  testWidgets('UPD-02 / UPD-03 create: required fields, sub-community audience, group chat', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/audience-options', (_, q) => {
          'streets': [
            {'id': 's1', 'name': 'Maple Road'},
            {'id': 's2', 'name': 'Oak Avenue'},
          ].where((s) => (s['name'] as String).toLowerCase().contains((q['q'] ?? '').toLowerCase())).toList(),
          'buildings': [],
        });
    h.fake.on('POST /updates', (b, _) => {'update': update('n', b['title']), 'message': 'Your update is now live.', 'chatId': 'c9'});
    await h.pump(t, const UpdateFormScreen());
    expect(buttonEnabled(t, 'Post update'), isFalse);
    expect(find.text('Schedule this update'), findsNothing); // later phase
    await t.enterText(find.byType(TextField).at(0), 'Temporary road closure');
    await t.enterText(find.byType(TextField).at(1), 'Expect lane closures this week.');
    await t.pumpAndSettle();
    expect(find.text('22/100'), findsOneWidget);
    expect(buttonEnabled(t, 'Post update'), isTrue);
    expect(find.text('All residents'), findsOneWidget);

    await t.tap(find.text('Modify'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sub-community'));
    await t.pumpAndSettle();
    expect(find.text('Residents of specific community'), findsOneWidget);
    expect(buttonEnabled(t, 'Done'), isFalse);
    await t.enterText(find.widgetWithText(TextField, 'Search street or building name'), 'oak');
    await t.pumpAndSettle();
    expect(find.text('Maple Road'), findsNothing);
    await t.tap(find.text('Oak Avenue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Oak Avenue'), findsOneWidget);
    expect(find.text('All residents'), findsNothing);

    await t.tap(find.text('Create a group chat for this update'));
    await t.pumpAndSettle();
    await t.tap(find.text('Post update'));
    await t.pumpAndSettle();
    final b = h.fake.lastBody('POST /updates');
    expect(b['audience'], 'sub');
    expect(b['streetIds'], ['s2']);
    expect(b['groupChat'], true);
    expect(find.text('Your update is now live.'), findsOneWidget);
  });

  testWidgets('UPD-02 discard sheet: Keep editing stays on the form', (t) async {
    final h = Harness();
    await h.pump(t, const UpdateFormScreen());
    await t.enterText(find.byType(TextField).at(0), 'Draft');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('Discard update?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.text('Create Update'), findsOneWidget);
  });

  testWidgets('UPD-05 detail: locations, document needs verification, options with pin limit', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/a', (_, _) => detail(update('a', 'Temporary road closure'), document: {'name': 'Notice.pdf', 'sizeBytes': 120000, 'fileType': 'PDF', 'downloads': 3}));
    h.fake.on('POST /updates/a/document/download', (_, _) => ApiException(403, 'VERIFICATION_REQUIRED', 'Verify your home address to do this.'));
    h.fake.on('POST /updates/a/pin', (_, _) => ApiException(409, 'PIN_LIMIT', 'You can only pin 3 updates'));
    await h.pump(t, const UpdateDetailScreen(id: 'a'));
    expect(find.text('Temporary road closure'), findsOneWidget);
    expect(find.textContaining('Maple Road, and Oak Avenue', findRichText: true), findsOneWidget);
    expect(find.text('PDF • 118 KB • 3 downloads'), findsOneWidget);

    await t.tap(find.bySemanticsLabel('Download Notice.pdf'));
    await t.pumpAndSettle();
    expect(find.text('Verify your home address'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Update options'));
    await t.pumpAndSettle();
    expect(find.text('Keep this update fixed at the top.'), findsOneWidget);
    expect(find.text('Mute update'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Resolve update'), findsNothing); // not the creator or Chair
    expect(find.text('Edit update'), findsNothing);
    await t.tap(find.text('Pin update'));
    await t.pumpAndSettle();
    expect(find.text('You can only pin 3 updates'), findsOneWidget);
  });

  testWidgets('UPD-09 mute asks for a duration', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/a', (_, _) => detail(update('a', 'Closure')));
    h.fake.on('PUT /updates/a/mute', (_, _) => {'muted': true});
    await h.pump(t, const UpdateDetailScreen(id: 'a'));
    await t.tap(find.byTooltip('Update options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mute update'));
    await t.pumpAndSettle();
    expect(buttonEnabled(t, 'Mute'), isFalse);
    await t.tap(find.text('For 24 hours'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mute'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('PUT /updates/a/mute')['duration'], '24h');
  });

  testWidgets('UPD-12 creator resolves after confirming', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/a', (_, _) => detail(update('a', 'Closure', mine: true, canResolve: true)));
    h.fake.on('POST /updates/a/resolve', (_, _) => {'message': 'Update has been resolved'});
    await h.pump(t, const UpdateDetailScreen(id: 'a'));
    await t.tap(find.byTooltip('Update options'));
    await t.pumpAndSettle();
    expect(find.text('Edit update'), findsOneWidget);
    expect(find.text('Delete update'), findsOneWidget);
    await t.tap(find.text('Resolve update'));
    await t.pumpAndSettle();
    expect(find.text('Resolve update?'), findsOneWidget);
    await t.tap(find.text('Resolve'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /updates/a/resolve'), isTrue);
    expect(find.text('Update has been resolved'), findsOneWidget);
  });

  testWidgets('UPD-06 committee adds an additional update; deleted ones show their notice', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/a', (_, _) => detail(update('a', 'Closure'), canAdd: true, additional: [
          {'id': 'x', 'deleted': true, 'text': 'Additional update is no longer available.', 'createdAt': '2026-03-11T10:00:00Z'},
        ]));
    h.fake.on('POST /updates/a/additional', (b, _) => {'additional': {}});
    await h.pump(t, const UpdateDetailScreen(id: 'a'));
    expect(find.text('Additional update is no longer available.'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Add an additional update'), 'Road reopens Friday');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Post additional update'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /updates/a/additional')['text'], 'Road reopens Friday');
  });

  testWidgets('UPD-05 resident cannot add additional updates', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/a', (_, _) => detail(update('a', 'Closure')));
    await h.pump(t, const UpdateDetailScreen(id: 'a'));
    expect(find.widgetWithText(TextField, 'Add an additional update'), findsNothing);
  });

  testWidgets('UCH-02 joining the update chat from the detail', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/a', (_, _) => detail(update('a', 'Closure', chatId: 'c1'), chat: {'id': 'c1', 'joined': false}));
    h.fake.on('POST /updates/a/chat/join', (_, _) => {'chatId': 'c1'});
    h.fake.on('GET /chats/c1', (_, _) => {'id': 'c1', 'type': 'update', 'name': 'Closure', 'myRole': 'member', 'canSend': true, 'settings': {}, 'memberCount': 3, 'at': '2026-03-11T10:00:00Z'});
    h.fake.on('GET /chats/c1/messages', (_, _) => {'messages': [], 'hasMore': false});
    h.fake.on('GET /chats/c1/members', (_, _) => {'members': []});
    h.fake.on('POST /chats/c1/read', (_, _) => {'ok': true});
    await h.pump(t, const UpdateDetailScreen(id: 'a'));
    await t.tap(find.byTooltip('Join group chat'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /updates/a/chat/join'), isTrue);
    expect(h.location, '/chats/c1');
  });

  testWidgets('UPD-05 deleted update shows the unavailable state', (t) async {
    final h = Harness();
    h.fake.on('GET /updates/a', (_, _) => ApiException(410, 'POST_DELETED', 'This post has been deleted by the author.', {'title': 'Post unavailable'}));
    await h.pump(t, const UpdateDetailScreen(id: 'a'));
    expect(find.text('Post unavailable'), findsOneWidget);
    expect(find.text('This post has been deleted by the author.'), findsOneWidget);
  });
}
