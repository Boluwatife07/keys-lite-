import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import 'poll_block.dart';

const kQuestionMax = 200;
const kPromiseMax = 200;
const kOptionMax = 40;
const kOptionsMax = 5;
const kDurations = {'24h': '24 hours', '48h': '48 hours', '7d': '7 days', '2w': '2 weeks'};

class _Option {
  final text = TextEditingController();
  PickedFile? image;
  String? error;
}

/// POL-02 - POL-04: committee members create a poll.
class CreatePollScreen extends StatefulWidget {
  const CreatePollScreen({super.key});
  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final _question = TextEditingController();
  final _promise = TextEditingController();
  final List<_Option> _options = [_Option(), _Option()];
  bool _multi = false;
  String _duration = '24h';

  bool get _hasInput => _question.text.trim().isNotEmpty || _promise.text.trim().isNotEmpty || _options.any((o) => o.text.text.trim().isNotEmpty || o.image != null);

  Future<bool> _confirmDiscard() async =>
      !_hasInput || await confirmSheet(context, title: 'Discard post', body: 'By discarding, all your input would be lost.', confirm: 'Yes, discard');

  Future<void> _pickImage(_Option o) async {
    final f = await context.deps.media.pickPhoto();
    if (f == null) return;
    final problem = photoProblem(f);
    setState(() {
      o.error = problem;
      if (problem == null) o.image = f;
    });
  }

  bool _validate() {
    final anyImage = _options.any((o) => o.image != null);
    var ok = true;
    setState(() {
      for (final o in _options) {
        o.error = null;
        if (o.text.text.trim().isEmpty) {
          o.error = 'Add an option';
          ok = false;
        } else if (anyImage && o.image == null) {
          // POL-03.3: images on every option or none.
          o.error = 'Please add an image';
          ok = false;
        }
      }
    });
    return ok;
  }

  void _preview() {
    if (!_validate()) return;
    context.push('/polls/preview', extra: {
      'question': _question.text.trim(),
      'promise': _promise.text.trim(),
      'multi': _multi,
      'duration': _duration,
      'options': [for (final o in _options) {'text': o.text.text.trim(), 'image': o.image}],
    });
  }

  Future<void> _pickDuration() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4), child: Text('Poll duration', style: KText.headingSmall)),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Specify the duration of this poll.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
          RadioGroup<String>(
            groupValue: _duration,
            onChanged: (x) => Navigator.pop(c, x),
            child: Column(children: [for (final e in kDurations.entries) RadioListTile<String>(value: e.key, title: Text(e.value), activeColor: KColors.surfaceInverted)]),
          ),
        ]),
      ),
    );
    if (v != null) setState(() => _duration = v);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmDiscard() && context.mounted) context.pop();
      },
      child: KeysScaffold(
        gradient: false,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
          child: Row(children: [
            IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () async {
              if (await _confirmDiscard() && context.mounted) context.pop();
            }),
            Text('Create poll', style: KText.headingXSmall),
          ]),
        ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KeysTextField(label: 'Question', required: true, controller: _question, hint: 'What question would like to get opinions on?', maxLength: kQuestionMax, maxLines: 3, minLines: 3, onChanged: (_) => setState(() {})),
          const SizedBox(height: 20),
          KeysTextField(label: 'Poll promise', controller: _promise, hint: 'What does this poll result stand to achieve?', maxLength: kPromiseMax, maxLines: 3, minLines: 3, onChanged: (_) => setState(() {})),
          for (var i = 0; i < _options.length; i++) ...[
            const SizedBox(height: 20),
            // Figma: label and counter across the top, then the image button
            // left of the field.
            Row(children: [
              Expanded(child: Text.rich(TextSpan(text: 'Option ${i + 1}', children: [TextSpan(text: ' *', style: TextStyle(color: KColors.error))]), style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500))),
              ValueListenableBuilder(
                valueListenable: _options[i].text,
                builder: (_, v, _) => Text('${v.text.characters.length}/$kOptionMax', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 6),
                child: _options[i].image != null
                    ? GestureDetector(
                        onTap: () => _pickImage(_options[i]),
                        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(_options[i].image!.bytes, width: 36, height: 36, fit: BoxFit.cover)),
                      )
                    : SizedBox.square(
                        dimension: 36,
                        child: IconButton(
                          tooltip: 'Add image',
                          padding: EdgeInsets.zero,
                          onPressed: () => _pickImage(_options[i]),
                          icon: Icon(PhosphorIconsRegular.image, size: 24, color: KColors.iconDefault),
                        ),
                      ),
              ),
              Expanded(
                child: KeysTextField(
                  controller: _options[i].text,
                  hint: 'Add option',
                  maxLength: kOptionMax,
                  showCount: false,
                  error: _options[i].error,
                  onChanged: (_) => setState(() => _options[i].error = null),
                  fieldKey: Key('option-$i'),
                ),
              ),
            ]),
            if (_options.length > 2)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => setState(() => _options.removeAt(i)), style: TextButton.styleFrom(foregroundColor: KColors.error), child: const Text('Delete')),
              ),
          ],
          if (_options.length < kOptionsMax)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _options.add(_Option())),
                style: OutlinedButton.styleFrom(shape: const StadiumBorder(), foregroundColor: KColors.textPrimary),
                icon: const Icon(PhosphorIconsRegular.plus, size: 18),
                label: const Text('Add option'),
              ),
            ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Allow multiple answers', style: KText.paragraphMediumLarge),
            value: _multi,
            activeTrackColor: KColors.surfaceInverted,
            onChanged: (v) => setState(() => _multi = v),
          ),
          const SizedBox(height: 8),
          Text('Poll duration', style: KText.paragraphMediumLarge),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDuration,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
              child: Row(children: [Expanded(child: Text(kDurations[_duration]!, style: KText.paragraphLarge)), const Icon(PhosphorIconsRegular.caretDown)]),
            ),
          ),
          const SizedBox(height: 20),
          Text('Audience', style: KText.paragraphMediumLarge),
          const SizedBox(height: 8),
          // POL-04.3: fixed to all residents in Phase 1.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: KColors.surfaceInverted, borderRadius: BorderRadius.circular(KRadius.pill)),
            child: Text('All residents', style: KText.paragraphMediumSmall.copyWith(color: KColors.textInverse, fontSize: 13)),
          ),
        ]),
        bottom: KeysButton('Preview poll', onPressed: _question.text.trim().isEmpty ? null : _preview),
      ),
    );
  }
}

