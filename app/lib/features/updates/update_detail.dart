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
import '../feed/comments.dart';
import '../feed/feed_screens.dart' show UnavailablePost;
import '../feed/social.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import '../verification/verification_screens.dart';
import 'updates_list.dart';

/// UPD-05: full update with locations, images, document, additional updates
/// and the group chat entry.
class UpdateDetailScreen extends StatefulWidget {
  const UpdateDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<UpdateDetailScreen> createState() => _UpdateDetailScreenState();
}

class _UpdateDetailScreenState extends State<UpdateDetailScreen> {
  Map<String, dynamic>? _json;
  ApiException? _error;

  UpdateItem? get _u => _json == null ? null : UpdateItem(_json!);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/updates/${widget.id}');
      if (mounted) setState(() => _json = Map<String, dynamic>.from(r['update']));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit() async {
    final r = await context.push('/updates/create', extra: {'edit': _json});
    if (r != null) _load();
  }

  Future<void> _download() async {
    final api = context.api;
    try {
      final r = await api.post('/updates/${widget.id}/document/download');
      await launchUrl(Uri.parse(api.absolute(r['url'])), mode: LaunchMode.externalApplication);
      _load();
    } catch (e) {
      if (!mounted) return;
      if (!handleVerificationRequired(context, e)) showToast(context, e is ApiException ? e.message : 'Could not download the document.');
    }
  }

  /// UCH-02: join the update's group chat, then open it.
  Future<void> _openChat() async {
    final api = context.api;
    final router = GoRouter.of(context);
    final chat = Map<String, dynamic>.from(_json!['chat']);
    try {
      if (chat['joined'] != true) await api.post('/updates/${widget.id}/chat/join');
      await router.push('/chats/${chat['id']}');
      _load();
    } on ApiException catch (e) {
      // Closed chats can still be read by members.
      if (e.code == 'READ_ONLY' && chat['joined'] == true) {
        await router.push('/chats/${chat['id']}');
      } else if (mounted) {
        showToast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => Navigator.of(context).maybePop()),
        actions: [
          if (u != null)
            IconButton(
              tooltip: 'Update options',
              icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
              onPressed: () => showUpdateOptions(context, u, onChanged: _load, onEdit: _edit, onGone: () => context.pop(true)),
            ),
        ],
      ),
      body: _error != null
          ? UnavailablePost(error: _error!)
          : u == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(child: RefreshIndicator(onRefresh: _load, child: _body(u))),
                  if (_json!['canAddAdditional'] == true) _AdditionalComposer(updateId: u.id, onPosted: _load),
                ]),
    );
  }

  Widget _body(UpdateItem u) {
    final me = context.session.me;
    final doc = _json!['document'] as Map?;
    final chat = _json!['chat'] as Map?;
    final extras = List<Map<String, dynamic>>.from(_json!['additional'] ?? []);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      if (u.resolved)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE6F6EA), borderRadius: BorderRadius.circular(KRadius.md)),
          child: Row(children: [
            const Icon(PhosphorIconsFill.checkCircle, color: KColors.success, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('This update has been resolved', style: KText.paragraphMedium.copyWith(color: KColors.success))),
          ]),
        ),
      Row(children: [
        Semantics(
          container: true,
          button: true,
          label: u.author.name,
          child: InkWell(
            onTap: () => context.push('/users/${u.author.id}'),
            child: Avatar(u.author.photoUrl, size: 40),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: AuthorLine(u.author, subtitle: me?.communityName)),
        if (chat != null)
          Stack(clipBehavior: Clip.none, children: [
            IconButton(tooltip: chat['joined'] == true ? 'Open group chat' : 'Join group chat', icon: const Icon(PhosphorIconsRegular.chatText), onPressed: _openChat),
            if (chat['joined'] != true && !u.resolved)
              Positioned(right: 8, top: 8, child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: KColors.error, shape: BoxShape.circle))),
          ]),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DateBlock(u.date, size: 46),
        const SizedBox(width: 12),
        Expanded(child: Text(u.title, style: KText.headingSmall)),
      ]),
      const SizedBox(height: 16),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'Affected locations:  ', style: KText.paragraphMedium.copyWith(color: KColors.textTertiary)),
        TextSpan(text: u.audience == 'all' ? 'All residents' : _joinNames(u.locationNames), style: KText.paragraphMedium),
      ])),
      const SizedBox(height: 16),
      SelectableText(u.details, style: KText.paragraphLarge.copyWith(fontSize: 17, height: 1.5)),
      if (_json!['editedAt'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Edited', style: KText.paragraphSmall.copyWith(color: KColors.textTertiary))),
      if (u.images.isNotEmpty) ...[
        const SizedBox(height: 16),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: u.images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Semantics(
              button: true,
              label: 'Image ${i + 1} of ${u.images.length}',
              child: InkWell(
                onTap: () => context.push('/media', extra: {'urls': u.images, 'index': i}),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(KRadius.sm),
                  child: Image.network(context.api.absolute(u.images[i]), width: 92, height: 92, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 92, color: KColors.surfaceSubtle)),
                ),
              ),
            ),
          ),
        ),
      ],
      if (doc != null) ...[
        const SizedBox(height: 16),
        DocumentTile(
          name: doc['name'] ?? 'Document',
          fileType: doc['fileType'] ?? 'PDF',
          meta: [doc['fileType'] ?? 'PDF', fileSize(doc['sizeBytes'] ?? 0), plural(doc['downloads'] ?? 0, 'download')].join(' • '),
          onTap: _download,
        ),
      ],
      const SizedBox(height: 24),
      const Divider(height: 1),
      const SizedBox(height: 16),
      Text('Additional updates', style: KText.headingXSmall),
      const SizedBox(height: 8),
      if (extras.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            _json!['canAddAdditional'] == true ? 'Post follow-ups here to keep residents informed.' : 'Follow-ups from the committee will show here.',
            style: KText.paragraphMedium.copyWith(color: KColors.textSecondary),
          ),
        )
      else
        for (final a in extras) _AdditionalItem(a, resolved: u.resolved, onChanged: _load),
    ]);
  }
}

