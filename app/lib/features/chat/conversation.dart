import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import 'chat_common.dart';
import 'chat_list.dart' show TypingDots;

const kReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
const kChatPhotosMax = 10;
const kChatVideoBytes = 100 * 1024 * 1024;
const kChatDocBytes = 25 * 1024 * 1024;
const kVoiceMax = Duration(minutes: 10);

/// CHT-05 - CHT-10: one conversation, direct or group.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.id, this.focus});
  final String id;
  /// Message to scroll to (from search).
  final String? focus;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  Map<String, dynamic>? _chat;
  final List<Map<String, dynamic>> _messages = [];
  bool _hasMore = false;
  bool _loadingOlder = false;
  ApiException? _error;
  final Map<String, String> _names = {}; // userId -> first name, for typing
  final Map<String, DateTime> _typing = {};
  Map<String, dynamic>? _replyTo;
  String? _highlight;
  final _keys = <String, GlobalKey>{};
  final _scroll = ScrollController();
  StreamSubscription? _sub;
  Timer? _typingTick;
  bool _searching = false;
  final _searchCtl = TextEditingController();
  List<Map<String, dynamic>>? _matches;

  String get _id => widget.id;
  bool get _isDirect => _chat?['type'] == 'direct';

  @override
  void initState() {
    super.initState();
    _highlight = widget.focus;
    _loadChat();
    _loadMessages();
    _sub = context.deps.realtime.events.listen(_onEvent);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadOlder();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _typingTick?.cancel();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['chatId'] != _id) return;
    switch (e['type']) {
      case 'message':
        _loadMessages();
      case 'read':
        _loadMessages();
      case 'chat':
        _loadChat();
      case 'typing':
        setState(() => _typing[e['userId']] = DateTime.now().add(const Duration(seconds: 6)));
        _typingTick ??= Timer.periodic(const Duration(seconds: 1), (_) {
          final now = DateTime.now();
          if (!mounted) return;
          setState(() => _typing.removeWhere((_, until) => until.isBefore(now)));
          if (_typing.isEmpty) {
            _typingTick?.cancel();
            _typingTick = null;
          }
        });
    }
  }

  Future<void> _loadChat() async {
    try {
      final r = await context.api.get('/chats/$_id');
      if (!mounted) return;
      setState(() => _chat = r);
      if (r['type'] != 'direct') _loadMembers();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadMembers() async {
    try {
      final r = await context.api.get('/chats/$_id/members');
      if (!mounted) return;
      setState(() {
        for (final m in r['members']) {
          _names[m['person']['id']] = m['person']['firstName'] ?? m['person']['name'];
        }
      });
    } catch (_) {}
  }

  /// Newest page; merged so older pages stay loaded.
  Future<void> _loadMessages() async {
    try {
      final r = await context.api.get('/chats/$_id/messages');
      if (!mounted) return;
      final page = List<Map<String, dynamic>>.from(r['messages']);
      setState(() {
        if (_messages.isEmpty) _hasMore = r['hasMore'] == true;
        final ids = {for (final m in page) m['id']};
        final oldestNew = page.isEmpty ? null : page.first['createdAt'] as String;
        _messages.removeWhere((m) => ids.contains(m['id']) || (oldestNew != null && (m['createdAt'] as String).compareTo(oldestNew) >= 0));
        _messages.addAll(page);
        _messages.sort((a, b) => (a['createdAt'] as String).compareTo(b['createdAt']));
      });
      context.api.post('/chats/$_id/read').catchError((_) => <String, dynamic>{});
      if (_highlight != null) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_highlight!));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadOlder() async {
    if (!_hasMore || _loadingOlder || _messages.isEmpty) return;
    _loadingOlder = true;
    try {
      final r = await context.api.get('/chats/$_id/messages', query: {'before': DateTime.parse(_messages.first['createdAt']).toUtc().toIso8601String()});
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, List<Map<String, dynamic>>.from(r['messages']));
        _hasMore = r['hasMore'] == true;
      });
    } catch (_) {
    } finally {
      _loadingOlder = false;
    }
  }

  void _jumpTo(String id) {
    final k = _keys[id];
    if (k?.currentContext != null) {
      Scrollable.ensureVisible(k!.currentContext!, alignment: 0.5, duration: const Duration(milliseconds: 250));
      setState(() => _highlight = id);
      Future.delayed(const Duration(seconds: 2), () => mounted ? setState(() => _highlight = null) : null);
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    try {
      final r = await context.api.get('/chats/$_id/search', query: {'q': q.trim()});
      if (mounted) setState(() => _matches = List<Map<String, dynamic>>.from(r['matches']));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _act(Future<Map<String, dynamic>> Function() fn, {String? toast, bool reload = true}) async {
    try {
      final r = await fn();
      final msg = toast ?? r['message'];
      if (mounted && msg is String && msg.isNotEmpty) showToast(context, msg);
      if (reload) {
        _loadChat();
        _loadMessages();
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  void _menu() {
    final c = _chat!;
    final api = context.api;
    final muted = c['muted'] == true;
    final left = c['myRole'] == null;
    showActionSheet(context, [
      if (_isDirect && c['otherUserId'] != null) SheetAction(PhosphorIconsRegular.user, 'View profile', () => context.push('/users/${c['otherUserId']}')),
      if (!_isDirect) SheetAction(PhosphorIconsRegular.info, 'Group info', _openInfo),
      SheetAction(PhosphorIconsRegular.magnifyingGlass, 'Search', () => setState(() => _searching = true)),
      muted
          ? SheetAction(PhosphorIconsRegular.speakerSimpleHigh, 'Unmute notifications', () => _act(() => api.put('/chats/$_id/mute', {'duration': null}), toast: 'Notifications unmuted'))
          : SheetAction(PhosphorIconsRegular.speakerSimpleSlash, 'Mute notifications', () async {
              final d = await pickMuteDuration(context, title: 'Mute notifications', body: "You won't be notified about new messages in this chat.");
              if (d != null) await _act(() => api.put('/chats/$_id/mute', {'duration': d}), toast: 'Notifications muted');
            }),
      SheetAction(PhosphorIconsRegular.broom, 'Clear chat', () async {
        final ok = await confirmSheet(context, title: 'Clear this chat?', body: 'All messages will be removed for you. Others in the chat will still see them.', confirm: 'Clear');
        if (!ok) return;
        await _act(() => api.post('/chats/$_id/clear'), toast: 'Chat cleared', reload: false);
        setState(() => _messages.clear());
      }),
      if (_isDirect && c['otherUserId'] != null)
        c['blockedByMe'] == true
            ? SheetAction(PhosphorIconsRegular.prohibit, 'Unblock', _unblock)
            : SheetAction(PhosphorIconsRegular.prohibit, 'Block', () async {
                final p = PersonRef({'id': c['otherUserId'], 'name': c['name']});
                if (await blockPerson(context, p)) _loadChat();
              }),
      SheetAction(PhosphorIconsRegular.flag, _isDirect ? 'Report user' : 'Report group', () {
        if (_isDirect) {
          showReportSheet(context, itemType: 'user', itemId: c['otherUserId'], title: 'Report ${c['name']}', intro: "Tell us why you are reporting this user. They won't be notified that you reported them.");
        } else {
          showReportSheet(context, itemType: 'group_chat', itemId: _id, title: 'Report group', intro: 'Tell us why you are reporting this group chat. No one would be notified that you reported.');
        }
      }),
      if (!_isDirect && !left) SheetAction(PhosphorIconsRegular.signOut, 'Exit group', _exit, destructive: true),
      if (_isDirect || left)
        SheetAction(PhosphorIconsRegular.trash, 'Delete chat', () async {
          final router = GoRouter.of(context);
          final ok = await confirmSheet(context, title: 'Delete this chat?', body: 'Messages will be removed for you only.', confirm: 'Delete');
          if (!ok) return;
          await _act(() => api.post('/chats/$_id/hide'), reload: false);
          router.pop();
        }, destructive: true),
    ]);
  }

  Future<void> _unblock() async {
    await _act(() => context.api.delete('/users/${_chat!['otherUserId']}/block'));
  }

  Future<void> _openInfo() async {
    await context.push('/chats/$_id/info');
    if (!mounted) return;
    _loadChat();
    _loadMessages();
  }

  /// CHT-16: the only admin assigns a new admin before leaving.
  Future<void> _exit() async {
    final api = context.api;
    final ok = await confirmSheet(context, title: 'Exit group?', body: "You won't be able to send or receive messages in this group.", confirm: 'Exit');
    if (!ok || !mounted) return;
    try {
      final r = await api.post('/chats/$_id/exit');
      if (mounted) showToast(context, r['message']);
    } on ApiException catch (e) {
      if (e.code != 'ASSIGN_ADMIN' || !mounted) {
        if (mounted) showToast(context, e.message);
        return;
      }
      final pick = await pickNewAdmin(context, _id, message: e.message);
      if (pick == null) return;
      await _act(() => api.post('/chats/$_id/exit', {'newAdminId': pick}), reload: false);
    }
    _loadChat();
    _loadMessages();
  }

  void _messageActions(Map<String, dynamic> m) {
    if (m['kind'] == 'system' || m['deleted'] == true) return;
    final api = context.api;
    final canAct = _chat?['myRole'] != null || _isDirect;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (canAct)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final e in kReactions)
                  Semantics(
                    button: true,
                    label: 'React $e',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        Navigator.pop(c);
                        _act(() => api.post('/messages/${m['id']}/react', {'emoji': e}), toast: '', reload: true);
                      },
                      child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                  ),
              ]),
            ),
          if (canAct && _chat?['canSend'] == true)
            ListTile(leading: const Icon(PhosphorIconsRegular.arrowBendUpLeft), title: const Text('Reply'), onTap: () {
              Navigator.pop(c);
              setState(() => _replyTo = m);
            }),
          if ((m['text'] as String? ?? '').isNotEmpty)
            ListTile(leading: const Icon(PhosphorIconsRegular.copy), title: const Text('Copy'), onTap: () async {
              Navigator.pop(c);
              await Clipboard.setData(ClipboardData(text: m['text']));
              if (mounted) showToast(context, 'Message copied');
            }),
          ListTile(leading: const Icon(PhosphorIconsRegular.arrowBendUpRight), title: const Text('Forward'), onTap: () {
            Navigator.pop(c);
            context.push('/chats/forward', extra: {'messageIds': [m['id']]});
          }),
          ListTile(leading: const Icon(PhosphorIconsRegular.trash, color: KColors.error), title: Text('Delete', style: TextStyle(color: KColors.error)), onTap: () {
            Navigator.pop(c);
            _delete(m);
          }),
        ]),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final api = context.api;
    final scope = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Delete message?', style: KText.headingSmall)),
          ListTile(title: const Text('Delete for me'), onTap: () => Navigator.pop(c, 'me')),
          if (m['isMine'] == true) ListTile(title: Text('Delete for everyone', style: TextStyle(color: KColors.error)), onTap: () => Navigator.pop(c, 'all')),
          ListTile(title: const Text('Cancel'), onTap: () => Navigator.pop(c)),
        ]),
      ),
    );
    if (scope == null) return;
    try {
      await api.delete('/messages/${m['id']}?scope=$scope');
      setState(() {
        if (scope == 'me') {
          _messages.removeWhere((x) => x['id'] == m['id']);
        }
      });
      if (scope == 'all') _loadMessages();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _showReactions(Map<String, dynamic> m) async {
    try {
      final r = await context.api.get('/messages/${m['id']}/reactions');
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(r['reactions']);
      showModalBottomSheet(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Reactions', style: KText.headingSmall)),
            for (final x in list)
              ListTile(
                leading: Avatar(x['person']?['photoUrl'], size: 36),
                title: Text(x['person']?['name'] ?? ''),
                trailing: Text(x['emoji'], style: const TextStyle(fontSize: 22)),
              ),
          ]),
        ),
      );
    } catch (_) {}
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = _chat;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: _searching ? _searchBar() : _appBar(c),
      body: _error != null && c == null
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!.message, textAlign: TextAlign.center)))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  const Divider(height: 1),
                  Expanded(child: _matches != null && _searching ? _matchList() : _messageList(c)),
                  if (_typing.isNotEmpty) _typingLine(),
                  _bottom(c),
                ]),
    );
  }

  PreferredSizeWidget _appBar(Map<String, dynamic>? c) {
    String? subtitle;
    if (c != null) {
      if (_isDirect) {
        subtitle = c['online'] == true ? 'Online' : null;
      } else if (_names.isNotEmpty) {
        final me = context.session.me?.id;
        final others = _names.entries.where((e) => e.key != me).map((e) => e.value).take(3).toList();
        subtitle = [...others, if (c['myRole'] != null) 'You'].join(', ');
      }
    }
    return AppBar(
      backgroundColor: KColors.surfaceDefault,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => context.pop()),
      title: c == null
          ? null
          : Semantics(
              container: true,
              button: true,
              label: c['name'],
              child: InkWell(
                onTap: _isDirect ? (c['otherUserId'] == null ? null : () => context.push('/users/${c['otherUserId']}')) : _openInfo,
                child: Row(children: [
                  ChatAvatar(url: c['iconUrl'], group: !_isDirect, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['name'] ?? '', style: KText.paragraphMediumLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
      actions: [if (c != null) IconButton(tooltip: 'Chat options', icon: const Icon(PhosphorIconsRegular.dotsThreeVertical), onPressed: _menu)],
    );
  }

  PreferredSizeWidget _searchBar() => AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Close search',
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => setState(() {
            _searching = false;
            _matches = null;
            _searchCtl.clear();
          }),
        ),
        title: TextField(
          controller: _searchCtl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: const InputDecoration(hintText: 'Search in chat', border: InputBorder.none),
        ),
        actions: [IconButton(tooltip: 'Search', icon: const Icon(PhosphorIconsRegular.magnifyingGlass), onPressed: () => _search(_searchCtl.text))],
      );

  Widget _matchList() {
    if (_matches!.isEmpty) return Center(child: Text('No results found', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)));
    return ListView(children: [
      for (final m in _matches!)
        ListTile(
          title: Text(m['isMine'] == true ? 'You' : (m['sender']?['name'] ?? ''), style: KText.paragraphMediumLarge),
          subtitle: Text(m['text'] ?? m['document']?['name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(chatTime(DateTime.parse(m['createdAt']).toLocal()), style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
          onTap: () {
            setState(() {
              _searching = false;
              _matches = null;
              _highlight = m['id'];
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(m['id']));
          },
        ),
    ]);
  }

  Widget _messageList(Map<String, dynamic> c) {
    // Built oldest to newest, shown reversed so the newest sits at the bottom.
    final items = <Widget>[];
    if (!_hasMore && !_isDirect) items.add(_GroupIntro(chat: c, onChanged: _loadChat));
    DateTime? lastDay;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final t = DateTime.parse(m['createdAt']).toLocal();
      final day = DateTime(t.year, t.month, t.day);
      if (lastDay != day) {
        items.add(_DateSeparator(dayLabel(t)));
        lastDay = day;
      }
      final prev = i > 0 ? _messages[i - 1] : null;
      final sameSender = prev != null && prev['kind'] != 'system' && prev['sender']?['id'] == m['sender']?['id'] && DateTime.parse(prev['createdAt']).toLocal().day == t.day;
      final key = _keys.putIfAbsent(m['id'], () => GlobalKey());
      items.add(KeyedSubtree(
        key: key,
        child: m['kind'] == 'system'
            ? _SystemLine(m['text'])
            : MessageBubble(
                m: m,
                showSender: !_isDirect && !sameSender,
                highlight: _highlight == m['id'],
                onLongPress: () => _messageActions(m),
                onReactions: () => _showReactions(m),
                onReplyTap: m['replyTo'] == null ? null : () => _jumpTo(m['replyTo']['id']),
              ),
      ));
    }
    if (_hasMore) items.insert(0, const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    final reversed = items.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: reversed.length,
      itemBuilder: (_, i) => reversed[i],
    );
  }

  Widget _typingLine() {
    final names = _typing.keys.map((u) => _names[u] ?? (_isDirect ? (_chat?['name'] as String?) : null)).whereType<String>().toList();
    final who = names.isEmpty ? 'Someone' : names.join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(children: [
        Text('$who ${names.length > 1 ? 'are' : 'is'} typing', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        const SizedBox(width: 6),
        const TypingDots(),
      ]),
    );
  }

  Widget _notice(String title, [String? body, Widget? action]) => SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: KColors.borderDefault))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, textAlign: TextAlign.center, style: body == null ? KText.paragraphMedium.copyWith(color: KColors.textSecondary) : KText.headingXSmall),
            if (body != null) ...[const SizedBox(height: 8), Text(body, textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))],
            if (action != null) ...[const SizedBox(height: 16), action],
          ]),
        ),
      );

  Widget _bottom(Map<String, dynamic> c) {
    final api = context.api;
    final req = c['request'] as Map?;
    if (req != null && req['role'] == 'recipient') {
      // CHT-04.2: accept or delete a message request.
      return _notice(
        'Do you want to let ${c['name']} message you?',
        'If you accept, they will also be able to see when you\'ve read their messages.',
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextButton.icon(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  await _act(() => api.post('/chats/$_id/request/delete'), toast: 'Message request deleted', reload: false);
                  router.pop();
                },
                icon: const Icon(PhosphorIconsRegular.trash),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: KColors.error, backgroundColor: const Color(0xFFFDE8EC), shape: const StadiumBorder()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _act(() => api.post('/chats/$_id/accept')),
                icon: const Icon(PhosphorIconsRegular.check),
                label: const Text('Accept'),
                style: OutlinedButton.styleFrom(foregroundColor: KColors.textPrimary, side: const BorderSide(color: KColors.borderStrong), shape: const StadiumBorder()),
              ),
            ),
          ),
        ]),
      );
    }
    if (req != null && req['role'] == 'sender' && (req['remaining'] ?? 2) <= 0) {
      return _notice('Your message request has been sent', "You've reached your 2-message limit. You'll be able to send more messages once this user replies you.");
    }
    if (c['blockedByMe'] == true) {
      return InkWell(onTap: _unblock, child: _notice('You blocked this user. Tap to unblock.'));
    }
    if (c['myRole'] == null && !_isDirect) return _notice('You cannot send messages to this group because you are no longer a member');
    if (c['readOnly'] == true) return _notice('This chat is closed. You can still read the messages.');
    if (c['canSend'] != true) return _notice('Only admins can send messages in this group.');
    return Composer(
      chatId: _id,
      replyTo: _replyTo,
      onCancelReply: () => setState(() => _replyTo = null),
      onSent: (r) {
        setState(() => _replyTo = null);
        if (r['notice'] != null) showToast(context, r['notice']);
        if (r['message'] != null) {
          setState(() {
            _messages.removeWhere((m) => m['id'] == r['message']['id']);
            _messages.add(Map<String, dynamic>.from(r['message']));
          });
        }
        if (req != null) _loadChat();
      },
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          const Expanded(child: Divider(indent: 24, endIndent: 16)),
          Text(label, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          const Expanded(child: Divider(indent: 16, endIndent: 24)),
        ]),
      );
}

