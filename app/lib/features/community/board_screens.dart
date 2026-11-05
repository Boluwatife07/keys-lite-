import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/models.dart' show formatCount;
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';
import '../verification/verification_screens.dart';

Scaffold _page(BuildContext context, String title, Widget body, {List<Widget>? actions}) => Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, title: Text(title, style: KText.headingXSmall), actions: actions),
      body: body,
    );

/// CBM-09: the committee board with All / Members / Champions.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  Map<String, dynamic>? _b;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.api.get('/board');
    if (mounted) setState(() => _b = r);
  }

  Future<void> _seatTap(Map<String, dynamic> s) async {
    final b = _b!;
    if (s['status'] != 'unoccupied' || b['mySeat'] != null || b['myApplication'] != null) return;
    final preset = s['kind'] == 'preset';
    await context.push('/board/join', extra: preset ? {'role': s['role']} : {'seatId': s['id'], 'role': s['role']});
    _load();
  }

  Future<void> _actions(Map<String, dynamic> s) async {
    final b = _b!;
    final me = context.session.me!;
    final occ = PersonRef(Map<String, dynamic>.from(s['occupant']));
    final mine = occ.id == me.id;
    final iAmCommittee = b['mySeat'] != null && b['mySeat']['kind'] != 'champion';
    final voting = b['votingAvailable'] == true;
    final items = <SheetAction>[
      if (mine) ...[
        // CBM-15.4: reassign needs a board of 5+.
        if (voting && s['kind'] != 'champion') SheetAction(Icons.swap_horiz, 'Reassign my role', () => _propose('reassign', occ)),
        SheetAction(Icons.logout, 'Exit committee', () async {
          await context.push('/board/exit');
          _load();
        }, destructive: true),
      ] else if (iAmCommittee && voting) ...[
        if (s['kind'] != 'champion') SheetAction(Icons.swap_horiz, 'Reassign member', () => _propose('reassign', occ)),
        SheetAction(Icons.person_remove_outlined, 'Remove member', () => _propose('remove', occ), destructive: true),
      ],
      SheetAction(Icons.person_outline, 'View profile', () => context.push('/users/${occ.id}')),
    ];
    await showActionSheet(context, items);
  }

  Future<void> _propose(String type, PersonRef p) async {
    await context.push('/board/propose', extra: {'type': type, 'subject': p.json, 'seats': _b!['seats']});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    if (b == null) return _page(context, 'Committee board', const Center(child: CircularProgressIndicator()));
    final seats = List<Map<String, dynamic>>.from(b['seats']);
    final shown = switch (_tab) { 1 => seats.where((s) => s['kind'] != 'champion').toList(), 2 => seats.where((s) => s['kind'] == 'champion').toList(), _ => seats };
    final counts = b['counts'];
    final canApply = b['mySeat'] == null && b['myApplication'] == null;
    return _page(
      context,
      'Committee board',
      ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(spacing: 8, children: [
            for (final (i, l) in ['All', 'Members', 'Champions'].indexed)
              ChoiceChip(
                label: Text(l),
                selected: _tab == i,
                showCheckmark: false,
                selectedColor: KColors.surfaceInverted,
                labelStyle: TextStyle(color: _tab == i ? Colors.white : KColors.textPrimary),
                shape: const StadiumBorder(side: BorderSide(color: KColors.borderDefault)),
                onSelected: (_) => setState(() => _tab = i),
              ),
          ]),
        ),
        Container(
          color: KColors.brandSubtle,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Text(_tab == 2 ? plural(counts['champions'], 'Champion') : _tab == 1 ? plural(counts['members'], 'Member') : plural(counts['all'], 'Member'), style: KText.paragraphMediumLarge),
            const Spacer(),
            IconButton(tooltip: 'Community size and tiers', icon: const Icon(Icons.info, color: KColors.brand), onPressed: () => context.push('/board/tiers')),
          ]),
        ),
        if (b['canManageSeats'] == true)
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Manage seats'),
            subtitle: const Text('Activate or deactivate empty committee and champion seats'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await context.push('/board/manage');
              _load();
            },
          ),
        if (_tab == 2 && shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Text('No champions yet', style: KText.headingXSmall),
              const SizedBox(height: 4),
              Text("When champions are accepted, they'll appear here.", style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            ]),
          ),
        for (final s in shown)
          s['occupant'] != null
              ? ListTile(
                  leading: Avatar(s['occupant']['photoUrl'], size: 44),
                  title: Row(children: [
                    Flexible(child: Text(s['occupant']['name'], style: KText.paragraphMediumLarge)),
                    const SizedBox(width: 4),
                    s['kind'] == 'champion' ? const Icon(Icons.workspace_premium, size: 16, color: KColors.progressStart) : const CommitteeMark(size: 14),
                  ]),
                  subtitle: Text(s['role'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  trailing: IconButton(tooltip: 'Actions', icon: const Icon(Icons.more_vert), onPressed: () => _actions(s)),
                )
              : ListTile(
                  leading: const CircleAvatar(radius: 22, backgroundColor: KColors.surfaceSubtle, child: Icon(Icons.person, color: KColors.textTertiary)),
                  title: Text(s['status'] == 'pending' ? 'Active Application' : 'Unoccupied', style: KText.paragraphMediumLarge),
                  subtitle: Text(s['role'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  trailing: s['status'] == 'pending'
                      ? const Chip(label: Text('Pending'))
                      : canApply
                          ? SizedBox(
                              width: 92,
                              height: 36,
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, shape: const StadiumBorder()),
                                onPressed: () => _seatTap(s),
                                child: Text(s['kind'] == 'preset' ? 'Join' : 'Apply'),
                              ),
                            )
                          : null,
                ),
      ]),
      actions: [
        if (b['mySeat'] != null && b['mySeat']['kind'] != 'champion')
          IconButton(tooltip: 'Invite members to committee board', icon: const Icon(Icons.person_add_alt), onPressed: () => context.push('/board/invite')),
      ],
    );
  }
}

