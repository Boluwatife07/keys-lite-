import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../events/event_common.dart';
import '../feed/feed_screens.dart' show EmptyState;
import '../feed/post_card.dart';
import '../feed/social.dart';
import '../updates/updates_list.dart' show SearchField;
import 'clubs_tab.dart' show joinClub;

/// CLB-14.1: club event with the club pre-selected.
Future<void> startClubEvent(BuildContext context, String clubId) async {
  final router = GoRouter.of(context);
  try {
    final r = await context.api.get('/events/create-check', query: {'category': 'club'});
    if (r['ok'] != true) {
      if (context.mounted) showToast(context, r['message']);
      return;
    }
    await router.push('/events/create', extra: {'category': 'club', 'clubs': r['clubs'], 'clubId': clubId});
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
  }
}

/// CLB-05 visitor view and the member / President view.
class ClubDetailScreen extends StatefulWidget {
  const ClubDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  Map<String, dynamic>? _c;
  List<Post> _posts = [];
  bool _hiddenPosts = false;
  List<EventItem> _events = [];
  ApiException? _error;

  String get _id => widget.id;
  String? get _role => _c?['myRole'];
  bool get _manager => _role == 'president' || _role == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.api;
    try {
      final r = await api.get('/clubs/$_id');
      final a = await api.get('/clubs/$_id/announcements');
      final ev = await api.get('/clubs/$_id/events');
      if (!mounted) return;
      setState(() {
        _c = Map<String, dynamic>.from(r['club']);
        _posts = (a['announcements'] as List).map((p) => Post(Map<String, dynamic>.from(p))).toList();
        _hiddenPosts = a['membersOnlyHidden'] == true;
        _events = (ev['events'] as List).map((e) => EventItem(Map<String, dynamic>.from(e))).toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() fn, {bool pop = false}) async {
    final router = GoRouter.of(context);
    try {
      final r = await fn();
      if (mounted && r['message'] is String) showToast(context, r['message']);
      if (pop) {
        router.pop(true);
      } else {
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  void _share() {
    final c = _c!;
    final deps = context.deps;
    showActionSheet(context, [
      SheetAction(PhosphorIconsRegular.link, 'Copy link', () async {
        await deps.sharer.copy(c['shareLink']);
        if (mounted) showToast(context, 'Club link copied.');
      }),
      SheetAction(PhosphorIconsRegular.shareFat, 'Share via', () => deps.sharer.share('${c['shareText']} ${c['shareLink']}')),
    ]);
  }

  void _menu() {
    final c = _c!;
    final api = context.api;
    final member = c['isMember'] == true;
    showActionSheet(context, [
      if (c['canEdit'] == true)
        SheetAction(PhosphorIconsRegular.pencilSimple, 'Edit club details', () async {
          final r = await context.push('/clubs/$_id/edit', extra: c);
          if (r != null) _load();
        }),
      if (member) SheetAction(PhosphorIconsRegular.users, 'Members', () => context.push('/clubs/$_id/members').then((_) => _load())),
      if (_role == 'president' && c['status'] == 'active' && c['transfer'] == null) SheetAction(PhosphorIconsRegular.arrowsLeftRight, 'Transfer ownership', _transfer),
      if (_role == 'president' && c['transfer'] != null)
        SheetAction(PhosphorIconsRegular.arrowCounterClockwise, 'Withdraw ownership offer', () => _act(() => api.delete('/clubs/$_id/transfer'))),
      if (member)
        c['muted'] == true
            ? SheetAction(PhosphorIconsRegular.speakerSimpleHigh, 'Unmute notifications', () => _act(() => api.put('/clubs/$_id/mute', {'duration': null})))
            : SheetAction(PhosphorIconsRegular.speakerSimpleSlash, 'Mute notifications', () async {
                final d = await pickMuteDuration(context, title: 'Mute ${c['name']}', body: "You won't get notifications from this club.");
                if (d != null) await _act(() => api.put('/clubs/$_id/mute', {'duration': d}));
              }),
      SheetAction(PhosphorIconsRegular.shareNetwork, 'Share', _share),
      if (_role != 'president') SheetAction(PhosphorIconsRegular.flag, 'Report club', () => showReportSheet(context, itemType: 'club', itemId: _id, title: 'Report club', intro: 'Tell us why you are reporting this club')),
      if (member && _role != 'president')
        SheetAction(PhosphorIconsRegular.signOut, 'Leave club', () async {
          final ok = await confirmSheet(context, title: 'Leave club', body: "Are you sure you want to leave ${c['name']}? You will no longer have access to this club's content.", confirm: 'Leave');
          if (ok) await _act(() => api.post('/clubs/$_id/leave'));
        }, destructive: true),
      if (_role == 'president' && c['status'] == 'active') SheetAction(PhosphorIconsRegular.trash, 'Delete club', _delete, destructive: true),
    ]);
  }

  // CLB-11
  Future<void> _transfer() async {
    final api = context.api;
    final pick = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => _PickMember(clubId: _id)));
    if (pick == null || !mounted) return;
    final ok = await confirmSheet(
      context,
      title: 'Transfer ownership?',
      body: '${pick['name']} will become the President of ${_c!['name']} if they accept. Once transferred, you will be removed from the club.',
      confirm: 'Transfer',
    );
    if (ok) await _act(() => api.post('/clubs/$_id/transfer', {'userId': pick['id']}));
  }

  // CLB-12
  Future<void> _delete() async {
    final api = context.api;
    final name = _c!['name'];
    final first = await confirmSheet(context, title: 'Delete this club?', body: 'Instead of deleting the club, you can transfer ownership to another member so the club can continue.', confirm: 'Delete anyways', cancel: 'Transfer ownership');
    if (!mounted) return;
    if (!first) return;
    final sure = await confirmSheet(context, title: 'Delete $name', body: 'Deleting this club will permanently erase all its data in 48hours. Members will be told and club events will be cancelled.', confirm: 'Delete', destructive: true);
    if (!sure || !mounted) return;
    try {
      final r = await api.post('/clubs/$_id/delete');
      if (!mounted) return;
      await confirmSheet(context, title: r['title'], body: r['message'], confirm: 'OK', cancel: 'Close');
      _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  void _about() {
    final c = _c!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'], style: KText.headingSmall),
            const SizedBox(height: 8),
            Text(c['description'] ?? '', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 12),
            Text('Free • ${c['category']}', style: KText.paragraphMediumSmall),
            const SizedBox(height: 4),
            Text('Created on ${DateFormat('d MMMM y').format(DateTime.parse(c['createdAt']).toLocal())}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(PhosphorIconsRegular.megaphone), title: const Text('Announcement'), onTap: () => Navigator.pop(c, 'post')),
          ListTile(leading: const Icon(PhosphorIconsRegular.calendarDots), title: const Text('Club event'), onTap: () => Navigator.pop(c, 'event')),
        ]),
      ),
    );
    if (!mounted || v == null) return;
    if (v == 'post') {
      final r = await context.push('/feed/compose', extra: {'clubId': _id, 'clubName': _c!['name']});
      if (r != null) _load();
    } else {
      await startClubEvent(context, _id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(), body: EmptyState(title: 'Club not available', body: _error!.message));
    final c = _c;
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final member = c['isMember'] == true;
    final transfer = c['transfer'] as Map?;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      floatingActionButton: _manager && c['status'] == 'active'
          ? FloatingActionButton(heroTag: 'club-create', tooltip: 'Create in club', backgroundColor: KColors.brand, foregroundColor: KColors.staticBlack, shape: const CircleBorder(), onPressed: _create, child: const Icon(PhosphorIconsRegular.plus, size: 28))
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            backgroundColor: KColors.surfaceDefault,
            foregroundColor: Colors.white,
            leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30, shadows: [Shadow(blurRadius: 6)]), onPressed: () => context.pop()),
            actions: [
              IconButton(tooltip: 'Share club', icon: const Icon(PhosphorIconsRegular.shareNetwork, shadows: [Shadow(blurRadius: 6)]), onPressed: _share),
              IconButton(tooltip: 'Club options', icon: const Icon(PhosphorIconsRegular.dotsThreeVertical, shadows: [Shadow(blurRadius: 6)]), onPressed: _menu),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: c['coverUrl'] == null
                  ? Container(color: KColors.surfaceInverted)
                  : Image.network(context.api.absolute(c['coverUrl']), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: KColors.surfaceInverted)),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (c['status'] == 'closing')
                Container(
                  width: double.infinity,
                  color: KColors.errorSubtle,
                  padding: const EdgeInsets.all(12),
                  child: Text('This club will be closed permanently on ${DateFormat('d MMM, h:mma').format(DateTime.parse(c['closingAt']).toLocal())}.', style: KText.paragraphMedium.copyWith(color: KColors.error)),
                ),
              if (transfer != null && transfer['forMe'] == true) _TransferOffer(transferId: transfer['id'], clubName: c['name'], onDone: _load),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'About ${c['name']}',
                      child: InkWell(
                        onTap: _about,
                        child: Row(children: [
                          Flexible(child: Text(c['name'], style: KText.headingSmall, overflow: TextOverflow.ellipsis)),
                          const Icon(PhosphorIconsRegular.caretRight),
                        ]),
                      ),
                    ),
                  ),
                  if (c['chatId'] != null) IconButton(tooltip: 'Club group chat', icon: const Icon(PhosphorIconsRegular.chatText), onPressed: () => context.push('/chats/${c['chatId']}')),
                ]),
              ),
              if (_role == 'president' && transfer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    Text('Transfer status', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(PhosphorIconsRegular.hourglass, size: 14), const SizedBox(width: 4), Text(transfer['status'], style: KText.paragraphSmall)]),
                    ),
                  ]),
                ),
              if (!member) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['description'] ?? '', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text('Free • ${c['category']} • Created on ${DateFormat('d MMM y').format(DateTime.parse(c['createdAt']).toLocal())}', style: KText.paragraphSmall),
                  ]),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(children: [
                  Expanded(child: Text(c['membersText'] ?? '${c['memberCount']} members', style: KText.paragraphMedium)),
                  TextButton(onPressed: () => context.push('/clubs/$_id/members').then((_) => _load()), child: const Text('View all')),
                ]),
              ),
              _sectionHeader('Upcoming events', 'View all →', () => context.push('/clubs/$_id/events')),
              if (_events.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(children: [
                    Expanded(child: Text('No upcoming events.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
                    if (_manager && c['status'] == 'active') TextButton(onPressed: () => startClubEvent(context, _id).then((_) => _load()), child: const Text('Create an event')),
                  ]),
                )
              else
                SizedBox(
                  height: 290,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                    for (final e in _events) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: EventCard(e, width: 280)),
                  ]),
                ),
              Divider(height: 24, thickness: 6, color: KColors.surfaceSubtle),
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Activities', style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
              if (_posts.isEmpty && !_hiddenPosts)
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No activities yet', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)))),
              for (final p in _posts) ...[PostCard(post: p, showClub: false, onChanged: (_) => _load()), Divider(height: 8, thickness: 6, color: KColors.surfaceSubtle)],
              if (_hiddenPosts)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
                  child: Column(children: [
                    const Icon(PhosphorIconsRegular.lock),
                    const SizedBox(height: 8),
                    Text('Join ${c['name']}', style: KText.paragraphMediumLarge),
                    const SizedBox(height: 4),
                    Text('To view messages, see all activities and participate in club events you have to be a member of this club.', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                  ]),
                ),
              const SizedBox(height: 96),
            ]),
          ),
        ]),
      ),
      bottomNavigationBar: member || c['status'] != 'active'
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: KeysButton('Join club', onPressed: () async {
                  if (await joinClub(context, _id, c['name'])) _load();
                }),
              ),
            ),
    );
  }

  Widget _sectionHeader(String t, String action, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(children: [
          Expanded(child: Text(t, style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
          TextButton(onPressed: onTap, style: TextButton.styleFrom(foregroundColor: KColors.textPrimary), child: Text(action)),
        ]),
      );
}

/// CLB-11.3: the recipient answers the ownership offer.
class _TransferOffer extends StatelessWidget {
  const _TransferOffer({required this.transferId, required this.clubName, required this.onDone});
  final String transferId;
  final String clubName;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    Future<void> go(String a) async {
      try {
        final r = await context.api.post('/club-transfers/$transferId/$a');
        if (context.mounted) showToast(context, r['message']);
        onDone();
      } on ApiException catch (e) {
        if (context.mounted) showToast(context, e.message);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Club Ownership Transfer', style: KText.paragraphMediumLarge),
        const SizedBox(height: 4),
        Text('You have been offered ownership of $clubName. As President you will manage members, admins and the club.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: KeysButton('Decline', variant: ButtonVariant.secondary, onPressed: () => go('decline'))),
          const SizedBox(width: 8),
          Expanded(child: KeysButton('Accept', onPressed: () => go('accept'))),
        ]),
      ]),
    );
  }
}