class _SystemLine extends StatelessWidget {
  const _SystemLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
        child: Text(text, textAlign: TextAlign.center, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
      );
}

/// Group header shown above the first message (CHT-11.4).
class _GroupIntro extends StatelessWidget {
  const _GroupIntro({required this.chat, required this.onChanged});
  final Map<String, dynamic> chat;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final settings = Map<String, dynamic>.from(chat['settings'] ?? {});
    final member = chat['myRole'] != null;
    final canAdd = member && chat['type'] == 'group' && (chat['myRole'] == 'admin' || settings['membersCanInvite'] == true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Column(children: [
        ChatAvatar(url: chat['iconUrl'], group: true, size: 72),
        const SizedBox(height: 12),
        Text(chat['isCreator'] == true ? 'You created this group' : chat['name'] ?? '', style: KText.paragraphMediumLarge, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(plural(chat['memberCount'] ?? 0, 'member'), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        if ((chat['description'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(chat['description'], textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        ],
        if (canAdd) ...[
          const SizedBox(height: 16),
          KeysButton('Add members', variant: ButtonVariant.outline, icon: const Icon(PhosphorIconsRegular.plus, size: 18), onPressed: () async {
            await context.push('/chats/${chat['id']}/add');
            onChanged();
          }),
          const SizedBox(height: 8),
          KeysButton('Copy group link', variant: ButtonVariant.outline, icon: const Icon(PhosphorIconsRegular.link, size: 18), onPressed: () => copyGroupLink(context, chat['id'])),
        ],
      ]),
    );
  }
}

/// CHT-14.3: create (once) and copy the invite link.
Future<void> copyGroupLink(BuildContext context, String chatId) async {
  final deps = context.deps;
  try {
    final r = await deps.api.post('/chats/$chatId/invite-link');
    await deps.sharer.copy(r['link']);
    if (context.mounted) showToast(context, r['message'] ?? 'Group link copied.');
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
  }
}

/// CHT-16.2: choose a member to become admin.
Future<String?> pickNewAdmin(BuildContext context, String chatId, {required String message}) async {
  final api = context.api;
  final me = context.session.me?.id;
  List<Map<String, dynamic>> members;
  try {
    members = List<Map<String, dynamic>>.from((await api.get('/chats/$chatId/members'))['members']).where((m) => m['person']['id'] != me).toList();
  } catch (_) {
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4), child: Text('Assign a new admin', style: KText.headingSmall)),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(message, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final m in members)
                ListTile(
                  leading: Avatar(m['person']['photoUrl'], size: 36),
                  title: Text(m['person']['name']),
                  onTap: () => Navigator.pop(c, m['person']['id'] as String),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

/// One message bubble with replies, media, documents, voice, links and reactions.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.m, required this.showSender, required this.onLongPress, required this.onReactions, this.onReplyTap, this.highlight = false});
  final Map<String, dynamic> m;
  final bool showSender;
  final bool highlight;
  final VoidCallback onLongPress;
  final VoidCallback onReactions;
  final VoidCallback? onReplyTap;

  static const _statusLabel = {'sent': 'Sent', 'delivered': 'Delivered', 'seen': 'Seen'};

  @override
  Widget build(BuildContext context) {
    final mine = m['isMine'] == true;
    final deleted = m['deleted'] == true;
    final sender = m['sender'] as Map?;
    final t = DateTime.parse(m['createdAt']).toLocal();
    final status = mine ? _statusLabel[m['status']] : null;
    final reactions = List<Map<String, dynamic>>.from(m['reactions'] ?? []);
    final text = (m['text'] as String?) ?? '';
    final media = List<Map<String, dynamic>>.from(m['media'] ?? []);
    final bg = highlight ? const Color(0xFFFFE89A) : (mine ? KColors.brandSubtle : KColors.surfaceSubtle);
    final radius = BorderRadius.only(
      topLeft: Radius.circular(mine ? 16 : 4),
      topRight: Radius.circular(mine ? 4 : 16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    final content = <Widget>[
      if (showSender && !mine && sender != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(sender['name'] ?? '', style: KText.paragraphMediumSmall.copyWith(fontSize: 11))),
      if (m['forwarded'] == true && !deleted)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(PhosphorIconsRegular.arrowBendUpRight, size: 14, color: KColors.textTertiary),
            const SizedBox(width: 4),
            Text('Forwarded', style: KText.paragraphSmall.copyWith(color: KColors.textTertiary, fontStyle: FontStyle.italic)),
          ]),
        ),
      if (m['replyTo'] != null && !deleted)
        InkWell(
          onTap: onReplyTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8), border: const Border(left: BorderSide(color: KColors.brand, width: 3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['replyTo']['sender'] ?? '', style: KText.paragraphMediumSmall.copyWith(fontSize: 11)),
              Text(m['replyTo']['preview'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ]),
          ),
        ),
      if (media.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: _MediaGrid(media)),
      if (m['document'] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: DocumentTile(
            dense: true,
            name: m['document']['name'] ?? 'Document',
            fileType: ((m['document']['name'] ?? 'file.pdf') as String).split('.').last.toUpperCase(),
            meta: fileSize(m['document']['sizeBytes'] ?? 0),
            onTap: () => launchUrl(Uri.parse(context.api.absolute(m['document']['url'])), mode: LaunchMode.externalApplication),
          ),
        ),
      if (m['voice'] != null) VoiceNotePlayer(url: context.api.absolute(m['voice']['url']), label: m['voice']['label'] ?? ''),
      if (m['link'] != null && !deleted) Padding(padding: const EdgeInsets.only(bottom: 6), child: _LinkCard(Map<String, dynamic>.from(m['link']))),
      if (text.isNotEmpty)
        Text(text, style: KText.paragraphLarge.copyWith(fontSize: 15, color: deleted ? KColors.textTertiary : null, fontStyle: deleted ? FontStyle.italic : null)),
      const SizedBox(height: 2),
      Align(
        alignment: Alignment.bottomRight,
        child: Text([clockTime(t), ?status].join(' • '), style: KText.paragraphSmall.copyWith(fontSize: 11, color: KColors.textTertiary)),
      ),
    ];

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: content),
    );

    return Padding(
      padding: EdgeInsets.only(top: showSender ? 10 : 4, bottom: reactions.isEmpty ? 2 : 0),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine && sender != null && showSender) ...[Avatar(sender['photoUrl'], size: 28), const SizedBox(width: 8)] else if (!mine && sender != null) const SizedBox(width: 36),
          Flexible(
            child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              Semantics(
                container: true,
                label: '${mine ? 'You' : sender?['name'] ?? ''}: ${text.isEmpty ? (m['voice'] != null ? 'Voice message' : m['document'] != null ? 'Document' : media.isNotEmpty ? 'Photo' : '') : text}',
                onLongPressHint: 'Message options',
                child: GestureDetector(onLongPress: onLongPress, child: bubble),
              ),
              if (reactions.isNotEmpty)
                Transform.translate(
                  offset: const Offset(0, -4),
                  child: InkWell(
                    onTap: onReactions,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(KRadius.pill), border: Border.all(color: KColors.borderDefault)),
                      child: Text(reactions.map((r) => r['count'] > 1 ? '${r['emoji']} ${r['count']}' : r['emoji']).join(' '), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid(this.media);
  final List<Map<String, dynamic>> media;
  @override
  Widget build(BuildContext context) {
    final api = context.api;
    final photos = media.where((x) => x['kind'] == 'photo').map((x) => x['url'] as String).toList();
    Widget tile(Map<String, dynamic> x, {double h = 180}) {
      final video = x['kind'] == 'video';
      return InkWell(
        onTap: () => video ? context.push('/video', extra: api.absolute(x['url'])) : context.push('/media', extra: {'urls': photos, 'index': photos.indexOf(x['url'])}),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: video
              ? Container(height: h, color: Colors.black87, alignment: Alignment.center, child: const Icon(PhosphorIconsFill.playCircle, color: Colors.white, size: 48, semanticLabel: 'Play video'))
              : Image.network(api.absolute(x['url']), height: h, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(height: h, color: KColors.surfaceMuted)),
        ),
      );
    }

    if (media.length == 1) return tile(media.first, h: 200);
    final shown = media.take(4).toList();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var i = 0; i < shown.length; i++)
          Stack(fit: StackFit.expand, children: [
            tile(shown[i], h: 120),
            if (i == 3 && media.length > 4)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: Text('+${media.length - 4}', style: KText.headingSmall.copyWith(color: Colors.white)),
                ),
              ),
          ]),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard(this.l);
  final Map<String, dynamic> l;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => launchUrl(Uri.parse(l['url']), mode: LaunchMode.externalApplication),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            if (l['image'] != null) Image.network(l['image'], width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 0)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l['title'] ?? l['url'], maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.paragraphMediumSmall),
                  if (l['description'] != null) Text(l['description'], maxLines: 2, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  Text(Uri.tryParse(l['url'] ?? '')?.host ?? '', style: KText.paragraphSmall.copyWith(color: KColors.textTertiary, fontSize: 11)),
                ]),
              ),
            ),
          ]),
        ),
      );
}