/// CBM-04 - CBM-06: pledge, leadership question, role, justification.
class JoinBoardScreen extends StatefulWidget {
  const JoinBoardScreen({super.key, this.create = false, this.role, this.seatId});
  final bool create;
  final String? role;
  final String? seatId;
  @override
  State<JoinBoardScreen> createState() => _JoinBoardScreenState();
}

class _JoinBoardScreenState extends State<JoinBoardScreen> with Busy {
  int _step = 0; // 0 pledge, 1 leadership, 2 role, 3 justification
  bool _pledge = false;
  bool? _leader;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _qualified = TextEditingController();
  final _aim = TextEditingController();
  List<Map<String, dynamic>> _roles = [];
  String? _role;
  Map<String, String?> _err = {};

  bool get _fixedSeat => widget.seatId != null;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
    context.api.get('/board/roles').then((r) => mounted ? setState(() => _roles = List<Map<String, dynamic>>.from(r['roles'])) : null);
  }

  void _next() {
    setState(() {
      _err = {};
      if (_step == 1 && _leader == true && _title.text.trim().isEmpty) {
        _err['title'] = 'Add your role title';
        return;
      }
      _step = (_step == 1 && (_fixedSeat || widget.role != null)) ? 3 : _step + 1;
    });
  }

  Future<void> _submit() async {
    setState(() => _err = {
          'qualified': _qualified.text.trim().isEmpty ? 'Tell us what makes you qualified for this role' : null,
          'aim': _aim.text.trim().isEmpty ? 'Tell us what you aim to achieve in this role' : null,
        });
    if (_err.values.any((e) => e != null)) return;
    final body = {
      'pledge': true,
      'hasLeadership': _leader == true,
      if (_leader == true) 'leadershipTitle': _title.text.trim(),
      if (_leader == true && _desc.text.trim().isNotEmpty) 'leadershipDescription': _desc.text.trim(),
      'qualified': _qualified.text.trim(),
      'aim': _aim.text.trim(),
      if (_fixedSeat) 'seatId': widget.seatId else 'role': _role,
    };
    await run(() async {
      final r = await context.api.post(widget.create ? '/board' : '/board/join', body);
      if (!mounted) return;
      final pending = r['status'] == 'pending';
      context.pushReplacement('/board/done', extra: {
        'title': pending ? r['title'] : 'Success',
        'message': r['message'],
        'pending': pending,
      });
    }, onError: (e) {
      if (handleVerificationRequired(context, e)) return;
      showToast(context, e is ApiException ? e.message : 'Something went wrong.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final about = _roles.firstWhere((r) => r['role'] == _role, orElse: () => {})['about'] as List?;
    Widget body;
    Widget? bottom;
    switch (_step) {
      case 0:
        body = Column(children: [
          const SizedBox(height: 40),
          const Icon(Icons.groups_2_outlined, size: 72),
          const SizedBox(height: 20),
          Text('Welcome to Committee', style: KText.headingSmall),
          const SizedBox(height: 8),
          Text('Committee members manage community services, finances, projects, and also serve as the voice of residents in your community.',
              textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 24),
          CheckboxListTile(
            value: _pledge,
            onChanged: (v) => setState(() => _pledge = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: KColors.surfaceInverted,
            title: const Text('I pledge to be an active member of the committee'),
          ),
        ]);
        bottom = KeysButton('Got it', onPressed: _pledge ? _next : null);
      case 1:
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(title: 'Do you currently hold a leadership position in your community?'),
          const SizedBox(height: 16),
          RadioGroup<bool>(
            groupValue: _leader,
            onChanged: (v) => setState(() => _leader = v),
            child: const Column(children: [
              RadioListTile<bool>(value: true, title: Text('Yes'), activeColor: KColors.surfaceInverted),
              RadioListTile<bool>(value: false, title: Text('No'), activeColor: KColors.surfaceInverted),
            ]),
          ),
          if (_leader == true) ...[
            KeysTextField(label: 'Role title', controller: _title, error: _err['title'], maxLength: 100),
            const SizedBox(height: 16),
            KeysTextField(label: 'Describe your role', controller: _desc, maxLength: 500, maxLines: 4),
          ],
        ]);
        bottom = KeysButton('Continue', onPressed: _leader == null ? null : _next);
      case 2:
        final free = _roles.where((r) => r['available'] == true).toList();
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(title: 'What role would you like to hold in the committee?'),
          const SizedBox(height: 16),
          Text('Select a role', style: KText.paragraphMediumLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in free)
              ChoiceChip(
                label: Text(r['role']),
                selected: _role == r['role'],
                showCheckmark: false,
                selectedColor: KColors.surfaceInverted,
                labelStyle: TextStyle(color: _role == r['role'] ? Colors.white : KColors.textPrimary),
                onSelected: (_) => setState(() => _role = r['role']),
              ),
          ]),
          if (about != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.sm), border: Border.all(color: KColors.brand)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.info_outline, size: 16), const SizedBox(width: 6), Text('About the role', style: KText.paragraphMediumSmall)]),
                const SizedBox(height: 6),
                for (final line in about) Text('•  $line', style: KText.paragraphSmall),
              ]),
            ),
          ],
        ]);
        bottom = KeysButton('Continue', onPressed: _role == null ? null : _next);
      default:
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_role != null) Text(_role!, style: KText.overline),
          const SizedBox(height: 8),
          KeysTextField(label: 'What makes you qualified for this role? *', controller: _qualified, hint: 'Tell us duties you would perform in order to improve your community if assigned this role', maxLength: 500, maxLines: 5, error: _err['qualified']),
          const SizedBox(height: 20),
          KeysTextField(label: widget.create ? 'What do you aim to achieve in this role? *' : 'What will you do differently in this role? *', controller: _aim, hint: 'Specific action points and projects you intend for the role', maxLength: 500, maxLines: 5, error: _err['aim']),
        ]);
        bottom = KeysButton(_fixedSeat ? 'Submit application' : 'Continue', loading: busy, onPressed: _submit);
    }
    return KeysScaffold(
      gradient: false,
      header: KeysHeader(onBack: () => _step == 0 ? context.pop() : setState(() => _step = (_step == 3 && (_fixedSeat || widget.role != null)) ? 1 : _step - 1)),
      body: body,
      bottom: bottom,
    );
  }
}

