import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../../widgets/tab_header.dart';
import '../feed/feed_screens.dart' show EmptyState;
import '../updates/updates_list.dart' show SearchField;
import '../feed/social.dart' show confirmSheet;
import 'event_common.dart';
import 'event_detail.dart' show showRatingSheet;

const kTagIcons = <String, IconData>{
  'All': PhosphorIconsRegular.squaresFour,
  'Music': PhosphorIconsRegular.musicNotes,
  'Culture': PhosphorIconsRegular.maskHappy,
  'Networking': PhosphorIconsRegular.treeStructure,
  'Food & Drink': PhosphorIconsRegular.forkKnife,
  'Fashion': PhosphorIconsRegular.tShirt,
  'Education': PhosphorIconsRegular.graduationCap,
  'Tech': PhosphorIconsRegular.desktop,
  'Social': PhosphorIconsRegular.usersThree,
  'Others': PhosphorIconsRegular.dotsThree,
};

/// EVT-04 / EVT-11: create from scratch or from a template.
Future<void> startEvent(BuildContext context, {Map<String, dynamic>? template, String? clubId}) async {
  final router = GoRouter.of(context);
  final pick = template != null && template['category'] != null
      ? await _checkOnly(context, template['category'])
      : await pickEventCategory(context);
  if (pick == null) return;
  await router.push('/events/create', extra: {'category': pick.category, 'clubs': pick.clubs, 'template': template?['data'], 'clubId': clubId});
}

Future<({String category, List<Map<String, dynamic>> clubs})?> _checkOnly(BuildContext context, String category) async {
  try {
    final r = await context.api.get('/events/create-check', query: {'category': category});
    if (r['ok'] == true) return (category: category, clubs: List<Map<String, dynamic>>.from(r['clubs'] ?? []));
    if (context.mounted) showToast(context, r['message']);
  } on ApiException catch (e) {
    if (context.mounted) {
      if (e.code == 'VERIFICATION_REQUIRED') return pickEventCategory(context);
      showToast(context, e.message);
    }
  }
  return null;
}

/// EVT-01 / EVT-02: Events tab with Discover and My events.
class EventsTab extends StatefulWidget {
  const EventsTab({super.key});
  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _discover = GlobalKey<_DiscoverState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _popups());
  }

  /// EVT-25.1: cancelled pop-ups, then EVT-24.2 rating prompts.
  Future<void> _popups() async {
    final api = context.api;
    try {
      final r = await api.get('/events/cancelled-popups');
      for (final p in List<Map<String, dynamic>>.from(r['popups'])) {
        if (!mounted) return;
        await confirmSheet(context, title: p['title'], body: p['message'], confirm: 'OK', cancel: 'Close');
        await api.post('/tickets/${p['ticketId']}/cancel-seen');
      }
      final rp = await api.get('/events/rating-prompts');
      final prompts = List<Map<String, dynamic>>.from(rp['prompts']);
      if (prompts.isNotEmpty && mounted) await showRatingSheet(context, EventItem(prompts.first));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        Column(children: [
          // Figma 4031:14770: avatar, centred "Events", search; Discover / My events.
          TabPageHeader('Events', actionIcon: PhosphorIconsRegular.magnifyingGlass, actionLabel: 'Search events', onAction: () => context.push('/events/search')),
          KeysTabs(controller: _tabs, labels: const ['Discover', 'My events']),
          Expanded(child: TabBarView(controller: _tabs, children: [_Discover(key: _discover), const _MyEvents()])),
        ]),
        Positioned(
          right: 16,
          bottom: 24,
          child: KeysFab(
            label: 'Create event',
            onTap: () async {
              await startEvent(context);
              _discover.currentState?._load();
            },
          ),
        ),
      ]);
}

