import 'dart:async';
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
import 'social.dart';

/// Tracks "@Name" tags typed into a field (FED-03). Ids whose names are no
/// longer in the text are dropped when sending.
class MentionTracker {
  final Map<String, String> _byName = {};
  void add(String id, String name) => _byName[name] = id;
  List<String> idsIn(String text) => _byName.entries.where((e) => text.contains('@${e.key}')).map((e) => e.value).toSet().toList();
  void seed(List<Map<String, dynamic>> mentions) {
    for (final m in mentions) {
      _byName[m['name']] = m['id'];
    }
  }
}

/// The word being typed after "@" at the cursor, or null.
String? mentionQuery(TextEditingValue v) {
  final cur = v.selection.baseOffset;
  if (cur < 0 || cur > v.text.length) return null;
  final before = v.text.substring(0, cur);
  final m = RegExp(r'(?:^|\s)@([^\s@]{0,30})$').firstMatch(before);
  return m?.group(1);
}

void insertMention(TextEditingController c, MentionTracker t, Map<String, dynamic> person) {
  final v = c.value;
  final cur = v.selection.baseOffset;
  final before = v.text.substring(0, cur);
  final start = before.lastIndexOf('@');
  final name = person['name'] as String;
  final next = '${v.text.substring(0, start)}@$name ${v.text.substring(cur)}';
  c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + name.length + 2));
  t.add(person['id'], name);
}

/// Suggestions list for @ tagging: community members with role, blocked people excluded by the API.
class MentionSuggestions extends StatefulWidget {
  const MentionSuggestions({super.key, required this.query, required this.onPick, this.committeeOnly = false});
  final String query;
  /// UPD-06.3: additional updates can only tag committee members.
  final bool committeeOnly;
  final void Function(Map<String, dynamic>) onPick;
  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  List<Map<String, dynamic>> _people = [];
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MentionSuggestions old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 200), _load);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = widget.committeeOnly
          ? await context.api.get('/chats/people', query: {'q': widget.query, 'committeeOnly': '1'})
          : await context.api.get('/members/search', query: {'q': widget.query});
      if (mounted) setState(() => _people = List<Map<String, dynamic>>.from(r[widget.committeeOnly ? 'people' : 'members']));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_people.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: KColors.borderDefault))),
      child: Material(color: KColors.surfaceDefault, child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
        for (final p in _people)
          ListTile(
            dense: true,
            leading: Avatar(p['photoUrl'], size: 32),
            title: Text(p['name'], style: KText.paragraphMediumLarge.copyWith(fontSize: 14)),
            subtitle: p['role'] == null ? null : Text(p['role'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            onTap: () => widget.onPick(p),
          ),
      ])),
    );
  }
}

Future<void> showCommentsSheet(BuildContext context, Post post) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(children: [
              Expanded(child: Text('Comments', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500, height: 26 / 18, letterSpacing: -0.2, color: KColors.textPrimary))),
              IconButton(tooltip: 'Close', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => Navigator.pop(c)),
            ]),
          ),
          Divider(height: 1, color: KColors.borderDefault),
          Expanded(child: CommentsThread(post: post)),
        ]),
      ),
    );

/// FED-12 - FED-15: comments list, replies, input bar.
class CommentsThread extends StatefulWidget {
  const CommentsThread({super.key, required this.post, this.header});
  final Post post;
  final Widget? header;
  @override
  State<CommentsThread> createState() => _CommentsThreadState();
}

class _CommentsThreadState extends State<CommentsThread> with Busy {
  List<Comment>? _comments;
  final Map<String, List<Comment>> _replies = {};
  final Set<String> _loadingReplies = {};
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _tags = MentionTracker();
  Comment? _replyTo;
  Comment? _editing;
  PickedFile? _image;
  String? _imageError;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _load();
    _input.addListener(() => setState(() {}));
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/posts/${widget.post.id}/comments');
      if (mounted) setState(() => _comments = (r['comments'] as List).map((e) => Comment(Map<String, dynamic>.from(e))).toList());
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _loadReplies(Comment c) async {
    setState(() => _loadingReplies.add(c.id));
    try {
      final r = await context.api.get('/comments/${c.id}/replies');
      setState(() => _replies[c.id] = (r['replies'] as List).map((e) => Comment(Map<String, dynamic>.from(e))).toList());
    } finally {
      if (mounted) setState(() => _loadingReplies.remove(c.id));
    }
  }