class BoardDoneScreen extends StatelessWidget {
  const BoardDoneScreen({super.key, required this.title, required this.message, this.pending = false});
  final String title, message;
  final bool pending;
  @override
  Widget build(BuildContext context) => KeysScaffold(
        body: Column(children: [
          const SizedBox(height: 120),
          CircleAvatar(radius: 40, backgroundColor: pending ? KColors.brand : KColors.success, child: Icon(pending ? Icons.hourglass_top : Icons.check_rounded, color: Colors.white, size: 40)),
          const SizedBox(height: 24),
          Intro(center: true, title: title, body: message),
        ]),
        bottom: KeysButton(pending ? 'Close' : 'Get started', onPressed: () => context.pop()),
      );
}

/// CBM-11: Chair activates or deactivates empty seats.
class ManageSeatsScreen extends StatefulWidget {
  const ManageSeatsScreen({super.key});
  @override
  State<ManageSeatsScreen> createState() => _ManageSeatsScreenState();
}

class _ManageSeatsScreenState extends State<ManageSeatsScreen> {
  Map<String, dynamic>? _m;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.api.get('/board/manage');
    if (mounted) setState(() => _m = r);
  }

  Future<void> _toggle(Map<String, dynamic> s, bool on) async {
    if (!on) {
      final ok = await confirmSheet(context, title: 'Deactivate this seat?', body: 'Residents will no longer be able to apply for this role as it will become an inactive seat. You can always reactivate it at any time.', confirm: 'Deactivate');
      if (!ok || !mounted) return;
    }
    try {
      final r = await context.api.post('/board/seats/${s['id']}/${on ? 'activate' : 'deactivate'}');
      if (mounted) showToast(context, r['message']);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
    _load();
  }

  Widget _seat(Map<String, dynamic> s) => SwitchListTile(
        title: Text(s['occupant']?['name'] ?? (s['active'] == true ? 'Unoccupied' : 'Inactive seat')),
        subtitle: Text(s['role']),
        value: s['active'] == true,
        activeTrackColor: KColors.surfaceInverted,
        onChanged: s['canToggle'] == true ? (v) => _toggle(s, v) : null,
      );

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (m == null) return _page(context, 'Manage seats', const Center(child: CircularProgressIndicator()));
    return _page(
      context,
      'Manage seats',
      ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('Activate or deactivate empty committee and champion seats', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('Committee Seats')), ButtonSegment(value: 1, label: Text('Champion seats'))],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        if (_tab == 0) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text("Preset roles (Can't be edited)", style: KText.overline)),
          for (final s in List<Map<String, dynamic>>.from(m['presetRoles']))
            ListTile(title: Text(s['role']), subtitle: Text(s['occupant']?['name'] ?? 'Unoccupied'), trailing: const Icon(Icons.lock_outline, size: 18)),
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Additional Seats · ${m['tierLabel']}', style: KText.overline)),
          if ((m['additionalSeats'] as List).isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text('Tier 1 has no additional committee seats. They unlock at Tier 2.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
          for (final s in List<Map<String, dynamic>>.from(m['additionalSeats'])) _seat(s),
        ] else ...[
          if (m['championsLockedReason'] != null) Padding(padding: const EdgeInsets.all(16), child: ErrorLine(m['championsLockedReason'])),
          for (final s in List<Map<String, dynamic>>.from(m['championSeats'])) _seat(s),
        ],
      ]),
    );
  }
}

