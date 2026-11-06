import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'comments.dart';
import 'post_card.dart';
import 'social.dart';

/// Paged list of posts (Feed tab, My posts, a resident's posts).
class PostList extends StatefulWidget {
  const PostList({super.key, required this.path, this.empty, this.header, this.shrinkWrap = false});
  final String path;
  final Widget? empty;
  final Widget? header;
  final bool shrinkWrap;
  @override
  State<PostList> createState() => PostListState();
}

class PostListState extends State<PostList> {
  final List<Post> _posts = [];
  String? _cursor;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _posts.clear();
      _cursor = null;
      _done = false;
    });
    await _more();
  }

  void prepend(Post p) => setState(() => _posts.insert(0, p));

  // FED-01.4: next page at the end of the list.
  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final r = await context.api.get(widget.path, query: {'cursor': ?_cursor});
      final page = (r['posts'] as List).map((e) => Post(Map<String, dynamic>.from(e))).toList();
      setState(() {
        _posts.addAll(page);
        _cursor = r['nextCursor'];
        _done = _cursor == null;
        _error = null;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[?widget.header];
    if (_posts.isEmpty && _done && widget.empty != null) items.add(widget.empty!);
    for (var i = 0; i < _posts.length; i++) {
      final p = _posts[i];
      items.add(PostCard(
        key: ValueKey(p.id),
        post: p,
        onChanged: (n) => setState(() {
          final j = _posts.indexWhere((x) => x.id == p.id);
          if (j < 0) return;
          if (n == null) {
            // Deleted, or the author was muted/blocked: drop all their posts.
            final author = p.author.id;
            _posts.removeWhere((x) => x.id == p.id || (!p.isMine && x.author.id == author));
          } else {
            _posts[j] = n;
          }
        }),
      ));
      // Figma: posts sit 4pt apart on the grey feed.
      items.add(Container(height: 4, color: KColors.surfaceSubtle));
    }
    if (_loading) items.add(const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
    if (_error != null) items.add(Padding(padding: const EdgeInsets.all(16), child: Column(children: [ErrorLine(_error!), TextButton(onPressed: _more, child: const Text('Retry'))])));
    final list = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600) _more();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: refresh,
        // Bottom padding keeps the last card's actions clear of the create button.
        child: ListView(padding: const EdgeInsets.only(bottom: 96), shrinkWrap: widget.shrinkWrap, physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(), children: items),
      ),
    );
    // The empty state sits on white, like the Figma empty feed.
    return _posts.isEmpty && _done && !widget.shrinkWrap ? ColoredBox(color: KColors.surfaceDefault, child: list) : list;
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.body, this.action, this.icon, this.actionLabel, this.onAction, this.top = 64, this.iconSize = 82, this.bodyWidth = 260, this.bodyHeight});
  final double top;
  final double iconSize;
  final double bodyWidth;
  final double? bodyHeight;
  final String title;
  final String body;
  final Widget? action;
  /// Figma empty state: 137pt grey disc holding an 82pt icon.
  final IconData? icon;
  /// Small outlined button (Figma "Button / Small / Secondary").
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(32, top, 32, 64),
        child: Column(children: [
          if (icon != null) ...[
            Container(
              width: 137,
              height: 137,
              decoration: BoxDecoration(color: KColors.surfaceSubtle, shape: BoxShape.circle),
              child: Icon(icon, size: iconSize, color: KColors.iconDefault),
            ),
            const SizedBox(height: 32),
          ],
          Text(title, style: KText.headingXSmall.copyWith(height: 26 / 18), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bodyWidth),
            child: Text(body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary, height: bodyHeight), textAlign: TextAlign.center),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            Semantics(
              button: true,
              child: Material(
                color: Colors.transparent,
                shape: StadiumBorder(side: BorderSide(color: KColors.borderStrong)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onAction,
                  child: SizedBox(
                    height: 36,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(widthFactor: 1, child: Text(actionLabel!, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, height: 1, color: KColors.textPrimary))),
                    ),
                  ),
                ),
              ),
            ),
          ] else if (action != null) ...[const SizedBox(height: 20), SizedBox(width: 180, child: action!)],
        ]),
      );
}

