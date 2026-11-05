import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../core/scope.dart';
import '../feed/feed_screens.dart';
import '../community/community_tab.dart';
import '../updates/updates_list.dart';
import 'dart:async';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'learning_tour.dart';

/// Home: Feed | Updates (News is out of Phase 1, polls live in the Feed).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.autoPrompts = true});
  final bool autoPrompts;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0; // bottom navigation
  int _homeTab = 0; // Feed | Updates
  final keys = TourKeys();
  final _feedKey = GlobalKey<PostListState>();
  bool _touring = false;
  int _unreadChats = 0;
  int _unseenUpdates = 0;
  StreamSubscription? _live;

  /// Badges: unread chats (not muted) and unread updates.
  Future<void> _counts() async {
    final api = context.api;
    try {
      final r = await api.get('/chats');
      final n = (r['chats'] as List).where((c) => c['muted'] != true && (c['unread'] ?? 0) > 0).length;
      if (mounted) setState(() => _unreadChats = n);
    } catch (_) {}
    try {
      final r = await api.get('/updates');
      final n = (r['updates'] as List).where((u) => u['seen'] == false).length;
      if (mounted) setState(() => _unseenUpdates = n);
    } catch (_) {}
  }

  Future<void> _openChats() async {
    await context.push('/chats');
    _counts();
  }

  /// POL-01.1: committee members choose Post or Poll; everyone else goes straight to a post.
  Future<void> _create() async {
    var poll = false;
    try {
      poll = (await context.api.get('/polls/can-create'))['canCreate'] == true;
    } catch (_) {}
    if (!mounted) return;
    String? kind = 'post';
    if (poll) {
      kind = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Post'), onTap: () => Navigator.pop(c, 'post')),
            ListTile(leading: const Icon(Icons.poll_outlined), title: const Text('Poll'), onTap: () => Navigator.pop(c, 'poll')),
          ]),
        ),
      );
    }
    if (kind == null || !mounted) return;
    final r = await context.push(kind == 'poll' ? '/polls/create' : '/feed/compose');
    if (r != null) _feedKey.currentState?.refresh();
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoPrompts) WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
    _counts();
    _live = context.deps.realtime.events.listen((e) {
      if (e['type'] == 'message') _counts();
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  /// ONB-25.1 welcome prompt first, then LRN-01.1 learning experience.
  Future<void> _firstRun() async {
    final me = context.session.me;
    if (me == null) return;
    if (me.showWelcomePrompt) {
      await showWelcomePrompt(context, me);
      if (!mounted) return;
      await context.api.post('/onboarding/welcome-prompt/done');
    }
    if (mounted && me.showLearning) setState(() => _touring = true);
  }

  Future<void> _endTour(String outcome) async {
    setState(() => _touring = false);
    await context.api.post('/learning/done', {'outcome': outcome});
    if (mounted) await context.session.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.session.me;
    final pages = [
      _HomeTab(
        keys: keys,
        feedKey: _feedKey,
        tab: _homeTab,
        onTab: (i) => setState(() => _homeTab = i),
        onCreate: _create,
        unseenUpdates: _unseenUpdates,
        onUnseen: (n) => setState(() => _unseenUpdates = n),
      ),
      const CommunityTab(),
      const _Placeholder(title: 'Services', body: 'Recommended vendors and bookings arrive with the Keys services release.'),
      const _Placeholder(title: 'Events', body: 'Browse community events, track the ones you have joined, or create something new.'),
      const _Placeholder(title: 'Clubs', body: 'Join an existing group, create your own, or use a template.'),
    ];
    return Stack(children: [
      Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 16,
          title: Row(children: [
            GestureDetector(
              key: keys.profile,
              onTap: () => context.push('/profile'),
              child: Semantics(
                container: true,
                button: true,
                label: 'Profile',
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: KColors.surfaceSubtle,
                  backgroundImage: me?.photoUrl == null ? null : NetworkImage(context.api.absolute(me!.photoUrl!)),
                  child: me?.photoUrl == null ? const Icon(Icons.person_outline, size: 18) : null,
                ),
              ),
            ),
            const Spacer(),
          ]),
          actions: [
            IconButton(
              tooltip: _unreadChats > 0 ? 'Chats, $_unreadChats unread' : 'Chats',
              icon: Badge(isLabelVisible: _unreadChats > 0, label: Text('$_unreadChats'), backgroundColor: KColors.error, child: const Icon(Icons.chat_bubble_outline)),
              onPressed: _openChats,
            ),
            IconButton(tooltip: 'Notifications', icon: const Icon(Icons.notifications_none), onPressed: () => context.push('/notifications')),
            const SizedBox(width: 4),
          ],
        ),
        body: pages[_tab],
        floatingActionButton: _tab == 0 && _homeTab == 0
            ? FloatingActionButton(
                key: keys.compose,
                tooltip: 'Create post',
                backgroundColor: KColors.brand,
                foregroundColor: KColors.textPrimary,
                shape: const CircleBorder(),
                onPressed: _create,
                child: const Icon(Icons.add, size: 28),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          backgroundColor: KColors.surfaceDefault,
          indicatorColor: KColors.brandSubtle,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.apartment_outlined, key: keys.community), selectedIcon: const Icon(Icons.apartment), label: 'Community'),
            NavigationDestination(icon: Icon(Icons.handyman_outlined, key: keys.services), selectedIcon: const Icon(Icons.handyman), label: 'Services'),
            NavigationDestination(icon: Icon(Icons.event_outlined, key: keys.events), selectedIcon: const Icon(Icons.event), label: 'Events'),
            NavigationDestination(icon: Icon(Icons.interests_outlined, key: keys.clubs), selectedIcon: const Icon(Icons.interests), label: 'Clubs'),
          ],
        ),
      ),
      if (_touring) LearningTour(keys: keys, onDone: _endTour),
    ]);
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.keys, required this.feedKey, required this.tab, required this.onTab, required this.onCreate, required this.unseenUpdates, required this.onUnseen});
  final int unseenUpdates;
  final ValueChanged<int> onUnseen;
  final TourKeys keys;
  final GlobalKey<PostListState> feedKey;
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    Widget tabButton(String label, int i, {int badge = 0}) => Expanded(
          child: InkWell(
            onTap: () => onTab(i),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == i ? KColors.textPrimary : KColors.borderDefault, width: tab == i ? 2 : 1))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: KText.labelSemibold.copyWith(color: tab == i ? KColors.textPrimary : KColors.textSecondary)),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: KColors.error, borderRadius: BorderRadius.circular(KRadius.pill)),
                    child: Text('$badge', style: KText.paragraphMediumSmall.copyWith(color: Colors.white, fontSize: 11)),
                  ),
                ],
              ]),
            ),
          ),
        );
    return Column(children: [
      // FED-01.1: Calendar preview above the tabs (calendar items arrive with the Calendar milestone).
      Padding(
        key: keys.calendar,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Text('Upcoming', style: KText.headingXSmall),
          const Spacer(),
          TextButton(onPressed: () {}, style: TextButton.styleFrom(foregroundColor: KColors.textPrimary), child: const Text('Calendar →')),
        ]),
      ),
      Row(key: keys.tabs, children: [tabButton('Feed', 0), tabButton('Updates', 1, badge: unseenUpdates)]),
      Expanded(
        child: tab == 0
            ? Container(
                color: KColors.surfaceSubtle,
                child: PostList(
                  key: feedKey,
                  path: '/feed',
                  empty: EmptyState(
                    title: 'No posts yet',
                    body: 'Posts and activities of your neighbors would be shown here',
                    action: KeysButton('Create post', onPressed: onCreate),
                  ),
                ),
              )
            : UpdatesTab(onUnseen: onUnseen),
      ),
    ]);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: KText.headingXSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary), textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// ONB-25.1: "Welcome to [Community]" with a pre-filled intro post.
Future<void> showWelcomePrompt(BuildContext context, Me me) async {
  final api = context.api;
  Map<String, dynamic> t;
  try {
    t = await api.get('/onboarding/welcome-post');
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  final post = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Welcome to ${t['community']}', style: KText.headingSmall)),
          IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c, false)),
        ]),
        const SizedBox(height: 8),
        Text('Say hello with a quick intro post. You can edit it first.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: KColors.borderDefault), borderRadius: BorderRadius.circular(KRadius.md)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['text'], style: KText.paragraphMedium),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(KRadius.sm), child: Image.asset('assets/images/community_live_street.png', height: 160, width: double.infinity, fit: BoxFit.cover)),
          ]),
        ),
        const SizedBox(height: 20),
        KeysButton('Post now', onPressed: () => Navigator.pop(c, true)),
      ]),
    ),
  );
  if (post == true && context.mounted) {
    await context.push('/feed/compose', extra: {'text': t['text'], 'welcomeImage': true});
  }
}
