import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/feed_screens.dart' show EmptyState;
import '../updates/updates_list.dart' show SearchField;
import 'chat_common.dart';

const kChatTabs = {'all': 'All', 'primary': 'Primary', 'groups': 'Groups', 'clubs': 'Clubs', 'events': 'Events', 'services': 'Services', 'volunteering': 'Volunteering'};

/// CHT-01: chat list with search, tabs, recently active residents and New Chat.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String _tab = 'all';
  List<ChatCell>? _chats;
  List<PersonRef> _active = [];
  final _search = TextEditingController();
  Map<String, dynamic>? _results;
  StreamSubscription? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _loadActive();
    _sub = context.deps.realtime.events.listen((e) {
      if (e['type'] == 'message' || e['type'] == 'typing' || e['type'] == 'chat') {
        _load();
        // Typing dots fade after a few seconds.
        if (e['type'] == 'typing') Future.delayed(const Duration(seconds: 7), () => mounted ? _load() : null);
      }
    });
    _search.addListener(() {
      setState(() {});
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/chats', query: {'tab': _tab});
      if (mounted) setState(() => _chats = (r['chats'] as List).map((e) => ChatCell(Map<String, dynamic>.from(e))).toList());
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _loadActive() async {
    try {
      final r = await context.api.get('/chats/active');
      if (mounted) setState(() => _active = (r['people'] as List).map((e) => PersonRef(Map<String, dynamic>.from(e))).toList());
    } catch (_) {}
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return setState(() => _results = null);
    try {
      final r = await context.api.get('/chats/search', query: {'q': q});
      if (mounted && _search.text.trim() == q) setState(() => _results = r);
    } catch (_) {}
  }

  Future<void> _open(String id) async {
    await context.push('/chats/$id');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => context.pop()),
        title: Text('Chat', style: KText.headingXSmall),
      ),
      // Figma yellow pill with soft shadows (no outline).
      floatingActionButton: Semantics(
        button: true,
        label: 'New Chat',
        child: Container(
          height: 52,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(9999)),
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 1)), BoxShadow(color: Color(0x24000000), blurRadius: 10, offset: Offset(0, 2))],
          ),
          child: Material(
            color: KColors.brand,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () async {
                await context.push('/chats/new');
                _load();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ExcludeSemantics(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(PhosphorIconsRegular.plus, size: 22, color: Color(0xFF171717)),
                    const SizedBox(width: 8),
                    Text('New Chat', style: KText.labelSemibold.copyWith(fontSize: 15, color: const Color(0xFF171717))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SearchField(controller: _search, hint: 'Search...')),
        Expanded(child: _results != null ? _searchResults() : _list()),
      ]),
    );
  }

  Widget _list() {
    final chats = _chats;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_load(), _loadActive()]);
      },
      child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final e in kChatTabs.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _tab == e.key,
                  showCheckmark: false,
                  selectedColor: KColors.surfaceInverted,
                  labelStyle: KText.paragraphMedium.copyWith(color: _tab == e.key ? KColors.textInverse : KColors.textPrimary),
                  onSelected: (_) {
                    setState(() {
                      _tab = e.key;
                      _chats = null;
                    });
                    _load();
                  },
                ),
              ),
          ]),
        ),
        if (_active.isNotEmpty && _tab == 'all') ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Text('Recently active', style: KText.paragraphMediumLarge.copyWith(fontSize: 14))),
          SizedBox(
            height: 84,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final p in _active)
                Semantics(
                  container: true,
                  button: true,
                  label: 'Message ${p.name}',
                  child: InkWell(
                    onTap: () => openDirectChat(context, p.id).then((_) => _load()),
                    child: SizedBox(
                      width: 68,
                      child: ExcludeSemantics(
                        child: Column(children: [
                          ChatAvatar(url: p.photoUrl, size: 52, online: true),
                          const SizedBox(height: 4),
                          Text(p.firstName, style: KText.paragraphSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ],
        Container(height: 6, color: KColors.surfaceSubtle, margin: const EdgeInsets.only(top: 8)),
        if (chats == null)
          const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
        else if (chats.isEmpty)
          EmptyState(
            title: 'No chats yet',
            body: _tab == 'services' || _tab == 'volunteering' ? 'Chats about ${kChatTabs[_tab]!.toLowerCase()} will show here.' : 'Start a conversation with a neighbour or create a group.',
          )
        else
          for (final c in chats) ChatRow(c, onTap: () => _open(c.id), onLongPress: () => showChatOptions(context, c, _load)),
      ]),
    );
  }

  Widget _searchResults() {
    final chats = (_results!['chats'] as List).map((e) => ChatCell(Map<String, dynamic>.from(e))).toList();
    final msgs = List<Map<String, dynamic>>.from(_results!['messages']);
    if (chats.isEmpty && msgs.isEmpty) return const EmptyState(title: 'No results found', body: 'Try another keyword.');
    return ListView(children: [
      if (chats.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Chats', style: KText.overline)),
        for (final c in chats) ChatRow(c, onTap: () => _open(c.id)),
      ],
      if (msgs.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Messages', style: KText.overline)),
        for (final m in msgs)
          ListTile(
            title: Text(m['chatName'] ?? '', style: KText.paragraphMediumLarge),
            subtitle: Text('${m['isMine'] == true ? 'You' : (m['sender']?['firstName'] ?? '')}: ${m['text']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            trailing: Text(chatTime(DateTime.parse(m['createdAt']).toLocal()), style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
            onTap: () => context.push('/chats/${m['chatId']}', extra: {'focus': m['id']}),
          ),
      ],
    ]);
  }
}

/// One row: icon, name, preview or typing, time, unread badge, muted icon.
class ChatRow extends StatelessWidget {
  const ChatRow(this.c, {super.key, required this.onTap, this.onLongPress});
  final ChatCell c;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final last = c.lastMessage;
    final bold = c.unread > 0;
    Widget preview;
    if (c.typing) {
      preview = Row(children: [
        Text('typing', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
        const SizedBox(width: 6),
        const TypingDots(),
      ]);
    } else if (c.blockedByMe) {
      preview = Text('You blocked this user', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary));
    } else {
      final text = last == null ? (c.isRequest ? 'Message request' : 'No messages yet') : '${last['isMine'] == true && !c.isDirect ? 'You: ' : ''}${last['text']}';
      preview = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.paragraphMedium.copyWith(color: bold ? KColors.textPrimary : KColors.textSecondary));
    }
    return Semantics(
      container: true,
      button: true,
      label: '${c.name}${c.unread > 0 ? ', ${plural(c.unread, 'unread message')}' : ''}',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            ChatAvatar(url: c.iconUrl, group: !c.isDirect, online: c.isDirect && c.online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.paragraphLarge.copyWith(fontWeight: bold ? FontWeight.w600 : FontWeight.w400))),
                  if (c.pinned) Padding(padding: EdgeInsets.only(left: 4), child: Icon(PhosphorIconsFill.pushPin, size: 14, color: KColors.textTertiary, semanticLabel: 'Pinned')),
                ]),
                const SizedBox(height: 2),
                ExcludeSemantics(excluding: false, child: preview),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(chatTime(c.at), style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
              const SizedBox(height: 6),
              if (c.unread > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: KColors.brand, borderRadius: BorderRadius.circular(KRadius.pill)),
                  child: Text('${c.unread}', style: KText.paragraphMediumSmall.copyWith(color: KColors.staticBlack)),
                )
              else if (c.muted)
                Icon(PhosphorIconsRegular.speakerSimpleSlash, size: 18, color: KColors.textTertiary, semanticLabel: 'Muted')
              else
                const SizedBox(height: 20),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Animated yellow dots after "typing" (CHT-01.3).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KColors.brand.withValues(alpha: ((_c.value * 3 - i) % 3) < 1 ? 1 : 0.35),
              ),
            ),
        ]),
      );
}