String _joinNames(List<String> n) => n.length <= 1 ? n.join() : '${n.sublist(0, n.length - 1).join(', ')}, and ${n.last}';

/// UPD-06 / UPD-07: one follow-up with its options.
class _AdditionalItem extends StatelessWidget {
  const _AdditionalItem(this.a, {required this.resolved, required this.onChanged});
  final Map<String, dynamic> a;
  final bool resolved;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.parse(a['createdAt']).toLocal();
    if (a['deleted'] == true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(a['text'], style: KText.paragraphMedium.copyWith(color: KColors.textTertiary, fontStyle: FontStyle.italic)),
      );
    }
    final p = PersonRef(Map<String, dynamic>.from(a['author']));
    final mine = a['isMine'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(p.photoUrl, size: 32),
          const SizedBox(width: 8),
          Expanded(child: AuthorLine(p, subtitle: '${timeAgo(at)}${a['editedAt'] != null ? ' • Edited' : ''}')),
          IconButton(
            tooltip: 'Additional update options',
            visualDensity: VisualDensity.compact,
            icon: const Icon(PhosphorIconsRegular.dotsThree),
            onPressed: () => _options(context, mine),
          ),
        ]),
        if ((a['text'] as String).isNotEmpty) ...[
          const SizedBox(height: 8),
          TaggedText(a['text'], mentions: List<Map<String, dynamic>>.from(a['mentions'] ?? []), style: KText.paragraphMedium),
        ],
        if (a['imageUrl'] != null) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => context.push('/media', extra: {'urls': [a['imageUrl']]}),
            child: ClipRRect(borderRadius: BorderRadius.circular(KRadius.sm), child: Image.network(context.api.absolute(a['imageUrl']), height: 160, width: double.infinity, fit: BoxFit.cover)),
          ),
        ],
      ]),
    );
  }

  void _options(BuildContext context, bool mine) {
    final api = context.api;
    showActionSheet(context, [
      SheetAction(PhosphorIconsRegular.copy, 'Copy text', () async {
        await Clipboard.setData(ClipboardData(text: a['text'] ?? ''));
        if (context.mounted) showToast(context, 'Copied');
      }),
      if (mine && !resolved)
        SheetAction(PhosphorIconsRegular.pencilSimple, 'Edit additional update', () async {
          final c = TextEditingController(text: a['text']);
          final text = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (s) => StatefulBuilder(
              builder: (s, set) => Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Edit additional update', style: KText.headingSmall),
                  const SizedBox(height: 16),
                  KeysTextField(controller: c, maxLines: 5, maxLength: 700, autofocus: true, onChanged: (_) => set(() {})),
                  const SizedBox(height: 16),
                  KeysButton('Save', onPressed: c.text.trim().isEmpty || c.text.trim() == a['text'] ? null : () => Navigator.pop(s, c.text.trim())),
                ]),
              ),
            ),
          );
          if (text == null) return;
          try {
            await api.patch('/additional-updates/${a['id']}', {'text': text});
            if (context.mounted) showToast(context, 'Changes saved');
            onChanged();
          } on ApiException catch (e) {
            if (context.mounted) showToast(context, e.message);
          }
        }),
      if (mine)
        SheetAction(PhosphorIconsRegular.trash, 'Delete additional update', () async {
          final ok = await confirmSheet(context, title: 'Delete additional update?', body: 'Residents will see that this additional update is no longer available.', confirm: 'Delete');
          if (!ok) return;
          try {
            final r = await api.delete('/additional-updates/${a['id']}');
            if (context.mounted) showToast(context, r['message']);
            onChanged();
          } on ApiException catch (e) {
            if (context.mounted) showToast(context, e.message);
          }
        }, destructive: true)
      else
        SheetAction(PhosphorIconsRegular.flag, 'Report', () => showReportSheet(context, itemType: 'additional_update', itemId: a['id'], title: 'Report additional update')),
    ]);
  }
}