/// CLB-11.1: choose who receives ownership.
class _PickMember extends StatelessWidget {
  const _PickMember({required this.clubId});
  final String clubId;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('Transfer ownership', style: KText.headingXSmall)),
        body: FutureBuilder(
          future: context.api.get('/clubs/$clubId/members'),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final members = List<Map<String, dynamic>>.from(s.data!['members']).where((m) => m['role'] != 'president').toList();
            return ListView(children: [
              Padding(padding: const EdgeInsets.all(16), child: Text('Select who you would like to transfer the ownership of the club to.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
              if (members.isEmpty) const EmptyState(title: 'No members yet', body: 'Invite residents to your club first.'),
              for (final m in members)
                ListTile(
                  leading: Avatar(m['person']['photoUrl'], size: 40),
                  title: Text(m['person']['name']),
                  subtitle: Text(m['roleLabel']),
                  onTap: () => Navigator.pop(context, Map<String, dynamic>.from(m['person'])),
                ),
            ]);
          },
        ),
      );
}

/// CLB-05.2 / CLB-10: members with roles; President and admins manage.
class ClubMembersScreen extends StatefulWidget {
  const ClubMembersScreen({super.key, required this.id});
  final String id;
  @override
  State<ClubMembersScreen> createState() => _ClubMembersScreenState();
}

