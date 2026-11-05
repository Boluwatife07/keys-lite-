import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_screens.dart' show openLegal;
import '../feed/feed_screens.dart' show EmptyState;
import '../feed/social.dart';

class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.subtitle, this.onTap, {this.external = false});
  final IconData? icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool external;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: icon == null ? null : Icon(icon, color: KColors.textPrimary),
        title: Text(title, style: KText.paragraphMediumLarge),
        subtitle: subtitle == null ? null : Text(subtitle!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        trailing: Icon(external ? Icons.north_east : Icons.chevron_right),
        onTap: onTap,
      );
}

Scaffold _page(String title, List<Widget> children) => Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, title: Text(title, style: KText.headingXSmall)),
      body: ListView(children: children),
    );

/// PRF-12: Phase 1 rows only. Address book, payment methods, security,
/// language and display (dark mode open) are hidden.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => _page('Settings', [
        _Row(Icons.person_outline, 'Your account', 'View all relevant information on your account', () => context.push('/settings/account')),
        _Row(Icons.notifications_none, 'Notification', 'Choose your desired preferences about your activities, interests etc', () => context.push('/settings/notifications')),
        _Row(Icons.folder_shared_outlined, 'Privacy and Safety', 'Manage what information you see and share', () => context.push('/settings/privacy')),
        _Row(null, 'Terms & Conditions', 'English (UK)', () => openLegal(AppConfig.termsUrl), external: true),
      ]);
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final me = context.session.me!;
    final hasPw = me.json['hasPassword'] == true;
    return _page('Your account', [
      _Row(Icons.edit_outlined, 'Edit profile', null, () => context.push('/profile/edit')),
      hasPw
          ? _Row(Icons.lock_outline, 'Change password', null, () => context.push('/settings/password'))
          : _Row(Icons.lock_outline, 'Create password', 'Keep access to your account secured', () => context.push('/settings/password/create')),
      _Row(Icons.no_accounts_outlined, 'Deactivate account', null, () => context.push('/settings/deactivate')),
      ListTile(
        leading: const Icon(Icons.logout, color: KColors.error),
        title: Text('Log out', style: KText.paragraphMediumLarge.copyWith(color: KColors.error)),
        onTap: () async {
          // PRF-17.1 (design copy "our account" corrected).
          if (!await confirmSheet(context, title: 'Log out', body: 'Are you sure you want to log out of your account?', confirm: 'Log out')) return;
          if (!context.mounted) return;
          await context.session.logout();
          if (context.mounted) context.go('/auth/email');
        },
      ),
    ]);
  }
}

/// PRF-14: toggles; newsletter (marketing) starts off.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  Map<String, dynamic>? _prefs;
  static const labels = {
    'likes': ('Likes', 'When someone likes your post or comment'),
    'comments': ('Comments and replies', 'When someone comments on your post or replies to you'),
    'mentions': ('Tags', 'When someone tags you'),
    'polls': ('Polls', 'When a poll you voted on closes'),
    'updates': ('Updates', 'Official updates from your committee'),
    'committee': ('Committee', 'Board changes and proposals'),
    'chat': ('Chat', 'New messages'),
    'events': ('Events', 'Events you are going to or hosting'),
    'clubs': ('Clubs', 'Clubs you belong to'),
  };

  @override
  void initState() {
    super.initState();
    context.api.get('/me/notification-prefs').then((r) => mounted ? setState(() => _prefs = Map<String, dynamic>.from(r['prefs'])) : null);
  }

  Future<void> _set(String key, bool v) async {
    setState(() => _prefs![key] = v);
    try {
      final r = await context.api.put('/me/notification-prefs', {key: v});
      setState(() => _prefs = Map<String, dynamic>.from(r['prefs']));
    } on ApiException catch (e) {
      setState(() => _prefs![key] = !v);
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    if (p == null) return _page('Notification', [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))]);
    return _page('Notification', [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('In-app and push', style: KText.overline)),
      for (final e in labels.entries)
        SwitchListTile(title: Text(e.value.$1), subtitle: Text(e.value.$2), value: p[e.key] == true, activeTrackColor: KColors.surfaceInverted, onChanged: (v) => _set(e.key, v)),
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Text('Email', style: KText.overline)),
      SwitchListTile(title: const Text('Newsletter'), subtitle: const Text('Get latest news and updates about Keys community'), value: p['newsletter'] == true, activeTrackColor: KColors.surfaceInverted, onChanged: (v) => _set('newsletter', v)),
      const ListTile(title: Text('Sign-in alerts and account updates'), subtitle: Text('Service emails we always send to keep your account safe')),
    ]);
  }
}

