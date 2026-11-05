import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../polls/poll_block.dart';
import 'comments.dart';
import 'social.dart';

/// One post or poll in the Feed (FED-01.2, FED-06). [onChanged] gets the new
/// post, or null when it should leave the list (deleted, author muted/blocked).
class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, required this.onChanged, this.full = false, this.showClub = true});
  final Post post;
  final void Function(Post? post) onChanged;
  final bool full;
  /// Club announcements show which club they came from (hidden on the club page).
  final bool showClub;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post p = widget.post;
  bool _expanded = false;

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (old.post != widget.post) p = widget.post;
  }

  void _set(Post n) {
    setState(() => p = n);
    widget.onChanged(n);
  }

  Future<void> _toggleLike() async {
    final liked = !p.likedByMe;
    // Optimistic, then corrected by the server count.
    _set(Post({...p.json, 'likedByMe': liked, 'likeCount': p.likeCount + (liked ? 1 : -1)}));
    try {
      final r = liked ? await context.api.post('/posts/${p.id}/like') : await context.api.delete('/posts/${p.id}/like');
      _set(Post({...p.json, 'likedByMe': r['liked'], 'likeCount': r['likeCount']}));
    } on ApiException catch (e) {
      _set(Post({...p.json, 'likedByMe': !liked, 'likeCount': p.likeCount + (liked ? -1 : 1)}));
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _openMenu() async {
    if (p.isMine) {
      await showActionSheet(context, [
        if (!p.isPoll) SheetAction(Icons.edit_outlined, 'Edit post', () async {
          final r = await context.push<Post>('/feed/compose', extra: {'edit': p});
          if (r != null) _set(r);
        }),
        SheetAction(Icons.delete_outline, 'Delete post', _delete, destructive: true),
      ]);
      return;
    }
    final a = p.author;
    await showActionSheet(context, [
      if (p.canDelete) SheetAction(Icons.delete_outline, 'Delete post', _delete, destructive: true),
      SheetAction(Icons.volume_off_outlined, 'Mute ${a.firstName}', () => muteFromPost(context, a, () => widget.onChanged(null)), subtitle: 'Stop seeing posts from this user for 30 days'),
      SheetAction(Icons.flag_outlined, 'Report this post', () => showReportSheet(context, itemType: p.isPoll ? 'poll' : 'post', itemId: p.id, title: 'Report this post'), subtitle: "${a.firstName} won't know you reported."),
      SheetAction(Icons.block, 'Block ${a.firstName}', () async {
        if (await blockPerson(context, a)) widget.onChanged(null);
      }, subtitle: "${a.firstName} won't be able to message you. They won't know you blocked them."),
    ]);
  }

  Future<void> _delete() async {
    final ok = await confirmSheet(
      context,
      title: 'Delete post?',
      body: p.isPoll ? 'Everyone including you would no longer see or have access to this poll.' : "This post would be permanently removed from your timeline and everyone else's.",
      confirm: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final r = await context.api.delete('/posts/${p.id}');
      widget.onChanged(null);
      if (mounted) showToast(context, r['message']);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final long = p.text.length > 140 || '\n'.allMatches(p.text).length > 2;
    return Container(
      color: KColors.surfaceDefault,
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p.club != null && widget.showClub)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InkWell(
              onTap: () => context.push('/clubs/${p.club!['id']}'),
              child: Row(children: [
                const Icon(Icons.groups_outlined, size: 16, color: KColors.textSecondary),
                const SizedBox(width: 6),
                Flexible(child: Text(p.club!['name'] ?? '', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Semantics(
                container: true,
                button: true,
                label: 'Open ${p.author.name}\'s profile',
                child: GestureDetector(
                  onTap: () => context.push('/users/${p.author.id}'),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Avatar(p.author.photoUrl, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AuthorLine(p.author,
                          subtitle: p.club != null ? (p.club!['audience'] == 'members' ? 'Members only' : 'All') : context.session.me?.communityName),
                    ),
                  ]),
                ),
              ),
            ),
            Text(timeAgo(p.createdAt), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            SizedBox(width: 32, height: 24, child: IconButton(padding: EdgeInsets.zero, tooltip: 'More options', icon: const Icon(Icons.more_vert, size: 20), onPressed: _openMenu)),
          ]),
        ),
        const SizedBox(height: 10),
        if (p.isPoll)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: PollBlock(post: p, onChanged: _set))
        else if (p.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: widget.full ? null : () => context.push('/posts/${p.id}', extra: p),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TaggedText(p.text, mentions: p.mentions, maxLines: widget.full || _expanded || !long ? null : 3),
                if (long && !_expanded && !widget.full)
                  GestureDetector(onTap: () => setState(() => _expanded = true), child: Text('...Read more', style: KText.paragraphLarge.copyWith(color: KColors.textSecondary, fontWeight: FontWeight.w500))),
                if (p.edited) Text('(Edited)', style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
              ]),
            ),
          ),
        if (!p.isPoll) _Attachment(p),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: p.likeCount == 0 ? null : () => context.push('/posts/${p.id}/likes'),
              child: Text(plural(p.likeCount, 'like'), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ),
            if (p.canComment) ...[
              const SizedBox(width: 12),
              Text(plural(p.commentCount, 'comment'), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ],
          ]),
        ),
        const Divider(height: 16, indent: 16, endIndent: 16, color: KColors.borderDefault),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Action(icon: p.likedByMe ? Icons.favorite : Icons.favorite_border, color: p.likedByMe ? KColors.error : null, label: 'Like', onTap: _toggleLike, selected: p.likedByMe),
            if (p.canComment) _Action(icon: Icons.chat_bubble_outline, label: 'Comment', onTap: () async {
              final api = context.api;
              await showCommentsSheet(context, p);
              if (!mounted) return;
              try {
                _set(Post(Map<String, dynamic>.from((await api.get('/posts/${p.id}'))['post'])));
              } catch (_) {}
            }),
            _Action(icon: Icons.reply_outlined, label: 'Share', onTap: () => showShareSheet(context, p.shareLink), flip: true),
          ]),
        ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color, this.flip = false, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool flip;
  final bool selected;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ExcludeSemantics(
              child: Row(children: [
                Transform.flip(flipX: flip, child: Icon(icon, size: 20, color: color ?? KColors.textSecondary)),
                const SizedBox(width: 6),
                Text(label, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              ]),
            ),
          ),
        ),
      );
}