class _ClubMembersScreenState extends State<ClubMembersScreen> {
  final _q = TextEditingController();
  Map<String, dynamic>? _d;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(() {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), _load);
    });
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/clubs/${widget.id}/members', query: _q.text.trim().isEmpty ? null : {'q': _q.text.trim()});
      if (mounted) setState(() => _d = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() fn) async {
    try {
      final r = await fn();
      if (mounted) showToast(context, r['message']);
      _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  void _options(Map<String, dynamic> m) {
    final my = _d!['myRole'];
    final p = PersonRef(Map<String, dynamic>.from(m['person']));
    final api = context.api;
    final id = widget.id;
    if (p.id == context.session.me?.id) return;
    final canRemove = (my == 'president' && m['role'] != 'president') || (my == 'admin' && m['role'] == 'member');
    showActionSheet(context, [
      SheetAction(PhosphorIconsRegular.user, 'View profile', () => context.push('/users/${p.id}')),
      if (my == 'president' && m['role'] == 'member')
        SheetAction(PhosphorIconsRegular.shieldCheck, 'Make an admin', () async {
          final ok = await confirmSheet(context, title: 'Make ${p.name} an admin?', body: 'Are you sure you want to give ${p.name} admin access? They will be able to remove members, create club events and post club activities', confirm: 'Make admin');
          if (ok) await _act(() => api.post('/clubs/$id/admins/${p.id}'));
        }),
      if (my == 'president' && m['role'] == 'admin')
        SheetAction(PhosphorIconsRegular.shieldSlash, 'Dismiss as admin', () async {
          final ok = await confirmSheet(context, title: 'Dismiss ${p.name}?', body: '${p.name} will no longer be able to remove members, create club events or post club activities.', confirm: 'Dismiss');
          if (ok) await _act(() => api.delete('/clubs/$id/admins/${p.id}'));
        }),
      if (canRemove)
        SheetAction(PhosphorIconsRegular.userMinus, 'Remove ${p.firstName}', () async {
          final ok = await confirmSheet(context, title: 'Remove ${p.name}', body: 'Are you sure you want to remove ${p.name} from the club?', confirm: 'Remove', destructive: true);
          if (ok) await _act(() => api.delete('/clubs/$id/members/${p.id}'));
        }, destructive: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Members', style: KText.headingXSmall),
          if (d != null) Text(d['countLabel'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        ]),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SearchField(controller: _q, hint: 'Search members')),
              if (d['myRole'] != null)
                ListTile(
                  leading: CircleAvatar(backgroundColor: KColors.brand, child: Icon(PhosphorIconsRegular.link, color: KColors.staticBlack)),
                  title: const Text('Invite via link'),
                  onTap: () async {
                    final api = context.api;
                    final deps = context.deps;
                    final c = await api.get('/clubs/${widget.id}');
                    await deps.sharer.copy(c['club']['inviteLink']);
                    if (context.mounted) showToast(context, 'Club link copied.');
                  },
                ),
              if (d['myRole'] != null)
                ListTile(
                  leading: CircleAvatar(backgroundColor: KColors.surfaceSubtle, child: Icon(PhosphorIconsRegular.userPlus, color: KColors.textPrimary)),
                  title: const Text('Invite members'),
                  onTap: () => context.push('/clubs/${widget.id}/invite'),
                ),
              for (final m in List<Map<String, dynamic>>.from(d['members']))
                ListTile(
                  leading: Avatar(m['person']['photoUrl'], size: 40),
                  title: Text(m['person']['id'] == context.session.me?.id ? 'You' : m['person']['name']),
                  subtitle: Text(m['roleLabel']),
                  trailing: d['myRole'] == 'president' || d['myRole'] == 'admin' ? const Icon(PhosphorIconsRegular.dotsThree) : null,
                  onTap: () => _options(m),
                ),
            ]),
    );
  }
}