/// Play / pause with progress for a voice note (CHT-07.3).
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({super.key, required this.url, required this.label});
  final String url;
  final String label;
  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  AudioPlayer? _p;
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;

  AudioPlayer _player() {
    if (_p != null) return _p!;
    final p = AudioPlayer();
    p.onPositionChanged.listen((d) => mounted ? setState(() => _pos = d) : null);
    p.onDurationChanged.listen((d) => mounted ? setState(() => _len = d) : null);
    p.onPlayerComplete.listen((_) => mounted ? setState(() {
          _playing = false;
          _pos = Duration.zero;
        }) : null);
    return _p = p;
  }

  @override
  void dispose() {
    _p?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final p = _player();
    if (_playing) {
      await p.pause();
    } else {
      await p.play(UrlSource(widget.url));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _len.inMilliseconds == 0 ? 0.0 : _pos.inMilliseconds / _len.inMilliseconds;
    return SizedBox(
      width: 220,
      child: Row(children: [
        IconButton(tooltip: _playing ? 'Pause voice message' : 'Play voice message', icon: Icon(_playing ? PhosphorIconsFill.pauseCircle : PhosphorIconsFill.playCircle, size: 34), onPressed: _toggle),
        Expanded(child: LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 3, color: KColors.textPrimary, backgroundColor: KColors.borderDefault)),
        const SizedBox(width: 8),
        Text(widget.label, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
      ]),
    );
  }
}