/// FED-06: photo grid (1, 2, 3, 4+ with "+N"), video, document and link cards.
class _Attachment extends StatelessWidget {
  const _Attachment(this.p);
  final Post p;

  Widget _img(BuildContext context, int i, {String? overlay}) => GestureDetector(
        onTap: () => context.push('/media', extra: {'urls': p.photos, 'index': i, 'caption': p.text}),
        child: Stack(fit: StackFit.expand, children: [
          Image.network(context.api.absolute(p.photos[i]), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: KColors.surfaceSubtle)),
          if (overlay != null) Container(color: Colors.black45, alignment: Alignment.center, child: Text(overlay, style: KText.headingSmall.copyWith(color: Colors.white))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (p.attachment) {
      case 'photos':
        final n = p.photos.length;
        const gap = 3.0;
        if (n == 1) {
          child = AspectRatio(aspectRatio: 4 / 3, child: _img(context, 0));
        } else if (n == 2) {
          child = AspectRatio(aspectRatio: 4 / 3, child: Row(children: [Expanded(child: _img(context, 0)), const SizedBox(width: gap), Expanded(child: _img(context, 1))]));
        } else if (n == 3) {
          child = AspectRatio(
            aspectRatio: 4 / 3,
            child: Row(children: [
              Expanded(flex: 3, child: _img(context, 0)),
              const SizedBox(width: gap),
              Expanded(flex: 2, child: Column(children: [Expanded(child: _img(context, 1)), const SizedBox(height: gap), Expanded(child: _img(context, 2))])),
            ]),
          );
        } else {
          child = AspectRatio(
            aspectRatio: 1,
            child: Column(children: [
              Expanded(child: Row(children: [Expanded(child: _img(context, 0)), const SizedBox(width: gap), Expanded(child: _img(context, 1))])),
              const SizedBox(height: gap),
              Expanded(child: Row(children: [Expanded(child: _img(context, 2)), const SizedBox(width: gap), Expanded(child: _img(context, 3, overlay: n > 4 ? '+${n - 4}' : null))])),
            ]),
          );
        }
        child = ClipRRect(borderRadius: BorderRadius.circular(KRadius.md), child: child);
      case 'video':
        child = GestureDetector(
          onTap: () => context.push('/video', extra: p.video!['url']),
          child: Container(
            height: 200,
            decoration: BoxDecoration(color: KColors.surfaceInverted, borderRadius: BorderRadius.circular(KRadius.md)),
            alignment: Alignment.center,
            child: Semantics(label: 'Play video', child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 56)),
          ),
        );
      case 'document':
        final d = p.document!;
        final size = ((d['sizeBytes'] ?? 0) as num) / 1024 / 1024;
        child = InkWell(
          onTap: () async {
            final api = context.api;
            try {
              final r = await api.post('/posts/${p.id}/document/download');
              await launchUrl(Uri.parse(api.absolute(r['url'])), mode: LaunchMode.externalApplication);
            } on ApiException catch (e) {
              if (context.mounted) showToast(context, e.message);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
            child: Row(children: [
              Container(
                width: 44, height: 52, alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(6)),
                child: Text(d['fileType'] ?? 'PDF', style: KText.paragraphMediumSmall.copyWith(color: KColors.error)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d['title'] ?? '', style: KText.paragraphMediumLarge.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [if (d['pages'] != null) plural(d['pages'], 'page'), d['fileType'], '${size.toStringAsFixed(1)} MB', plural(d['downloads'] ?? 0, 'download')].join(' • '),
                    style: KText.paragraphSmall.copyWith(color: KColors.textSecondary),
                  ),
                ]),
              ),
              const Icon(Icons.download_outlined),
            ]),
          ),
        );
      case 'link':
        final l = p.link!;
        child = InkWell(
          onTap: () => launchUrl(Uri.parse(l['url']), mode: LaunchMode.externalApplication),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(border: Border.all(color: KColors.borderDefault), borderRadius: BorderRadius.circular(KRadius.md)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (l['image'] != null) AspectRatio(aspectRatio: 1.91, child: Image.network(l['image'], fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: KColors.surfaceSubtle))),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Uri.parse(l['url']).host.replaceFirst('www.', ''), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  Text(l['title'] ?? l['url'], style: KText.paragraphMediumLarge.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: child);
  }
}

/// FED-07.1: full-screen photos; swipe between them, tap toggles the chrome.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.urls, this.index = 0, this.caption});
  final List<String> urls;
  final int index;
  final String? caption;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late int _i = widget.index;
  bool _chrome = true;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => setState(() => _chrome = !_chrome),
          child: Stack(children: [
            PageView.builder(
              controller: PageController(initialPage: widget.index),
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) => InteractiveViewer(child: Center(child: Image.network(context.api.absolute(widget.urls[i])))),
            ),
            if (_chrome)
              SafeArea(
                child: Column(children: [
                  Row(children: [
                    IconButton(tooltip: 'Close', icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    const Spacer(),
                    if (widget.urls.length > 1) Padding(padding: const EdgeInsets.only(right: 16), child: Text('${_i + 1}/${widget.urls.length}', style: const TextStyle(color: Colors.white))),
                  ]),
                  const Spacer(),
                  if (widget.caption != null && widget.caption!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      color: Colors.black54,
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.caption!, style: const TextStyle(color: Colors.white)),
                    ),
                ]),
              ),
          ]),
        ),
      );
}
