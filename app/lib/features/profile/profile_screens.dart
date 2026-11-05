import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/flow.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/feed_screens.dart';
import '../feed/social.dart';
import '../onboarding/profile_screens.dart' show SquareCropScreen, photoProblem;

String joined(String? iso) => iso == null ? '' : 'Joined ${DateFormat('MMMM yyyy').format(DateTime.parse(iso).toLocal())}';

class _Meta extends StatelessWidget {
  const _Meta({required this.community, required this.joinedAt});
  final String community;
  final String? joinedAt;
  @override
  Widget build(BuildContext context) {
    final s = KText.paragraphSmall.copyWith(color: KColors.textSecondary);
    return Wrap(spacing: 16, runSpacing: 4, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.apartment_outlined, size: 14, color: KColors.textSecondary), const SizedBox(width: 4), Text(community, style: s)]),
      if (joinedAt != null) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.calendar_today_outlined, size: 13, color: KColors.textSecondary), const SizedBox(width: 4), Text(joined(joinedAt), style: s)]),
    ]);
  }
}

/// PRF-01 / PRF-19: my profile with My Activities (My post only in Phase 1).
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});
  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? _p;
  int? _total;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.api;
    final me = context.session.me!;
    final r = await api.get('/users/${me.id}');
    final posts = await api.get('/users/${me.id}/posts');
    if (mounted) {
      setState(() {
        _p = r;
        _total = posts['total'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final me = s.me!;
        final p = _p;
        return Scaffold(
          backgroundColor: KColors.surfaceDefault,
          appBar: AppBar(
            backgroundColor: KColors.surfaceDefault,
            surfaceTintColor: Colors.transparent,
            title: Text('Profile', style: KText.headingXSmall),
            actions: [
              IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
              IconButton(tooltip: 'Share profile', icon: const Icon(Icons.share_outlined), onPressed: () => context.deps.sharer.share(p?['shareLink'] ?? '')),
            ],
          ),
          body: PostList(
            path: '/users/${me.id}/posts',
            header: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(me.photoUrl, size: 80),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(me.fullName, style: KText.headingSmall),
                      const SizedBox(height: 4),
                      if (!me.isVerified) UnverifiedChip(text: me.underReview ? 'Under review' : 'Unverified'),
                      if (p?['role'] != null) Text(p!['role'], style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                    ]),
                  ),
                ]),
                if ((me.bio ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text(me.bio!, style: KText.paragraphMedium)],
                const SizedBox(height: 8),
                _Meta(community: me.communityName, joinedAt: p?['joinedAt']),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: SizedBox(height: 40, child: KeysButton('Edit profile', onPressed: () => context.push('/profile/edit')))),
                  if (!me.isVerified) ...[
                    const SizedBox(width: 12),
                    // AVW-08.2
                    Expanded(child: SizedBox(height: 40, child: KeysButton(me.underReview ? 'Under review' : 'Get verified', variant: ButtonVariant.outline, onPressed: () => context.push('/verify')))),
                  ],
                ]),
                const SizedBox(height: 24),
                Text('My Activities', style: KText.headingXSmall),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: KColors.surfaceInverted, borderRadius: BorderRadius.circular(KRadius.pill)),
                  child: Text('My post${_total == null ? '' : ' ($_total)'}', style: KText.paragraphMediumSmall.copyWith(color: Colors.white, fontSize: 13)),
                ),
              ]),
            ),
            empty: const EmptyState(title: 'No posts yet', body: 'Posts you create on the feed would be shown here'),
          ),
        );
      },
    );
  }
}