/// FED-08 / FED-10: post full view with comments, or the unavailable state.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.id, this.initial});
  final String id;
  final Post? initial;
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Post? _post = widget.initial;
  ApiException? _gone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/posts/${widget.id}');
      if (mounted) setState(() => _post = Post(Map<String, dynamic>.from(r['post'])));
    } on ApiException catch (e) {
      if (mounted) setState(() => _gone = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      // Figma 3430:177910: back only, post edge to edge, small "Comments" label.
      appBar: const PageHeader('', bottomBorder: true),
      body: _gone != null
          ? UnavailablePost(error: _gone!)
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : CommentsThread(
                  post: p,
                  header: Column(children: [
                    PostCard(post: p, full: true, onChanged: (n) => n == null ? context.pop() : setState(() => _post = n)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Comments', style: KText.paragraphSmall.copyWith(fontWeight: FontWeight.w600))),
                    ),
                  ]),
                ),
    );
  }
}

/// FED-10 / POL-13: deleted by the author, removed by Keys, or not available.
class UnavailablePost extends StatelessWidget {
  const UnavailablePost({super.key, required this.error});
  final ApiException error;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(error.code == 'POST_REMOVED' ? PhosphorIconsRegular.shieldWarning : PhosphorIconsRegular.eyeSlash, size: 48, color: KColors.textTertiary),
            const SizedBox(height: 16),
            Text(error.data['title'] ?? 'Not available', style: KText.headingXSmall),
            const SizedBox(height: 8),
            Text(error.message, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary), textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// FED-11.3: everyone who liked.
class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key, required this.path});
  final String path;
  @override
  // Figma 3430:178689: count band, ruled rows with a red heart marker.
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: const PageHeader('Likes', bottomBorder: true),
        body: FutureBuilder(
          future: context.api.get(path),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final people = (s.data!['people'] as List).map((e) => PersonRef(Map<String, dynamic>.from(e))).toList();
            final total = (s.data!['total'] as int?) ?? people.length;
            return ListView(children: [
              Container(
                color: KColors.brandSubtle,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Text.rich(TextSpan(style: KText.paragraphMedium, children: [
                  TextSpan(text: '$total', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: total == 1 ? ' like' : ' likes'),
                ])),
              ),
              const SizedBox(height: 8),
              for (final p in people)
                InkWell(
                  onTap: () => context.push('/users/${p.id}'),
                  child: Container(
                    height: 60,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.borderDefault))),
                    child: Row(children: [
                      Avatar(p.photoUrl, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis, style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500))),
                            if (p.isCommittee) ...[const SizedBox(width: 4), const CommitteeMark(size: 14)],
                          ]),
                          if (p.role != null) Text(p.role!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                        ]),
                      ),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: KColors.error, shape: BoxShape.circle),
                        child: const Icon(PhosphorIconsFill.heart, size: 10, color: Colors.white),
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}

/// FED-07.2: play, pause, scrub; works for vertical videos.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.url});
  final String url;
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _c;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c ??= VideoPlayerController.networkUrl(Uri.parse(context.api.absolute(widget.url)))
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _c!.play();
      });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: c.value.isInitialized
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
                VideoProgressIndicator(c, allowScrubbing: true, colors: VideoProgressColors(playedColor: KColors.brand)),
                IconButton(
                  tooltip: c.value.isPlaying ? 'Pause' : 'Play',
                  iconSize: 48,
                  color: Colors.white,
                  icon: Icon(c.value.isPlaying ? PhosphorIconsRegular.pauseCircle : PhosphorIconsRegular.playCircle),
                  onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
                ),
              ])
            : const CircularProgressIndicator(),
      ),
    );
  }
}
