import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import 'chat_common.dart';
import 'conversation.dart' show copyGroupLink, pickNewAdmin;

/// CHT-13 / CHT-18: chat profile with shared Media, Links and Documents;
/// for groups also members, admin tools and settings.
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.id});
  final String id;
  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  Map<String, dynamic>? _chat;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>>? _past;
  int _requests = 0;

  String get _id => widget.id;
  bool get _admin => _chat?['myRole'] == 'admin';
  bool get _group => _chat?['type'] != 'direct';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.api;
    try {
      final c = await api.get('/chats/$_id');
      Map<String, dynamic>? m;
      int req = 0;
      if (c['type'] != 'direct') {
        m = await api.get('/chats/$_id/members');
        if (c['myRole'] == 'admin' && c['type'] == 'group') {
          try {
            req = ((await api.get('/chats/$_id/requests'))['requests'] as List).length;
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _chat = c;
        _members = m == null ? [] : List<Map<String, dynamic>>.from(m['members']);
        _past = m?['pastMembers'] == null ? null : List<Map<String, dynamic>>.from(m!['pastMembers']);
        _requests = req;
      });
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() fn, [String? toast]) async {
    try {
      final r = await fn();
      final msg = toast ?? r['message'];
      if (mounted && msg is String && msg.isNotEmpty) showToast(context, msg);
      _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _editText(String field, String title, String? current, int max) async {
    final c = TextEditingController(text: current ?? '');
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: KText.headingSmall),
          if (field == 'description') ...[
            const SizedBox(height: 4),
            Text('This group description is visible to current members and invited users.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          KeysTextField(controller: c, maxLength: max, maxLines: field == 'description' ? 4 : 1, autofocus: true),
          const SizedBox(height: 16),
          KeysButton('Save', onPressed: () => Navigator.pop(s, c.text.trim())),
        ]),
      ),
    );
    if (v == null || v == (current ?? '')) return;
    await _act(() => context.api.patch('/chats/$_id', {field: v}));
  }

  Future<void> _changeIcon() async {
    final api = context.api;
    final f = await context.deps.media.pickPhoto();
    if (f == null || !mounted) return;
    final problem = photoProblem(f);
    if (problem != null) return showToast(context, problem);
    await _act(() async {
      final id = (await api.upload('/media', bytes: f.bytes, filename: f.name, mime: f.mime, query: {'kind': 'photo'}))['id'];
      return api.patch('/chats/$_id', {'iconMediaId': id});
    });
  }

  void _memberActions(Map<String, dynamic> m) {
    final p = PersonRef(Map<String, dynamic>.from(m['person']));
    final me = context.session.me?.id;
    if (p.id == me) return;
    final api = context.api;
    final isAdmin = m['chatRole'] == 'admin';
    showActionSheet(context, [
      SheetAction(PhosphorIconsRegular.chatCircle, 'Message ${p.firstName}', () => openDirectChat(context, p.id)),
      SheetAction(PhosphorIconsRegular.user, 'View profile', () => context.push('/users/${p.id}')),
      if (_admin && _chat!['type'] == 'group') ...[
        isAdmin
            ? SheetAction(PhosphorIconsRegular.shieldSlash, 'Dismiss as admin', () => _act(() => api.delete('/chats/$_id/admins/${p.id}'), '${p.name} is no longer an admin'))
            : SheetAction(PhosphorIconsRegular.shieldCheck, 'Make group admin', () => _act(() => api.post('/chats/$_id/admins/${p.id}'), '${p.name} is now an admin')),
        SheetAction(PhosphorIconsRegular.userMinus, 'Remove from group', () async {
          final ok = await confirmSheet(context, title: 'Remove ${p.name}?', body: 'They will no longer be able to send or receive messages in this group.', confirm: 'Remove');
          if (ok) await _act(() => api.delete('/chats/$_id/members/${p.id}'));
        }, destructive: true),
      ],
    ]);
  }

  Future<void> _exit() async {
    final api = context.api;
    final router = GoRouter.of(context);
    final ok = await confirmSheet(context, title: 'Exit group?', body: "You won't be able to send or receive messages in this group.", confirm: 'Exit');
    if (!ok || !mounted) return;
    try {
      final r = await api.post('/chats/$_id/exit');
      if (mounted) showToast(context, r['message']);
      router.pop();
    } on ApiException catch (e) {
      if (e.code != 'ASSIGN_ADMIN') {
        if (mounted) showToast(context, e.message);
        return;
      }
      if (!mounted) return;
      final pick = await pickNewAdmin(context, _id, message: e.message);
      if (pick == null) return;
      await _act(() => api.post('/chats/$_id/exit', {'newAdminId': pick}));
      router.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _chat;
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final settings = Map<String, dynamic>.from(c['settings'] ?? {});
    final member = c['myRole'] != null;
    final isGroupType = c['type'] == 'group';
    final canAdd = member && isGroupType && (_admin || settings['membersCanInvite'] == true);
    final api = context.api;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, title: Text(_group ? 'Group info' : 'Chat info', style: KText.headingXSmall)),
        body: NestedScrollView(
          headerSliverBuilder: (_, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(children: [
                  Stack(children: [
                    ChatAvatar(url: c['iconUrl'], group: _group, size: 88),
                    if (_admin && _group)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: KColors.surfaceInverted,
                          shape: const CircleBorder(),
                          child: IconButton(tooltip: 'Change group icon', iconSize: 16, color: Colors.white, icon: const Icon(PhosphorIconsRegular.pencilSimple), onPressed: _changeIcon),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(child: Text(c['name'] ?? '', style: KText.headingSmall, textAlign: TextAlign.center)),
                    if (_admin && isGroupType) IconButton(tooltip: 'Edit group name', icon: const Icon(PhosphorIconsRegular.pencilSimple, size: 18), onPressed: () => _editText('name', 'Group name', c['name'], 100)),
                  ]),
                  if (_group) Text(plural(c['memberCount'] ?? 0, 'member'), style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                  if (_group) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _admin ? () => _editText('description', 'Group description', c['description'], 400) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          (c['description'] ?? '').toString().isEmpty ? (_admin ? 'Add group description' : 'No description') : c['description'],
                          textAlign: TextAlign.center,
                          style: KText.paragraphMedium.copyWith(color: (c['description'] ?? '').toString().isEmpty ? KColors.textLink : KColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                  if (!_group && c['otherUserId'] != null) ...[
                    const SizedBox(height: 12),
                    KeysButton('View profile', variant: ButtonVariant.outline, onPressed: () => context.push('/users/${c['otherUserId']}')),
                  ],
                  const SizedBox(height: 8),
                ]),
              ),
            ),
            if (_group)
              SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Divider(),
                  if (canAdd) ListTile(leading: const Icon(PhosphorIconsRegular.userPlus), title: const Text('Add members'), onTap: () => context.push('/chats/$_id/add').then((_) => _load())),
                  if (canAdd) ListTile(leading: const Icon(PhosphorIconsRegular.link), title: const Text('Copy group link'), onTap: () => copyGroupLink(context, _id)),
                  if (_admin && isGroupType) ListTile(leading: const Icon(PhosphorIconsRegular.slidersHorizontal), title: const Text('Group settings'), onTap: () => context.push('/chats/$_id/settings').then((_) => _load())),
                  if (_admin && _requests > 0)
                    ListTile(
                      leading: const Icon(PhosphorIconsRegular.userCheck),
                      title: const Text('Join requests'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: KColors.brand, borderRadius: BorderRadius.circular(KRadius.pill)),
                        child: Text('$_requests', style: KText.paragraphMediumSmall),
                      ),
                      onTap: () => context.push('/chats/$_id/requests').then((_) => _load()),
                    ),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Members', style: KText.paragraphMediumLarge)),
                  for (final m in _members)
                    ListTile(
                      leading: Avatar(m['person']['photoUrl'], size: 40),
                      title: Text(m['person']['id'] == context.session.me?.id ? 'You' : m['person']['name']),
                      subtitle: m['person']['role'] == null ? null : Text(m['person']['role'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                      trailing: m['chatRole'] == 'admin'
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFDDF2F0), borderRadius: BorderRadius.circular(4)),
                              child: Text('Admin', style: KText.paragraphMediumSmall.copyWith(color: KColors.selected)),
                            )
                          : null,
                      onTap: () => _memberActions(m),
                    ),
                  if (_past != null && _past!.isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Past members', style: KText.paragraphMediumLarge)),
                    for (final m in _past!)
                      ListTile(
                        leading: Avatar(m['person']['photoUrl'], size: 40),
                        title: Text(m['person']['name']),
                        subtitle: Text(m['reason'] == 'removed' ? 'Removed' : 'Left', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                      ),
                  ],
                  if (member && c['type'] != 'update') ListTile(leading: const Icon(PhosphorIconsRegular.signOut, color: KColors.error), title: Text('Exit group', style: TextStyle(color: KColors.error)), onTap: _exit),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.flag, color: KColors.error),
                    title: Text('Report group', style: TextStyle(color: KColors.error)),
                    onTap: () => showReportSheet(context, itemType: 'group_chat', itemId: _id, title: 'Report group', intro: 'Tell us why you are reporting this group chat. No one would be notified that you reported.'),
                  ),
                  const Divider(),
                ]),
              ),
            SliverToBoxAdapter(
              child: TabBar(
                labelColor: KColors.textPrimary,
                unselectedLabelColor: KColors.textSecondary,
                indicatorColor: KColors.textPrimary,
                labelStyle: KText.labelSemibold,
                tabs: const [Tab(text: 'Media'), Tab(text: 'Links'), Tab(text: 'Documents')],
              ),
            ),
          ],
          body: TabBarView(children: [
            _Shared(chatId: _id, tab: 'media', api: api),
            _Shared(chatId: _id, tab: 'links', api: api),
            _Shared(chatId: _id, tab: 'documents', api: api),
          ]),
        ),
      ),
    );
  }
}

