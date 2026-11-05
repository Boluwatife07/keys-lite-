import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/feed_screens.dart' show EmptyState;
import '../feed/social.dart';

/// One update as the API returns it.
class UpdateItem {
  UpdateItem(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get title => json['title'] ?? '';
  String get details => json['details'] ?? '';
  PersonRef get author => PersonRef(Map<String, dynamic>.from(json['author']));
  DateTime get date => DateTime.parse(json['date']).toLocal();
  String get locations => json['locations'] ?? '';
  List<String> get locationNames => List<String>.from(json['locationNames'] ?? []);
  String get audience => json['audience'] ?? 'all';
  List<String> get images => List<String>.from(json['images'] ?? []);
  int get newAdditional => json['newAdditional'] ?? 0;
  bool get pinned => json['pinned'] == true;
  bool get muted => json['muted'] == true;
  bool get seen => json['seen'] != false;
  String get status => json['status'] ?? 'live';
  bool get resolved => status == 'resolved';
  bool get isMine => json['isMine'] == true;
  bool get canResolve => json['canResolve'] == true;
  String? get chatId => json['chatId'];
  String get shareLink => json['shareLink'] ?? '';
}

/// UPD-01: Home > Updates. Pinned on top, search by title, resolved link.
class UpdatesTab extends StatefulWidget {
  const UpdatesTab({super.key, this.onUnseen});
  /// Unread count for the tab badge.
  final ValueChanged<int>? onUnseen;
  @override
  State<UpdatesTab> createState() => UpdatesTabState();
}

class UpdatesTabState extends State<UpdatesTab> {
  List<UpdateItem>? _items;
  bool _hasResolved = false;
  bool _canCreate = false;
  ApiException? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    refresh();
    _search.addListener(() => setState(() {}));
  }

  Future<void> refresh() async {
    try {
      final r = await context.api.get('/updates');
      if (!mounted) return;
      setState(() {
        _items = (r['updates'] as List).map((e) => UpdateItem(Map<String, dynamic>.from(e))).toList();
        _hasResolved = r['hasResolved'] == true;
        _canCreate = r['canCreate'] == true;
        _error = null;
      });
      widget.onUnseen?.call(_items!.where((u) => !u.seen).length);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(UpdateItem u) async {
    await context.push('/updates/${u.id}');
    refresh();
  }

  Future<void> _create() async {
    final r = await context.push('/updates/create');
    if (r != null) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    Widget body;
    if (items == null) {
      body = _error == null
          ? const Center(child: CircularProgressIndicator())
          : EmptyState(title: 'Could not load updates', body: _error!.message, action: KeysButton('Try again', onPressed: refresh));
    } else {
      final q = _search.text.trim().toLowerCase();
      final shown = q.isEmpty ? items : items.where((u) => u.title.toLowerCase().contains(q)).toList();
      body = RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (items.isNotEmpty || q.isNotEmpty) ...[
              SearchField(controller: _search, hint: 'Search by update title'),
              const SizedBox(height: 16),
            ],
            if (items.isEmpty)
              EmptyState(
                title: 'No updates yet',
                body: 'Urgent information posted by the Committee members will be shown here',
                action: _canCreate ? KeysButton('Post update', onPressed: _create) : null,
              )
            else if (shown.isEmpty)
              const EmptyState(title: 'No results found', body: 'Try another keyword.')
            else
              for (final u in shown) Padding(padding: const EdgeInsets.only(bottom: 12), child: UpdateCard(u, onTap: () => _open(u), onChanged: refresh)),
            if (_hasResolved && q.isEmpty)
              Center(
                child: TextButton(
                  onPressed: () async {
                    await context.push('/updates/resolved');
                    refresh();
                  },
                  style: TextButton.styleFrom(foregroundColor: KColors.textLink),
                  child: const Text('View resolved updates'),
                ),
              ),
          ],
        ),
      );
    }
    return Stack(children: [
      Positioned.fill(child: Container(color: KColors.surfaceDefault, child: body)),
      if (_canCreate)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'update-fab',
            tooltip: 'Create update',
            backgroundColor: KColors.brand,
            foregroundColor: KColors.textPrimary,
            shape: const CircleBorder(),
            onPressed: _create,
            child: const Icon(PhosphorIconsRegular.plus, size: 28),
          ),
        ),
    ]);
  }
}

