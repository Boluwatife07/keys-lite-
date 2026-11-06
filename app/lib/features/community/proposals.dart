import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';

const kStatusLabels = {
  'all': 'Show all',
  'pending': 'Pending',
  'awaiting_approval': 'Awaiting Approval',
  'approved': 'Approved',
  'declined': 'Declined',
  'added': 'Added',
  'no_longer_applicable': 'No longer applicable',
};

String statusLabel(String s) => kStatusLabels[s] ?? s;

/// VOT-01: committee proposals with a status filter and "Closes today".
class ProposalsList extends StatefulWidget {
  const ProposalsList({super.key});
  @override
  State<ProposalsList> createState() => _ProposalsListState();
}

class _ProposalsListState extends State<ProposalsList> {
  List<Map<String, dynamic>>? _list;
  String _status = 'all';
  bool _today = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/board/proposals', query: {'status': _status, if (_today) 'closesToday': '1'});
      if (mounted) setState(() => _list = List<Map<String, dynamic>>.from(r['proposals']));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  // Figma 3579:900744: title + close, ruled text rows with a check.
  Future<void> _filter() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: KColors.surfaceDefault,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(children: [
              Expanded(child: Text('Filter', style: TextStyle(fontFamily: 'Inter', fontSize: 18, height: 26 / 18, color: KColors.textPrimary))),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(c), icon: Icon(PhosphorIconsRegular.x, size: 24, color: KColors.iconDefault)),
            ]),
          ),
          Container(height: 1, color: KColors.borderDefault),
          const SizedBox(height: 8),
          for (final e in kStatusLabels.entries)
            InkWell(
              onTap: () => Navigator.pop(c, e.key),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: Text(e.value, style: KText.paragraphMedium)),
                    if (_status == e.key) Icon(PhosphorIconsRegular.check, size: 20, color: KColors.iconDefault),
                  ]),
                ),
              ),
            ),
          InkWell(
            onTap: () {
              setState(() => _today = !_today);
              Navigator.pop(c, _status);
            },
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: Text('Closes today', style: KText.paragraphMedium)),
                  if (_today) Icon(PhosphorIconsRegular.check, size: 20, color: KColors.iconDefault),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (v == null) return;
    setState(() => _status = v);
    _load();
  }

  // Figma 3579:900702: "n items" + Filter pill over a grey band, then cards.
  @override
  Widget build(BuildContext context) {
    final l = _list;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.surfaceSubtle, width: 8))),
          child: Row(children: [
            Text(l == null ? '' : plural(l.length, 'item'), style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const Spacer(),
            Semantics(
              button: true,
              child: Material(
                color: KColors.surfaceSubtle,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _filter,
                  child: SizedBox(
                    height: 36,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Filter', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: KColors.textPrimary)),
                        const SizedBox(width: 6),
                        Icon(PhosphorIconsRegular.funnelSimple, size: 18, color: KColors.iconDefault),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
        if (l == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (l != null && l.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No committee proposals yet', style: KText.headingXSmall))),
        for (final p in l ?? <Map<String, dynamic>>[]) Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 0), child: ProposalCard(p: p, onChanged: _load)),
      ]),
    );
  }
}

const _kStatusColors = {
  'pending': (Color(0xFFFFD12A), Color(0xFF171717)),
  'awaiting_approval': (Color(0xFF5E5E5E), Colors.white),
  'approved': (Color(0xFF21AE48), Colors.white),
  'added': (Color(0xFF21AE48), Colors.white),
  'declined': (Color(0xFFDE1135), Colors.white),
  'no_longer_applicable': (Color(0xFFA6A6A6), Colors.white),
};

/// Figma status tag: 24pt, radius 8, Inter Medium 12.
class StatusTag extends StatelessWidget {
  const StatusTag(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _kStatusColors[status] ?? (KColors.surfaceSubtle, KColors.textPrimary);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Center(widthFactor: 1, child: Text(statusLabel(status), style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: fg))),
    );
  }
}

/// The grey subject box on cards: person, and for reassign "from -> to".
class _SubjectBox extends StatelessWidget {
  const _SubjectBox({required this.subject, this.from, this.to});
  final PersonRef subject;
  final String? from, to;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Avatar(subject.photoUrl, size: 24),
            const SizedBox(width: 8),
            Flexible(child: Text(subject.name, style: KText.paragraphLarge, overflow: TextOverflow.ellipsis)),
          ]),
          if (to != null) ...[
            const SizedBox(height: 12),
            Container(
              height: 40,
              decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: Text(from ?? '', textAlign: TextAlign.center, style: KText.paragraphLarge)),
                Icon(PhosphorIconsRegular.arrowRight, size: 20, color: KColors.iconMuted),
                Expanded(child: Text(to!, textAlign: TextAlign.center, style: KText.paragraphLarge)),
              ]),
            ),
          ],
        ]),
      );
}

