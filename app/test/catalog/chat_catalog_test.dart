import 'package:keys_lite/features/chat/chat_list.dart';
import 'package:keys_lite/features/chat/conversation.dart';
import '../harness.dart';
import 'catalog.dart';

Map<String, dynamic> person(String id, String name) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': null};

Map<String, dynamic> cell(String id, String name, {String type = 'direct', int unread = 0, bool muted = false, bool blocked = false, String? last, bool typing = false}) => {
      'id': id, 'type': type, 'name': name, 'iconUrl': null, 'otherUserId': type == 'direct' ? 'u-$id' : null,
      'lastMessage': last == null ? null : {'text': last, 'isMine': false, 'at': '2026-03-13T10:00:00Z'},
      'typing': typing, 'unread': unread, 'muted': muted, 'pinned': false, 'isRequest': false, 'blockedByMe': blocked,
      'online': false, 'left': false, 'readOnly': false, 'at': '2026-03-13T10:00:00Z',
    };

Map<String, dynamic> chat({Map<String, dynamic>? request, String name = 'Sydney Jimenez'}) => {
      ...cell('c1', name), 'description': null, 'myRole': 'member', 'isCreator': false, 'readOnly': false,
      'settings': {'membersCanMessage': true, 'membersCanInvite': true, 'approvalRequired': false, 'committeeOnly': false},
      'canSend': true, 'updateId': null, 'memberCount': 2, 'request': request, 'blockedByMe': false,
    };

int _n = 0;
Map<String, dynamic> msg(String text, {bool mine = false, String at = '2026-03-13T15:05:00Z'}) => {
      'id': 'm${_n++}', 'chatId': 'c1', 'kind': 'text', 'sender': mine ? person('u1', 'Amy Duncan') : person('u2', 'Sydney Jimenez'), 'isMine': mine,
      'text': text, 'deleted': false, 'media': [], 'document': null, 'voice': null, 'link': null, 'replyTo': null, 'forwarded': false,
      'system': null, 'reactions': [], 'status': mine ? 'read' : null, 'createdAt': at,
    };

void convo(Harness h, Map<String, dynamic> c, List messages) {
  h.fake.on('GET /chats/c1', (_, _) => c);
  h.fake.on('GET /chats/c1/messages', (_, _) => {'messages': messages, 'hasMore': false});
  h.fake.on('GET /chats/c1/members', (_, _) => {'members': []});
  h.fake.on('POST /chats/c1/read', (_, _) => {'ok': true});
}

void main() {
  shot('chat_list', () => const ChatListScreen(), setup: (h) => h.fake.on('GET /chats', (_, _) => {
        'chats': [
          cell('a', 'Parents of Modern Wharf', type: 'group', unread: 4, last: 'See you there'),
          cell('b', 'Sydney Jimenez', unread: 1, last: 'Wait, should i boil for 30 or 15 minutes?'),
          cell('c', 'Cameron Hale', muted: true, last: 'Hello, Amy. How are you today?'),
          cell('d', 'Modern Wharfield', type: 'group', last: 'Do not spam the group please'),
          cell('e', 'Bradlee Goff', blocked: true, last: 'You blocked this user'),
          cell('f', 'Liam Johnson', unread: 2, last: 'Looking forward to our meeting next week!'),
        ],
        'unread': 7,
      }));
  shot('conversation', () => const ConversationScreen(id: 'c1'), setup: (h) => convo(h, chat(), [
        msg(' Heyyy Amy! I’ve been alright, just swamped with work lately. How about you?', at: '2026-03-13T15:03:00Z'),
        msg('Same here honestly.', mine: true),
        msg('I’ve been trying to take short walks around the neighborhood to clear my head.', mine: true),
        msg('Oh? What’s new?'),
      ]));
  shot('message_request', () => const ConversationScreen(id: 'c1'), setup: (h) => convo(h, chat(name: 'Amy Duncan', request: {'role': 'recipient', 'prompt': ''}), [
        msg('Hey Sydney!', at: '2025-04-24T13:23:00Z'),
        msg('Long time no chat How have you been?', at: '2025-04-24T13:23:00Z'),
      ]));
}
