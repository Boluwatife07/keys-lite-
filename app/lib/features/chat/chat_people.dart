import 'dart:async';
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
import '../updates/updates_list.dart' show SearchField;
import 'chat_common.dart';

/// Residents A to Z with roles, searchable (CHT-03.1).
class _PeopleLoader {
  _PeopleLoader(this.api, {this.committeeOnly = false});
  final ApiClient api;
  final bool committeeOnly;
  Future<List<PersonRef>> load(String q) async {
    final r = await api.get('/chats/people', query: {'q': q, if (committeeOnly) 'committeeOnly': '1'});
    return (r['people'] as List).map((e) => PersonRef(Map<String, dynamic>.from(e))).toList();
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile(this.p, {required this.onTap, this.selected});
  final PersonRef p;
  final VoidCallback onTap;
  final bool? selected;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Avatar(p.photoUrl, size: 44),
        title: Row(children: [
          Flexible(child: Text(p.name, style: KText.paragraphLarge, overflow: TextOverflow.ellipsis)),
          if (p.isCommittee) ...[const SizedBox(width: 4), const CommitteeMark(size: 14)],
        ]),
        subtitle: p.role == null ? null : Text(p.role!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        trailing: selected == null
            ? null
            : Icon(selected! ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square, color: selected! ? KColors.surfaceInverted : KColors.textTertiary),
      );
}

/// CHT-03: pick a resident to message, or start a new group.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});
  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _q = TextEditingController();
  List<PersonRef>? _people;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(() {
      setState(() {});
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), _load);
    });
  }

  Future<void> _load() async {
    final q = _q.text.trim();
    try {
      final list = await _PeopleLoader(context.api).load(q);
      if (mounted && _q.text.trim() == q) setState(() => _people = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    // A to Z section letters.
    final rows = <Widget>[];
    String? letter;
    for (final p in people ?? <PersonRef>[]) {
      final l = p.name.isEmpty ? '#' : p.name[0].toUpperCase();
      if (l != letter) {
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(l, style: KText.overline)));
        letter = l;
      }
      rows.add(_PersonTile(p, onTap: () => openDirectChat(context, p.id, replace: true)));
    }
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('New Chat', style: KText.headingXSmall)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SearchField(controller: _q, hint: 'Search residents')),
        ListTile(
          leading: const CircleAvatar(radius: 22, backgroundColor: KColors.brand, child: Icon(PhosphorIconsRegular.usersThree, color: KColors.textPrimary)),
          title: Text('New group', style: KText.paragraphMediumLarge),
          onTap: () => context.push('/chats/new/group'),
        ),
        const Divider(height: 1),
        Expanded(
          child: people == null
              ? const Center(child: CircularProgressIndicator())
              : people.isEmpty
                  ? Center(child: Text('No results found', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)))
                  : ListView(children: rows),
        ),
      ]),
    );
  }
}

/// Multi-select of residents: group members (CHT-11.1) or adding to a group (CHT-14.1).
class PickMembersScreen extends StatefulWidget {
  const PickMembersScreen({super.key, this.chatId, this.committeeOnly = false});
  /// Adding to an existing group; null when creating one.
  final String? chatId;
  final bool committeeOnly;
  @override
  State<PickMembersScreen> createState() => _PickMembersScreenState();
}

class _PickMembersScreenState extends State<PickMembersScreen> with Busy {
  final _q = TextEditingController();
  List<PersonRef>? _people;
  final Map<String, PersonRef> _picked = {};
  Set<String> _existing = {};
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.chatId != null) _loadExisting();
    _q.addListener(() {
      setState(() {});
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), _load);
    });
  }

  Future<void> _loadExisting() async {
    try {
      final r = await context.api.get('/chats/${widget.chatId}/members');
      if (mounted) setState(() => _existing = {for (final m in r['members']) m['person']['id'] as String});
    } catch (_) {}
  }

  Future<void> _load() async {
    final q = _q.text.trim();
    try {
      final list = await _PeopleLoader(context.api, committeeOnly: widget.committeeOnly).load(q);
      if (mounted && _q.text.trim() == q) setState(() => _people = list);
    } catch (_) {}
  }

  Future<void> _next() async {
    if (widget.chatId == null) {
      final r = await context.push('/chats/new/group/details', extra: {'members': _picked.values.toList()});
      if (r != null && mounted) context.pop(r);
      return;
    }
    final router = GoRouter.of(context);
    await run(() async {
      final r = await context.api.post('/chats/${widget.chatId}/members', {'userIds': _picked.keys.toList()});
      if (!mounted) return;
      showToast(context, r['message']);
      router.pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final people = (_people ?? []).where((p) => !_existing.contains(p.id)).toList();
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.chatId == null ? 'New group' : 'Add members', style: KText.headingXSmall),
          Text(_picked.isEmpty ? 'Select members' : '${_picked.length} selected', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        ]),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SearchField(controller: _q, hint: 'Search residents')),
        if (_picked.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final p in _picked.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    avatar: Avatar(p.photoUrl, size: 24),
                    label: Text(p.firstName),
                    onDeleted: () => setState(() => _picked.remove(p.id)),
                    deleteButtonTooltipMessage: 'Remove ${p.name}',
                  ),
                ),
            ]),
          ),
        Expanded(
          child: _people == null
              ? const Center(child: CircularProgressIndicator())
              : people.isEmpty
                  ? Center(child: Text('No results found', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)))
                  : ListView(children: [
                      for (final p in people)
                        _PersonTile(p, selected: _picked.containsKey(p.id), onTap: () => setState(() => _picked.containsKey(p.id) ? _picked.remove(p.id) : _picked[p.id] = p)),
                    ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: KeysButton(widget.chatId == null ? 'Next' : 'Add', loading: busy, onPressed: _picked.isEmpty ? null : _next),
        ),
      ),
    );
  }
}

