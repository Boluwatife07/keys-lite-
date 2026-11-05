import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// Round profile photo with the default avatar when none is set (FED-09.2).
class Avatar extends StatelessWidget {
  const Avatar(this.url, {super.key, this.size = 40});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: KColors.surfaceSubtle,
        backgroundImage: url == null ? null : NetworkImage(context.api.absolute(url!)),
        child: url == null ? Icon(PhosphorIconsRegular.user, size: size * 0.5, color: KColors.textTertiary) : null,
      );
}

/// Yellow committee mark shown after a committee member's name.
class CommitteeMark extends StatelessWidget {
  const CommitteeMark({super.key, this.size = 16});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Committee member',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: KColors.brand, shape: BoxShape.circle),
          child: Icon(PhosphorIconsFill.star, size: size * 0.7, color: KColors.staticBlack),
        ),
      );
}

/// AVW-09.3 / FED-09.1: "Unverified" label; tap explains it.
class UnverifiedChip extends StatelessWidget {
  const UnverifiedChip({super.key, this.text = 'Unverified'});
  final String text;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'This resident has not verified their home address yet.',
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: KColors.selectedSubtle, borderRadius: BorderRadius.circular(4)),
          child: Text(text, style: KText.paragraphMediumSmall.copyWith(fontSize: 11, color: KColors.selected)),
        ),
      );
}

/// Name with committee mark, then role or Unverified label and a subtitle.
class AuthorLine extends StatelessWidget {
  const AuthorLine(this.p, {super.key, this.subtitle, this.trailing});
  final PersonRef p;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final sub = [?p.role, ?subtitle].join(' • ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(child: Text(p.name, style: KText.paragraphMediumLarge.copyWith(fontSize: 15), overflow: TextOverflow.ellipsis)),
        if (p.isCommittee) ...[const SizedBox(width: 4), const CommitteeMark(size: 14)],
        if (trailing != null) ...[const Spacer(), ?trailing],
      ]),
      const SizedBox(height: 2),
      Row(children: [
        if (!p.verified) ...[const UnverifiedChip(), const SizedBox(width: 6)],
        if (sub.isNotEmpty) Flexible(child: Text(sub, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary), overflow: TextOverflow.ellipsis)),
      ]),
    ]);
  }
}

/// Text with @tags highlighted in the design's orange.
class TaggedText extends StatelessWidget {
  const TaggedText(this.text, {super.key, this.mentions = const [], this.style, this.maxLines, this.onTagTap});
  final String text;
  final List<Map<String, dynamic>> mentions;
  final TextStyle? style;
  final int? maxLines;
  final void Function(String userId)? onTagTap;
  @override
  Widget build(BuildContext context) {
    final base = style ?? KText.paragraphLarge;
    final names = mentions.map((m) => m['name'] as String).where((n) => n.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty) return Text(text, style: base, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
    final re = RegExp(names.map((n) => '@?${RegExp.escape(n)}').join('|'));
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(0), style: base.copyWith(color: KColors.progressStart, fontWeight: FontWeight.w500)));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(TextSpan(style: base, children: spans), maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
  }
}

class SheetAction {
  const SheetAction(this.icon, this.title, this.onTap, {this.subtitle, this.destructive = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
}

Future<void> showActionSheet(BuildContext context, List<SheetAction> actions) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.destructive ? KColors.error : KColors.textPrimary),
              title: Text(a.title, style: KText.paragraphMediumLarge.copyWith(color: a.destructive ? KColors.error : null)),
              subtitle: a.subtitle == null ? null : Text(a.subtitle!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              onTap: () {
                Navigator.pop(c);
                a.onTap();
              },
            ),
        ])),
        ),
      ),
    );

