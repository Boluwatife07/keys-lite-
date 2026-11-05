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
import '../feed/post_card.dart';
import '../updates/updates_list.dart' show SearchField;
import '../verification/verification_screens.dart' show showVerifySheet;
import '../feed/social.dart' show confirmSheet;

/// A club card from the API.
class ClubItem {
  ClubItem(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get name => json['name'] ?? '';
  String get description => json['description'] ?? '';
  String get category => json['category'] ?? '';
  String? get coverUrl => json['coverUrl'];
  int get memberCount => json['memberCount'] ?? 0;
  int get memberLimit => json['memberLimit'] ?? 0;
  bool get full => json['full'] == true;
  bool get isMember => json['isMember'] == true;
  String? get myRole => json['myRole'];
  String get status => json['status'] ?? 'active';
  String? get othersText => json['othersText'];
  Map<String, dynamic>? get president => json['president'];
}

/// CLB-03.6: verified residents create clubs; others see the verify sheet.
Future<void> startClub(BuildContext context, {Map<String, dynamic>? template}) async {
  final me = context.session.me;
  if (me != null && me.json['verificationStatus'] != 'verified') {
    await showVerifySheet(context);
    return;
  }
  await context.push('/clubs/create', extra: {'template': template});
}

/// CLB-01 / CLB-02: Clubs tab with Home and Discover.
class ClubsTab extends StatefulWidget {
  const ClubsTab({super.key});
  @override
  State<ClubsTab> createState() => _ClubsTabState();
}

class _ClubsTabState extends State<ClubsTab> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _home = GlobalKey<_ClubsHomeState>();

  @override
  Widget build(BuildContext context) => Stack(children: [
        Column(children: [
          Row(children: [
            Expanded(
              child: TabBar(
                controller: _tabs,
                labelColor: KColors.textPrimary,
                unselectedLabelColor: KColors.textSecondary,
                indicatorColor: KColors.textPrimary,
                labelStyle: KText.labelSemibold,
                tabs: const [Tab(text: 'Home'), Tab(text: 'Discover')],
              ),
            ),
            IconButton(tooltip: 'Search clubs', icon: const Icon(PhosphorIconsRegular.magnifyingGlass), onPressed: () => context.push('/clubs/search')),
          ]),
          Expanded(child: TabBarView(controller: _tabs, children: [_ClubsHome(key: _home), const _Discover()])),
        ]),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'club-fab',
            tooltip: 'Create club',
            backgroundColor: KColors.brand,
            foregroundColor: KColors.staticBlack,
            shape: const CircleBorder(),
            onPressed: () async {
              await startClub(context);
              _home.currentState?._load();
            },
            child: const Icon(PhosphorIconsRegular.plus, size: 28),
          ),
        ),
      ]);
}

class _ClubsHome extends StatefulWidget {
  const _ClubsHome({super.key});
  @override
  State<_ClubsHome> createState() => _ClubsHomeState();
}