/// CHT-05.1 / CHT-06 / CHT-07: text, photos, video, a document or a voice note.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.chatId, required this.onSent, this.replyTo, this.onCancelReply});
  final String chatId;
  final Map<String, dynamic>? replyTo;
  final VoidCallback? onCancelReply;
  final ValueChanged<Map<String, dynamic>> onSent;
  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> with Busy {
  final _c = TextEditingController();
  final List<PickedFile> _photos = [];
  PickedFile? _video;
  PickedFile? _doc;
  DateTime? _lastTyping;
  // voice
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTimer;

  bool get _hasAttachment => _photos.isNotEmpty || _video != null || _doc != null;
  bool get _ready => _c.text.trim().isNotEmpty || _hasAttachment;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      setState(() {});
      final now = DateTime.now();
      if (_c.text.isNotEmpty && (_lastTyping == null || now.difference(_lastTyping!).inSeconds >= 4)) {
        _lastTyping = now;
        context.api.post('/chats/${widget.chatId}/typing').catchError((_) => <String, dynamic>{});
      }
    });
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    if (_recording) context.deps.recorder?.cancel();
    super.dispose();
  }

  void _attach() {
    final media = context.deps.media;
    showActionSheet(context, [
      SheetAction(PhosphorIconsRegular.camera, 'Camera', () async => _addPhoto(await media.pickPhoto(camera: true))),
      SheetAction(PhosphorIconsRegular.image, 'Photo', () async => _addPhoto(await media.pickPhoto())),
      SheetAction(PhosphorIconsRegular.videoCamera, 'Video', () async {
        final f = await media.pickVideo();
        if (f == null || !mounted) return;
        if (f.size > kChatVideoBytes) return showToast(context, 'The video you selected is too large. Please choose a video of 100 MB or less.');
        final len = await context.deps.videoLength?.call(f);
        if (len != null && len.inMilliseconds > 60500 && mounted) return showToast(context, 'Videos can be up to 60 seconds long. Please trim your video.');
        setState(() {
          _photos.clear();
          _doc = null;
          _video = f;
        });
      }),
      SheetAction(PhosphorIconsRegular.fileText, 'Document', () async {
        final f = await media.pickDocument(extensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']);
        if (f == null || !mounted) return;
        if (f.size > kChatDocBytes) return showToast(context, 'The document you selected is too large. Please choose a file of 25 MB or less.');
        setState(() {
          _photos.clear();
          _video = null;
          _doc = f;
        });
      }),
    ]);
  }

  void _addPhoto(PickedFile? f) {
    if (f == null || !mounted) return;
    if (_photos.length >= kChatPhotosMax) return showToast(context, 'You can send up to $kChatPhotosMax photos at a time');
    final problem = photoProblem(f);
    if (problem != null) return showToast(context, problem);
    setState(() {
      _video = null;
      _doc = null;
      _photos.add(f);
    });
  }

  Future<String> _upload(PickedFile f, String kind) async =>
      (await context.api.upload('/media', bytes: f.bytes, filename: f.name, mime: f.mime, query: {'kind': kind}))['id'];

  Future<void> _send({String? voiceId}) async {
    final api = context.api;
    await run(() async {
      final body = <String, dynamic>{
        if (_c.text.trim().isNotEmpty && voiceId == null) 'text': _c.text.trim(),
        if (widget.replyTo != null) 'replyToId': widget.replyTo!['id'],
        'voiceId': ?voiceId,
      };
      if (voiceId == null) {
        if (_photos.isNotEmpty || _video != null) {
          body['mediaIds'] = [for (final p in _photos) await _upload(p, 'photo'), if (_video != null) await _upload(_video!, 'video')];
        }
        if (_doc != null) body['documentId'] = await _upload(_doc!, 'document');
      }
      final r = await api.post('/chats/${widget.chatId}/messages', body);
      if (voiceId == null) {
        _c.clear();
        setState(() {
          _photos.clear();
          _video = null;
          _doc = null;
        });
      }
      widget.onSent(r);
    });
  }

  Future<void> _startVoice() async {
    final rec = context.deps.recorder;
    if (rec == null) return;
    if (!await rec.start()) {
      if (mounted) showToast(context, 'Allow microphone access in Settings to send voice notes.');
      return;
    }
    setState(() {
      _recording = true;
      _recStart = DateTime.now();
    });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().difference(_recStart!) >= kVoiceMax) _stopVoice(send: true);
    });
  }

  Future<void> _stopVoice({required bool send}) async {
    final rec = context.deps.recorder!;
    _recTimer?.cancel();
    setState(() => _recording = false);
    if (!send) return rec.cancel();
    final f = await rec.stop();
    if (f == null || !mounted) return;
    try {
      final id = await _upload(f, 'audio');
      await _send(voiceId: id);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.replyTo;
    final elapsed = _recStart == null ? Duration.zero : DateTime.now().difference(_recStart!);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: KColors.borderDefault))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (reply != null)
            Container(
              color: KColors.surfaceSubtle,
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(children: [
                Container(width: 3, height: 32, color: KColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Replying to ${reply['isMine'] == true ? 'yourself' : reply['sender']?['name'] ?? ''}', style: KText.paragraphMediumSmall),
                    Text(reply['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  ]),
                ),
                IconButton(tooltip: 'Cancel reply', icon: const Icon(PhosphorIconsRegular.x, size: 18), onPressed: widget.onCancelReply),
              ]),
            ),
          if (_hasAttachment)
            SizedBox(
              height: 72,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
                for (var i = 0; i < _photos.length; i++)
                  _Pending(
                    label: 'Photo ${i + 1}',
                    onRemove: () => setState(() => _photos.removeAt(i)),
                    child: Image.memory(_photos[i].bytes, width: 60, height: 60, fit: BoxFit.cover),
                  ),
                if (_video != null) _Pending(label: 'Video', onRemove: () => setState(() => _video = null), child: Container(width: 60, height: 60, color: Colors.black87, child: const Icon(PhosphorIconsFill.videoCamera, color: Colors.white))),
                if (_doc != null)
                  _Pending(
                    label: _doc!.name,
                    onRemove: () => setState(() => _doc = null),
                    child: Container(
                      width: 160, height: 60, color: KColors.surfaceSubtle, padding: const EdgeInsets.all(8),
                      child: Row(children: [const Icon(PhosphorIconsRegular.fileText), const SizedBox(width: 6), Expanded(child: Text(_doc!.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall))]),
                    ),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: _recording
                ? Row(children: [
                    IconButton(tooltip: 'Cancel voice message', icon: const Icon(PhosphorIconsRegular.trash, color: KColors.error), onPressed: () => _stopVoice(send: false)),
                    const Icon(PhosphorIconsFill.circle, color: KColors.error, size: 14),
                    const SizedBox(width: 6),
                    Text('${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}', style: KText.paragraphLarge),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Recording…', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
                    _RoundButton(icon: PhosphorIconsFill.paperPlaneRight, tooltip: 'Send voice message', onTap: () => _stopVoice(send: true)),
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(tooltip: 'Add attachment', icon: const Icon(PhosphorIconsRegular.plusCircle, size: 28), onPressed: busy ? null : _attach),
                    Expanded(
                      child: TextField(
                        controller: _c,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 5000,
                        textCapitalization: TextCapitalization.sentences,
                        style: KText.paragraphLarge,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Write a message',
                          hintStyle: KText.paragraphLarge.copyWith(color: KColors.textTertiary),
                          filled: true,
                          fillColor: KColors.surfaceSubtle,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (busy)
                      const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    else if (_ready || context.deps.recorder == null)
                      _RoundButton(icon: PhosphorIconsFill.paperPlaneRight, tooltip: 'Send message', onTap: _ready ? () => _send() : null)
                    else
                      _RoundButton(icon: PhosphorIconsFill.microphone, tooltip: 'Record voice message', onTap: _startVoice),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: tooltip,
          child: Material(
            color: onTap == null ? KColors.surfaceMuted : KColors.brand,
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22, color: KColors.textPrimary))),
          ),
        ),
      );
}

class _Pending extends StatelessWidget {
  const _Pending({required this.child, required this.onRemove, required this.label});
  final Widget child;
  final VoidCallback onRemove;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
          Positioned(
            right: 2,
            top: 2,
            child: Semantics(
              button: true,
              label: 'Remove $label',
              child: InkWell(onTap: onRemove, child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(2), child: const Icon(PhosphorIconsRegular.x, size: 14, color: Colors.white))),
            ),
          ),
        ]),
      );
}