class _Discover extends StatefulWidget {
  const _Discover({super.key});
  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  Map<String, dynamic>? _d;
  String _tag = 'All';
  final _pager = PageController(viewportFraction: 0.92);
  Timer? _auto;
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() {
    super.initState();
    _load();
    context.api.get('/events/templates').then((r) {
      if (mounted) setState(() => _templates = List<Map<String, dynamic>>.from(r['templates']));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/events/discover', query: _tag == 'All' ? null : {'tag': _tag});
      if (!mounted) return;
      setState(() => _d = r);
      // EVT-01.1: trending cards advance every 5 seconds.
      _auto?.cancel();
      final n = (r['trending'] as List).length;
      if (n > 1) {
        _auto = Timer.periodic(const Duration(seconds: 5), (_) {
          if (!_pager.hasClients) return;
          final next = ((_pager.page ?? 0).round() + 1) % n;
          _pager.animateToPage(next, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
        });
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final trending = (d['trending'] as List).map((e) => EventItem(Map<String, dynamic>.from(e))).toList();
    final soon = (d['happeningSoon'] as List).map((e) => EventItem(Map<String, dynamic>.from(e))).toList();
    final tags = List<String>.from(d['tags']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (trending.isNotEmpty) ...[
          _Heading('Trending'),
          SizedBox(
            height: 250,
            child: PageView(controller: _pager, children: [
              for (final e in trending) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: EventCard(e)),
            ]),
          ),
        ],
        if (_templates.isNotEmpty) ...[
          _Heading('Create your event in one click', subtitle: 'Choose from ready-made event templates.', action: 'View all →', onAction: () => context.push('/events/templates')),
          // Figma: 329pt cards, 12pt apart, 16pt side margins.
          SizedBox(
            height: 284,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _templates.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => TemplateCard(_templates[i], width: 329),
            ),
          ),
        ],
        // Figma: 48pt discs, 12pt labels, 81pt apart, 46pt below the templates.
        const SizedBox(height: 46),
        SizedBox(
          height: 76,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final t in tags)
              Semantics(
                button: true,
                selected: _tag == t,
                label: t,
                child: InkWell(
                  borderRadius: BorderRadius.circular(KRadius.md),
                  onTap: () {
                    setState(() => _tag = t);
                    _load();
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 81),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ExcludeSemantics(
                        child: Column(children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: _tag == t ? KColors.brand : KColors.surfaceSubtle),
                            child: Icon(kTagIcons[t] ?? PhosphorIconsRegular.tag, size: 24, color: _tag == t ? KColors.staticBlack : KColors.iconDefault),
                          ),
                          const SizedBox(height: 8),
                          Text(t, style: KText.paragraphSmall, maxLines: 1),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        _Heading('Happening soon', action: 'Event calendar →', onAction: () => context.push('/calendar', extra: {'eventsOnly': true})),
        if (soon.isEmpty)
          // Figma: 136pt disc, 64pt CalendarDots, 14/24 body.
          const EmptyState(
            icon: PhosphorIconsRegular.calendarDots,
            iconSize: 64,
            top: 48,
            bodyWidth: 320,
            bodyHeight: 24 / 14,
            title: 'No events yet',
            body: 'Discover new events hosted by other residents. Click on the + button to create an event.',
          )
        else
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [for (final e in soon) EventRow(e)])),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.subtitle, this.action, this.onAction});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600)),
              if (subtitle != null) Text(subtitle!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ]),
          ),
          // Figma "View all →": 13pt secondary link.
          if (action != null)
            Semantics(
              button: true,
              child: InkWell(onTap: onAction, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(action!, style: KText.paragraphMedium.copyWith(fontSize: 13, color: KColors.textSecondary)))),
            ),
        ]),
      );
}

/// Template card: picture, name, description, "Use template".
class TemplateCard extends StatelessWidget {
  const TemplateCard(this.t, {super.key, this.width});
  final Map<String, dynamic> t;
  final double? width;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Container(
          clipBehavior: Clip.antiAlias,
          // Figma template card: 12pt corners, 123pt picture, 16pt name, 14/20 description.
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: KColors.borderDefault), color: KColors.surfaceDefault),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (t['image'] != null) Image.asset('assets/images/${t['image']}', height: 123, width: double.infinity, fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['name']}${t['personal'] == true ? '' : ' template'}', style: KText.paragraphLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(t['data']?['description'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                const SizedBox(height: 9),
                SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, foregroundColor: KColors.textInverse, shape: const StadiumBorder(), textStyle: KText.labelSemibold.copyWith(fontSize: 13)),
                    onPressed: () => startEvent(context, template: t),
                    child: const Text('Use template'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
}