/// Grey rounded search field from the design.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.hint, this.onSubmitted, this.autofocus = false});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: KText.paragraphLarge,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: KText.paragraphLarge.copyWith(color: KColors.textTertiary),
          prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, color: KColors.textPrimary),
          suffixIcon: controller.text.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(PhosphorIconsRegular.x, size: 20), onPressed: controller.clear),
          filled: true,
          fillColor: KColors.surfaceSubtle,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.pill), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.pill), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.pill), borderSide: const BorderSide(color: KColors.borderStrong)),
        ),
      );
}

/// UPD-01.2: date block, title, 3-line preview, location and author.
/// Unseen updates get the yellow tint and a red dot.
class UpdateCard extends StatelessWidget {
  const UpdateCard(this.u, {super.key, required this.onTap, required this.onChanged});
  final UpdateItem u;
  final VoidCallback onTap;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final fresh = !u.seen && !u.resolved;
    return Semantics(
      container: true,
      button: true,
      label: u.title,
      child: Material(
        color: fresh ? KColors.brandSubtle : KColors.surfaceDefault,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md), side: BorderSide(color: fresh ? const Color(0xFFFFEDB0) : KColors.borderDefault)),
        child: InkWell(
          borderRadius: BorderRadius.circular(KRadius.md),
          onTap: onTap,
          onLongPress: u.resolved ? null : () => showUpdateOptions(context, u, onChanged: onChanged, fromList: true),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DateBlock(u.date, dot: fresh),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(u.title, style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (u.pinned) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(PhosphorIconsFill.pushPin, size: 18, semanticLabel: 'Pinned')),
                      if (u.muted) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(PhosphorIconsRegular.speakerSimpleSlash, size: 18, semanticLabel: 'Muted')),
                    ]),
                    const SizedBox(height: 4),
                    Text(u.details, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary), maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (u.newAdditional > 0) ...[
                      const SizedBox(height: 6),
                      Text('+${plural(u.newAdditional, 'new additional update')}', style: KText.paragraphSmall.copyWith(color: KColors.textLink)),
                    ],
                  ]),
                ),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
              Row(children: [
                Expanded(child: Text(u.locations, style: KText.paragraphMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (u.resolved) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE6F6EA), borderRadius: BorderRadius.circular(KRadius.pill)),
                    child: Text('Resolved', style: KText.paragraphMediumSmall.copyWith(color: KColors.success)),
                  ),
                  const SizedBox(width: 8),
                ],
                Avatar(u.author.photoUrl, size: 24),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// UPD-08 / UPD-09 / UPD-10 options (pin, mute, delete for me), plus the
