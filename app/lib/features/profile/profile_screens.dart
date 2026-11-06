import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/flow.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../chat/chat_common.dart' show openDirectChat;
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
      Row(mainAxisSize: MainAxisSize.min, children: [Icon(PhosphorIconsRegular.buildings, size: 16, color: KColors.textSecondary), const SizedBox(width: 6), Text(community, style: s)]),
      if (joinedAt != null) Row(mainAxisSize: MainAxisSize.min, children: [Icon(PhosphorIconsRegular.calendarDots, size: 16, color: KColors.textSecondary), const SizedBox(width: 6), Text(joined(joinedAt), style: s)]),
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
        // Figma 1239:179788.
        return Scaffold(
          backgroundColor: KColors.surfaceSubtle,
          appBar: PageHeader('Profile', bottomBorder: true, actions: [
            IconButton(tooltip: 'Settings', icon: Icon(PhosphorIconsRegular.gearSix, size: 28, color: KColors.iconDefault), onPressed: () => context.push('/settings')),
            IconButton(tooltip: 'Share profile', icon: Icon(PhosphorIconsRegular.shareFat, size: 28, color: KColors.iconDefault), onPressed: () => context.deps.sharer.share(p?['shareLink'] ?? '')),
          ]),
          body: PostList(
            path: '/users/${me.id}/posts',
            header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                color: KColors.surfaceDefault,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _ProfileHead(photoUrl: me.photoUrl, name: me.fullName, unverified: me.isVerified ? null : (me.underReview ? 'Under review' : 'Unverified'), role: p?['role']),
                  if ((me.bio ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text(me.bio!, style: KText.paragraphMedium)],
                  const SizedBox(height: 10),
                  _Meta(community: me.communityName, joinedAt: p?['joinedAt']),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: _SmallButton('Edit profile', primary: true, onTap: () => context.push('/profile/edit'))),
                    if (!me.isVerified) ...[
                      const SizedBox(width: 8),
                      // AVW-08.2
                      Expanded(child: _SmallButton(me.underReview ? 'Under review' : 'Get verified', onTap: () => context.push('/verify'))),
                    ],
                  ]),
                ]),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                color: KColors.surfaceDefault,
                padding: const EdgeInsets.fromLTRB(16, 23, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('My Activities', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w600, color: KColors.textPrimary)),
                  const SizedBox(height: 16),
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: KColors.surfaceInverted, borderRadius: BorderRadius.circular(20)),
                    child: Center(widthFactor: 1, child: Text('My post${_total == null ? '' : ' ($_total)'}', style: KText.paragraphMedium.copyWith(height: 1, color: KColors.textInverse))),
                  ),
                ]),
              ),
            ]),
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
      // Figma 1239:178669: centred modal with a red action.
      if (!await confirmDialog(context, title: 'Mute ${p['name']}', body: "Are you sure you want to mute $first? You won't receive any posts, messages notification from them for the next 30 days.", confirm: 'Yes, mute')) return;
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
    // Figma 1239:179248.
    return Scaffold(
      backgroundColor: KColors.surfaceSubtle,
      appBar: const PageHeader('', bottomBorder: true),
      body: _error != null
          ? EmptyState(title: 'Not available', body: _error!.message)
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  Container(
                    color: KColors.surfaceDefault,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _ProfileHead(
                        photoUrl: p['photoUrl'],
                        name: p['name'],
                        committee: PersonRef(p).isCommittee,
                        unverified: p['verified'] != true ? 'Unverified' : null,
                        role: p['role'],
                        onAvatar: p['photoUrl'] == null ? null : () => context.push('/media', extra: {'urls': [p['photoUrl']], 'index': 0}),
                      ),
                      if ((p['bio'] ?? '').isNotEmpty) ...[const SizedBox(height: 16), Text(p['bio'], style: KText.paragraphLarge)],
                      const SizedBox(height: 10),
                      _Meta(community: p['community'], joinedAt: p['joinedAt']),
                      const SizedBox(height: 20),
                      // PRF-05.2: blocked -> the Chat button becomes Unblock and the actions go.
                      p['isBlocked'] == true
                          ? KeysButton('Unblock', onPressed: _unblock)
                          : KeysButton('Chat', onPressed: () => openDirectChat(context, widget.id)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  if (p['isBlocked'] != true)
                    Container(
                      color: KColors.surfaceDefault,
                      child: Column(children: [
                        _ActionRow(PhosphorIconsRegular.shareFat, 'Share profile', () => context.deps.sharer.share(p['shareLink'])),
                        _ActionRow(p['isMuted'] == true ? PhosphorIconsRegular.speakerSimpleHigh : PhosphorIconsRegular.speakerSimpleSlash, '${p['isMuted'] == true ? 'Unmute' : 'Mute'} ${PersonRef(p).firstName}', _mute),
                        _ActionRow(PhosphorIconsRegular.prohibit, 'Block ${PersonRef(p).firstName}', () async {
                          if (await blockPerson(context, PersonRef(p))) _load();
                        }),
                        _ActionRow(PhosphorIconsRegular.flag, 'Report ${PersonRef(p).firstName}',
                            () => showReportSheet(context, itemType: 'user', itemId: widget.id, title: 'Report ${p['name']}', intro: "Tell us why you are reporting this user. They won't be notified that you reported them.")),
                      ]),
                    ),
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
          ListTile(leading: const Icon(PhosphorIconsRegular.camera), title: const Text('Take Photo'), onTap: () => Navigator.pop(c, true)),
          ListTile(leading: const Icon(PhosphorIconsRegular.images), title: const Text('Choose Photo'), onTap: () => Navigator.pop(c, false)),
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
      showDragHandle: false,
    backgroundColor: KColors.surfaceDefault,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      // Figma 1239:180503: grabber, title + copy with a close X, the field,
      // a rule, then Save.
      builder: (b) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(b).bottom),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            Center(child: Container(width: 48, height: 4, decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(100)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bio', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500, height: 26 / 18, color: KColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Describe yourself and let your neighbors connect with you.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                  ]),
                ),
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(b, false), icon: Icon(PhosphorIconsRegular.x, size: 24, color: KColors.iconDefault)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              child: KeysTextField(label: 'Bio', controller: c, maxLength: 160, maxLines: 4, minLines: 3, autofocus: true),
            ),
            Container(height: 1, color: KColors.borderDefault),
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: KeysButton('Save', onPressed: () => Navigator.pop(b, true))),
          ]),
        ),
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
        // Figma 1239:180145 "Menu item": 72 high, 16/24 title, 14/20 value.
        Widget row(String label, String value, {VoidCallback? onTap, IconData? icon}) => InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    if (icon != null) ...[Icon(icon, size: 24, color: KColors.iconDefault), const SizedBox(width: 12)],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: KText.paragraphLarge),
                          if (value.isNotEmpty) ...[const SizedBox(height: 2), Text(value, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))],
                        ]),
                      ),
                    ),
                    if (onTap != null) ...[const SizedBox(width: 8), Icon(PhosphorIconsRegular.caretRight, size: 24, color: KColors.iconMuted)],
                  ]),
                ),
              ),
            );
        return Scaffold(
          backgroundColor: KColors.surfaceDefault,
          appBar: const PageHeader('Edit profile', bottomBorder: true),
          body: ListView(children: [
            const SizedBox(height: 26),
            Center(
              child: Semantics(
                container: true,
                button: true,
                label: 'Change profile photo',
                child: GestureDetector(
                  onTap: _photo,
                  child: Stack(children: [
                    Avatar(me.photoUrl, size: 120),
                    Positioned(right: 5, bottom: 4, child: CircleAvatar(radius: 18, backgroundColor: KColors.surfaceMuted, child: Icon(PhosphorIconsRegular.pencilSimple, size: 20, color: KColors.textPrimary))),
                  ]),
                ),
              ),
            ),
            if (_progress != null) Padding(padding: const EdgeInsets.fromLTRB(80, 12, 80, 0), child: LinearProgressIndicator(value: _progress, color: KColors.surfaceInverted)),
            const SizedBox(height: 25),
            // PRF-07.1: legal name, not editable.
            row('Name', me.fullName),
            row('Bio', (me.bio ?? '').isEmpty ? 'Add a bio' : me.bio!, onTap: _bio),
            row('Email address', me.email, onTap: _email),
            row('Home address', me.address?['formatted'] ?? '', onTap: () => context.push('/profile/address')),
            if (!me.isVerified) row(me.underReview ? 'Verification under review' : 'Verify your home address', '', icon: PhosphorIconsRegular.sealCheck, onTap: () => context.push('/verify')),
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
      // Figma 1239:179976 / 1239:180020.
      0 => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepHead('Enter password', 'Enter your password to continue'),
          const SizedBox(height: 32),
          KeysTextField(label: 'Password', hint: 'Enter your password here', controller: _pw, obscure: true, error: _error, autofocus: true, onChanged: (_) => setState(() => _error = null)),
        ]),
      1 => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepHead('Change email address', 'Enter your new email address and proceed to email verification'),
          const SizedBox(height: 32),
          Text('Current email address:', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 2),
          Text(me.email, style: KText.paragraphLarge.copyWith(decoration: TextDecoration.underline, decorationColor: KColors.textPrimary)),
          const SizedBox(height: 32),
          KeysTextField(label: 'New email address', hint: 'Enter new email address', controller: _email, keyboardType: TextInputType.emailAddress, error: _error, autofocus: true, onChanged: (_) => setState(() => _error = null)),
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
                    Padding(padding: EdgeInsets.only(top: 2), child: Icon(PhosphorIconsRegular.info, size: 18, color: KColors.textSecondary)),
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


/// Figma profile "User Info": 80 avatar, Inter SemiBold 20 name with the
/// committee badge, then the unverified tag or the role.
class _ProfileHead extends StatelessWidget {
  const _ProfileHead({required this.photoUrl, required this.name, this.committee = false, this.unverified, this.role, this.onAvatar});
  final String? photoUrl;
  final String name;
  final bool committee;
  final String? unverified;
  final String? role;
  final VoidCallback? onAvatar;
  @override
  Widget build(BuildContext context) => Row(children: [
        GestureDetector(onTap: onAvatar, child: Avatar(photoUrl, size: 80)),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, height: 28 / 20, color: KColors.textPrimary))),
              if (committee) ...[const SizedBox(width: 4), const CommitteeMark(size: 16)],
            ]),
            if (unverified != null) UnverifiedChip(text: unverified!),
            if (role != null) Text(role!, style: KText.paragraphMedium.copyWith(color: KColors.textPlaceholder)),
          ]),
        ),
      ]);
}

/// 36pt pill button with a 12pt label (Figma "Button / Small").
class _SmallButton extends StatelessWidget {
  const _SmallButton(this.label, {required this.onTap, this.primary = false});
  final String label;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: Material(
          color: primary ? KColors.surfaceInverted : Colors.transparent,
          shape: StadiumBorder(side: primary ? BorderSide.none : BorderSide(color: KColors.borderStrong)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(height: 36, child: Center(child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, height: 1, color: primary ? KColors.textInverse : KColors.textPrimary)))),
          ),
        ),
      );
}

/// Figma "Menu item" with a 28pt icon (profile actions).
class _ActionRow extends StatelessWidget {
  const _ActionRow(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(icon, size: 28, color: KColors.iconDefault),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: KText.paragraphLarge)),
            ]),
          ),
        ),
      );
}


/// 24pt title over 14pt grey copy (change email steps).
class _StepHead extends StatelessWidget {
  const _StepHead(this.title, this.body);
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: KText.headingSmall),
        const SizedBox(height: 8),
        Text(body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
      ]);
}