/// PRF-13
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => _page('Privacy and Safety', [
        _Row(Icons.block, 'Blocked accounts', "Manage all accounts you've blocked", () => context.push('/settings/blocked')),
        _Row(Icons.volume_off_outlined, 'Muted accounts', "Manage all accounts you've muted", () => context.push('/settings/muted')),
      ]);
}

class PeopleListScreen extends StatefulWidget {
  const PeopleListScreen({super.key, required this.blocked});
  final bool blocked;
  @override
  State<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends State<PeopleListScreen> {
  List<Map<String, dynamic>>? _people;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.api.get(widget.blocked ? '/me/blocked' : '/me/muted');
    if (mounted) setState(() => _people = List<Map<String, dynamic>>.from(r['accounts']));
  }

  String _when(String iso) {
    final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
    if (d.inDays >= 7) return '${plural(d.inDays ~/ 7, 'week')} ago';
    if (d.inDays >= 1) return '${plural(d.inDays, 'day')} ago';
    return 'Today';
  }

  Future<void> _undo(Map<String, dynamic> p) async {
    final ok = widget.blocked
        ? await confirmSheet(context, title: 'Unblock ${p['name']}?', body: "They will now be able to engage and see your content and profile on Keys. They won't be notified that you unblocked them.", confirm: 'Unblock')
        : await confirmSheet(context, title: 'Unmute ${p['name']}', body: 'Unmute ${p['name']} to see their post, activities and send a message', confirm: 'Unmute');
    if (!ok || !mounted) return;
    final r = await context.api.delete('/users/${p['id']}/${widget.blocked ? 'block' : 'mute'}');
    if (mounted) showToast(context, r['message']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _people;
    return _page(widget.blocked ? 'Blocked accounts' : 'Muted accounts', [
      if (list == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      if (list != null && list.isEmpty)
        widget.blocked
            ? const EmptyState(title: 'No blocked accounts', body: "Blocked accounts won't show up in your feed, inbox, or activity.")
            : const EmptyState(title: 'No muted accounts', body: "Posts and activities from muted accounts won't show up in your home feed. Mute accounts directly from their profile or posts."),
      for (final p in list ?? <Map<String, dynamic>>[])
        ListTile(
          leading: Avatar(p['photoUrl']),
          title: Text(p['name'], style: KText.paragraphMediumLarge),
          subtitle: Text(_when(p['since'])),
          trailing: OutlinedButton(onPressed: () => _undo(p), style: OutlinedButton.styleFrom(shape: const StadiumBorder()), child: Text(widget.blocked ? 'Unblock' : 'Unmute')),
        ),
    ]);
  }
}

/// PRF-15 / PRF-16
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key, required this.create});
  final bool create;
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> with Busy {
  final _current = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _code = TextEditingController();
  final Map<String, String?> _err = {};
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.create) {
      context.api.post('/me/password/create/start').then((_) => mounted ? setState(() => _codeSent = true) : null, onError: (_) {});
    }
  }

  Future<void> _submit() async {
    setState(_err.clear);
    if (_pw.text != _pw2.text) return setState(() => _err['confirmPassword'] = 'Passwords do not match');
    final s = context.session;
    await run(() async {
      final r = widget.create
          ? await s.api.post('/me/password/create', {'code': _code.text, 'password': _pw.text, 'confirmPassword': _pw2.text})
          : await s.api.put('/me/password', {'current': _current.text, 'password': _pw.text, 'confirmPassword': _pw2.text});
      await s.refresh();
      if (!mounted) return;
      showToast(context, r['message']);
      context.pop();
    }, onError: (e) {
      if (e is ApiException) setState(() => _err[e.field ?? (e.code == 'INVALID_CODE' ? 'code' : 'password')] = e.message);
    });
  }

  @override
  Widget build(BuildContext context) {
    void changed(_) => setState(() {});
    final me = context.session.me!;
    return KeysScaffold(
      gradient: false,
      header: const KeysHeader(),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Intro(title: widget.create ? 'Create password' : 'Change password', body: widget.create ? 'Keep access to your account secured' : null),
        const SizedBox(height: 24),
        if (widget.create) ...[
          Text(_codeSent ? 'Enter the 6-digit code we sent to ${me.email}' : 'Sending a code to ${me.email}...', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 12),
          CodeInput(controller: _code, error: _err['code'], onCompleted: (_) => setState(() {})),
          const SizedBox(height: 16),
        ] else ...[
          KeysTextField(label: 'Current password', controller: _current, obscure: true, error: _err['current'], onChanged: changed),
          Align(alignment: Alignment.centerRight, child: LinkText('Forgot password', onTap: () => context.push('/auth/forgot', extra: {'email': me.email}))),
          const SizedBox(height: 8),
        ],
        KeysTextField(label: 'New password', controller: _pw, obscure: true, error: _err['password'], onChanged: changed),
        PasswordRules(password: _pw.text),
        const SizedBox(height: 16),
        KeysTextField(label: 'Re-type new password', controller: _pw2, obscure: true, error: _err['confirmPassword'], onChanged: changed),
      ]),
      bottom: KeysButton(
        widget.create ? 'Add password' : 'Change password',
        loading: busy,
        onPressed: PasswordRules.ok(_pw.text) && _pw2.text.isNotEmpty && (widget.create ? _code.text.length == 6 : _current.text.isNotEmpty) ? _submit : null,
      ),
    );
  }
}