class _ClubsHomeState extends State<_ClubsHome> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() {
    super.initState();
    _load();
    context.api.get('/clubs/templates').then((r) {
      if (mounted) setState(() => _templates = List<Map<String, dynamic>>.from(r['templates']));
    }).catchError((_) {});
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/clubs/home');
      if (mounted) setState(() => _d = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final mine = (d['myClubs'] as List).map((c) => ClubItem(Map<String, dynamic>.from(c))).toList();
    final posts = (d['announcements'] as List).map((p) => Post(Map<String, dynamic>.from(p))).toList();
    final templates = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Create your club in one click', style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600)),
                Text('Choose from ready-made club templates tailored to different interests and activities.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              ]),
            ),
            TextButton(onPressed: () => context.push('/clubs/templates'), style: TextButton.styleFrom(foregroundColor: KColors.textPrimary), child: const Text('View all →')),
          ]),
        ),
        SizedBox(
          height: 270,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final t in _templates) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ClubTemplateCard(t, width: 290)),
          ]),
        ),
      ]),
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(children: [
            Expanded(child: Text('My clubs', style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
            if (mine.isNotEmpty) TextButton(onPressed: () => context.push('/clubs/mine'), style: TextButton.styleFrom(foregroundColor: KColors.textPrimary), child: const Text('view all →')),
          ]),
        ),
        if (mine.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Text('Click on the + button to create a new club or use one of the provided templates below.', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          )
        else
          SizedBox(
            height: 128,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final c in mine)
                Semantics(
                  container: true,
                  button: true,
                  label: c.name,
                  child: InkWell(
                    onTap: () => context.push('/clubs/${c.id}').then((_) => _load()),
                    child: Container(
                      width: 120,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: ExcludeSemantics(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ClipRRect(borderRadius: BorderRadius.circular(KRadius.sm), child: _Cover(c.coverUrl, height: 80)),
                          const SizedBox(height: 6),
                          Text(c.name, style: KText.paragraphMediumSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${c.memberCount} members', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary, fontSize: 11)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        Divider(height: 24, thickness: 6, color: KColors.surfaceSubtle),
        if (posts.isEmpty) templates,
        for (var i = 0; i < posts.length; i++) ...[
          PostCard(post: posts[i], onChanged: (_) => _load()),
          Divider(height: 8, thickness: 6, color: KColors.surfaceSubtle),
          if (i == 1 || (posts.length < 2 && i == posts.length - 1)) templates,
        ],
      ]),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover(this.url, {required this.height});
  final String? url;
  final double height;
  @override
  Widget build(BuildContext context) => url == null
      ? Container(height: height, width: double.infinity, color: KColors.surfaceSubtle, child: Icon(PhosphorIconsRegular.usersThree, color: KColors.textTertiary))
      : Image.network(context.api.absolute(url!), height: height, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(height: height, color: KColors.surfaceSubtle));
}

class ClubTemplateCard extends StatelessWidget {
  const ClubTemplateCard(this.t, {super.key, this.width});
  final Map<String, dynamic> t;
  final double? width;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault), color: KColors.surfaceDefault),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Image.asset('assets/images/${t['image']}', height: 110, width: double.infinity, fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['label']} Club Template', style: KText.paragraphMediumLarge),
                const SizedBox(height: 4),
                Text(t['description'] ?? 'Start a ${t['name']} club for your neighbours.', maxLines: 3, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, shape: const StadiumBorder()),
                    onPressed: () => startClub(context, template: t),
                    child: const Text('Use template'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
}

/// Club card for Discover and search (CLB-01.3).
class ClubCard extends StatelessWidget {
  const ClubCard(this.c, {super.key, required this.onChanged});
  final ClubItem c;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        label: c.name,
        child: Material(
          color: KColors.surfaceDefault,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md), side: BorderSide(color: KColors.borderDefault)),
          child: InkWell(
            onTap: () => context.push('/clubs/${c.id}').then((_) => onChanged()),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Cover(c.coverUrl, height: 150),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: KText.paragraphMediumLarge),
                  const SizedBox(height: 4),
                  Row(children: [
                    _Tag('Free club', KColors.successSubtle, KColors.success),
                    const SizedBox(width: 6),
                    _Tag(c.category, KColors.isDark ? const Color(0xFF201932) : const Color(0xFFEDE7FF), KColors.isDark ? const Color(0xFFBEA9FC) : const Color(0xFF6941C6)),
                    if (c.status == 'closing') ...[const SizedBox(width: 6), _Tag('Closing', KColors.errorSubtle, KColors.error)],
                  ]),
                  const SizedBox(height: 6),
                  Text(c.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text(c.othersText ?? '', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
                    if (!c.isMember)
                      SizedBox(
                        height: 32,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, shape: const StadiumBorder()),
                          onPressed: c.status == 'active' ? () => joinClub(context, c.id, c.name).then((_) => onChanged()) : null,
                          child: const Text('Join'),
                        ),
                      )
                    else
                      Text(c.myRole == 'president' ? 'President' : 'Member', style: KText.paragraphMediumSmall.copyWith(color: KColors.success)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.bg, this.fg);
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: KText.paragraphMediumSmall.copyWith(color: fg, fontSize: 11)),
      );
}