/// CLB-14.3: club events by status.
class ClubEventsScreen extends StatefulWidget {
  const ClubEventsScreen({super.key, required this.id});
  final String id;
  @override
  State<ClubEventsScreen> createState() => _ClubEventsScreenState();
}

class _ClubEventsScreenState extends State<ClubEventsScreen> {
  String _status = 'upcoming';
  List<EventItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _items = null);
    try {
      final r = await context.api.get('/clubs/${widget.id}/events', query: {'status': _status});
      if (mounted) setState(() => _items = (r['events'] as List).map((e) => EventItem(Map<String, dynamic>.from(e))).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('Club events', style: KText.headingXSmall)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            for (final s in ['upcoming', 'completed', 'cancelled'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s[0].toUpperCase() + s.substring(1)),
                  selected: _status == s,
                  showCheckmark: false,
                  selectedColor: KColors.surfaceInverted,
                  labelStyle: KText.paragraphMedium.copyWith(color: _status == s ? KColors.textInverse : KColors.textPrimary),
                  onSelected: (_) {
                    _status = s;
                    _load();
                  },
                ),
              ),
          ]),
          const SizedBox(height: 12),
          if (_items == null)
            const Center(child: CircularProgressIndicator())
          else if (_items!.isEmpty)
            EmptyState(title: 'No events', body: _status == 'upcoming' ? 'No upcoming events.' : 'Nothing here yet.')
          else
            for (final e in _items!) Padding(padding: const EdgeInsets.only(bottom: 16), child: EventCard(e)),
        ]),
      );
}
