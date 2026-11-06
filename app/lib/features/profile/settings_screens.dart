import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/theme_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_screens.dart' show openLegal;
import '../feed/feed_screens.dart' show EmptyState;
import '../feed/social.dart';

/// Figma "Menu item": 28px icon, title Paragraph/Regular/Large, subtitle
/// Paragraph/Regular/Small, 24px CaretRight (or 28px ArrowUpRight for links).
class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.subtitle, this.onTap, {this.external = false});
  final IconData? icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool external;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Row(children: [
            if (icon != null) Padding(padding: const EdgeInsets.only(right: 16), child: Icon(icon, size: 28, color: KColors.iconDefault)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: KText.paragraphLarge),
                  if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))],
                ]),
              ),
            ),
            const SizedBox(width: 8),
            external
                ? Icon(PhosphorIconsRegular.arrowUpRight, size: 28, color: KColors.iconDisabled)
                : SizedBox(height: 48, child: Icon(PhosphorIconsRegular.caretRight, size: 24, color: KColors.iconMuted)),
          ]),
        ),
      );
}

/// Settings pages: Page Header with a 0.5px border-subtle line, rows 16 from
/// the sides, 8 from the top and 4 apart.
Scaffold _page(String title, List<Widget> children) => Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: PageHeader(title, bottomBorder: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 4), c]],
      ),
    );

/// PRF-12: Phase 1 rows. Address book, payment methods, security and
/// language are later phase and hidden.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => _page('Settings', [
        _Row(PhosphorIconsRegular.user, 'Your account', 'View all relevant information on your account', () => context.push('/settings/account')),
        _Row(PhosphorIconsRegular.bellSimple, 'Notification', 'Choose your desired preferences about your activities, interests etc', () => context.push('/settings/notifications')),
        _Row(PhosphorIconsRegular.folderSimpleLock, 'Privacy and Safety', 'Manage what information you see and share', () => context.push('/settings/privacy')),
        _Row(PhosphorIconsRegular.monitor, 'Display', 'Manage your app theme here', () => context.push('/settings/display')),
        _Row(null, 'Terms & Conditions', 'English (UK)', () => openLegal(AppConfig.termsUrl), external: true),
      ]);
}

/// Settings > Display (frames 1239:180529 / 1239:180538). Exactly one switch
/// is on; tapping the one that is on keeps it on.
class DisplayScreen extends StatelessWidget {
  const DisplayScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = context.deps.theme;
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) {
        Widget row(IconData? icon, String label, ThemeChoice c) => Semantics(
              toggled: theme.choice == c,
              label: label,
              child: InkWell(
                onTap: () => theme.set(c),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Row(children: [
                    if (icon != null) Padding(padding: const EdgeInsets.only(right: 16), child: Icon(icon, size: 28, color: KColors.iconDefault)),
                    Expanded(child: ExcludeSemantics(child: Text(label, style: KText.paragraphLarge))),
                    Padding(padding: const EdgeInsets.only(left: 6, right: 8), child: KSwitch(value: theme.choice == c, onChanged: (_) => theme.set(c))),
                  ]),
                ),
              ),
            );
        return Scaffold(
          backgroundColor: KColors.surfaceDefault,
          appBar: const PageHeader('Display', bottomBorder: true),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), children: [
            row(PhosphorIconsRegular.moon, 'Light mode', ThemeChoice.light),
            row(PhosphorIconsFill.moon, 'Dark mode', ThemeChoice.dark),
            row(null, 'Use device default settings', ThemeChoice.system),
          ]),
        );
      },
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final me = context.session.me!;
    final hasPw = me.json['hasPassword'] == true;
    Future<void> logout() async {
      // PRF-17.1 (design copy "our account" corrected).
      if (!await confirmSheet(context, title: 'Log out', body: 'Are you sure you want to log out of your account?', confirm: 'Log out')) return;
      if (!context.mounted) return;
      await context.session.logout();
      if (context.mounted) context.go('/auth/email');
    }

    // Figma 1239:182677: two rows, Log out pinned under an 8pt grey band.
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: const PageHeader('Account', bottomBorder: true),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
            hasPw
                ? _Row(PhosphorIconsRegular.key, 'Change password', null, () => context.push('/settings/password'))
                : _Row(PhosphorIconsRegular.key, 'Create password', 'Keep access to your account secured', () => context.push('/settings/password/create')),
            const SizedBox(height: 4),
            _Row(PhosphorIconsRegular.heartBreak, 'Deactivate account', null, () => context.push('/settings/deactivate')),
          ]),
        ),
        Container(height: 8, color: KColors.surfaceSubtle),
        SafeArea(
          top: false,
          child: InkWell(
            onTap: logout,
            child: SizedBox(
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Icon(PhosphorIconsRegular.signOut, size: 20, color: KColors.error),
                  const SizedBox(width: 12),
                  Text('Log out', style: KText.paragraphMedium.copyWith(color: KColors.error)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
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
    // Figma 1239:181303: two white sections on grey, Geist 20 titles, rows
    // ruled in surface/subtle. Rows are the Phase 1 notification types.
    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(t, style: TextStyle(fontFamily: 'Geist', fontSize: 20, fontWeight: FontWeight.w600, height: 26 / 20, color: KColors.textPrimary)),
        );
    Widget row(String t, String? sub, {bool? value, ValueChanged<bool>? onChanged}) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.surfaceSubtle))),
          constraints: const BoxConstraints(minHeight: 72),
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: KText.paragraphLarge),
                  if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))],
                ]),
              ),
            ),
            if (value != null) ...[const SizedBox(width: 12), Semantics(label: t, toggled: value, child: KSwitch(value: value, onChanged: onChanged))],
          ]),
        );
    Widget section(List<Widget> kids) => Container(color: KColors.surfaceDefault, padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids));
    return Scaffold(
      backgroundColor: KColors.surfaceSubtle,
      appBar: const PageHeader('Notification', bottomBorder: true),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        section([
          title('In-app notification'),
          for (final e in labels.entries) row(e.value.$1, e.value.$2, value: p[e.key] == true, onChanged: (v) => _set(e.key, v)),
          const SizedBox(height: 16),
        ]),
        const SizedBox(height: 8),
        section([
          title('Email notification'),
          row('Newsletter', 'Get latest news and updates about Keys community', value: p['newsletter'] == true, onChanged: (v) => _set('newsletter', v)),
          row('Sign-in alerts and account updates', 'Service emails we always send to keep your account safe'),
          const SizedBox(height: 16),
        ]),
      ]),
    );
  }
}

/// PRF-13
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  // Figma 1239:181126: text-only rows.
  Widget build(BuildContext context) => _page('Privacy & Safety', [
        _Row(null, 'Blocked accounts', "Manage all accounts you've blocked", () => context.push('/settings/blocked')),
        _Row(null, 'Muted accounts', "Manage all accounts you've muted", () => context.push('/settings/muted')),
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
