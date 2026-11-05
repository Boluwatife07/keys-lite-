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
import '../feed/social.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import '../updates/updates_list.dart' show SearchField;

const kClubNameMax = 60;
const kClubDescriptionMax = 300;
const kClubLimitMin = 10;
const kClubCategories = ['Lifestyle', 'Sports', 'Music', 'Food & Drink', 'Creative', 'Gaming', 'Pets', 'Wellness', 'Learning', 'Others'];

/// CLB-03 / CLB-04 create (optionally from a template) and CLB-09 edit.
class ClubFormScreen extends StatefulWidget {
  const ClubFormScreen({super.key, this.template, this.edit});
  final Map<String, dynamic>? template;
  final Map<String, dynamic>? edit;
  @override
  State<ClubFormScreen> createState() => _ClubFormScreenState();
}

class _ClubFormScreenState extends State<ClubFormScreen> with Busy {
  late final _name = TextEditingController(text: widget.edit?['name'] ?? widget.template?['name'] ?? '');
  late final _description = TextEditingController(text: widget.edit?['description'] ?? widget.template?['description'] ?? '');
  late final _limit = TextEditingController(text: '${widget.edit?['memberLimit'] ?? widget.template?['memberLimit'] ?? ''}');
  late String? _category = widget.edit?['category'] ?? widget.template?['category'];
  PickedFile? _cover;
  String? _error;
  String? _nameError;

