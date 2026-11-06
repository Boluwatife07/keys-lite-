import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../core/scope.dart';
import '../feed/feed_screens.dart';
import '../feed/social.dart' show Avatar;
import '../community/community_tab.dart';
import '../updates/updates_list.dart';
import '../events/events_tab.dart';
import '../clubs/clubs_tab.dart';
import '../calendar/calendar.dart';
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
            ListTile(leading: const Icon(PhosphorIconsRegular.pencilSimple), title: const Text('Post'), onTap: () => Navigator.pop(c, 'post')),
            ListTile(leading: const Icon(PhosphorIconsRegular.chartBar), title: const Text('Poll'), onTap: () => Navigator.pop(c, 'poll')),
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
      const EventsTab(),
      const ClubsTab(),
    ];
    return Stack(children: [
      Scaffold(
        backgroundColor: KColors.surfaceDefault,
        // Figma "Home page header": 36 avatar, 36pt round buttons with 28pt
        // ChatCircleText and BellSimple, red count badges.
        // The Community tab draws its own Figma header (title + share).
        appBar: _tab == 1 ? null : PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: SafeArea(
            bottom: false,
            child: Container(
              color: KColors.surfaceDefault,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(children: [
                GestureDetector(
                  key: keys.profile,
                  onTap: () => context.push('/profile'),
                  child: Semantics(container: true, button: true, label: 'Profile', child: Avatar(me?.photoUrl, size: 36)),
                ),
                const Spacer(),
                _HeaderButton(icon: PhosphorIconsRegular.chatCircleText, label: _unreadChats > 0 ? 'Chats, $_unreadChats unread' : 'Chats', count: _unreadChats, onTap: _openChats),
                const SizedBox(width: 8),
                _HeaderButton(icon: PhosphorIconsRegular.bellSimple, label: 'Notifications', onTap: () => context.push('/notifications')),
              ]),
            ),
          ),
        ),
        body: pages[_tab],
        floatingActionButton: _tab == 0 && _homeTab == 0
            // Figma "FAB Button": 52pt yellow disc, 28pt plus, two soft shadows.
            ? Semantics(
                key: keys.compose,
                button: true,
                label: 'Create post',
                child: Tooltip(
                  message: 'Create post',
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 1)), BoxShadow(color: Color(0x24000000), blurRadius: 10, offset: Offset(0, 2))],
                    ),
                    child: Material(
                      color: KColors.brand,
                      shape: const CircleBorder(),
                      child: InkWell(customBorder: const CircleBorder(), onTap: _create, child: const Icon(PhosphorIconsRegular.plus, size: 28, color: Color(0xFF171717))),
                    ),
                  ),
                ),
              )
            : null,
        bottomNavigationBar: KeysTabBar(
          index: _tab,
          onTap: (i) => setState(() => _tab = i),
          items: [
            const KeysTab('Home', Ic28.homeOff, Ic28.homeOn),
            KeysTab('Community', Ic28.buildingOff, Ic28.buildingOn, key: keys.community, evenOdd: true),
            KeysTab('Services', Ic28.servicesOff, Ic28.servicesOff, key: keys.services),
            KeysTab('Events', Ic28.calendarOff, Ic28.calendarOn, key: keys.events),
            KeysTab('Clubs', Ic28.usersOff, Ic28.usersOn, key: keys.clubs),
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
      KeyedSubtree(key: keys.calendar, child: const UpcomingPreview()),
      Row(key: keys.tabs, children: [tabButton('Feed', 0), tabButton('Updates', 1, badge: unseenUpdates)]),
      Expanded(
        child: tab == 0
            ? Container(
                color: KColors.surfaceSubtle,
                child: PostList(
                  key: feedKey,
                  path: '/feed',
                  // Figma 3430:176990.
                  empty: EmptyState(
                    icon: PhosphorIconsRegular.mailbox,
                    top: 150,
                    title: 'No posts yet',
                    body: 'Posts and activities of your neighbors would be shown here',
                    actionLabel: 'Create post',
                    onAction: onCreate,
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
          IconButton(tooltip: 'Close', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => Navigator.pop(c, false)),
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

/// One bottom bar destination.
class KeysTab {
  const KeysTab(this.label, this.icon, this.activeIcon, {this.key, this.evenOdd = false});
  final String label;
  final String icon;
  final String activeIcon;
  final GlobalKey? key;
  final bool evenOdd;
}

/// Figma "Floating Nav bar": white bar with a top rule, five 49pt tabs,
/// 28pt ic28 icons, Inter SemiBold 12 labels (active #171717, rest #5e5e5e).
class KeysTabBar extends StatelessWidget {
  const KeysTabBar({super.key, required this.index, required this.items, required this.onTap});
  final int index;
  final List<KeysTab> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: KColors.surfaceDefault,
          border: Border(top: BorderSide(color: KColors.palette.brightness == Brightness.dark ? KColors.borderDefault : const Color(0xFFDDDDDD))),
        ),
        padding: const EdgeInsets.only(top: 20),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 49,
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: items[i].label,
                    child: InkResponse(
                      key: items[i].key,
                      onTap: () => onTap(i),
                      containedInkWell: true,
                      highlightShape: BoxShape.rectangle,
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Column(children: [
                            NavIcon(i == index ? items[i].activeIcon : items[i].icon, evenOdd: items[i].evenOdd && i != index, color: i == index ? KColors.textPrimary : KColors.textSecondary),
                            const SizedBox(height: 2),
                            Text(items[i].label,
                                maxLines: 1,
                                style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, height: 14 / 12, color: i == index ? KColors.textPrimary : KColors.textSecondary)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, required this.onTap, this.count = 0});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int count;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox.square(
            dimension: 36,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Icon(icon, size: 28, color: KColors.iconDefault),
              if (count > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: KColors.error, borderRadius: BorderRadius.circular(20), border: Border.all(color: KColors.surfaceDefault, width: 1)),
                    child: Center(child: Text('$count', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, height: 1, color: Colors.white))),
                  ),
                ),
            ]),
          ),
        ),
      );
}