/// CLB-06: join, or the full / verify states.
Future<bool> joinClub(BuildContext context, String id, String name) async {
  final api = context.api;
  try {
    final r = await api.post('/clubs/$id/join');
    if (context.mounted) showToast(context, r['message']);
    return true;
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    if (e.code == 'VERIFICATION_REQUIRED') {
      await showVerifySheet(context);
    } else if (e.code == 'CLUB_FULL') {
      await confirmSheet(context, title: e.data['title'] ?? 'This club is currently full', body: e.message, confirm: 'OK', cancel: 'Close');
    } else {
      showToast(context, e.message);
    }
    return false;
  }
}

class _Discover extends StatefulWidget {
  const _Discover();
  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  String _category = 'All';
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/clubs/discover', query: _category == 'All' ? null : {'category': _category});
      if (mounted) setState(() => _d = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final clubs = (d['clubs'] as List).map((c) => ClubItem(Map<String, dynamic>.from(c))).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in List<String>.from(d['categories']))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  showCheckmark: false,
                  selectedColor: KColors.surfaceInverted,
                  labelStyle: KText.paragraphMedium.copyWith(color: _category == c ? KColors.textInverse : KColors.textPrimary),
                  onSelected: (_) {
                    setState(() => _category = c);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (clubs.isEmpty)
          const EmptyState(title: 'No Clubs yet', body: 'Discover new clubs created other residents. Click on the + button to create a club.')
        else
          for (final c in clubs) Padding(padding: const EdgeInsets.only(bottom: 16), child: ClubCard(c, onChanged: _load)),
      ]),
    );
  }
}

/// CLB-02: search by name.
class ClubSearchScreen extends StatefulWidget {
  const ClubSearchScreen({super.key});
  @override
  State<ClubSearchScreen> createState() => _ClubSearchScreenState();
}

class _ClubSearchScreenState extends State<ClubSearchScreen> {
  final _q = TextEditingController();
  List<ClubItem>? _items;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), _run);
    });
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.isEmpty) return setState(() => _items = null);
    try {
      final r = await context.api.get('/clubs/discover', query: {'q': q});
      if (mounted && _q.text.trim() == q) setState(() => _items = (r['clubs'] as List).map((c) => ClubItem(Map<String, dynamic>.from(c))).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Padding(padding: const EdgeInsets.only(right: 16), child: SearchField(controller: _q, hint: 'Search clubs', autofocus: true)),
        ),
        body: _items == null
            ? const SizedBox.shrink()
            : _items!.isEmpty
                ? const EmptyState(title: 'No results found', body: 'Try another keyword.')
                : ListView(padding: const EdgeInsets.all(16), children: [for (final c in _items!) Padding(padding: const EdgeInsets.only(bottom: 16), child: ClubCard(c, onChanged: _run))]),
      );
}

/// CLB-04.1: all eight templates.
class ClubTemplatesScreen extends StatelessWidget {
  const ClubTemplatesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('Club templates', style: KText.headingXSmall)),
        body: FutureBuilder(
          future: context.api.get('/clubs/templates'),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final t in List<Map<String, dynamic>>.from(s.data!['templates'])) Padding(padding: const EdgeInsets.only(bottom: 16), child: ClubTemplateCard(t)),
            ]);
          },
        ),
      );
}

/// "My clubs → view all".
class MyClubsScreen extends StatelessWidget {
  const MyClubsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('My clubs', style: KText.headingXSmall)),
        body: FutureBuilder(
          future: context.api.get('/clubs/home'),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final clubs = (s.data!['myClubs'] as List).map((c) => ClubItem(Map<String, dynamic>.from(c))).toList();
            return ListView(padding: const EdgeInsets.all(16), children: [for (final c in clubs) Padding(padding: const EdgeInsets.only(bottom: 16), child: ClubCard(c, onChanged: () {}))]);
          },
        ),
      );
}