/// POL-05: preview, then post. Polls cannot be edited after publishing.
class PollPreviewScreen extends StatefulWidget {
  const PollPreviewScreen({super.key, required this.draft});
  final Map<String, dynamic> draft;
  @override
  State<PollPreviewScreen> createState() => _PollPreviewScreenState();
}

class _PollPreviewScreenState extends State<PollPreviewScreen> with Busy {
  Map<String, dynamic> get d => widget.draft;

  Future<void> _post() async {
    final api = context.api;
    await run(() async {
      final options = <Map<String, dynamic>>[];
      for (final o in d['options'] as List) {
        final img = o['image'] as PickedFile?;
        String? id;
        if (img != null) id = (await api.upload('/media', bytes: img.bytes, filename: img.name, mime: img.mime, query: {'kind': 'photo'}))['id'];
        options.add({'text': o['text'], 'mediaId': ?id});
      }
      final r = await api.post('/polls', {
        'question': d['question'],
        if ((d['promise'] as String).isNotEmpty) 'promise': d['promise'],
        'options': options,
        'multi': d['multi'],
        'duration': d['duration'],
      });
      if (!mounted) return;
      final post = Post(Map<String, dynamic>.from(r['post']));
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      router.go('/home', extra: {'refresh': true});
      messenger.showSnackBar(SnackBar(
        content: Text(r['message']),
        action: SnackBarAction(label: 'View post', textColor: KColors.brand, onPressed: () => router.push('/posts/${post.id}', extra: post)),
      ));
    }, onError: (e) => showToast(context, e is ApiException ? e.message : 'Posting failed.'));
  }

  @override
  Widget build(BuildContext context) {
    final me = context.session.me!;
    final hours = {'24h': 24, '48h': 48, '7d': 168, '2w': 336}[d['duration']]!;
    final preview = Poll({
      'question': d['question'],
      'promise': d['promise'],
      'multi': d['multi'],
      'closesAt': DateTime.now().add(Duration(hours: hours)).toIso8601String(),
      'closed': false,
      'totalVotes': 0,
      'canVote': false,
      'resultsVisible': false,
      'options': [for (final (i, o) in (d['options'] as List).indexed) {'id': '$i', 'text': o['text']}],
    });
    final fake = Post({'id': 'preview', 'kind': 'poll', 'author': {'id': me.id, 'name': me.fullName}, 'createdAt': DateTime.now().toIso8601String()});
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Preview poll', style: KText.headingSmall),
        const SizedBox(height: 16),
        PollBlock(post: fake, preview: preview, onChanged: (_) {}),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
          child: Text('Polls cannot be edited after publishing. Please proofread before posting.', style: KText.paragraphSmall),
        ),
      ]),
      bottom: KeysButton('Post', loading: busy, onPressed: _post),
    );
  }
}