/// PRF-02 - PRF-06: another resident.
class OtherProfileScreen extends StatefulWidget {
  const OtherProfileScreen({super.key, required this.id});
  final String id;
  @override
  State<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

class _OtherProfileScreenState extends State<OtherProfileScreen> {
  Map<String, dynamic>? _p;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/users/${widget.id}');
      if (r['isMe'] == true && mounted) return context.pushReplacement('/profile');
      if (mounted) setState(() => _p = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _mute() async {
    final p = _p!;
    final first = PersonRef(p).firstName;
    if (p['isMuted'] == true) {
      if (!await confirmSheet(context, title: 'Unmute ${p['name']}', body: 'Unmute ${p['name']} to see their post, activities and send a message', confirm: 'Unmute')) return;
      if (!mounted) return;
      final r = await context.api.delete('/users/${widget.id}/mute');
      if (mounted) showToast(context, r['message']);
    } else {
      if (!await confirmSheet(context, title: 'Mute $first?', body: "Are you sure you want to mute ${p['name']}? You won't receive any posts, messages notification from them for the next 30 days.", confirm: 'Yes, mute')) return;
      if (!mounted) return;
      final api = context.api;
      final r = await api.post('/users/${widget.id}/mute');
      if (mounted) {
        showToast(context, r['message'], actionLabel: 'Undo', onAction: () async {
          await api.delete('/users/${widget.id}/mute');
          _load();
        });
      }
    }
    _load();
  }

  Future<void> _unblock() async {
    final p = _p!;
    if (!await confirmSheet(context, title: 'Unblock ${p['name']}?', body: 'Unblock ${p['name']} to see their post, activities and send a message.', confirm: 'Unblock')) return;
    if (!mounted) return;
    final r = await context.api.delete('/users/${widget.id}/block');
    if (mounted) showToast(context, r['message']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent),
      body: _error != null
          ? EmptyState(title: 'Not available', body: _error!.message)
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        GestureDetector(
                          onTap: p['photoUrl'] == null ? null : () => context.push('/media', extra: {'urls': [p['photoUrl']], 'index': 0}),
                          child: Avatar(p['photoUrl'], size: 80),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(p['name'], style: KText.headingSmall)),
                              if (PersonRef(p).isCommittee) ...[const SizedBox(width: 6), const CommitteeMark(size: 18)],
                            ]),
                            const SizedBox(height: 4),
                            if (p['verified'] != true) const UnverifiedChip(),
                            if (p['role'] != null) Text(p['role'], style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                          ]),
                        ),
                      ]),
                      if ((p['bio'] ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text(p['bio'], style: KText.paragraphMedium)],
                      const SizedBox(height: 8),
                      _Meta(community: p['community'], joinedAt: p['joinedAt']),
                      const SizedBox(height: 16),
                      // PRF-05.2: blocked -> the Chat button becomes Unblock and the actions go.
                      p['isBlocked'] == true
                          ? KeysButton('Unblock', onPressed: _unblock)
                          : KeysButton('Chat', onPressed: () => context.push('/chat/new/${widget.id}')),
                    ]),
                  ),
                  Container(height: 8, color: KColors.surfaceSubtle),
                  if (p['isBlocked'] != true) ...[
                    ListTile(leading: const Icon(Icons.share_outlined), title: const Text('Share profile'), onTap: () => context.deps.sharer.share(p['shareLink'])),
                    ListTile(leading: Icon(p['isMuted'] == true ? Icons.volume_up_outlined : Icons.volume_off_outlined), title: Text('${p['isMuted'] == true ? 'Unmute' : 'Mute'} ${PersonRef(p).firstName}'), onTap: _mute),
                    ListTile(leading: const Icon(Icons.block), title: Text('Block ${PersonRef(p).firstName}'), onTap: () async {
                      if (await blockPerson(context, PersonRef(p))) _load();
                    }),
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: Text('Report ${PersonRef(p).firstName}'),
                      onTap: () => showReportSheet(context, itemType: 'user', itemId: widget.id, title: 'Report ${p['name']}', intro: "Tell us why you are reporting this user. They won't be notified that you reported them."),
                    ),
                  ],
                ]),
    );
  }
}

/// PRF-07 - PRF-11: edit profile.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  double? _progress;

  Future<void> _photo() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take Photo'), onTap: () => Navigator.pop(c, true)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose Photo'), onTap: () => Navigator.pop(c, false)),
        ]),
      ),
    );
    if (camera == null || !mounted) return;
    final f = await context.deps.media.pickPhoto(camera: camera);
    if (f == null || !mounted) return;
    final problem = photoProblem(f);
    if (problem != null) return showToast(context, problem);
    final cropped = await Navigator.of(context).push<PickedFile>(MaterialPageRoute(builder: (_) => SquareCropScreen(file: f)));
    if (cropped == null || !mounted) return;
    final s = context.session;
    setState(() => _progress = null);
    setState(() => _progress = 0.5);
    try {
      final m = await s.api.upload('/media', bytes: cropped.bytes, filename: cropped.name, mime: cropped.mime, query: {'kind': 'photo'});
      final r = await s.api.put('/me/photo', {'mediaId': m['id']});
      await s.refresh();
      if (mounted) showToast(context, r['message']);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _bio() async {
    final s = context.session;
    final c = TextEditingController(text: s.me?.bio ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (b) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(b).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bio', style: KText.headingSmall),
          const SizedBox(height: 4),
          Text('Describe yourself and let your neighbors connect with you.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 16),
          KeysTextField(controller: c, maxLength: 160, maxLines: 4, autofocus: true),
          const SizedBox(height: 16),
          KeysButton('Save', onPressed: () => Navigator.pop(b, true)),
        ]),
      ),
    );
    if (saved != true) return;
    try {
      final r = await s.api.put('/me/bio', {'bio': c.text});
      await s.refresh();
      if (mounted) showToast(context, r['message']);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _email() async {
    final me = context.session.me!;
    if (me.json['hasPassword'] != true) {
      // PRF-10.7
      final add = await confirmSheet(context, title: 'Add a password first', body: 'You signed up with Apple or Google. Add a password to change your email address.', confirm: 'Add password', cancel: 'Not now');
      if (add && mounted) context.push('/settings/password/create');
      return;
    }
    context.push('/profile/email');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final me = s.me!;
        Widget row(String label, String value, {VoidCallback? onTap}) => ListTile(
              onTap: onTap,
              title: Text(label, style: KText.paragraphMediumLarge),
              subtitle: Text(value, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              trailing: onTap == null ? null : const Icon(Icons.chevron_right),
            );
        return Scaffold(
          backgroundColor: KColors.surfaceDefault,
          appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, title: Text('Edit profile', style: KText.headingXSmall)),
          body: ListView(children: [
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                container: true,
                button: true,
                label: 'Change profile photo',
                child: GestureDetector(
                  onTap: _photo,
                  child: Stack(children: [
                    Avatar(me.photoUrl, size: 116),
                    const Positioned(right: 0, bottom: 4, child: CircleAvatar(radius: 16, backgroundColor: KColors.surfaceMuted, child: Icon(Icons.edit_outlined, size: 16, color: KColors.textPrimary))),
                  ]),
                ),
              ),
            ),
            if (_progress != null) Padding(padding: const EdgeInsets.fromLTRB(80, 12, 80, 0), child: LinearProgressIndicator(value: _progress, color: KColors.surfaceInverted)),
            const SizedBox(height: 16),
            // PRF-07.1: legal name, not editable.
            row('Name', me.fullName),
            row('Bio', (me.bio ?? '').isEmpty ? 'Add a bio' : me.bio!, onTap: _bio),
            row('Email address', me.email, onTap: _email),
            row('Home address', me.address?['formatted'] ?? '', onTap: () => context.push('/profile/address')),
            if (!me.isVerified) ListTile(leading: const Icon(Icons.verified_outlined), title: Text(me.underReview ? 'Verification under review' : 'Verify your home address'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/verify')),
          ]),
        );
      },
    );
  }
}