/// CHT-18: shared items grouped by month.
class _Shared extends StatefulWidget {
  const _Shared({required this.chatId, required this.tab, required this.api});
  final String chatId;
  final String tab;
  final ApiClient api;
  @override
  State<_Shared> createState() => _SharedState();
}

class _SharedState extends State<_Shared> {
  List<Map<String, dynamic>>? _groups;
  @override
  void initState() {
    super.initState();
    widget.api.get('/chats/${widget.chatId}/shared', query: {'tab': widget.tab}).then((r) {
      if (mounted) setState(() => _groups = List<Map<String, dynamic>>.from(r['groups']));
    }).catchError((_) {
      if (mounted) setState(() => _groups = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = _groups;
    if (g == null) return const Center(child: CircularProgressIndicator());
    if (g.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text('No ${widget.tab} shared yet', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
      );
    }
    final api = widget.api;
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final group in g) ...[
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(group['label'], style: KText.overline)),
        if (widget.tab == 'media')
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final item in group['items'])
                for (final m in item['media'])
                  InkWell(
                    onTap: () => m['kind'] == 'video' ? context.push('/video', extra: api.absolute(m['url'])) : context.push('/media', extra: {'urls': [m['url']]}),
                    child: m['kind'] == 'video'
                        ? Container(color: Colors.black87, child: const Icon(PhosphorIconsFill.playCircle, color: Colors.white, semanticLabel: 'Video'))
                        : Image.network(api.absolute(m['url']), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: KColors.surfaceSubtle)),
                  ),
            ],
          )
        else
          for (final item in group['items'])
            if (widget.tab == 'links')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(PhosphorIconsRegular.link),
                title: Text(item['link']?['title'] ?? item['link']?['url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item['link']?['url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall.copyWith(color: KColors.textLink)),
                onTap: () => launchUrl(Uri.parse(item['link']['url']), mode: LaunchMode.externalApplication),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DocumentTile(
                  dense: true,
                  name: item['document']?['name'] ?? 'Document',
                  fileType: ((item['document']?['name'] ?? 'f.pdf') as String).split('.').last.toUpperCase(),
                  meta: fileSize(item['document']?['sizeBytes'] ?? 0),
                  onTap: () => launchUrl(Uri.parse(api.absolute(item['document']['url'])), mode: LaunchMode.externalApplication),
                ),
              ),
      ],
    ]);
  }
}