/// CBM-10: community size and tiers.
class TiersScreen extends StatelessWidget {
  const TiersScreen({super.key});
  @override
  Widget build(BuildContext context) => _page(
        context,
        'Community size',
        FutureBuilder(
          future: context.api.get('/board/tiers'),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final d = s.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('${formatCount(d['residents'])} residents · Tier ${d['currentTier']}', style: KText.headingXSmall),
              const SizedBox(height: 16),
              for (final t in List<Map<String, dynamic>>.from(d['tiers']))
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t['tier'] == d['currentTier'] ? KColors.brandSubtle : KColors.surfaceDefault,
                    borderRadius: BorderRadius.circular(KRadius.md),
                    border: Border.all(color: t['tier'] == d['currentTier'] ? KColors.brand : KColors.borderDefault),
                  ),
                  child: Row(children: [
                    Expanded(child: Text('Tier ${t['tier']}${t['tier'] == d['currentTier'] ? ' (current)' : ''}', style: KText.paragraphMediumLarge)),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Number of residents required: ${t['residentsLabel']}', style: KText.paragraphSmall),
                      Text('Board seats: ${t['committee']} committee, ${t['champions']} champions', style: KText.paragraphSmall),
                    ]),
                  ]),
                ),
              const SizedBox(height: 12),
              Text('Available seats: ${d['seats']['available']} — seats your tier allows.', style: KText.paragraphMedium),
              Text('Active seats: ${d['seats']['active']} — seats the Chair has opened.', style: KText.paragraphMedium),
              Text('Occupied seats: ${d['seats']['occupied']} — seats with a member.', style: KText.paragraphMedium),
              const SizedBox(height: 8),
              Text('Every resident counts towards the tier, verified or not.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ]);
          },
        ),
      );
}

/// CBM-13: exit with a reason, confirm, done.
class ExitBoardScreen extends StatefulWidget {
  const ExitBoardScreen({super.key});
  @override
  State<ExitBoardScreen> createState() => _ExitBoardScreenState();
}

