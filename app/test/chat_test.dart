import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/features/chat/chat_list.dart';
import 'package:keys_lite/features/chat/chat_people.dart';
import 'package:keys_lite/features/chat/conversation.dart';
import 'harness.dart';

Map<String, dynamic> person(String id, String name, {String? role}) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': role};

Map<String, dynamic> cell(String id, String name, {String type = 'direct', int unread = 0, bool muted = false, bool blocked = false, String? last}) => {
      'id': id, 'type': type, 'name': name, 'iconUrl': null, 'otherUserId': type == 'direct' ? 'u-$id' : null,
      'lastMessage': last == null ? null : {'text': last, 'isMine': false, 'at': '2026-03-13T10:00:00Z'},
      'typing': false, 'unread': unread, 'muted': muted, 'pinned': false, 'isRequest': false, 'blockedByMe': blocked,
      'online': false, 'left': false, 'readOnly': false, 'at': '2026-03-13T10:00:00Z',
    };

Map<String, dynamic> chat(String id, {String type = 'direct', String name = 'Sydney Jimenez', String? myRole = 'member', bool canSend = true, bool readOnly = false, Map<String, dynamic>? request, bool creator = false}) => {
      ...cell(id, name, type: type),
      'description': null, 'myRole': myRole, 'isCreator': creator, 'readOnly': readOnly,
      'settings': {'membersCanMessage': true, 'membersCanInvite': true, 'approvalRequired': false, 'committeeOnly': false},
      'canSend': canSend, 'updateId': null, 'memberCount': 3, 'request': request, 'blockedByMe': false,
    };

Map<String, dynamic> msg(String id, String text, {bool mine = false, String status = 'sent', String at = '2026-03-13T10:01:00Z'}) => {
      'id': id, 'chatId': 'c1', 'kind': 'text', 'sender': mine ? person('u1', 'Amy Duncan') : person('u2', 'Sydney Jimenez'), 'isMine': mine,
      'text': text, 'deleted': false, 'media': [], 'document': null, 'voice': null, 'link': null, 'replyTo': null, 'forwarded': false,
      'system': null, 'reactions': [], 'status': mine ? status : null, 'createdAt': at,
    };

void conversation(Harness h, Map<String, dynamic> c, [List messages = const []]) {
  h.fake.on('GET /chats/c1', (_, _) => c);
  h.fake.on('GET /chats/c1/messages', (_, _) => {'messages': messages, 'hasMore': false});
  h.fake.on('GET /chats/c1/members', (_, _) => {'members': [
        {'person': person('u1', 'Amy Duncan'), 'chatRole': 'admin'},
        {'person': person('u2', 'Ella White'), 'chatRole': 'member'},
      ]});
  h.fake.on('POST /chats/c1/read', (_, _) => {'ok': true});
}