/// CHT-12: admin-only group settings.
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({super.key, required this.id});
  final String id;
  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  Map<String, dynamic>? _s;

  @override
  void initState() {
    super.initState();
    context.api.get('/chats/${widget.id}').then((r) {
      if (mounted) setState(() => _s = Map<String, dynamic>.from(r['settings']));
    }).catchError((_) {});
  }

  Future<void> _set(String key, bool v) async {
    final old = _s![key];
    setState(() => _s![key] = v);
    try {
      final r = await context.api.put('/chats/${widget.id}/settings', {key: v});
      if (mounted && (r['approved'] ?? 0) > 0) showToast(context, '${plural(r['approved'], 'pending member')} approved');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _s![key] = old);
      showToast(context, e.message);
    }
  }

  Widget _toggle(String key, String title, String subtitle) => SwitchListTile(
        title: Text(title, style: KText.paragraphLarge),
        subtitle: Text(subtitle, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        value: _s![key] == true,
        activeTrackColor: KColors.surfaceInverted,
        onChanged: (v) => _set(key, v),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, title: Text('Group settings', style: KText.headingXSmall)),
        body: _s == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                _toggle('membersCanMessage', 'Send messages', 'Allow all members to send messages'),
                _toggle('membersCanInvite', 'Add others', 'Allow all members to add others'),
                _toggle('approvalRequired', 'Approve new members', 'New members require admin approval to join this group chat'),
                if (context.session.me?.json['isCommittee'] == true) _toggle('committeeOnly', 'Committee board only', 'Only committee board members can join'),
              ]),
      );
}