/// PRF-18: deactivate, permanent after 30 days.
class DeactivateScreen extends StatefulWidget {
  const DeactivateScreen({super.key});
  @override
  State<DeactivateScreen> createState() => _DeactivateScreenState();
}

class _DeactivateScreenState extends State<DeactivateScreen> with Busy {
  bool _confirm = false;
  final _pw = TextEditingController();
  String? _error;
  List<Map<String, dynamic>> _blockers = [];

  @override
  void initState() {
    super.initState();
    context.api.get('/me/exit-check', query: {'reason': 'deactivate'}).then((r) => mounted ? setState(() => _blockers = List<Map<String, dynamic>>.from(r['blockers'])) : null);
  }

  Future<void> _go() async {
    final s = context.session;
    await run(() async {
      await s.api.post('/me/deactivate', {'password': _pw.text});
      await s.logout();
      if (mounted) context.go('/auth/email');
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong.'));
  }

  @override
  Widget build(BuildContext context) {
    final points = [
      'Your profile, posts and activity will be hidden from your community.',
      'You have 30 days to reactivate your account by logging in.',
      'You can only deactivate your account once a week.',
      'After 30 days your account will be deleted permanently.',
    ];
    final hasPw = context.session.me?.json['hasPassword'] == true;
    return KeysScaffold(
      gradient: false,
      header: KeysHeader(onBack: () => _confirm ? setState(() => _confirm = false) : context.pop()),
      body: !_confirm
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Intro(title: 'Deactivate account'),
              const SizedBox(height: 16),
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(p, style: KText.paragraphMedium))]),
                ),
              for (final b in _blockers) Padding(padding: const EdgeInsets.only(bottom: 8), child: ErrorLine(b['message'])),
              if (!hasPw) const ErrorLine('Add a password first. You will need it to confirm.'),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Intro(title: 'Confirm deactivation', body: 'Enter your password to deactivate your account.'),
              const SizedBox(height: 24),
              KeysTextField(label: 'Password', controller: _pw, obscure: true, error: _error, autofocus: true, onChanged: (_) => setState(() => _error = null)),
            ]),
      bottom: !_confirm
          ? KeysButton('Continue', onPressed: _blockers.isEmpty && hasPw ? () => setState(() => _confirm = true) : null)
          : KeysButton('Deactivate account', loading: busy, onPressed: _pw.text.isEmpty ? null : _go),
    );
  }
}