/// Yes / No confirmation sheet used for delete, block, unmute, log out...
Future<bool> confirmSheet(BuildContext context, {required String title, required String body, required String confirm, String cancel = 'Cancel', bool destructive = false, String? footnote}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: KText.headingSmall),
        const SizedBox(height: 8),
        Text(body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
        if (footnote != null) ...[const SizedBox(height: 8), Text(footnote, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))],
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: KeysButton(cancel, variant: ButtonVariant.secondary, onPressed: () => Navigator.pop(c, false))),
          const SizedBox(width: 12),
          Expanded(child: KeysButton(confirm, onPressed: () => Navigator.pop(c, true))),
        ]),
      ]),
    ),
  );
  return r == true;
}

/// XFR-03: the shared report form. "Other" needs text; Submit inactive until a reason is picked.
Future<void> showReportSheet(BuildContext context, {required String itemType, required String itemId, required String title, String? intro}) async {
  final api = context.api;
  List<String> reasons;
  try {
    reasons = List<String>.from((await api.get('/reports/reasons'))['reasons']);
  } catch (_) {
    if (context.mounted) showToast(context, 'Could not load the report form. Please try again.');
    return;
  }
  if (!context.mounted) return;
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _ReportForm(itemType: itemType, itemId: itemId, title: title, intro: intro, reasons: reasons),
  );
  if (sent == true && context.mounted) showToast(context, 'Your report has been submitted');
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({required this.itemType, required this.itemId, required this.title, required this.reasons, this.intro});
  final String itemType, itemId, title;
  final String? intro;
  final List<String> reasons;
  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> with Busy {
  String? _reason;
  final _text = TextEditingController();
  String? _error;

  bool get _ready => _reason != null && (_reason != 'Other' || _text.text.trim().isNotEmpty);

  Future<void> _submit() async {
    await run(() async {
      await context.api.post('/reports', {'itemType': widget.itemType, 'itemId': widget.itemId, 'reason': _reason, if (_text.text.trim().isNotEmpty) 'text': _text.text.trim()});
      if (mounted) Navigator.pop(context, true);
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong.'));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: KText.headingSmall),
          const SizedBox(height: 8),
          Text(widget.intro ?? "Tell us why you are reporting this. They won't be notified that you reported them.", style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(children: [
              for (final r in widget.reasons)
                RadioListTile<String>(value: r, title: Text(r, style: KText.paragraphMedium), dense: true, contentPadding: EdgeInsets.zero, activeColor: KColors.surfaceInverted),
            ]),
          ),
          if (_reason == 'Other') KeysTextField(controller: _text, hint: 'Tell us more', maxLength: 500, maxLines: 3, onChanged: (_) => setState(() {})),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorLine(_error!)),
          const SizedBox(height: 16),
          KeysButton('Submit', loading: busy, onPressed: _ready ? _submit : null),
        ]),
      ),
    );
  }
}

/// Mute straight from a post (FED-17.2): toast with Undo.
Future<void> muteFromPost(BuildContext context, PersonRef p, VoidCallback onChanged) async {
  final api = context.api;
  try {
    final r = await api.post('/users/${p.id}/mute');
    onChanged();
    if (!context.mounted) return;
    showToast(context, r['message'], actionLabel: 'Undo', onAction: () async {
      await api.delete('/users/${p.id}/mute');
      onChanged();
    });
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
  }
}

/// FED-17.3 / PRF-05.1
Future<bool> blockPerson(BuildContext context, PersonRef p) async {
  final ok = await confirmSheet(
    context,
    title: 'Block ${p.name}?',
    body: "You won't see their posts or comments, they won't be able to message you and you won't receive notifications from them.",
    footnote: "They won't be notified that you blocked or reported them.",
    confirm: 'Block',
  );
  if (!ok || !context.mounted) return false;
  try {
    final r = await context.api.post('/users/${p.id}/block');
    if (context.mounted) showToast(context, r['message']);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
    return false;
  }
}