/// Figma proposal card (3579:900702): yellow title band with the committee
/// mark, reason, subject box, time left, creator and Vote.
class ProposalCard extends StatelessWidget {
  const ProposalCard({super.key, required this.p, required this.onChanged});
  final Map<String, dynamic> p;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final open = p['status'] == 'pending' || p['status'] == 'awaiting_approval';
    final canVote = p['canVote'] == true;
    final subject = PersonRef(Map<String, dynamic>.from(p['subject']));
    final creator = PersonRef(Map<String, dynamic>.from(p['creator']));
    final text = p['type'] == 'join' ? '${subject.name} has requested to join the committee as ${p['role']}.' : (p['reason'] ?? '');
    Future<void> openIt() async {
      await context.push('/board/proposals/${p['id']}');
      onChanged();
    }

    return Semantics(
      button: true,
      label: '${p['typeLabel']}, ${statusLabel(p['status'])}',
      child: Material(
        color: KColors.surfaceDefault,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: KColors.brandSubtle, width: 2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openIt,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              color: KColors.brandSubtle,
              padding: const EdgeInsets.only(left: 16),
              height: 48,
              child: Row(children: [
                Expanded(child: Text(p['typeLabel'], style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w600))),
                if (!open) Padding(padding: const EdgeInsets.only(right: 8), child: StatusTag(p['status'])),
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 32,
                    height: 34,
                    decoration: const BoxDecoration(color: Color(0xFFFFD12A), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(4))),
                    child: const Icon(PhosphorIconsFill.usersThree, size: 18, color: Color(0xFF171717)),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: KText.paragraphMedium),
                if (p['type'] != 'join') ...[
                  const SizedBox(height: 16),
                  _SubjectBox(subject: subject, from: p['type'] == 'reassign' ? p['role'] : null, to: p['type'] == 'reassign' ? p['proposedRole'] : null),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Icon(PhosphorIconsRegular.clockCountdown, size: 16, color: KColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(open ? timeLeft(DateTime.parse(p['closesAt']).toLocal()) : 'Closed', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Avatar(creator.photoUrl, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Created by:', style: TextStyle(fontFamily: 'Inter', fontSize: 10, height: 1.4, color: KColors.textSecondary)),
                      Text(creator.name, style: KText.paragraphSmall.copyWith(fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  if (open)
                    SizedBox(
                      height: 36,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: KColors.surfaceInverted,
                          foregroundColor: KColors.textInverse,
                          disabledBackgroundColor: KColors.surfaceSubtle,
                          disabledForegroundColor: KColors.textDisabled,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: canVote ? openIt : null,
                        child: Text(canVote ? 'Vote' : 'Already voted'),
                      ),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// VOT-02 - VOT-04: details, "Do you approve of this request?", results.
class ProposalDetailScreen extends StatefulWidget {
  const ProposalDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<ProposalDetailScreen> createState() => _ProposalDetailScreenState();
}

class _ProposalDetailScreenState extends State<ProposalDetailScreen> with Busy {
  Map<String, dynamic>? _p;
  bool _more = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.api.get('/board/proposals/${widget.id}');
    if (mounted) setState(() => _p = Map<String, dynamic>.from(r['proposal']));
  }

  Future<void> _vote(String choice) async {
    String? reason;
    // VOT-03.2: No on reassign/remove needs a reason.
    if (choice == 'no' && _p!['type'] != 'join') {
      final c = TextEditingController();
      reason = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: KColors.surfaceDefault,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (s) => Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(s).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Why are you voting no?', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500, height: 26 / 18, color: KColors.textPrimary)),
            const SizedBox(height: 16),
            KeysTextField(controller: c, maxLength: 500, maxLines: 4, minLines: 3, autofocus: true),
            const SizedBox(height: 16),
            KeysButton('Submit vote', onPressed: () => Navigator.pop(s, c.text.trim())),
          ]),
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    await run(() async {
      final r = await context.api.post('/board/proposals/${widget.id}/vote', {'choice': choice, 'reason': ?reason});
      setState(() => _p = Map<String, dynamic>.from(r['proposal']));
    });
  }

  Widget _cell(String label, Widget value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.borderDefault))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: KText.paragraphSmall.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          value,
        ]),
      );

  Widget _section(String title, Widget child, {bool rule = true}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: rule ? Border(bottom: BorderSide(color: KColors.borderDefault)) : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: KText.paragraphLarge.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _person(PersonRef p, {String? role, double size = 64}) => Row(children: [
        Avatar(p.photoUrl, size: size),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.name, style: TextStyle(fontFamily: 'Inter', fontSize: size > 56 ? 18 : 14, fontWeight: FontWeight.w600, color: KColors.textPrimary))),
              if (p.isCommittee) ...[const SizedBox(width: 4), const CommitteeMark(size: 14)],
            ]),
            if ((role ?? p.role) != null) Text(role ?? p.role!, style: KText.paragraphMedium.copyWith(color: size > 56 ? KColors.textSecondary : KColors.textPrimary)),
          ]),
        ),
      ]);

  Widget _voteButton(String label, IconData icon, String choice) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: KColors.surfaceMuted,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: busy ? null : () => _vote(choice),
              child: SizedBox(
                height: 48,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 20, color: KColors.iconDefault),
                  const SizedBox(width: 8),
                  ExcludeSemantics(child: Text(label, style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500))),
                ]),
              ),
            ),
          ),
        ),
      );

  // Figma 3579:900941 / 900964 / 900988 / 901036 / 900805.
  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final subject = PersonRef(Map<String, dynamic>.from(p['subject']));
    final creator = PersonRef(Map<String, dynamic>.from(p['creator']));
    final a = p['answers'] as Map?;
    final res = p['results'] as Map?;
    final open = p['status'] == 'pending' || p['status'] == 'awaiting_approval';
    final grey = KText.paragraphMedium.copyWith(color: KColors.textSecondary);
    final body = KText.paragraphLarge;
    final swapWith = p['swap'] == null ? null : PersonRef(Map<String, dynamic>.from(p['swap']['with']));
    Widget pair(Widget l, Widget r) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: l), const SizedBox(width: 16), Expanded(child: r)]);
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: const PageHeader('View proposal', bottomBorder: true),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        // Facts grid
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.surfaceSubtle, width: 8))),
          child: Column(children: [
            pair(
              _cell('Created by', Row(children: [Avatar(creator.photoUrl, size: 24), const SizedBox(width: 8), Flexible(child: Text(creator.name, style: grey, overflow: TextOverflow.ellipsis))])),
              _cell('Category', Text(p['category'], style: grey)),
            ),
            if (_more) ...[
              pair(
                _cell('Status', Align(alignment: Alignment.centerLeft, child: StatusTag(p['status']))),
                _cell('Action', Text({'join': 'Join', 'reassign': 'Reassign', 'remove': 'Remove'}[p['type']]!, style: grey)),
              ),
              pair(
                _cell('Vote close', Text(open ? timeLeft(DateTime.parse(p['closesAt']).toLocal()) : 'Closed', style: grey)),
                _cell('Date created', Text(DateFormat("EEE, MMM d 'at' h:mm a").format(DateTime.parse(p['createdAt']).toLocal()), style: grey)),
              ),
            ],
            const SizedBox(height: 8),
            // Figma: blue underlined Medium 14 link.
            InkWell(
              onTap: () => setState(() => _more = !_more),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(_more ? 'Show less' : 'Show more', style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500, color: KColors.textLink, decoration: TextDecoration.underline, decorationColor: KColors.textLink)),
              ),
            ),
          ]),
        ),
        if (p['outcomeNote'] != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: KColors.errorSubtle, borderRadius: BorderRadius.circular(12)),
            child: Text('New seat protection: ${p['outcomeNote']}', style: KText.paragraphSmall),
          ),
        _section('Subject', _person(subject, role: p['type'] == 'join' ? '' : null), rule: p['type'] != 'join'),
        if (p['type'] == 'join')
          _section('Role', Text(p['role'] ?? '', style: body), rule: false)
        else if (p['type'] == 'reassign')
          _section(
            'Proposed role',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              swapWith != null ? _person(swapWith, size: 56) : Text(p['proposedRole'] ?? '', style: body),
              if (p['swap'] != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFFE37F))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(PhosphorIconsRegular.info, size: 18, color: KColors.iconDefault),
                      const SizedBox(width: 8),
                      Text('Role swapping', style: KText.paragraphSmall.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 8),
                    Text(p['swap']['note'], style: KText.paragraphSmall),
                  ]),
                ),
              ],
            ]),
          )
        else
          _section('Current role', Text(p['role'] ?? '', style: body)),
        if (p['reason'] != null) _section(p['type'] == 'remove' ? 'Reason for removal' : 'Reason for reassignment', Text(p['reason'], style: body), rule: false),
        if (a != null) ...[
          if (a['hasLeadership'] == true) _section('Leadership role', Text([a['leadershipTitle'], a['leadershipDescription']].whereType<String>().join('\n'), style: body), rule: false),
          _section('What makes you qualified for this role?', Text(a['qualified'], style: body), rule: false),
          _section('What will you do differently in this role?', Text(a['aim'], style: body), rule: false),
        ],
        Container(height: 8, color: KColors.surfaceSubtle),
        if (p['canVote'] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Do you approve of this request?', style: KText.paragraphLarge.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 20),
              _voteButton('Yes', PhosphorIconsRegular.check, 'yes'),
              _voteButton('No', PhosphorIconsRegular.x, 'no'),
            ]),
          ),
        if (res != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Vote results', style: KText.paragraphLarge.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 20),
              _Bar(label: 'Yes', icon: PhosphorIconsRegular.check, percent: res['yesPercent'], mine: p['myVote'] == 'yes'),
              const SizedBox(height: 10),
              _Bar(label: 'No', icon: PhosphorIconsRegular.x, percent: res['noPercent'], mine: p['myVote'] == 'no'),
              const SizedBox(height: 8),
              Text('${res['yes'] + res['no']} of ${res['eligible']} eligible voters have voted', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              const SizedBox(height: 16),
              _VoterTable(voters: List<Map<String, dynamic>>.from(res['voters'])),
            ]),
          ),
      ]),
    );
  }
}