/// PRF-10: password -> new email -> code.
class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});
  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> with Busy {
  int _step = 0;
  final _pw = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  String? _error;

  Future<void> _next() async {
    setState(() => _error = null);
    final s = context.session;
    await run(() async {
      if (_step == 0) {
        await s.api.post('/me/email/password', {'password': _pw.text});
        setState(() => _step = 1);
      } else if (_step == 1) {
        await s.api.post('/me/email/start', {'password': _pw.text, 'newEmail': _email.text.trim()});
        setState(() => _step = 2);
      } else {
        final r = await s.api.post('/me/email/verify', {'newEmail': _email.text.trim(), 'code': _code.text});
        await s.refresh();
        if (!mounted) return;
        showToast(context, r['message']);
        context.pop();
      }
    }, onError: (e) {
      if (_step == 2) _code.clear();
      setState(() => _error = e is ApiException ? e.message : 'Something went wrong.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = context.session.me!;
    final body = switch (_step) {
      0 => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(title: 'Enter password', body: 'Enter your password to change your email address'),
          const SizedBox(height: 24),
          KeysTextField(label: 'Password', controller: _pw, obscure: true, error: _error, autofocus: true, onChanged: (_) => setState(() => _error = null)),
        ]),
      1 => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(title: 'Change email address'),
          const SizedBox(height: 24),
          KeysTextField(label: 'Current email address', controller: TextEditingController(text: me.email), enabled: false),
          const SizedBox(height: 16),
          KeysTextField(label: 'New email address', controller: _email, keyboardType: TextInputType.emailAddress, error: _error, autofocus: true, onChanged: (_) => setState(() => _error = null)),
        ]),
      _ => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Intro(title: 'Enter verification code', body: 'Enter the 6-digit verification code sent to ${_email.text.trim()}'),
          const SizedBox(height: 24),
          CodeInput(controller: _code, error: _error, onCompleted: (_) => _next()),
        ]),
    };
    return KeysScaffold(
      gradient: false,
      header: KeysHeader(onBack: () {
        if (_step == 0) return context.pop();
        setState(() {
          _step--;
          _error = null;
        });
      }),
      body: body,
      bottom: _step == 2 ? null : KeysButton('Continue', loading: busy, onPressed: (_step == 0 ? _pw.text.isEmpty : _email.text.trim().isEmpty) ? null : _next),
    );
  }
}

/// PRF-11.1: what changing address means, then re-onboarding.
class ChangeAddressScreen extends StatefulWidget {
  const ChangeAddressScreen({super.key});
  @override
  State<ChangeAddressScreen> createState() => _ChangeAddressScreenState();
}

class _ChangeAddressScreenState extends State<ChangeAddressScreen> with Busy {
  Map<String, dynamic>? _check;
  @override
  void initState() {
    super.initState();
    context.api.get('/me/exit-check', query: {'reason': 'move'}).then((r) => mounted ? setState(() => _check = r) : null);
  }

  Future<void> _go() async {
    await run(() async {
      await context.api.post('/me/move');
      if (mounted) await goToCurrentStep(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _check;
    final blockers = List<Map<String, dynamic>>.from(c?['blockers'] ?? []);
    final warnings = List<Map<String, dynamic>>.from(c?['warnings'] ?? []);
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Intro(title: 'Change home address', body: 'If you change your home address:'),
              const SizedBox(height: 16),
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, size: 18, color: KColors.textSecondary)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(w['message'], style: KText.paragraphMedium)),
                  ]),
                ),
              for (final b in blockers) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorLine(b['message'])),
            ]),
      bottom: KeysButton('Proceed to change address', loading: busy, onPressed: c == null || blockers.isNotEmpty ? null : _go),
    );
  }
}