/// creator's edit, resolve and delete when opened from the detail.
Future<void> showUpdateOptions(BuildContext context, UpdateItem u, {required VoidCallback onChanged, bool fromList = false, VoidCallback? onEdit, VoidCallback? onGone}) {
  final api = context.api;
  Future<void> call(Future<Map<String, dynamic>> Function() fn, [String? toast]) async {
    try {
      final r = await fn();
      if (context.mounted && (toast ?? r['message']) != null) showToast(context, toast ?? r['message']);
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  return showActionSheet(context, [
    if (!u.resolved)
      u.pinned
          ? SheetAction(PhosphorIconsRegular.pushPin, 'Unpin update', () => call(() => api.delete('/updates/${u.id}/pin'), 'Update unpinned'), subtitle: 'Remove this update from the top.')
          : SheetAction(PhosphorIconsRegular.pushPin, 'Pin update', () => call(() => api.post('/updates/${u.id}/pin'), 'Update pinned'), subtitle: 'Keep this update fixed at the top.'),
    if (!u.resolved)
      u.muted
          ? SheetAction(PhosphorIconsRegular.speakerSimpleHigh, 'Unmute update', () => call(() => api.put('/updates/${u.id}/mute', {'duration': null}), 'Update unmuted'), subtitle: 'Resume receiving notifications for this update.')
          : SheetAction(PhosphorIconsRegular.speakerSimpleSlash, 'Mute update', () async {
              final d = await pickMuteDuration(context, title: 'Mute update', body: "You won't get notifications for new additional updates on this update.");
              if (d != null) await call(() => api.put('/updates/${u.id}/mute', {'duration': d}), 'Update muted');
            }, subtitle: 'Stop receiving notifications for this update.'),
    if (!fromList) SheetAction(PhosphorIconsRegular.shareFat, 'Share update', () => showShareSheet(context, u.shareLink), subtitle: 'Copy the link or share it.'),
    if (!fromList && u.isMine && !u.resolved && onEdit != null) SheetAction(PhosphorIconsRegular.pencilSimple, 'Edit update', onEdit, subtitle: 'Change the details of this update.'),
    if (!fromList && u.canResolve)
      SheetAction(PhosphorIconsRegular.checkCircle, 'Resolve update', () async {
        final ok = await confirmSheet(context,
            title: 'Resolve update?',
            body: 'This update will move to resolved updates. Additional updates and its group chat become read-only.',
            confirm: 'Resolve');
        if (ok) await call(() => api.post('/updates/${u.id}/resolve'));
      }, subtitle: 'Mark this update as resolved.'),
    SheetAction(PhosphorIconsRegular.trash, 'Delete for me', () async {
      final ok = await confirmSheet(context, title: 'Delete for me?', body: 'This update will be removed from your updates. Other residents will still see it.', confirm: 'Delete');
      if (!ok) return;
      await call(() => api.post('/updates/${u.id}/hide'));
      onGone?.call();
    }, subtitle: 'Remove this update for me'),
    if (!fromList && u.isMine && !u.resolved)
      SheetAction(PhosphorIconsRegular.trash, 'Delete update', () async {
        final ok = await confirmSheet(context, title: 'Delete update?', body: 'This update will be deleted for all residents. This cannot be undone.', confirm: 'Delete');
        if (!ok) return;
        await call(() => api.delete('/updates/${u.id}'));
        onGone?.call();
      }, subtitle: 'Delete this update for everyone', destructive: true),
  ]);
}

/// UPD-14: resolved updates with title search.
class ResolvedUpdatesScreen extends StatefulWidget {
  const ResolvedUpdatesScreen({super.key});
  @override
  State<ResolvedUpdatesScreen> createState() => _ResolvedUpdatesScreenState();
}

class _ResolvedUpdatesScreenState extends State<ResolvedUpdatesScreen> {
  final _search = TextEditingController();
  List<UpdateItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() {
      setState(() {});
      _load();
    });
  }

  Future<void> _load() async {
    final q = _search.text.trim();
    try {
      final r = await context.api.get('/updates/resolved', query: q.isEmpty ? null : {'q': q});
      if (mounted && _search.text.trim() == q) setState(() => _items = (r['updates'] as List).map((e) => UpdateItem(Map<String, dynamic>.from(e))).toList());
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => Navigator.of(context).maybePop()), titleSpacing: 0, title: Text('Resolved updates', style: KText.headingXSmall)),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          SearchField(controller: _search, hint: 'Search by update title'),
          const SizedBox(height: 16),
          if (_items == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_items!.isEmpty)
            _search.text.trim().isEmpty
                ? const EmptyState(title: 'No resolved updates', body: 'Updates the committee marks as resolved will show here.')
                : const EmptyState(title: 'No results found', body: 'Try another keyword.')
          else
            for (final u in _items!)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: UpdateCard(u, onTap: () async {
                  await context.push('/updates/${u.id}');
                  _load();
                }, onChanged: _load),
              ),
        ]),
      );
}