/// FED-16: copy link or the phone's share sheet.
Future<void> showShareSheet(BuildContext context, String link) => showActionSheet(context, [
      SheetAction(PhosphorIconsRegular.link, 'Copy link', () async {
        await context.deps.sharer.copy(link);
        if (context.mounted) showToast(context, 'Link copied');
      }),
      SheetAction(PhosphorIconsRegular.shareFat, 'Share via', () => context.deps.sharer.share(link)),
    ]);

const kMuteDurations = {'1h': 'For 1 hour', '24h': 'For 24 hours', '1w': 'For 1 week', 'forever': 'Until I turn it back on'};

/// UPD-09 / CHT-02.2: choose how long to mute; returns '1h', '24h', '1w' or 'forever'.
Future<String?> pickMuteDuration(BuildContext context, {required String title, required String body}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _MuteSheet(title: title, body: body),
    );

class _MuteSheet extends StatefulWidget {
  const _MuteSheet({required this.title, required this.body});
  final String title, body;
  @override
  State<_MuteSheet> createState() => _MuteSheetState();
}

class _MuteSheetState extends State<_MuteSheet> {
  String? _pick;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: KText.headingSmall),
            const SizedBox(height: 8),
            Text(widget.body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _pick,
              onChanged: (v) => setState(() => _pick = v),
              child: Column(children: [
                for (final e in kMuteDurations.entries)
                  RadioListTile<String>(value: e.key, title: Text(e.value, style: KText.paragraphLarge), contentPadding: EdgeInsets.zero, activeColor: KColors.surfaceInverted),
              ]),
            ),
            const SizedBox(height: 12),
            KeysButton('Mute', onPressed: _pick == null ? null : () => Navigator.pop(context, _pick)),
          ]),
        ),
      );
}

/// Black date block used on update cards and the update detail (UPD-01.2).
class DateBlock extends StatelessWidget {
  const DateBlock(this.date, {super.key, this.dot = false, this.size = 46});
  final DateTime date;
  final bool dot;
  final double size;
  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  @override
  Widget build(BuildContext context) => Semantics(
        label: '${date.day} ${_m[date.month - 1]}',
        child: SizedBox(
          width: size,
          height: size * 1.3,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              decoration: BoxDecoration(color: KColors.surfaceInverted, borderRadius: BorderRadius.circular(KRadius.sm)),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${date.day}', style: KText.paragraphMediumLarge.copyWith(color: KColors.textInverse, fontWeight: FontWeight.w700, height: 1.1)),
                  const SizedBox(height: 4),
                  Text(_m[date.month - 1], style: KText.paragraphSmall.copyWith(color: KColors.textInverse, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (dot)
              Positioned(
                right: -3,
                top: -3,
                child: Container(width: 11, height: 11, decoration: BoxDecoration(color: KColors.error, shape: BoxShape.circle, border: Border.all(color: KColors.surfaceDefault, width: 1.5))),
              ),
          ]),
        ),
      );
}

/// Document row with type badge, size and a download icon.
class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.name, required this.meta, required this.onTap, this.fileType = 'PDF', this.dense = false});
  final String name, meta, fileType;
  final VoidCallback onTap;
  final bool dense;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        label: 'Download $name',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KRadius.md),
          child: Container(
            padding: EdgeInsets.all(dense ? 8 : 12),
            decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
            child: ExcludeSemantics(
              child: Row(children: [
                Container(
                  width: dense ? 36 : 44, height: dense ? 42 : 52, alignment: Alignment.center,
                  decoration: BoxDecoration(color: KColors.errorSubtle, borderRadius: BorderRadius.circular(6)),
                  child: Text(fileType, style: KText.paragraphMediumSmall.copyWith(color: KColors.error, fontSize: dense ? 10 : 12)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: KText.paragraphMediumLarge.copyWith(fontSize: dense ? 14 : 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(meta, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  ]),
                ),
                const Icon(PhosphorIconsRegular.downloadSimple),
              ]),
            ),
          ),
        ),
      );
}

String fileSize(num bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';
