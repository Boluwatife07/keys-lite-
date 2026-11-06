import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import 'comments.dart';
import 'social.dart';

const kPostMax = 200;
const kMaxPhotos = 10;
const kMaxVideoBytes = 100 * 1024 * 1024;
const kMaxDocBytes = 25 * 1024 * 1024;

/// FED-02 - FED-05 compose; also edits a post (text and tags, FED-18.2).
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.initialText, this.edit, this.welcomeImage = false, this.clubId, this.clubName});
  final String? initialText;
  final Post? edit;
  final bool welcomeImage;
  /// CLB-13.1: a club announcement, for the community or members only.
  final String? clubId;
  final String? clubName;
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> with Busy {
  late final _text = TextEditingController(text: widget.edit?.text ?? widget.initialText ?? '');
  final _tags = MentionTracker();
  final _focus = FocusNode();
  final List<PickedFile> _photos = [];
  PickedFile? _video;
  ({PickedFile file, String title})? _doc;
  Map<String, dynamic>? _link;
  String? _error;
  bool _failed = false;
  String _audience = 'all';

  bool get _editing => widget.edit != null;
  String get _type => _photos.isNotEmpty ? 'photos' : _video != null ? 'video' : _doc != null ? 'document' : _link != null ? 'link' : 'none';
  bool get _hasInput => _text.text.trim().isNotEmpty || _type != 'none';
  bool get _changed => _editing ? _text.text.trim() != widget.edit!.text : _hasInput;

  @override
  void initState() {
    super.initState();
    if (widget.edit != null) _tags.seed(widget.edit!.mentions);
    _text.addListener(() => setState(() {}));
    if (widget.welcomeImage) {
      // ONB-25.2: the welcome post comes with its image pre-loaded.
      rootBundle.load('assets/images/community_live_street.png').then((b) {
        if (mounted) setState(() => _photos.add(PickedFile(bytes: b.buffer.asUint8List(), name: 'welcome.png', mime: 'image/png')));
      });
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_changed) return true;
    return confirmSheet(context, title: 'Discard post', body: 'By discarding, all your input would be lost.', confirm: 'Yes, discard');
  }

  Future<void> _addPhotos() async {
    if (_photos.length >= kMaxPhotos) return setState(() => _error = 'You can add up to $kMaxPhotos photos');
    final f = await context.deps.media.pickPhoto();
    if (f == null) return;
    final problem = photoProblem(f);
    setState(() {
      _error = problem;
      if (problem == null) _photos.add(f);
    });
  }

  Future<void> _addVideo() async {
    final f = await context.deps.media.pickVideo();
    if (f == null || !mounted) return;
    if (f.size > kMaxVideoBytes) return setState(() => _error = 'The video you selected is too large. Please choose a video of 100 MB or less.');
    final len = await context.deps.videoLength?.call(f);
    if (len != null && len.inMilliseconds > 60500) return setState(() => _error = 'Videos can be up to 60 seconds long. Please trim your video.');
    setState(() {
      _video = f;
      _error = null;
    });
  }

  Future<void> _addDocument() async {
    final r = await showModalBottomSheet<({PickedFile file, String title})>(context: context, isScrollControlled: true, builder: (_) => const _AddDocumentSheet());
    if (r != null) setState(() => _doc = r);
  }

  Future<void> _addLink() async {
    final c = TextEditingController();
    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add link', style: KText.headingSmall),
          const SizedBox(height: 16),
          KeysTextField(controller: c, hint: 'https://', keyboardType: TextInputType.url, autofocus: true),
          const SizedBox(height: 16),
          KeysButton('Add', onPressed: () => Navigator.pop(s, c.text.trim())),
        ]),
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    final u = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (u == null || u.host.isEmpty) return setState(() => _error = 'Enter a valid link');
    try {
      final r = await context.api.post('/link-preview', {'url': u.toString()});
      setState(() {
        _link = r;
        _error = null;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _tag() {
    final t = _text.text;
    final sep = t.isEmpty || t.endsWith(' ') ? '' : ' ';
    _text.value = TextEditingValue(text: '$t$sep@', selection: TextSelection.collapsed(offset: t.length + sep.length + 1));
    _focus.requestFocus();
  }

  Future<void> _post() async {
    setState(() => _failed = false);
    final api = context.api;
    await run(() async {
      final text = _text.text.trim();
      if (_editing) {
        final r = await api.patch('/posts/${widget.edit!.id}', {'text': text, 'mentionIds': _tags.idsIn(text)});
        if (!mounted) return;
        showToast(context, r['message']);
        context.pop(Post(Map<String, dynamic>.from(r['post'])));
        return;
      }
      Future<String> up(PickedFile f, String kind) async => (await api.upload('/media', bytes: f.bytes, filename: f.name, mime: f.mime, query: {'kind': kind}))['id'];
      final body = <String, dynamic>{'text': text, 'mentionIds': _tags.idsIn(text), if (widget.clubId != null) 'clubId': widget.clubId, if (widget.clubId != null) 'audience': _audience};
      if (_photos.isNotEmpty) body['photoIds'] = [for (final p in _photos) await up(p, 'photo')];
      if (_video != null) body['videoId'] = await up(_video!, 'video');
      if (_doc != null) body['document'] = {'mediaId': await up(_doc!.file, 'document'), 'title': _doc!.title};
      if (_link != null) body['linkUrl'] = _link!['url'];
      final r = await api.post('/posts', body);
      if (!mounted) return;
      final post = Post(Map<String, dynamic>.from(r['post']));
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      context.pop(post);
      // FED-05.1: "Your post has been sent" with "View post".
      messenger.showSnackBar(SnackBar(
        content: Text(r['message']),
        action: SnackBarAction(label: 'View post', textColor: KColors.brand, onPressed: () => router.push('/posts/${post.id}', extra: post)),
      ));
    }, onError: (e) {
      // FED-05.2: nothing is lost; the user can retry.
      setState(() {
        _failed = true;
        if (e is ApiException && e.status == 400) _error = e.message;
      });
    });
  }

  Widget _preview() {
    switch (_type) {
      case 'photos':
        return SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(KRadius.sm), child: Image.memory(_photos[i].bytes, width: 110, height: 110, fit: BoxFit.cover)),
              Positioned(
                right: 4,
                top: 4,
                child: InkWell(
                  onTap: () => setState(() => _photos.removeAt(i)),
                  child: Semantics(label: 'Remove photo ${i + 1}', child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(PhosphorIconsRegular.x, size: 14, color: Colors.white))),
                ),
              ),
            ]),
          ),
        );
      case 'video':
        return _FileChip(icon: PhosphorIconsRegular.videoCamera, title: _video!.name, onRemove: () => setState(() => _video = null));
      case 'document':
        return _FileChip(icon: PhosphorIconsRegular.fileText, title: _doc!.title, subtitle: _doc!.file.name, onRemove: () => setState(() => _doc = null));
      case 'link':
        return _FileChip(icon: PhosphorIconsRegular.link, title: _link!['title'] ?? _link!['url'], subtitle: _link!['url'], onRemove: () => setState(() => _link = null));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _tool(String tip, IconData icon, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: SizedBox.square(
          dimension: 36,
          child: IconButton(
            tooltip: tip,
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: 24, color: onTap == null ? KColors.iconDisabled : KColors.iconDefault),
            onPressed: onTap,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final me = context.session.me;
    final q = mentionQuery(_text.value);
    final t = _type;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
        backgroundColor: KColors.surfaceDefault,
        body: SafeArea(
          child: Column(children: [
            // Figma 3430:177014 header: X, avatar + audience, Post.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(children: [
                Tooltip(
                  message: 'Close',
                  child: InkResponse(
                    radius: 20,
                    onTap: () async {
                      if (await _confirmDiscard() && context.mounted) context.pop();
                    },
                    child: Icon(PhosphorIconsRegular.x, size: 26, color: KColors.iconDefault),
                  ),
                ),
                const SizedBox(width: 16),
                Avatar(me?.photoUrl, size: 36),
                const SizedBox(width: 4),
                // FED-02.4: audience is everyone and cannot change in Phase 1; club announcements choose (CLB-13.1).
                if (widget.clubId == null)
                  Semantics(
                    label: 'Audience: Everyone',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Everyone', style: KText.paragraphMedium),
                        const SizedBox(width: 4),
                        Icon(PhosphorIconsRegular.caretDown, size: 14, color: KColors.iconDefault),
                      ]),
                    ),
                  )
                else if (!_editing)
                  Semantics(
                    button: true,
                    label: 'Audience: ${_audience == 'all' ? 'Everyone in this community' : 'Only members of this club'}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(KRadius.pill),
                      onTap: () async {
                        final v = await showModalBottomSheet<String>(
                          context: context,
                          builder: (c) => SafeArea(
                            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Audience', style: KText.headingSmall)),
                              ListTile(leading: const Icon(PhosphorIconsRegular.globe), title: const Text('Everyone in this community'), onTap: () => Navigator.pop(c, 'all')),
                              ListTile(leading: const Icon(PhosphorIconsRegular.usersThree), title: const Text('Only members of this club'), onTap: () => Navigator.pop(c, 'members')),
                            ]),
                          ),
                        );
                        if (v != null) setState(() => _audience = v);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(border: Border.all(color: KColors.borderDefault), borderRadius: BorderRadius.circular(KRadius.pill)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_audience == 'all' ? 'Everyone' : 'Members only', style: KText.paragraphMedium),
                          const Icon(PhosphorIconsRegular.caretDown, size: 18),
                        ]),
                      ),
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  height: 36,
                  child: FilledButton(
                    key: const Key('post-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: KColors.surfaceInverted,
                      foregroundColor: KColors.textInverse,
                      disabledBackgroundColor: KColors.surfaceSubtle,
                      disabledForegroundColor: KColors.textDisabled,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: (_editing ? _text.text.trim().isNotEmpty || widget.edit!.attachment != 'none' : _hasInput) && !busy ? _post : null,
                    child: busy ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KColors.textInverse)) : Text(_editing ? 'Save' : 'Post'),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
                TextField(
                  key: const Key('compose-field'),
                  controller: _text,
                  focusNode: _focus,
                  autofocus: true,
                  maxLines: null,
                  minLines: 4,
                  inputFormatters: [LengthLimitingTextInputFormatter(kPostMax)],
                  style: KText.paragraphLarge.copyWith(fontSize: 20, height: 28 / 20),
                  decoration: InputDecoration(
                    hintText: "What's happening?",
                    hintStyle: KText.paragraphLarge.copyWith(fontSize: 20, color: KColors.textTertiary),
                    border: InputBorder.none,
                  ),
                ),
                Align(alignment: Alignment.centerRight, child: Text('${_text.text.characters.length}/$kPostMax', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
                const SizedBox(height: 8),
                if (!_editing) _preview(),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorLine(_error!)),
              ]),
            ),
            if (q != null) MentionSuggestions(query: q, onPick: (p) => insertMention(_text, _tags, p)),
            if (_failed)
              Container(
                color: KColors.errorSubtle,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: Text('Posting failed.', style: KText.paragraphMedium.copyWith(color: KColors.error))),
                  TextButton(onPressed: _post, child: const Text('Retry')),
                ]),
              ),
            Container(
              // Figma "Typing bar": 56pt, #dddddd rule, 36pt buttons with 24pt icons.
              height: 56,
              decoration: BoxDecoration(color: KColors.surfaceDefault, border: Border(top: BorderSide(color: KColors.palette.brightness == Brightness.dark ? KColors.borderDefault : const Color(0xFFDDDDDD)))),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                // FED-04.1: once one attachment type is used, the others are unavailable.
                if (!_editing) ...[
                  _tool('Add photos', PhosphorIconsRegular.image, t == 'none' || t == 'photos' ? _addPhotos : null),
                  _tool('Add video', PhosphorIconsRegular.videoCamera, t == 'none' ? _addVideo : null),
                  _tool('Add document', PhosphorIconsRegular.paperclip, t == 'none' ? _addDocument : null),
                ],
                _tool('Tag someone', PhosphorIconsRegular.at, _tag),
                if (!_editing) _tool('Add link', PhosphorIconsRegular.link, t == 'none' ? _addLink : null),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.icon, required this.title, this.subtitle, required this.onRemove});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
        child: Row(children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: KText.paragraphMediumLarge.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null) Text(subtitle!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          IconButton(tooltip: 'Remove', icon: const Icon(PhosphorIconsRegular.x), onPressed: onRemove),
        ]),
      );
}