/// CHT-14.5: approve or decline people waiting to join.
class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen({super.key, required this.id});
  final String id;
  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  List<Map<String, dynamic>>? _list;
  final Map<String, String> _done = {};

  @override
  void initState() {
    super.initState();
    context.api.get('/chats/${widget.id}/requests').then((r) {
      if (mounted) setState(() => _list = List<Map<String, dynamic>>.from(r['requests']));
    }).catchError((_) {});
  }

  Future<void> _decide(String userId, String action) async {
    try {
      await context.api.post('/chats/${widget.id}/requests/$userId/$action');
      if (mounted) setState(() => _done[userId] = action == 'approve' ? 'Approved' : 'Declined');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, title: Text('Join requests', style: KText.headingXSmall)),
        body: _list == null
            ? const Center(child: CircularProgressIndicator())
            : _list!.isEmpty
                ? Center(child: Text('No pending requests', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)))
                : ListView(children: [
                    for (final r in _list!)
                      ListTile(
                        leading: Avatar(r['person']['photoUrl'], size: 40),
                        title: Text(r['person']['name']),
                        subtitle: Text(timeAgo(DateTime.parse(r['requestedAt']).toLocal()), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                        trailing: _done[r['person']['id']] != null
                            ? Text(_done[r['person']['id']]!, style: KText.paragraphMediumSmall.copyWith(color: KColors.textSecondary))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(tooltip: 'Decline', icon: const Icon(PhosphorIconsRegular.x, color: KColors.error), onPressed: () => _decide(r['person']['id'], 'decline')),
                                IconButton(tooltip: 'Approve', icon: const Icon(PhosphorIconsRegular.check, color: KColors.success), onPressed: () => _decide(r['person']['id'], 'approve')),
                              ]),
                      ),
                  ]),
      );
}

/// CHT-14.4: opened from a group invite link.
class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key, required this.code});
  final String code;
  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> with Busy {
  Map<String, dynamic>? _info;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/chats/join/${widget.code}');
      if (mounted) setState(() => _info = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _join() async {
    final router = GoRouter.of(context);
    await run(() async {
      final r = await context.api.post('/chats/join/${widget.code}');
      if (r['state'] == 'member') {
        router.pushReplacement('/chats/${r['chatId']}');
      } else {
        setState(() => _info = {..._info!, 'state': r['state']});
      }
    });
  }

  Future<void> _cancel() async {
    await run(() async {
      await context.api.delete('/chats/join/${widget.code}');
      setState(() => _info = {..._info!, 'state': 'can_join'});
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    return KeysScaffold(
      header: const KeysHeader(),
      body: _error != null
          ? Padding(padding: const EdgeInsets.only(top: 64), child: Text(_error!.message, textAlign: TextAlign.center, style: KText.paragraphLarge))
          : i == null
              ? const Padding(padding: EdgeInsets.only(top: 64), child: Center(child: CircularProgressIndicator()))
              : Column(children: [
                  const SizedBox(height: 32),
                  const ChatAvatar(group: true, size: 96),
                  const SizedBox(height: 16),
                  Text(i['name'] ?? '', style: KText.headingMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(plural(i['memberCount'] ?? 0, 'member'), style: KText.paragraphLarge.copyWith(color: KColors.textSecondary)),
                  if (i['message'] != null) ...[
                    const SizedBox(height: 16),
                    Text(i['message'], textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                  ],
                ]),
      bottom: i == null
          ? null
          : switch (i['state']) {
              'member' => KeysButton('Open chat', onPressed: () => context.pushReplacement('/chats/${i['chatId']}')),
              'awaiting' => Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Awaiting admin approval', style: KText.paragraphMediumLarge),
                  const SizedBox(height: 12),
                  KeysButton('Cancel request', variant: ButtonVariant.secondary, loading: busy, onPressed: _cancel),
                ]),
              _ => KeysButton(i['approvalRequired'] == true ? 'Request to join' : 'Join group', loading: busy, onPressed: _join),
            },
    );
  }
}