/// UPD-06.1: committee members add follow-ups with an image and @tags.
class _AdditionalComposer extends StatefulWidget {
  const _AdditionalComposer({required this.updateId, required this.onPosted});
  final String updateId;
  final VoidCallback onPosted;
  @override
  State<_AdditionalComposer> createState() => _AdditionalComposerState();
}

class _AdditionalComposerState extends State<_AdditionalComposer> with Busy {
  final _c = TextEditingController();
  final _tags = MentionTracker();
  PickedFile? _image;
  String? _query;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() => _query = mentionQuery(_c.value)));
  }

  Future<void> _pick() async {
    final f = await context.deps.media.pickPhoto();
    if (f == null || !mounted) return;
    final problem = photoProblem(f);
    if (problem != null) return showToast(context, problem);
    setState(() => _image = f);
  }

  Future<void> _send() async {
    final api = context.api;
    await run(() async {
      String? mediaId;
      if (_image != null) mediaId = (await api.upload('/media', bytes: _image!.bytes, filename: _image!.name, mime: _image!.mime, query: {'kind': 'photo'}))['id'];
      final text = _c.text.trim();
      await api.post('/updates/${widget.updateId}/additional', {'text': text, 'mediaId': ?mediaId, 'mentionIds': _tags.idsIn(text)});
      _c.clear();
      setState(() => _image = null);
      if (mounted) showToast(context, 'Additional update posted');
      widget.onPosted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = _c.text.trim().isNotEmpty || _image != null;
    return Material(
      color: KColors.surfaceDefault,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_query != null) MentionSuggestions(query: _query!, committeeOnly: true, onPick: (p) => insertMention(_c, _tags, p)),
          const Divider(height: 1),
          if (_image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(_image!.bytes, width: 56, height: 56, fit: BoxFit.cover)),
                IconButton(tooltip: 'Remove image', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => setState(() => _image = null)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(children: [
              IconButton(tooltip: 'Add image', icon: const Icon(PhosphorIconsRegular.image), onPressed: _image == null ? _pick : null),
              Expanded(
                child: TextField(
                  controller: _c,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 700,
                  style: KText.paragraphMedium,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Add an additional update',
                    filled: true,
                    fillColor: KColors.surfaceSubtle,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.pill), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(tooltip: 'Post additional update', icon: const Icon(PhosphorIconsFill.paperPlaneRight), color: KColors.textPrimary, onPressed: ready ? _send : null),
            ]),
          ),
        ]),
      ),
    );
  }
}
