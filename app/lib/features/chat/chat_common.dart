import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';

/// A chat list cell from GET /chats (CHT-01.1).
class ChatCell {
  ChatCell(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get type => json['type'] ?? 'direct';
  bool get isDirect => type == 'direct';
  String get name => json['name'] ?? '';
  String? get iconUrl => json['iconUrl'];
  String? get otherUserId => json['otherUserId'];
  Map<String, dynamic>? get lastMessage => json['lastMessage'];
  bool get typing => json['typing'] == true;
  int get unread => json['unread'] ?? 0;
  bool get muted => json['muted'] == true;
  bool get pinned => json['pinned'] == true;
  bool get isRequest => json['isRequest'] == true;
  bool get blockedByMe => json['blockedByMe'] == true;
  bool get online => json['online'] == true;
  bool get left => json['left'] == true;
  bool get readOnly => json['readOnly'] == true;
  DateTime get at => DateTime.parse(json['at']).toLocal();
}

/// "1:23 pm" today, "Yesterday", then "13 Mar" (CHT-01.1).
String chatTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return clockTime(t);
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat(t.year == n.year ? 'd MMM' : 'd MMM yyyy').format(t);
}

String clockTime(DateTime t) => DateFormat('h:mm a').format(t).toLowerCase();

/// Date separator inside a conversation: "Today", "Yesterday", "April 24, 2025".
String dayLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('MMMM d, y').format(t);
}

/// Round chat icon: a person's photo or a group icon, with an online dot.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, this.url, this.group = false, this.size = 48, this.online = false});
  final String? url;
  final bool group;
  final double size;
  final bool online;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          url == null && group
              ? CircleAvatar(radius: size / 2, backgroundColor: KColors.surfaceSubtle, child: Icon(Icons.groups_outlined, size: size * 0.5, color: KColors.textSecondary))
              : Avatar(url, size: size),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Semantics(
                label: 'Online',
                child: Container(width: size * 0.26, height: size * 0.26, decoration: BoxDecoration(color: KColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
              ),
            ),
        ]),
      );
}

/// CHT-03.3: open (or start) a direct chat with [userId].
Future<void> openDirectChat(BuildContext context, String userId, {bool replace = false}) async {
  final api = context.api;
  final router = GoRouter.of(context);
  try {
    final r = await api.post('/chats/direct', {'userId': userId});
    final id = r['chat']['id'];
    replace ? router.pushReplacement('/chats/$id') : await router.push('/chats/$id');
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
  }
}

/// Pin, mute and delete for one chat (CHT-02).
Future<void> showChatOptions(BuildContext context, ChatCell c, VoidCallback onChanged) {
  final api = context.api;
  Future<void> call(Future<Map<String, dynamic>> Function() fn, String toast) async {
    try {
      await fn();
      if (context.mounted) showToast(context, toast);
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  return showActionSheet(context, [
    c.pinned
        ? SheetAction(Icons.push_pin_outlined, 'Unpin chat', () => call(() => api.delete('/chats/${c.id}/pin'), 'Chat unpinned'))
        : SheetAction(Icons.push_pin_outlined, 'Pin chat', () => call(() => api.post('/chats/${c.id}/pin'), 'Chat pinned')),
    c.muted
        ? SheetAction(Icons.volume_up_outlined, 'Unmute notifications', () => call(() => api.put('/chats/${c.id}/mute', {'duration': null}), 'Notifications unmuted'))
        : SheetAction(Icons.volume_off_outlined, 'Mute notifications', () async {
            final d = await pickMuteDuration(context, title: 'Mute notifications', body: "You won't be notified about new messages in this chat.");
            if (d != null) await call(() => api.put('/chats/${c.id}/mute', {'duration': d}), 'Notifications muted');
          }),
    SheetAction(Icons.delete_outline, 'Delete chat', () async {
      final ok = await confirmSheet(context, title: 'Delete this chat?', body: 'Messages will be removed for you only. New messages will bring the chat back.', confirm: 'Delete');
      if (ok) await call(() => api.post('/chats/${c.id}/hide'), 'Chat deleted');
    }, destructive: true),
  ]);
}
