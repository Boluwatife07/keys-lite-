import 'package:flutter/material.dart';
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

  Future<void> _filter() async {
    await showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Filter', style: KText.headingSmall)),
            RadioGroup<String>(
              groupValue: _status,
              onChanged: (v) {
                set(() => _status = v!);
                setState(() {});
              },
              child: Column(children: [for (final e in kStatusLabels.entries) RadioListTile<String>(value: e.key, title: Text(e.value), dense: true, activeColor: KColors.surfaceInverted)]),
            ),
            SwitchListTile(title: const Text('Closes today'), value: _today, activeTrackColor: KColors.surfaceInverted, onChanged: (v) {
              set(() => _today = v);
              setState(() {});
            }),
            Padding(padding: const EdgeInsets.all(16), child: KeysButton('Apply', onPressed: () => Navigator.pop(c))),
          ]),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Row(children: [
          Text(l == null ? '' : plural(l.length, 'item'), style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const Spacer(),
          ActionChip(avatar: const Icon(Icons.filter_list, size: 16), label: const Text('Filter'), onPressed: _filter),
        ]),
        if (l == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (l != null && l.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No committee proposals yet', style: KText.headingXSmall))),
        for (final p in l ?? <Map<String, dynamic>>[]) ...[const SizedBox(height: 12), ProposalCard(p: p, onChanged: _load)],
      ]),
    );
  }
}

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
    return InkWell(
      onTap: () async {
        await context.push('/board/proposals/${p['id']}');
        onChanged();
      },
      borderRadius: BorderRadius.circular(KRadius.md),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            color: canVote ? KColors.brandSubtle : KColors.surfaceSubtle,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              Expanded(child: Text(p['typeLabel'], style: KText.paragraphMediumLarge)),
              if (!open) Chip(label: Text(statusLabel(p['status']))),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: canVote ? KColors.brand : KColors.textTertiary, borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.groups, size: 16),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['type'] == 'join' ? '${subject.name} has requested to join the committee as ${p['role']}.' : (p['reason'] ?? ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: KText.paragraphMedium),
              if (p['type'] != 'join') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Avatar(subject.photoUrl, size: 24), const SizedBox(width: 8), Text(subject.name, style: KText.paragraphMediumLarge.copyWith(fontSize: 14))]),
                    if (p['type'] == 'reassign')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(p['role'] ?? ''), const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.arrow_forward, size: 16)), Text(p['proposedRole'] ?? '')]),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.schedule, size: 14, color: KColors.textSecondary),
                const SizedBox(width: 4),
                Text(open ? timeLeft(DateTime.parse(p['closesAt']).toLocal()) : statusLabel(p['status']), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Avatar(creator.photoUrl, size: 24),
                const SizedBox(width: 8),
                Expanded(child: Text('Created by:\n${creator.name}', style: KText.paragraphSmall)),
                if (open)
                  SizedBox(
                    height: 34,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, disabledBackgroundColor: KColors.surfaceSubtle, shape: const StadiumBorder()),
                      onPressed: canVote ? () => context.push('/board/proposals/${p['id']}').then((_) => onChanged()) : null,
                      child: Text(canVote ? 'Vote' : 'Already voted'),
                    ),
                  ),
              ]),
            ]),
          ),
        ]),
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
        builder: (s) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Why are you voting no?', style: KText.headingSmall),
            const SizedBox(height: 12),
            KeysTextField(controller: c, maxLength: 500, maxLines: 4, autofocus: true),
            const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final subject = PersonRef(Map<String, dynamic>.from(p['subject']));
    final creator = PersonRef(Map<String, dynamic>.from(p['creator']));
    final a = p['answers'] as Map?;
    final res = p['results'] as Map?;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
            Expanded(child: Text(value, style: KText.paragraphMediumLarge.copyWith(fontSize: 14))),
          ]),
        );
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p['typeLabel'], style: KText.headingSmall),
        const SizedBox(height: 12),
        row('Created by', creator.name),
        row('Category', p['category']),
        row('Action', {'join': 'Join', 'reassign': 'Reassign', 'remove': 'Remove'}[p['type']]!),
        row(p['type'] == 'join' ? 'Applicant' : 'Member', subject.name),
        row(p['type'] == 'join' ? 'Role' : 'Current role', p['role'] ?? ''),
        if (p['proposedRole'] != null) row('Proposed role', p['proposedRole']),
        row('Status', statusLabel(p['status'])),
        row('Vote close', p['status'] == 'pending' || p['status'] == 'awaiting_approval' ? timeLeft(DateTime.parse(p['closesAt']).toLocal()) : 'Closed'),
        row('Date created', DateFormat('d MMM yyyy').format(DateTime.parse(p['createdAt']).toLocal())),
        if (p['outcomeNote'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('NEW SEAT PROTECTION\n${p['outcomeNote']}', style: KText.paragraphSmall.copyWith(color: KColors.error))),
        if (p['swap'] != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
            child: Text('Role swapping\n${p['swap']['note']}', style: KText.paragraphSmall),
          ),
        if (p['reason'] != null) ...[
          const SizedBox(height: 16),
          Text(p['type'] == 'remove' ? 'Reason for removal' : 'Reason for reassignment', style: KText.paragraphMediumLarge),
          const SizedBox(height: 4),
          Text(p['reason'], style: KText.paragraphMedium),
        ],
        if (a != null) ...[
          const SizedBox(height: 16),
          if (a['hasLeadership'] == true) ...[Text('Leadership role: ${a['leadershipTitle']}', style: KText.paragraphMediumLarge), if (a['leadershipDescription'] != null) Text(a['leadershipDescription']), const SizedBox(height: 12)],
          Text('What makes you qualified for this role?', style: KText.paragraphMediumLarge),
          Text(a['qualified'], style: KText.paragraphMedium),
          const SizedBox(height: 12),
          Text('What will you do differently in this role?', style: KText.paragraphMediumLarge),
          Text(a['aim'], style: KText.paragraphMedium),
        ],
        const SizedBox(height: 24),
        if (p['canVote'] == true) ...[
          Text('Do you approve of this request?', style: KText.headingXSmall),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: KeysButton('No', variant: ButtonVariant.outline, onPressed: busy ? null : () => _vote('no'))),
            const SizedBox(width: 12),
            Expanded(child: KeysButton('Yes', loading: busy, onPressed: () => _vote('yes'))),
          ]),
        ] else if (p['myVote'] != null)
          Text('Already voted', style: KText.paragraphMediumLarge.copyWith(color: KColors.textSecondary)),
        if (res != null) ...[
          const SizedBox(height: 16),
          _Bar(label: 'Yes', percent: res['yesPercent'], color: KColors.success),
          const SizedBox(height: 8),
          _Bar(label: 'No', percent: res['noPercent'], color: KColors.error),
          const SizedBox(height: 8),
          Text('${res['yes'] + res['no']} of ${res['eligible']} eligible voters have voted', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 12),
          for (final v in List<Map<String, dynamic>>.from(res['voters']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(v['person']?['photoUrl'], size: 32),
              title: Text(v['person']?['name'] ?? ''),
              subtitle: v['reason'] == null ? null : Text(v['reason']),
              trailing: Text(v['choice'] == 'yes' ? 'Yes' : 'No', style: KText.paragraphMediumLarge.copyWith(color: v['choice'] == 'yes' ? KColors.success : KColors.error)),
            ),
        ],
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.percent, required this.color});
  final String label;
  final int percent;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 36, child: Text(label, style: KText.paragraphMediumLarge.copyWith(fontSize: 14))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KRadius.pill),
            child: LinearProgressIndicator(value: percent / 100, minHeight: 10, color: color, backgroundColor: KColors.surfaceSubtle),
          ),
        ),
        SizedBox(width: 48, child: Text('$percent%', textAlign: TextAlign.right, style: KText.paragraphMedium)),
      ]);
}