  bool get _editing => widget.edit != null;
  bool get _canEditName => !_editing || widget.edit!['canEditName'] == true;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _description, _limit]) {
      c.addListener(() => setState(() {}));
    }
    final img = widget.template?['image'];
    if (img != null) {
      // CLB-04.2: the template cover comes pre-filled.
      rootBundle.load('assets/images/$img').then((b) {
        if (mounted) setState(() => _cover = PickedFile(bytes: b.buffer.asUint8List(), name: img, mime: 'image/jpeg'));
      });
    }
  }

  String? get _limitProblem {
    final n = int.tryParse(_limit.text.trim());
    if (_limit.text.trim().isEmpty) return null;
    if (n == null || n < kClubLimitMin) return 'Minimum of $kClubLimitMin members';
    final count = widget.edit?['memberCount'] as int?;
    if (count != null && n < count) return 'The limit cannot be lower than the $count members in the club';
    return null;
  }

  bool get _ready =>
      _name.text.trim().isNotEmpty &&
      _description.text.trim().isNotEmpty &&
      _category != null &&
      int.tryParse(_limit.text.trim()) != null &&
      _limitProblem == null &&
      (_cover != null || _editing);

  Future<void> _pickCover() async {
    final f = await context.deps.media.pickPhoto();
    if (f == null) return;
    final p = photoProblem(f);
    setState(() {
      _error = p;
      if (p == null) _cover = f;
    });
  }

  Future<void> _submit() async {
    final api = context.api;
    final router = GoRouter.of(context);
    if (!_editing) {
      // CLB-03.4: invite residents before creating.
      final invite = await router.push<List<String>>('/clubs/create/members');
      if (invite == null || !mounted) return;
      await run(() async {
        final cover = (await api.upload('/media', bytes: _cover!.bytes, filename: _cover!.name, mime: _cover!.mime, query: {'kind': 'photo'}))['id'];
        final r = await api.post('/clubs', {
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'category': _category,
          'memberLimit': int.parse(_limit.text.trim()),
          'coverMediaId': cover,
          'inviteIds': invite,
        });
        router.pushReplacement('/clubs/created', extra: r);
      }, onError: _onError);
      return;
    }
    await run(() async {
      String? cover;
      if (_cover != null) cover = (await api.upload('/media', bytes: _cover!.bytes, filename: _cover!.name, mime: _cover!.mime, query: {'kind': 'photo'}))['id'];
      final r = await api.patch('/clubs/${widget.edit!['id']}', {
        if (_canEditName) 'name': _name.text.trim(),
        'description': _description.text.trim(),
        'category': _category,
        'memberLimit': int.parse(_limit.text.trim()),
        'coverMediaId': ?cover,
      });
      if (!mounted) return;
      showToast(context, r['message']);
      router.pop(true);
    }, onError: _onError);
  }

  void _onError(Object e) => setState(() {
        if (e is ApiException && e.code == 'NAME_TAKEN') {
          _nameError = e.message;
        } else {
          _error = e is ApiException ? e.message : 'Something went wrong. Please try again.';
        }
      });

  Widget _label(String t, {bool required = false, String? counter}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(children: [
          Text(t, style: KText.paragraphMediumLarge),
          if (required) Text(' *', style: KText.paragraphMediumLarge.copyWith(color: KColors.error)),
          const Spacer(),
          if (counter != null) Text(counter, style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
        ]),
      );

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: KColors.surfaceSubtle,
        hintStyle: KText.paragraphLarge.copyWith(color: KColors.textTertiary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.sm), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final existing = widget.edit?['coverUrl'] as String?;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Text(_editing ? 'Edit club details' : 'Create a club', style: KText.headingXSmall),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        if (!_editing)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
            child: Row(children: [
              const Icon(PhosphorIconsRegular.info, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Free clubs are not eligible for monetization via subscriptions or event ticket sales.', style: KText.paragraphSmall)),
            ]),
          ),
        _label('Club name', required: true, counter: '${_name.text.length}/$kClubNameMax'),
        TextField(controller: _name, enabled: _canEditName, maxLength: kClubNameMax, decoration: _box('Enter club name').copyWith(errorText: _nameError), onChanged: (_) => setState(() => _nameError = null)),
        _label('Description', required: true, counter: '${_description.text.length}/$kClubDescriptionMax'),
        TextField(controller: _description, maxLength: kClubDescriptionMax, minLines: 3, maxLines: 6, decoration: _box('What is your club about and what should members expect?')),
        _label('Select club category', required: true),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: _box('Select a category'),
          items: [for (final c in kClubCategories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _category = v),
        ),
        _label('Members limit', required: true),
        TextField(controller: _limit, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: _box('Maximum number of members')),
        const SizedBox(height: 4),
        Text(_limitProblem ?? 'Minimum of 10 members', style: KText.paragraphSmall.copyWith(color: _limitProblem != null ? KColors.error : KColors.textSecondary)),
        _label('Set cover image', required: true),
        Text('The cover image is visible to both members and nonmembers', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: _cover == null && existing == null ? 'Upload cover image' : 'Change cover image',
          child: InkWell(
            onTap: _pickCover,
            borderRadius: BorderRadius.circular(KRadius.md),
            child: Container(
              height: 180,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
              child: _cover != null
                  ? Image.memory(_cover!.bytes, fit: BoxFit.cover)
                  : existing != null
                      ? Image.network(context.api.absolute(existing), fit: BoxFit.cover)
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(PhosphorIconsRegular.camera, size: 40),
                          const SizedBox(height: 8),
                          Text('Upload cover image', style: KText.paragraphMediumLarge),
                        ]),
            ),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: ErrorLine(_error!)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: KeysButton(_editing ? 'Save changes' : 'Continue', loading: busy, onPressed: _ready ? _submit : null),
        ),
      ),
    );
  }
}

/// CLB-03.4: frequently contacted and all residents, with search.
class ClubInviteScreen extends StatefulWidget {
  const ClubInviteScreen({super.key, this.clubId});
  /// Inviting to an existing club; null while creating.
  final String? clubId;
  @override
  State<ClubInviteScreen> createState() => _ClubInviteScreenState();
}

