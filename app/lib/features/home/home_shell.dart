import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../core/scope.dart';
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
  bool _touring = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrompts) WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
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
      _HomeTab(keys: keys, tab: _homeTab, onTab: (i) => setState(() => _homeTab = i)),
      const _Placeholder(title: 'Community', body: 'Your committee board and community hub.'),
      const _Placeholder(title: 'Clubs', body: 'Join an existing group, create your own, or use a template.'),
      const _Placeholder(title: 'Services', body: 'Recommended vendors and bookings arrive with the Keys services release.'),
      const _Placeholder(title: 'Events', body: 'Browse community events, track the ones you have joined, or create something new.'),
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
            const SizedBox(width: 12),
            Expanded(child: Text(me?.communityName ?? '', style: KText.headingXSmall, overflow: TextOverflow.ellipsis)),
          ]),
          actions: [
            IconButton(key: keys.calendar, tooltip: 'Calendar', icon: const Icon(Icons.calendar_today_outlined), onPressed: () {}),
            IconButton(tooltip: 'Chats', icon: const Icon(Icons.chat_bubble_outline), onPressed: () {}),
            const SizedBox(width: 4),
          ],
        ),
        body: pages[_tab],
        floatingActionButton: _tab == 0 && _homeTab == 0
            ? FloatingActionButton(
                key: keys.compose,
                tooltip: 'Create post',
                backgroundColor: KColors.surfaceInverted,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                onPressed: () => context.push('/feed/compose'),
                child: const Icon(Icons.edit_outlined),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          backgroundColor: KColors.surfaceDefault,
          indicatorColor: KColors.brandSubtle,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.groups_outlined, key: keys.community), selectedIcon: const Icon(Icons.groups), label: 'Community'),
            NavigationDestination(icon: Icon(Icons.interests_outlined, key: keys.clubs), selectedIcon: const Icon(Icons.interests), label: 'Clubs'),
            NavigationDestination(icon: Icon(Icons.handyman_outlined, key: keys.services), selectedIcon: const Icon(Icons.handyman), label: 'Services'),
            NavigationDestination(icon: Icon(Icons.event_outlined, key: keys.events), selectedIcon: const Icon(Icons.event), label: 'Events'),
          ],
        ),
      ),
      if (_touring) LearningTour(keys: keys, onDone: _endTour),
    ]);
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.keys, required this.tab, required this.onTab});
  final TourKeys keys;
  final int tab;
  final ValueChanged<int> onTab;
  @override
  Widget build(BuildContext context) {
    Widget tabButton(String label, int i) => Expanded(
          child: InkWell(
            onTap: () => onTab(i),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == i ? KColors.textPrimary : KColors.borderDefault, width: tab == i ? 2 : 1))),
              child: Text(label, style: KText.labelSemibold.copyWith(color: tab == i ? KColors.textPrimary : KColors.textSecondary)),
            ),
          ),
        );
    return Column(children: [
      Row(key: keys.tabs, children: [tabButton('Feed', 0), tabButton('Updates', 1)]),
      Expanded(
        child: tab == 0
            ? const _Placeholder(title: 'No posts yet', body: 'Be the first to say hello to your neighbours.')
            : const _Placeholder(title: 'No updates yet', body: 'Official updates from your committee will show here.'),
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