/// EVT-11.1: all templates, ready-made then personal.
class EventTemplatesScreen extends StatelessWidget {
  const EventTemplatesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('Event templates', style: KText.headingXSmall)),
        body: FutureBuilder(
          future: context.api.get('/events/templates'),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final all = [...List<Map<String, dynamic>>.from(s.data!['templates']), ...List<Map<String, dynamic>>.from(s.data!['personal'])];
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final t in all) Padding(padding: const EdgeInsets.only(bottom: 16), child: TemplateCard(t)),
            ]);
          },
        ),
      );
}

const _mineTabs = {'attending': 'Attending', 'saved': 'Saved', 'hosting': 'Hosting', 'cohosting': 'Co-hosting'};
const _empty = {
  'attending': "Events you've gotten tickets for would be shown here.",
  'saved': 'Events you save would appear here.',
  'hosting': 'Events you create will appear here. Click on the + button to create an event.',
  'cohosting': 'Events you co-hosts would be shown here.',
};

class _MyEvents extends StatefulWidget {
  const _MyEvents();
  @override
  State<_MyEvents> createState() => _MyEventsState();
}

class _MyEventsState extends State<_MyEvents> {
  String _tab = 'attending';
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
      final r = await context.api.get('/events/mine', query: {'tab': _tab, if (_tab != 'saved') 'status': _status});
      if (mounted) setState(() => _items = (r['events'] as List).map((e) => EventItem(Map<String, dynamic>.from(e))).toList());
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          selectedColor: KColors.surfaceInverted,
          labelStyle: KText.paragraphMedium.copyWith(color: on ? KColors.textInverse : KColors.textPrimary),
          onSelected: (_) => tap(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final e in _mineTabs.entries)
              _chip(e.value, _tab == e.key, () {
                _tab = e.key;
                _status = 'upcoming';
                _load();
              }),
          ]),
        ),
        if (_tab != 'saved') ...[
          const SizedBox(height: 8),
          Row(children: [
            for (final s in ['upcoming', 'completed', 'cancelled'])
              _chip(s[0].toUpperCase() + s.substring(1), _status == s, () {
                _status = s;
                _load();
              }),
          ]),
        ],
        const SizedBox(height: 12),
        if (items == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          EmptyState(
            icon: PhosphorIconsRegular.calendarDots,
            iconSize: 64,
            top: 120,
            title: 'No events yet',
            body: _status == 'cancelled' && _tab != 'saved'
                ? 'Events you have cancelled would be shown here.'
                : _status == 'completed' && _tab != 'saved'
                    ? 'Completed events would be shown here.'
                    : _empty[_tab]!,
          )
        else
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: EventCard(e, hosting: _tab == 'hosting' || _tab == 'cohosting', onTap: () async {
                await context.push(e.isDraft ? '/events/${e.id}/edit' : '/events/${e.id}');
                _load();
              }),
            ),
      ]),
    );
  }
}

/// EVT-03: search by name.
class EventSearchScreen extends StatefulWidget {
  const EventSearchScreen({super.key});
  @override
  State<EventSearchScreen> createState() => _EventSearchScreenState();
}

class _EventSearchScreenState extends State<EventSearchScreen> {
  final _q = TextEditingController();
  List<EventItem>? _items;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      setState(() {});
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), _run);
    });
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.isEmpty) return setState(() => _items = null);
    try {
      final r = await context.api.get('/events/search', query: {'q': q});
      if (mounted && _q.text.trim() == q) setState(() => _items = (r['events'] as List).map((e) => EventItem(Map<String, dynamic>.from(e))).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Padding(padding: const EdgeInsets.only(right: 16), child: SearchField(controller: _q, hint: 'Search events', autofocus: true)),
        ),
        body: _items == null
            ? const SizedBox.shrink()
            : _items!.isEmpty
                ? const EmptyState(title: 'No results found', body: 'Try another keyword.')
                : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [for (final e in _items!) EventRow(e)]),
      );
}