class _ClubInviteScreenState extends State<ClubInviteScreen> with Busy {
  final _q = TextEditingController();
  List<PersonRef> _people = [];
  List<PersonRef> _frequent = [];
  final Map<String, PersonRef> _picked = {};
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
    // Frequently contacted: people from recent direct chats.
    final api = context.api;
    api.get('/chats', query: {'tab': 'primary'}).then((r) async {
      final ids = (r['chats'] as List).map((c) => c['otherUserId']).whereType<String>().take(5).toList();
      final all = await api.get('/chats/people');
      if (!mounted) return;
      final ps = (all['people'] as List).map((e) => PersonRef(Map<String, dynamic>.from(e)));
      setState(() => _frequent = ps.where((p) => ids.contains(p.id)).toList());
    }).catchError((_) {});
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/chats/people', query: {'q': _q.text.trim()});
      if (mounted) setState(() => _people = (r['people'] as List).map((e) => PersonRef(Map<String, dynamic>.from(e))).toList());
    } catch (_) {}
  }

  Future<void> _done() async {
    if (widget.clubId == null) return context.pop(_picked.keys.toList());
    final router = GoRouter.of(context);
    await run(() async {
      final r = await context.api.post('/clubs/${widget.clubId}/invite', {'userIds': _picked.keys.toList()});
      if (!mounted) return;
      showToast(context, r['message']);
      router.pop(true);
    });
  }

  Widget _tile(PersonRef p) => CheckboxListTile(
        value: _picked.containsKey(p.id),
        activeColor: KColors.surfaceInverted,
        secondary: Avatar(p.photoUrl, size: 40),
        title: Text(p.name),
        subtitle: p.role == null ? null : Text(p.role!),
        onChanged: (v) => setState(() => v == true ? _picked[p.id] = p : _picked.remove(p.id)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Text(widget.clubId == null ? 'Add members' : 'Invite members', style: KText.headingXSmall),
          actions: [if (widget.clubId == null) TextButton(onPressed: () => context.pop(<String>[]), child: const Text('Skip'))],
        ),
        body: ListView(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SearchField(controller: _q, hint: 'Search residents')),
          if (_q.text.isEmpty && _frequent.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Frequently contacted', style: KText.overline)),
            for (final p in _frequent) _tile(p),
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('All residents', style: KText.overline)),
          ],
          for (final p in _people.where((p) => _q.text.isNotEmpty || !_frequent.any((f) => f.id == p.id))) _tile(p),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: KeysButton(widget.clubId == null ? 'Create club' : 'Send invites', loading: busy, onPressed: widget.clubId != null && _picked.isEmpty ? null : _done),
          ),
        ),
      );
}

/// CLB-03.5 / CLB-04.3: "Club created!" with invite, copy link and go to club.
class ClubCreatedScreen extends StatelessWidget {
  const ClubCreatedScreen({super.key, required this.result});
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) {
    final club = Map<String, dynamic>.from(result['club']);
    return KeysScaffold(
      body: Column(children: [
        const SizedBox(height: 48),
        CircleAvatar(radius: 48, backgroundColor: KColors.brandSubtle, child: Icon(PhosphorIconsRegular.confetti, size: 48, color: KColors.textPrimary)),
        const SizedBox(height: 20),
        Text(result['title'] ?? 'Club created!', style: KText.headingMedium),
        const SizedBox(height: 8),
        Text(result['message'] ?? '', textAlign: TextAlign.center, style: KText.paragraphLarge.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome!', style: KText.headingXSmall),
            const SizedBox(height: 8),
            Text('As the President of ${club['name']} you can:', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 8),
            for (final w in List<String>.from(result['welcome'] ?? []))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(PhosphorIconsFill.checkCircle, size: 18, color: KColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w, style: KText.paragraphMedium)),
                ]),
              ),
          ]),
        ),
      ]),
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        KeysButton('Go to club', onPressed: () => context.pushReplacement('/clubs/${club['id']}')),
        const SizedBox(height: 8),
        KeysButton('Invite members', variant: ButtonVariant.outline, onPressed: () => context.push('/clubs/${club['id']}/invite')),
        const SizedBox(height: 8),
        KeysButton('Copy invite link', variant: ButtonVariant.ghost, onPressed: () async {
          await context.deps.sharer.copy(club['inviteLink']);
          if (context.mounted) showToast(context, 'Club link copied.');
        }),
      ]),
    );
  }
}