/// FED-04.4: document title (required, n/100) and the file (25 MB max).
class _AddDocumentSheet extends StatefulWidget {
  const _AddDocumentSheet();
  @override
  State<_AddDocumentSheet> createState() => _AddDocumentSheetState();
}

class _AddDocumentSheetState extends State<_AddDocumentSheet> {
  final _title = TextEditingController();
  PickedFile? _file;
  String? _error;

  Future<void> _pick() async {
    final f = await context.deps.media.pickDocument(extensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']);
    if (f == null) return;
    if (f.size > kMaxDocBytes) return setState(() => _error = 'The document you selected is too large. Please choose a file of 25 MB or less.');
    setState(() {
      _file = f;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add document', style: KText.headingSmall),
          const SizedBox(height: 16),
          KeysTextField(label: 'Document title', hint: 'Descriptive title for your document', controller: _title, maxLength: 100, onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pick,
            borderRadius: BorderRadius.circular(KRadius.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
              child: Row(children: [
                const Icon(PhosphorIconsRegular.fileArrowUp),
                const SizedBox(width: 12),
                Expanded(child: Text(_file?.name ?? 'Select a document', style: KText.paragraphMediumLarge.copyWith(fontSize: 15))),
              ]),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorLine(_error!)),
          const SizedBox(height: 16),
          KeysButton('Add document', onPressed: _file != null && _title.text.trim().isNotEmpty ? () => Navigator.pop(context, (file: _file!, title: _title.text.trim())) : null),
        ]),
      );
}