/// CHT-11.2 / CHT-12: name, icon and settings, then create.
class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({super.key, required this.members});
  final List<PersonRef> members;
  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> with Busy {
  final _name = TextEditingController();
  PickedFile? _icon;
  bool _canMessage = true;
  bool _canInvite = true;
  bool _approval = false;
  bool _committee = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  Future<void> _pickIcon() async {
    final f = await context.deps.media.pickPhoto();
    if (f == null || !mounted) return;
    final problem = photoProblem(f);
    if (problem != null) return showToast(context, problem);
    setState(() => _icon = f);
  }

  Future<void> _create() async {
    final api = context.api;
    final router = GoRouter.of(context);
    await run(() async {
      String? iconId;
      if (_icon != null) iconId = (await api.upload('/media', bytes: _icon!.bytes, filename: _icon!.name, mime: _icon!.mime, query: {'kind': 'photo'}))['id'];
      final r = await api.post('/chats/groups', {
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        'iconMediaId': ?iconId,
        'memberIds': widget.members.map((m) => m.id).toList(),
        'membersCanMessage': _canMessage,
        'membersCanInvite': _canInvite,
        'approvalRequired': _approval,
        'committeeOnly': _committee,
      });
      final id = r['chat']['id'];
      router.go('/home');
      router.push('/chats');
      router.push('/chats/$id');
    });
  }

  Widget _toggle(String title, String subtitle, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: KText.paragraphLarge),
        subtitle: Text(subtitle, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        value: v,
        activeTrackColor: KColors.surfaceInverted,
        onChanged: on,
      );

  @override
  Widget build(BuildContext context) {
    final committee = context.session.me?.json['isCommittee'] == true;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('Customise group', style: KText.headingXSmall)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Center(
          child: Semantics(
            button: true,
            label: 'Add group icon',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _pickIcon,
              child: CircleAvatar(
                radius: 44,
                backgroundColor: KColors.surfaceSubtle,
                backgroundImage: _icon == null ? null : MemoryImage(_icon!.bytes),
                child: _icon == null ? const Icon(PhosphorIconsRegular.camera, color: KColors.textSecondary) : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        KeysTextField(label: 'Group name (optional)', controller: _name, hint: 'Add a group name', maxLength: 100),
        const SizedBox(height: 8),
        Text('Members: ${widget.members.map((m) => m.firstName).join(', ')}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 16),
        Text('Group settings', style: KText.paragraphMediumLarge),
        _toggle('Send messages', 'Allow all members to send messages', _canMessage, (v) => setState(() => _canMessage = v)),
        _toggle('Add others', 'Allow all members to add others', _canInvite, (v) => setState(() => _canInvite = v)),
        _toggle('Approve new members', 'New members require admin approval to join this group chat', _approval, (v) => setState(() => _approval = v)),
        if (committee) _toggle('Committee board only', 'Only committee board members can join', _committee, (v) => setState(() => _committee = v)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: KeysButton('Create group', loading: busy, onPressed: _create)),
      ),
    );
  }

}

/// CHT-08.4: forward to up to 5 chats with an optional note.
class ForwardScreen extends StatefulWidget {
  const ForwardScreen({super.key, required this.messageIds});
  final List<String> messageIds;
  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> with Busy {
  List<ChatCell>? _chats;
  final Set<String> _picked = {};
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.api.get('/chats').then((r) {
      if (mounted) setState(() => _chats = (r['chats'] as List).map((e) => ChatCell(Map<String, dynamic>.from(e))).where((c) => !c.left && !c.readOnly && !c.blockedByMe).toList());
    }).catchError((_) {});
  }

  Future<void> _send() async {
    final router = GoRouter.of(context);
    await run(() async {
      await context.api.post('/messages/forward', {'messageIds': widget.messageIds, 'chatIds': _picked.toList(), if (_note.text.trim().isNotEmpty) 'note': _note.text.trim()});
      if (!mounted) return;
      showToast(context, 'Message forwarded');
      router.pop(true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Forward to', style: KText.headingXSmall),
            Text('${_picked.length}/5 selected', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          ]),
        ),
        body: _chats == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                for (final c in _chats!)
                  CheckboxListTile(
                    value: _picked.contains(c.id),
                    activeColor: KColors.surfaceInverted,
                    secondary: ChatAvatar(url: c.iconUrl, group: !c.isDirect, size: 40),
                    title: Text(c.name, style: KText.paragraphLarge),
                    onChanged: (v) {
                      if (v == true && _picked.length >= 5) return showToast(context, 'You can forward to up to 5 chats');
                      setState(() => v == true ? _picked.add(c.id) : _picked.remove(c.id));
                    },
                  ),
              ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              KeysTextField(controller: _note, hint: 'Add a message (optional)'),
              const SizedBox(height: 8),
              KeysButton('Send', loading: busy, onPressed: _picked.isEmpty ? null : _send),
            ]),
          ),
        ),
      );
}