/// Figma result bar: 48pt grey pill with a yellow fill, icon + label, %.
class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.icon, required this.percent, this.mine = false});
  final String label;
  final IconData icon;
  final int percent;
  final bool mine;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label $percent percent${mine ? ', your vote' : ''}',
        child: ExcludeSemantics(
          child: Container(
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: KColors.surfaceMuted, borderRadius: BorderRadius.circular(9999)),
            child: Stack(fit: StackFit.expand, children: [
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (percent.clamp(0, 100) / 100).clamp(percent > 0 ? 0.25 : 0, 1).toDouble(),
                child: Container(decoration: BoxDecoration(color: const Color(0xFFFFD12A), borderRadius: BorderRadius.circular(9999))),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Icon(icon, size: 22, color: const Color(0xFF171717)),
                  const SizedBox(width: 8),
                  Text(label, style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500, color: percent > 0 ? const Color(0xFF171717) : KColors.textPrimary)),
                  const Spacer(),
                  Text('$percent%', style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Figma voter table: two ruled columns, Yes and No, inside a grey frame.
class _VoterTable extends StatelessWidget {
  const _VoterTable({required this.voters});
  final List<Map<String, dynamic>> voters;
  @override
  Widget build(BuildContext context) {
    final yes = voters.where((v) => v['choice'] == 'yes').toList();
    final no = voters.where((v) => v['choice'] == 'no').toList();
    final rows = yes.length > no.length ? yes.length : no.length;
    final line = BorderSide(color: KColors.borderDefault);
    Widget cell(Map<String, dynamic>? v, {bool right = false}) => Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(border: Border(top: line, left: right ? line : BorderSide.none)),
            child: v == null
                ? const SizedBox()
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(v['person']?['photoUrl'], size: 24),
                      const SizedBox(width: 8),
                      Flexible(child: Text(v['person']?['name'] ?? '', overflow: TextOverflow.ellipsis, style: KText.paragraphSmall)),
                    ]),
                    if (v['reason'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(v['reason'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
                  ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(16)),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(8)),
        child: IntrinsicHeight(
          child: Column(children: [
            Row(children: [
              Expanded(child: SizedBox(height: 44, child: Center(child: Text('Yes', style: KText.paragraphMedium)))),
              Expanded(child: Container(height: 44, decoration: BoxDecoration(border: Border(left: line)), child: Center(child: Text('No', style: KText.paragraphMedium)))),
            ]),
            for (var i = 0; i < rows; i++)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  cell(i < yes.length ? yes[i] : null),
                  cell(i < no.length ? no[i] : null, right: true),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