class _ExitBoardScreenState extends State<ExitBoardScreen> with Busy {
  final _reason = TextEditingController();
  Future<void> _go() async {
    final ok = await confirmSheet(context, title: 'Confirm exit', body: "Are you sure you want to exit the committee board? This action can't be undone.", confirm: 'Exit', destructive: true);
    if (!ok || !mounted) return;
    await run(() async {
      final r = await context.api.post('/board/exit', {'reason': _reason.text.trim()});
      if (mounted) context.pushReplacement('/board/done', extra: {'title': r['title'], 'message': r['message'], 'pending': true});
    });
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        header: const KeysHeader(),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(title: 'Reason for exit', body: 'Why do you want to exit the committee board?'),
          const SizedBox(height: 20),
          KeysTextField(controller: _reason, maxLength: 500, maxLines: 5, onChanged: (_) => setState(() {})),
        ]),
        bottom: KeysButton('Proceed', loading: busy, onPressed: _reason.text.trim().isEmpty ? null : _go),
      );
}

/// CBM-15 / CBM-16: reassign (to a vacant or filled role) or remove.
class ProposeScreen extends StatefulWidget {
  const ProposeScreen({super.key, required this.type, required this.subject, required this.seats});
  final String type;
  final Map<String, dynamic> subject;
  final List<Map<String, dynamic>> seats;
  @override
  State<ProposeScreen> createState() => _ProposeScreenState();
}

class _ProposeScreenState extends State<ProposeScreen> with Busy {
  final _reason = TextEditingController();
  String? _seat;

  bool get _self => widget.subject['id'] == context.session.me?.id;

  @override
  Widget build(BuildContext context) {
    final p = PersonRef(widget.subject);
    final targets = widget.seats.where((s) => s['kind'] != 'champion' && s['occupant']?['id'] != p.id).toList();
    final target = targets.where((s) => s['id'] == _seat).firstOrNull;
    final remove = widget.type == 'remove';
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Intro(title: remove ? 'Remove ${p.name}' : (_self ? 'Reassign my role' : 'Reassign ${p.name}')),
        const SizedBox(height: 20),
        if (!remove) ...[
          Text('Proposed role', style: KText.paragraphMediumLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _seat,
            items: [for (final s in targets) DropdownMenuItem(value: s['id'] as String, child: Text('${s['role']} · ${s['occupant']?['name'] ?? 'Vacant'}'))],
            onChanged: (v) => setState(() => _seat = v),
            decoration: const InputDecoration(filled: true, fillColor: KColors.surfaceSubtle, border: OutlineInputBorder(borderSide: BorderSide.none)),
          ),
          if (target?['occupant'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
                child: Text('Role swapping\nIf this request is granted by the board, ${_self ? 'your' : "${p.firstName}'s"} current role would be reassigned to ${target!['occupant']['name']} as well.', style: KText.paragraphSmall),
              ),
            ),
          const SizedBox(height: 20),
        ],
        KeysTextField(
          label: remove ? 'Reason for removal' : 'Reason for reassignment',
          hint: remove ? 'Tell us why you think this person should be removed?' : 'Tell us why you want to be reassigned to this role?',
          controller: _reason,
          maxLength: 500,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
        ),
      ]),
      bottom: KeysButton('Submit', loading: busy, onPressed: _reason.text.trim().isEmpty || (!remove && _seat == null) ? null : () async {
        final api = context.api;
        final router = GoRouter.of(context);
        await run(() async {
          final r = await api.post('/board/proposals', {'type': widget.type, 'subjectId': p.id, 'seatId': ?_seat, 'reason': _reason.text.trim()});
          if (mounted) router.pushReplacement('/board/done', extra: {'title': 'Request submitted', 'message': r['message'], 'pending': true});
        });
      }),
    );
  }
}

/// CBM-07.3: invite members to the committee board.
class BoardInviteScreen extends StatelessWidget {
  const BoardInviteScreen({super.key});
  @override
  Widget build(BuildContext context) => _page(
        context,
        'Invite members to committee board',
        FutureBuilder(
          future: context.api.get('/board/invite'),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final d = s.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('Send an invite to active and potential leaders in your community.', style: KText.paragraphMedium),
              const SizedBox(height: 20),
              KeysButton('Share invite', onPressed: () => context.deps.sharer.share(d['message'])),
              const SizedBox(height: 12),
              KeysButton('Copy link', variant: ButtonVariant.secondary, onPressed: () async {
                await context.deps.sharer.copy(d['link']);
                if (context.mounted) showToast(context, 'Link copied');
              }),
              const SizedBox(height: 24),
              Text('What it means to be a committee member', style: KText.headingXSmall),
              const SizedBox(height: 8),
              Text('Committee members manage community services, finances, projects, and also serve as the voice of residents in your community.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            ]);
          },
        ),
      );
}