void main() {
  testWidgets('CHT-01 list: unread badge, muted, blocked, recently active, New Chat', (t) async {
    final h = Harness();
    h.fake.on('GET /chats', (_, _) => {'chats': [
          cell('c1', 'Parents of Modern Wharf', type: 'group', unread: 4, last: 'Morning everyone'),
          cell('c2', 'Cameron Hale', muted: true, last: 'Hello, Amy.'),
          cell('c3', 'Bradlee Goff', blocked: true, last: 'hi'),
        ]});
    h.fake.on('GET /chats/active', (_, _) => {'people': [person('u5', 'Liam Johnson')]});
    h.fake.on('GET /chats/people', (_, _) => {'people': []});
    await h.pump(t, const ChatListScreen());
    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.speakerSimpleSlash), findsOneWidget);
    expect(find.text('You blocked this user'), findsOneWidget);
    expect(find.text('Recently active'), findsOneWidget);
    for (final tab in ['All', 'Primary', 'Groups']) {
      expect(find.text(tab), findsOneWidget);
    }
    await t.tap(find.text('New Chat'));
    await t.pumpAndSettle();
    expect(h.location, '/chats/new');
    expect(find.text('New group'), findsOneWidget);
  });

  testWidgets('CHT-04.1 sender at the 2-message limit sees the request notice, no composer', (t) async {
    final h = Harness();
    conversation(h, chat('c1', request: {'role': 'sender', 'remaining': 0}), [msg('m1', 'Hey Sydney!', mine: true), msg('m2', 'Long time no chat', mine: true)]);
    await h.pump(t, const ConversationScreen(id: 'c1'));
    expect(find.text('Your message request has been sent'), findsOneWidget);
    expect(find.text("You've reached your 2-message limit. You'll be able to send more messages once this user replies you."), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Write a message'), findsNothing);
    expect(find.textContaining('• Sent'), findsNWidgets(2));
  });

  testWidgets('CHT-04.2 recipient accepts the request', (t) async {
    final h = Harness();
    conversation(h, chat('c1', name: 'Amy Duncan', request: {'role': 'recipient', 'prompt': ''}), [msg('m1', 'Hey Sydney!')]);
    h.fake.on('POST /chats/c1/accept', (_, _) => {'ok': true});
    await h.pump(t, const ConversationScreen(id: 'c1'));
    expect(find.text('Do you want to let Amy Duncan message you?'), findsOneWidget);
    expect(find.text("If you accept, they will also be able to see when you've read their messages."), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /chats/c1/accept'), isTrue);
  });

  testWidgets('CHT-05 send a text; status shows after the time', (t) async {
    final h = Harness();
    conversation(h, chat('c1'));
    h.fake.on('POST /chats/c1/messages', (b, _) => {'message': msg('m9', b['text'], mine: true, at: DateTime.now().toUtc().toIso8601String())});
    h.fake.on('POST /chats/c1/typing', (_, _) => {'ok': true});
    await h.pump(t, const ConversationScreen(id: 'c1'));
    expect(find.byTooltip('Send message'), findsOneWidget); // no recorder in tests, so send instead of mic
    await t.enterText(find.widgetWithText(TextField, 'Write a message'), 'See you at 6');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /chats/c1/messages')['text'], 'See you at 6');
    expect(find.text('See you at 6'), findsOneWidget);
    expect(find.textContaining('• Sent'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  final notices = {
    'CHT-12.3 admins only': (chat('c1', type: 'group', name: 'G', canSend: false), 'Only admins can send messages in this group.'),
    'UCH-04.1 closed update chat': (chat('c1', type: 'update', name: 'G', readOnly: true), 'This chat is closed. You can still read the messages.'),
    'CHT-16 no longer a member': (chat('c1', type: 'group', name: 'G', myRole: null, canSend: false), 'You cannot send messages to this group because you are no longer a member'),
  };
  for (final e in notices.entries) {
    testWidgets('${e.key}: notice replaces the composer', (t) async {
      final h = Harness();
      conversation(h, e.value.$1);
      await h.pump(t, const ConversationScreen(id: 'c1'));
      expect(find.text(e.value.$2), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Write a message'), findsNothing);
    });
  }

  testWidgets('CHT-08 long press: reply bar, delete for everyone on own message', (t) async {
    final h = Harness();
    conversation(h, chat('c1'), [msg('m1', 'Are you coming?'), msg('m2', 'Yes!', mine: true)]);
    h.fake.on('DELETE /messages/m2', (_, q) => {'ok': true});
    await h.pump(t, const ConversationScreen(id: 'c1'));
    await t.longPress(find.text('Are you coming?'));
    await t.pumpAndSettle();
    for (final e in kReactions) {
      expect(find.text(e), findsOneWidget);
    }
    await t.tap(find.text('Reply'));
    await t.pumpAndSettle();
    expect(find.text('Replying to Sydney Jimenez'), findsOneWidget);

    await t.longPress(find.text('Yes!'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.text('Delete for everyone'), findsOneWidget);
    await t.tap(find.text('Delete for everyone'));
    await t.pumpAndSettle();
    expect(h.fake.calls.any((c) => c.$1 == 'DELETE /messages/m2'), isTrue);
  });

  testWidgets('CHT-08 others\' messages can only be deleted for me', (t) async {
    final h = Harness();
    conversation(h, chat('c1'), [msg('m1', 'Are you coming?')]);
    await h.pump(t, const ConversationScreen(id: 'c1'));
    await t.longPress(find.text('Are you coming?'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsNothing);
  });

  testWidgets('CHT-11 create group: pick members, then customise and create', (t) async {
    final h = Harness();
    h.fake.on('GET /chats/people', (_, _) => {'people': [person('u2', 'Ella White'), person('u3', 'Cameron Hale', role: 'Treasurer')]});
    h.fake.on('POST /chats/groups', (b, _) => {'chat': cell('g1', 'Parents', type: 'group')});
    conversation(h, chat('g1', type: 'group'));
    h.fake.on('GET /chats/g1', (_, _) => chat('g1', type: 'group', name: 'Parents', creator: true, myRole: 'admin'));
    h.fake.on('GET /chats/g1/messages', (_, _) => {'messages': [], 'hasMore': false});
    h.fake.on('GET /chats/g1/members', (_, _) => {'members': []});
    h.fake.on('POST /chats/g1/read', (_, _) => {'ok': true});
    h.fake.on('GET /chats', (_, _) => {'chats': []});
    h.fake.on('GET /chats/active', (_, _) => {'people': []});
    h.fake.on('GET /updates', (_, _) => {'updates': [], 'hasResolved': false, 'canCreate': false});
    h.fake.on('GET /feed', (_, _) => {'posts': [], 'next': null});
    await h.pump(t, const PickMembersScreen());
    expect(find.text('Select members'), findsOneWidget);
    expect(buttonEnabled(t, 'Next'), isFalse);
    await t.tap(find.text('Ella White'));
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Customise group'), findsOneWidget);
    expect(find.text('Committee board only'), findsNothing); // not a committee member
    await t.enterText(find.widgetWithText(TextField, 'Add a group name'), 'Parents');
    await t.tap(find.text('Approve new members'));
    await t.pumpAndSettle();
    await t.tap(find.text('Create group'));
    await t.pumpAndSettle();
    final b = h.fake.lastBody('POST /chats/groups');
    expect(b['name'], 'Parents');
    expect(b['memberIds'], ['u2']);
    expect(b['approvalRequired'], true);
    expect(h.location, '/chats/g1');
    expect(find.text('You created this group'), findsOneWidget);
  });

  testWidgets('CHT-16.2 the only admin assigns a new admin before leaving', (t) async {
    final h = Harness();
    conversation(h, chat('c1', type: 'group', name: 'Parents', myRole: 'admin'));
    var exits = 0;
    h.fake.on('POST /chats/c1/exit', (b, _) {
      exits++;
      if (b['newAdminId'] == null) return ApiException(409, 'ASSIGN_ADMIN', 'You are the only admin in this group, assign a new admin before leaving.');
      return {'ok': true, 'message': 'You are no longer a member of this group'};
    });
    await h.pump(t, const ConversationScreen(id: 'c1'));
    await t.tap(find.byTooltip('Chat options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Exit group'));
    await t.pumpAndSettle();
    await t.tap(find.text('Exit'));
    await t.pumpAndSettle();
    expect(find.text('Assign a new admin'), findsOneWidget);
    await t.tap(find.text('Ella White').last);
    await t.pumpAndSettle();
    expect(exits, 2);
    expect(h.fake.lastBody('POST /chats/c1/exit')['newAdminId'], 'u2');
  });
}