  Future<void> _pickImage() async {
    final f = await context.deps.media.pickPhoto();
    if (f == null) return;
    final problem = photoProblem(f);
    setState(() {
      _imageError = problem;
      _image = problem == null ? f : null;
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty && _image == null) return;
    setState(() => _failed = null);
    await run(() async {
      final api = context.api;
      if (_editing != null) {
        await api.patch('/comments/${_editing!.id}', {'text': text, 'mentionIds': _tags.idsIn(text)});
      } else {
        String? mediaId;
        if (_image != null) mediaId = (await api.upload('/media', bytes: _image!.bytes, filename: _image!.name, mime: _image!.mime, query: {'kind': 'photo'}))['id'];
        await api.post('/posts/${widget.post.id}/comments', {
          'text': text,
          'mediaId': ?mediaId,
          if (_replyTo != null) 'parentId': _replyTo!.id,
          'mentionIds': _tags.idsIn(text),
        });
      }
      final parent = _replyTo?.parentId ?? _replyTo?.id ?? _editing?.parentId;
      _input.clear();
      setState(() {
        _image = null;
        _replyTo = null;
        _editing = null;
      });
      await _load();
      if (parent != null) await _loadReplies(Comment({'id': parent, 'createdAt': DateTime.now().toIso8601String()}));
    }, onError: (_) => setState(() => _failed = 'Posting failed.'));
  }

  Future<void> _menu(Comment c) async {
    final what = c.parentId == null ? 'comment' : 'reply';
    if (c.isMine) {
      await showActionSheet(context, [
        SheetAction(PhosphorIconsRegular.pencilSimple, 'Edit $what', () {
          setState(() {
            _editing = c;
            _replyTo = null;
            _tags.seed(c.mentions);
            _input.text = c.text;
          });
          _focus.requestFocus();
        }),
        SheetAction(PhosphorIconsRegular.trash, 'Delete $what', () async {
          if (!await confirmSheet(context, title: 'Delete $what?', body: 'This $what will be removed for everyone.', confirm: 'Delete', destructive: true)) return;
          if (!mounted) return;
          final r = await context.api.delete('/comments/${c.id}');
          await _load();
          if (c.parentId != null) await _loadReplies(Comment({'id': c.parentId, 'createdAt': DateTime.now().toIso8601String()}));
          if (mounted) showToast(context, r['message']);
        }, destructive: true),
      ]);
    } else {
      await showActionSheet(context, [
        SheetAction(PhosphorIconsRegular.copy, 'Copy', () async {
          await Clipboard.setData(ClipboardData(text: c.text));
          if (mounted) showToast(context, what == 'comment' ? 'Comment copied.' : 'Reply copied.');
        }),
        SheetAction(PhosphorIconsRegular.flag, 'Report $what', () => showReportSheet(context, itemType: what, itemId: c.id, title: 'Report $what')),
      ]);
    }
  }

  Future<void> _like(Comment c) async {
    final api = context.api;
    c.likedByMe ? await api.delete('/comments/${c.id}/like') : await api.post('/comments/${c.id}/like');
    await _load();
    if (c.parentId != null) await _loadReplies(Comment({'id': c.parentId, 'createdAt': DateTime.now().toIso8601String()}));
  }

  Widget _comment(Comment c, {bool reply = false}) {
    if (c.deleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('Comment is no longer available.', style: KText.paragraphMedium.copyWith(color: KColors.textTertiary, fontStyle: FontStyle.italic)),
      );
    }
    final a = c.author!;
    return GestureDetector(
      onLongPress: () => _menu(c),
      child: Padding(
        padding: EdgeInsets.only(top: 12, left: reply ? 44 : 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(container: true, button: true, label: 'Open ${a.name}\'s profile', child: GestureDetector(onTap: () => context.push('/users/${a.id}'), child: Avatar(a.photoUrl, size: reply ? 28 : 36))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(a.name, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary), overflow: TextOverflow.ellipsis)),
                if (a.isCommittee) ...[const SizedBox(width: 4), const CommitteeMark(size: 12)],
                if (!a.verified) ...[const SizedBox(width: 4), const UnverifiedChip()],
                const Spacer(),
                Text(timeAgo(c.createdAt), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              ]),
              const SizedBox(height: 2),
              if (c.text.isNotEmpty) TaggedText(c.text, mentions: c.mentions, style: KText.paragraphMedium.copyWith(fontSize: 15)),
              if (c.edited) Text('(Edited)', style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
              if (c.imageUrl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    onTap: () => context.push('/media', extra: {'urls': [c.imageUrl!], 'index': 0}),
                    child: ClipRRect(borderRadius: BorderRadius.circular(KRadius.sm), child: Image.network(context.api.absolute(c.imageUrl!), height: 140, fit: BoxFit.cover)),
                  ),
                ),
              Row(children: [
                TextButton.icon(
                  onPressed: () => _like(c),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 36), foregroundColor: KColors.textSecondary),
                  icon: Icon(c.likedByMe ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart, size: 18, color: c.likedByMe ? KColors.error : null),
                  label: Text(c.likeCount > 0 ? '${c.likeCount}' : '', style: KText.paragraphSmall.copyWith(color: c.likedByMe ? KColors.error : KColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _replyTo = c;
                      _editing = null;
                    });
                    _focus.requestFocus();
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 36), foregroundColor: KColors.textSecondary),
                  icon: const Icon(PhosphorIconsRegular.chatCircle, size: 16),
                  label: Text('Reply', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _comments;
    final q = mentionQuery(_input.value);
    return Column(children: [
      Expanded(
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            // The post header runs edge to edge; comments sit 16 in.
            : ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                ?widget.header,
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (list.isEmpty)
                  // Figma 3430:177910 empty comments.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 120),
                    child: Center(
                      child: Column(children: [
                        Text('No comments yet', style: KText.headingXSmall.copyWith(height: 26 / 18)),
                        const SizedBox(height: 4),
                        Text('Be the first to comment.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                        const SizedBox(height: 16),
                        Semantics(
                          button: true,
                          child: Material(
                            color: Colors.transparent,
                            shape: StadiumBorder(side: BorderSide(color: KColors.borderStrong)),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: () => _focus.requestFocus(),
                              child: SizedBox(
                                height: 36,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Center(widthFactor: 1, child: Text('Write a comment', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, height: 1, color: KColors.textPrimary))),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                for (final c in list) ...[
                  _comment(c),
                  if (_replies[c.id] != null) ...[
                    for (final r in _replies[c.id]!) _comment(r, reply: true),
                    if (c.replyCount > 0) Padding(padding: const EdgeInsets.only(left: 44), child: LinkText('Hide all replies', onTap: () => setState(() => _replies.remove(c.id)))),
                  ] else if (_loadingReplies.contains(c.id))
                    Padding(padding: const EdgeInsets.only(left: 44, top: 6), child: Text('Loading...', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)))
                  else if (c.replyCount > 0)
                    Padding(padding: const EdgeInsets.only(left: 44), child: LinkText('Show ${c.replyCount} more ${c.replyCount == 1 ? 'reply' : 'replies'}', onTap: () => _loadReplies(c))),
                ],
                ])),
              ]),
      ),
      if (q != null) MentionSuggestions(query: q, onPick: (p) => insertMention(_input, _tags, p)),
      if (_failed != null)
        Container(
          color: KColors.errorSubtle,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [Expanded(child: Text(_failed!, style: KText.paragraphMedium.copyWith(color: KColors.error))), TextButton(onPressed: _send, child: const Text('Retry'))]),
        ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: KColors.borderDefault))),
          child: Column(children: [
            if (_replyTo != null || _editing != null)
              Row(children: [
                Expanded(
                  child: Text(_editing != null ? 'Editing' : 'Replying to ${_replyTo!.author?.name ?? ''}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(PhosphorIconsRegular.x, size: 16),
                  onPressed: () => setState(() {
                    _replyTo = null;
                    if (_editing != null) _input.clear();
                    _editing = null;
                  }),
                ),
              ]),
            if (_image != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(KRadius.sm), child: Image.memory(_image!.bytes, height: 72, width: 72, fit: BoxFit.cover)),
                  Positioned(right: 0, top: 0, child: InkWell(onTap: () => setState(() => _image = null), child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(PhosphorIconsRegular.x, size: 12, color: Colors.white)))),
                ]),
              ),
            if (_imageError != null) ErrorLine(_imageError!),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('comment-input'),
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                  decoration: InputDecoration(
                    hintText: _replyTo != null ? 'Add a reply...' : 'Add a comment...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.pill), borderSide: BorderSide(color: KColors.borderDefault)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.pill), borderSide: BorderSide(color: KColors.borderDefault)),
                  ),
                ),
              ),
              if (_editing == null) IconButton(tooltip: 'Add image', icon: const Icon(PhosphorIconsRegular.image), onPressed: _image != null ? null : _pickImage),
              if (_input.text.trim().isEmpty && _image == null)
                IconButton(tooltip: 'Tag someone', icon: const Icon(PhosphorIconsRegular.at), onPressed: () {
                  final t = _input.text;
                  _input.value = TextEditingValue(text: '$t${t.isEmpty || t.endsWith(' ') ? '' : ' '}@', selection: TextSelection.collapsed(offset: t.length + (t.isEmpty || t.endsWith(' ') ? 1 : 2)));
                  _focus.requestFocus();
                })
              else
                IconButton(tooltip: 'Send', icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(PhosphorIconsFill.paperPlaneRight), onPressed: busy ? null : _send),
            ]),
          ]),
        ),
      ),
    ]);
  }
}
