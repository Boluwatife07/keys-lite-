import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../verification/verification_screens.dart';

const kPromiseBg = Color(0xFFEDEAFB);
const kPromiseText = Color(0xFF6B5BD6);
const kResultFill = Color(0xFFE6F2DC);
const kWinner = Color(0xFF5AA02C);

/// POL-06 - POL-09: a poll inside a post. Votes are final (POL-Q1).
class PollBlock extends StatefulWidget {
  const PollBlock({super.key, required this.post, required this.onChanged, this.preview});
  final Post post;
  final void Function(Post) onChanged;
  /// Preview before publishing (POL-05.1): no voting.
  final Poll? preview;
  @override
  State<PollBlock> createState() => _PollBlockState();
}

class _PollBlockState extends State<PollBlock> with Busy {
  final Set<String> _picked = {};
  bool _promiseOpen = false;

  Poll get poll => widget.preview ?? widget.post.poll!;

  Future<void> _submit() async {
    await run(() async {
      final r = await context.api.post('/polls/${widget.post.id}/vote', {'optionIds': _picked.toList()});
      widget.onChanged(Post(Map<String, dynamic>.from(r['post'])));
    }, onError: (e) {
      if (!handleVerificationRequired(context, e)) showToast(context, e is ApiException ? e.message : 'Something went wrong.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = poll;
    final showResults = p.resultsVisible && (p.myVote != null || p.closed || widget.post.isMine);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(p.question, style: KText.headingXSmall.copyWith(fontSize: 20, height: 28 / 20)),
      if (p.promise != null && p.promise!.isNotEmpty) ...[
        const SizedBox(height: 8),
        InkWell(
          onTap: () => setState(() => _promiseOpen = !_promiseOpen),
          borderRadius: BorderRadius.circular(KRadius.sm),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: kPromiseBg, borderRadius: BorderRadius.circular(KRadius.sm)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Poll promise', style: KText.paragraphMediumSmall.copyWith(color: kPromiseText, fontSize: 13))),
                Icon(_promiseOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: kPromiseText),
              ]),
              if (_promiseOpen) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.promise!, style: KText.paragraphMedium)),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        const Icon(Icons.check_circle, size: 14),
        const SizedBox(width: 6),
        Text(p.multi ? 'Select one or more' : 'Select one', style: KText.paragraphSmall.copyWith(fontSize: 13)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(6)),
          child: Text(p.closed ? 'Closed' : timeLeft(p.closesAt), style: KText.paragraphSmall.copyWith(fontSize: 13)),
        ),
      ]),
      const SizedBox(height: 10),
      for (final o in p.options) ...[
        showResults ? _ResultRow(o, mine: p.myVote?.contains(o.id) == true, closed: p.closed) : _ChoiceRow(o, multi: p.multi, selected: _picked.contains(o.id), enabled: widget.preview == null && p.canVote, onTap: () {
          setState(() {
            if (p.multi) {
              _picked.contains(o.id) ? _picked.remove(o.id) : _picked.add(o.id);
            } else {
              _picked
                ..clear()
                ..add(o.id);
            }
          });
        }),
        const SizedBox(height: 8),
      ],
      Row(children: [
        Text(plural(p.totalVotes, 'Vote'), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        const Spacer(),
        if (p.myVote != null)
          Text('Already voted', style: KText.paragraphMediumSmall.copyWith(color: KColors.textTertiary))
        else if (!p.closed && widget.preview == null)
          SizedBox(
            width: 100,
            height: 36,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, disabledBackgroundColor: KColors.surfaceSubtle, shape: const StadiumBorder()),
              onPressed: _picked.isEmpty || busy ? null : _submit,
              child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit'),
            ),
          ),
      ]),
    ]);
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow(this.o, {required this.multi, required this.selected, required this.enabled, required this.onTap});
  final PollOption o;
  final bool multi, selected, enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: o.text,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(KRadius.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(KRadius.sm), border: Border.all(color: selected ? KColors.textPrimary : KColors.borderDefault)),
            child: Row(children: [
              Icon(
                multi ? (selected ? Icons.check_box : Icons.check_box_outline_blank) : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                color: enabled ? KColors.textPrimary : KColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(o.text, style: KText.paragraphMedium.copyWith(fontSize: 15))),
              if (o.imageUrl != null) _OptionImage(o),
            ]),
          ),
        ),
      );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.o, {required this.mine, required this.closed});
  final PollOption o;
  final bool mine, closed;
  @override
  Widget build(BuildContext context) {
    final pct = (o.percent ?? 0) / 100;
    final win = closed && o.winner;
    return Semantics(
      label: '${o.text}, ${o.percent ?? 0} percent, ${plural(o.votes ?? 0, 'vote')}${mine ? ', your vote' : ''}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(KRadius.sm), border: Border.all(color: KColors.borderDefault)),
        child: Stack(children: [
          Positioned.fill(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: pct, child: Container(color: kResultFill))),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: win ? kWinner : Colors.white, border: Border.all(color: win ? kWinner : KColors.borderDefault, width: 3)),
                child: Text('${o.percent ?? 0}%', style: KText.paragraphMediumSmall.copyWith(color: win ? Colors.white : KColors.textPrimary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.text, style: KText.paragraphMedium.copyWith(fontSize: 15)),
                  Row(children: [
                    Text(plural(o.votes ?? 0, 'vote'), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                    if (mine) ...[const SizedBox(width: 4), const Icon(Icons.check_circle, size: 14)],
                  ]),
                ]),
              ),
              if (o.imageUrl != null) _OptionImage(o),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// POL-06.5: option image opens full screen with the option text.
class _OptionImage extends StatelessWidget {
  const _OptionImage(this.o);
  final PollOption o;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.push('/media', extra: {'urls': [o.imageUrl!], 'index': 0, 'caption': o.text}),
        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(context.api.absolute(o.imageUrl!), width: 60, height: 56, fit: BoxFit.cover)),
      );
}
