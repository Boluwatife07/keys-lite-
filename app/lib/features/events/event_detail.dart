import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/feed_screens.dart' show EmptyState;
import '../feed/social.dart';
import '../updates/updates_list.dart' show SearchField;
import '../verification/verification_screens.dart' show handleVerificationRequired;
import 'event_common.dart';
import 'event_form.dart' show launchEvent, kCategoryNames;

const kCancelReasons = [
  'Low number of attendees / poor turnout',
  'Personal emergency or change of plans',
  'Technical issue',
  'Posted by mistake',
  'Other (please specify)',
];

/// EVT-18: the event page as residents, hosts, co-hosts and volunteers see it.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Map<String, dynamic>? _e;
  ApiException? _error;
  bool _readMore = false;
  int _page = 0;

  EventItem get _item => EventItem(_e!);
  String? get _role => _e?['myRole'];
  bool get _team => _role == 'host' || _role == 'cohost';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/events/${widget.id}');
      if (mounted) setState(() => _e = Map<String, dynamic>.from(r['event']));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() fn) async {
    try {
      final r = await fn();
      if (mounted && r['message'] is String) showToast(context, r['message']);
      _load();
    } catch (e) {
      if (mounted && !handleVerificationRequired(context, e)) showToast(context, e is ApiException ? e.message : 'Something went wrong. Please try again.');
    }
  }

  // EVT-19
  Future<void> _getTicket() async {
    final api = context.api;
    final router = GoRouter.of(context);
    final ok = await confirmSheet(context, title: 'Get ticket', body: 'Get a free ticket for ${_item.title}? One ticket per person.', confirm: 'Get ticket');
    if (!ok || !mounted) return;
    try {
      final r = await api.post('/events/${widget.id}/tickets');
      _load();
      if (!mounted) return;
      final view = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircleAvatar(radius: 32, backgroundColor: Color(0xFFE6F6EA), child: Icon(PhosphorIconsRegular.ticket, size: 32, color: KColors.success)),
              const SizedBox(height: 12),
              Text(r['title'] ?? "You're going", style: KText.headingSmall),
              const SizedBox(height: 8),
              Text(r['message'] ?? '', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              const SizedBox(height: 20),
              KeysButton('View ticket', onPressed: () => Navigator.pop(c, true)),
            ]),
          ),
        ),
      );
      if (view == true) router.push('/tickets/${r['ticket']['id']}');
    } catch (e) {
      if (mounted && !handleVerificationRequired(context, e)) showToast(context, e is ApiException ? e.message : 'Something went wrong. Please try again.');
    }
  }

  // EVT-22
  Future<void> _volunteer() async {
    final api = context.api;
    final router = GoRouter.of(context);
    final ok = await confirmSheet(
      context,
      title: 'Volunteer for this event',
      body: "By joining, you'll be giving your time to help the hosts run this event. You'll be added to the planning group chat.",
      confirm: 'Volunteer',
    );
    if (!ok || !mounted) return;
    try {
      final r = await api.post('/events/${widget.id}/volunteer');
      _load();
      if (!mounted) return;
      final go = await confirmSheet(context, title: r['title'], body: r['message'], confirm: 'Go to group chat', cancel: 'Close');
      if (go && r['chatId'] != null) router.push('/chats/${r['chatId']}');
    } catch (e) {
      if (mounted && !handleVerificationRequired(context, e)) showToast(context, e is ApiException ? e.message : 'Something went wrong.');
    }
  }

  // EVT-14
  Future<void> _cancel() async {
    final api = context.api;
    final r = await showModalBottomSheet<({String reason, String? text})>(context: context, isScrollControlled: true, builder: (_) => const _CancelSheet());
    if (r == null || !mounted) return;
    final ok = await confirmSheet(context, title: 'Cancel event', body: 'Once canceled, attendees will be notified. This action cannot be undone. Are you sure you want to cancel?', confirm: 'Yes, cancel', cancel: 'Go back', destructive: true);
    if (!ok) return;
    await _act(() => api.post('/events/${widget.id}/cancel', {'reason': r.reason, if (r.text != null) 'text': r.text}));
  }

  void _menu() {
    final api = context.api;
    final e = _e!;
    final status = e['status'];
    showActionSheet(context, [
      if (e['canEdit'] == true)
        SheetAction(PhosphorIconsRegular.pencilSimple, 'Edit event', () async {
          final r = await context.push('/events/${widget.id}/edit');
          if (r != null) _load();
        }),
      if (_team && status != 'draft') SheetAction(PhosphorIconsRegular.ticket, 'Tickets', () => context.push('/events/${widget.id}/attendees')),
      if (e['canScan'] == true) SheetAction(PhosphorIconsRegular.scan, 'QR Scan', () => context.push('/events/${widget.id}/scan')),
      if (_team && status == 'completed') SheetAction(PhosphorIconsRegular.star, 'Ratings', () => context.push('/events/${widget.id}/ratings')),
      if (status == 'live' && !_team)
        e['saved'] == true
            ? SheetAction(PhosphorIconsRegular.bookmarkSimple, 'Remove bookmark', () => _act(() => api.delete('/events/${widget.id}/save')))
            : SheetAction(PhosphorIconsRegular.bookmarkSimple, 'Bookmark event', () => _act(() => api.post('/events/${widget.id}/save'))),
      if (status == 'live' && _role == 'host') SheetAction(PhosphorIconsRegular.calendarX, 'Cancel event', _cancel, destructive: true),
      if (status == 'draft' && _role == 'host')
        SheetAction(PhosphorIconsRegular.trash, 'Delete draft', () async {
          final router = GoRouter.of(context);
          final ok = await confirmSheet(context, title: 'Delete draft?', body: 'This draft and its planning chat will be removed.', confirm: 'Delete');
          if (!ok) return;
          await _act(() => api.delete('/events/${widget.id}'));
          router.pop(true);
        }, destructive: true),
      if (!_team && status != 'draft') SheetAction(PhosphorIconsRegular.flag, 'Report event', () => showReportSheet(context, itemType: 'event', itemId: widget.id, title: 'Report event')),
    ]);
  }

  void _share() {
    final e = _e!;
    final deps = context.deps;
    showActionSheet(context, [
      SheetAction(PhosphorIconsRegular.link, 'Copy link', () async {
        await deps.sharer.copy(e['shareLink']);
        if (mounted) showToast(context, 'Link copied');
      }),
      SheetAction(PhosphorIconsRegular.shareFat, 'Share via', () => deps.sharer.share('${e['shareText']} ${e['shareLink']}')),
    ]);
  }

  void _hosts() {
    final hosts = List<Map<String, dynamic>>.from(_e!['hosts']);
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Hosts', style: KText.headingSmall)),
          for (final h in hosts)
            ListTile(
              leading: h['external'] == true ? const CircleAvatar(backgroundColor: KColors.surfaceSubtle, child: Icon(PhosphorIconsRegular.buildings)) : Avatar(h['person']?['photoUrl'], size: 40),
              title: Text(h['name']),
              subtitle: Text(h['external'] == true ? 'External • This co-host is not on Keys.' : '${h['role']}${h['status'] == 'invited' ? ' (invited)' : ''}'),
              onTap: h['person'] == null ? null : () {
                Navigator.pop(c);
                context.push('/users/${h['person']['id']}');
              },
              trailing: _role == 'host' && h['id'] != null
                  ? IconButton(
                      tooltip: 'Remove ${h['name']}',
                      icon: const Icon(PhosphorIconsRegular.userMinus),
                      onPressed: () {
                        Navigator.pop(c);
                        _act(() => context.api.delete('/events/${widget.id}/cohosts/${h['id']}'));
                      },
                    )
                  : null,
            ),
        ]),
      ),
    );
  }

  void _volunteersSheet() {
    final vols = List<Map<String, dynamic>>.from(_e!['volunteers']);
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Volunteers', style: KText.headingSmall)),
          if (vols.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No volunteers yet', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
          for (final v in vols)
            ListTile(
              leading: Avatar(v['photoUrl'], size: 40),
              title: Text(v['name']),
              trailing: _team
                  ? TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        final ok = await confirmSheet(context, title: 'Remove ${v['name']}?', body: 'They will leave the planning chat and cannot volunteer again for this event.', confirm: 'Remove');
                        if (ok) await _act(() => context.api.delete('/events/${widget.id}/volunteers/${v['id']}'));
                      },
                      child: Text('Remove', style: TextStyle(color: KColors.error)),
                    )
                  : null,
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(title: 'Event not available', body: _error!.message));
    }
    final e = _e;
    if (e == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final item = _item;
    final media = List<Map<String, dynamic>>.from(e['media']);
    final hosts = List<Map<String, dynamic>>.from(e['hosts']).where((h) => h['status'] == 'accepted').toList();
    final lineup = List<Map<String, dynamic>>.from(e['lineup']);
    final vols = List<Map<String, dynamic>>.from(e['volunteers']);
    final attending = List<Map<String, dynamic>>.from((e['attendingPreview'] as List).where((x) => x != null));
    final also = (e['youMightAlsoLike'] as List).map((x) => EventItem(Map<String, dynamic>.from(x))).toList();
    final status = e['status'] as String;
    final ticket = e['myTicket'] as Map?;
    final desc = (e['description'] as String?) ?? '';
    final hostNames = hosts.take(2).map((h) => h['name'] as String).toList();

    Widget section(String title, Widget child, {String? action, VoidCallback? onAction}) => Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: KColors.surfaceSubtle, width: 6))),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
              if (action != null) TextButton(onPressed: onAction, style: TextButton.styleFrom(foregroundColor: KColors.textSecondary), child: Text(action)),
            ]),
            const SizedBox(height: 6),
            child,
          ]),
        );

    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => context.pop()),
        actions: [
          if (status == 'live' || status == 'draft') IconButton(tooltip: 'Share event', icon: const Icon(PhosphorIconsRegular.shareNetwork), onPressed: _share),
          if (status != 'cancelled' || _team) IconButton(tooltip: 'Event options', icon: const Icon(PhosphorIconsRegular.dotsThreeVertical), onPressed: _menu),
        ],
      ),
      floatingActionButton: e['canScan'] == true && status == 'live'
          ? FloatingActionButton(
              heroTag: 'scan',
              tooltip: 'QR Scan',
              backgroundColor: KColors.brand,
              foregroundColor: KColors.textPrimary,
              shape: const CircleBorder(),
              onPressed: () => context.push('/events/${widget.id}/scan'),
              child: const Icon(PhosphorIconsRegular.scan),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (media.isNotEmpty)
            SizedBox(
              height: 280,
              child: Stack(children: [
                PageView(
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (var i = 0; i < media.length; i++)
                      Semantics(
                        button: true,
                        label: media[i]['kind'] == 'video' ? 'Play video' : 'Photo ${i + 1} of ${media.length}',
                        child: InkWell(
                          onTap: () => media[i]['kind'] == 'video'
                              ? context.push('/video', extra: context.api.absolute(media[i]['url']))
                              : context.push('/media', extra: {'urls': media.where((m) => m['kind'] == 'photo').map((m) => m['url']).toList(), 'index': i}),
                          child: media[i]['kind'] == 'video'
                              ? Container(color: Colors.black87, child: const Center(child: Icon(PhosphorIconsFill.playCircle, size: 56, color: Colors.white)))
                              : Image.network(context.api.absolute(media[i]['url']), fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, _, _) => Container(color: KColors.surfaceSubtle)),
                        ),
                      ),
                  ],
                ),
                if (media.length > 1)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < media.length; i++)
                        Container(width: i == _page ? 18 : 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: i == _page ? KColors.brand : Colors.white, borderRadius: BorderRadius.circular(3))),
                    ]),
                  ),
              ]),
            ),
          if (status != 'live')
            Container(
              width: double.infinity,
              color: status == 'cancelled' ? const Color(0xFFFDECEA) : status == 'draft' ? KColors.brandSubtle : const Color(0xFFE6F6EA),
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(switch (status) { 'cancelled' => 'Cancelled', 'draft' => 'Draft: only you and your co-hosts can see this', _ => 'Completed' },
                    style: KText.paragraphMediumLarge.copyWith(color: status == 'cancelled' ? KColors.error : status == 'draft' ? KColors.textPrimary : KColors.success)),
                if (status == 'draft')
                  for (final p in List<String>.from(e['launchProblems'] ?? [])) Text('•  $p', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
              ]),
            ),
          if (_role == 'cohost_invited') _CohostInvite(event: e, onDone: _load),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(item.title, style: KText.headingSmall)),
                if (e['chatId'] != null)
                  IconButton.filledTonal(tooltip: 'Event group chat', icon: const Icon(PhosphorIconsRegular.chatText), onPressed: () => context.push('/chats/${e['chatId']}')),
              ]),
              const SizedBox(height: 10),
              _Info(PhosphorIconsRegular.calendarBlank, item.startAt == null ? 'Date to be set' : eventDay(item.startAt!)),
              _Info(PhosphorIconsRegular.clock, eventTimes(item)),
              if (item.format == 'online')
                _Info(PhosphorIconsRegular.videoCamera, e['link'] != null ? '${item.platform} • Join link' : (item.platform ?? 'Online'), link: e['link'])
              else
                _Info(PhosphorIconsRegular.mapPin, item.locationName ?? 'Location to be added',
                    link: e['lat'] == null ? null : 'https://www.google.com/maps/search/?api=1&query=${e['lat']},${e['lng']}'),
              if (e['meetingId'] != null) _Info(PhosphorIconsRegular.hash, 'Meeting ID ${e['meetingId']}${e['meetingPassword'] != null ? ' • Password ${e['meetingPassword']}' : ''}'),
            ]),
          ),
          section(
            'Event details',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (desc.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _readMore = !_readMore),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: _readMore || desc.length <= 140 ? desc : '${desc.substring(0, 140)}…', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                    if (desc.length > 140 && !_readMore) TextSpan(text: ' ...Read more', style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w600)),
                  ])),
                ),
              const SizedBox(height: 10),
              Semantics(
                button: true,
                label: 'Hosts: ${hosts.map((h) => h['name']).join(', ')}',
                child: InkWell(
                  onTap: _hosts,
                  child: ExcludeSemantics(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: 'Hosts: ', style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w600)),
                      TextSpan(text: hostNames.join(', '), style: KText.paragraphMedium.copyWith(color: KColors.textLink, decoration: TextDecoration.underline)),
                      if (hosts.length > 2) TextSpan(text: ', +${hosts.length - 2} others', style: KText.paragraphMedium.copyWith(color: KColors.textLink, decoration: TextDecoration.underline)),
                    ])),
                  ),
                ),
              ),
              if (item.going > 0) ...[
                const SizedBox(height: 10),
                Row(children: [
                  SizedBox(
                    width: 24.0 + 18 * (attending.length.clamp(1, 3) - 1),
                    height: 28,
                    child: Stack(children: [
                      for (var i = 0; i < attending.length.clamp(0, 3); i++) Positioned(left: i * 18.0, child: Avatar(attending[i]['photoUrl'], size: 28)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text('+${item.going} attending', style: KText.paragraphMedium),
                ]),
              ],
            ]),
          ),
          section('Category', Text(kCategoryNames[item.category] ?? item.category, style: KText.paragraphLarge)),
          section('Audience', Text(e['audience'] == 'members' ? 'Members of ${e['clubName'] ?? 'the club'}' : 'All residents', style: KText.paragraphLarge)),
          section(
            'Tickets',
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tickets', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('Free', style: KText.headingSmall),
                    if (item.capacity != null) Text('${item.going}/${item.capacity} taken', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  ]),
                ),
                if (_team && status != 'draft')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, shape: const StadiumBorder()),
                    onPressed: () => context.push('/events/${widget.id}/attendees'),
                    icon: const Icon(PhosphorIconsRegular.caretRight),
                    label: const Text('View'),
                  ),
              ]),
            ),
          ),
          if (lineup.isNotEmpty)
            section(
              'Lineup',
              SizedBox(
                height: 128,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final g in lineup)
                    SizedBox(
                      width: 104,
                      child: Column(children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: KColors.brand,
                          child: CircleAvatar(
                            radius: 30,
                            backgroundColor: KColors.surfaceSubtle,
                            backgroundImage: g['photoUrl'] == null ? null : NetworkImage(context.api.absolute(g['photoUrl'])),
                            child: g['photoUrl'] == null ? const Icon(PhosphorIconsRegular.user) : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(g['name'], style: KText.paragraphMediumSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(g['title'] ?? '', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary, fontSize: 11), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                ]),
              ),
            ),
          if (e['acceptVolunteers'] == true)
            section(
              'Volunteers',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (vols.isEmpty)
                  Text('${e['volunteerCap']} volunteer${e['volunteerCap'] == 1 ? '' : 's'} needed', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))
                else
                  Text('${vols.take(2).map((v) => v['name']).join(', ')}${vols.length > 2 ? ' and others' : ''} • ${vols.length}/${e['volunteerCap']}', style: KText.paragraphMedium),
                if (e['volunteerState'] == 'open' || e['volunteerState'] == 'full') ...[
                  const SizedBox(height: 10),
                  KeysButton('Apply as volunteer', variant: ButtonVariant.outline, onPressed: e['volunteerState'] == 'open' && status == 'live' ? _volunteer : null),
                ],
                if (e['volunteerState'] == 'volunteering') Padding(padding: const EdgeInsets.only(top: 8), child: Text("You're volunteering for this event", style: KText.paragraphMediumSmall.copyWith(color: KColors.success))),
              ]),
              action: 'View all →',
              onAction: _volunteersSheet,
            ),
          if (also.isNotEmpty)
            section('You might also like', Column(children: [for (final a in also) EventRow(a)])),
        ]),
      ),
      bottomNavigationBar: _bottom(e, item, status, ticket),
    );
  }

  Widget? _bottom(Map<String, dynamic> e, EventItem item, String status, Map? ticket) {
    Widget? child;
    if (status == 'draft' && _role == 'host') {
      child = Row(children: [
        Expanded(child: KeysButton('Edit event', variant: ButtonVariant.secondary, onPressed: () async {
          final r = await context.push('/events/${widget.id}/edit');
          if (r != null) _load();
        })),
        const SizedBox(width: 12),
        Expanded(child: KeysButton('Launch event', onPressed: (e['launchProblems'] as List).isEmpty ? () async {
          if (await launchEvent(context, widget.id)) _load();
        } : null)),
      ]);
    } else if (status == 'completed') {
      if (_role == 'host') {
        child = Row(children: [
          Expanded(child: KeysButton('Ratings', variant: ButtonVariant.secondary, onPressed: () => context.push('/events/${widget.id}/ratings'))),
          const SizedBox(width: 12),
          Expanded(child: KeysButton('Redo this event', onPressed: () async {
            final router = GoRouter.of(context);
            try {
              final r = await context.api.post('/events/${widget.id}/redo');
              router.push('/events/${r['event']['id']}/edit');
            } on ApiException catch (x) {
              if (mounted) showToast(context, x.message);
            }
          })),
        ]);
      } else if (e['canRate'] == true) {
        child = KeysButton('Rate event', onPressed: () async {
          await showRatingSheet(context, item);
          _load();
        });
      }
    } else if (status == 'live') {
      if (ticket != null && ticket['status'] == 'active') {
        child = KeysButton('View ticket', onPressed: () => context.push('/tickets/${ticket['id']}'));
      } else if (_role != 'host') {
        child = KeysButton(item.soldOut ? 'Sold out' : 'Get ticket', onPressed: e['canGetTicket'] == true ? _getTicket : null);
      }
    }
    if (child == null) return null;
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: child));
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text, {this.link});
  final IconData icon;
  final String text;
  final String? link;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: link == null ? null : () => launchUrl(Uri.parse(link!), mode: LaunchMode.externalApplication),
          child: Row(children: [
            Icon(icon, size: 20, color: KColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: KText.paragraphLarge.copyWith(color: link == null ? null : KColors.textLink))),
          ]),
        ),
      );
}

/// EVT-15.1: "You have been added as a co-host!" with Accept / Decline.
class _CohostInvite extends StatelessWidget {
  const _CohostInvite({required this.event, required this.onDone});
  final Map<String, dynamic> event;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    final host = (event['hosts'] as List).firstWhere((h) => h['role'] == 'Host', orElse: () => {'name': 'The host'});
    Future<void> go(String action) async {
      try {
        final r = await context.api.post('/events/${event['id']}/cohost/$action');
        if (context.mounted) showToast(context, r['message']);
        onDone();
      } on ApiException catch (e) {
        if (context.mounted) showToast(context, e.message);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: const Color(0xFFFFEDB0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('You have been added as a co-host!', style: KText.paragraphMediumLarge),
        const SizedBox(height: 4),
        Text('${host['name']} has added you as a co-host for ${event['title']}. As a co-host you can edit the event, manage volunteers, see attendees and scan tickets.',
            style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: KeysButton('Decline invitation', variant: ButtonVariant.secondary, onPressed: () => go('decline'))),
          const SizedBox(width: 8),
          Expanded(child: KeysButton('Accept invitation', onPressed: () => go('accept'))),
        ]),
      ]),
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  String? _reason;
  final _text = TextEditingController();
  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final other = _reason == kCancelReasons.last;
    final ready = _reason != null && (!other || _text.text.trim().isNotEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reason for cancelling', style: KText.headingSmall),
          const SizedBox(height: 4),
          Text('Tell us why you are canceling this event', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(children: [
              for (final r in kCancelReasons) RadioListTile<String>(value: r, title: Text(r, style: KText.paragraphMedium), contentPadding: EdgeInsets.zero, activeColor: KColors.surfaceInverted),
            ]),
          ),
          if (other) KeysTextField(controller: _text, hint: 'Please specify', maxLength: 300, maxLines: 3),
          const SizedBox(height: 12),
          KeysButton('Continue', onPressed: ready ? () => Navigator.pop(context, (reason: _reason!, text: other ? _text.text.trim() : null)) : null),
        ]),
      ),
    );
  }
}

/// EVT-24.2 / EVT-24.3: stars and optional feedback.
Future<void> showRatingSheet(BuildContext context, EventItem e) => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _RatingSheet(e));

class _RatingSheet extends StatefulWidget {
  const _RatingSheet(this.e);
  final EventItem e;
  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> with Busy {
  int _stars = 0;
  final _text = TextEditingController();
  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  Future<void> _close() async {
    // Closing without rating dismisses the prompt for good.
    try {
      await context.api.post('/events/${widget.e.id}/rating/dismiss');
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  Future<void> _submit() async {
    final api = context.api;
    await run(() async {
      final r = await api.post('/events/${widget.e.id}/rating', {'stars': _stars, 'text': _text.text.trim()});
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, '${r['title']}. ${r['message']}');
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(widget.e.title, style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
              IconButton(tooltip: 'Close', icon: const Icon(PhosphorIconsRegular.x), onPressed: _close),
            ]),
            if (widget.e.coverUrl != null)
              ClipRRect(borderRadius: BorderRadius.circular(KRadius.sm), child: Image.network(context.api.absolute(widget.e.coverUrl!), height: 140, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())),
            const SizedBox(height: 16),
            Center(child: Text('How was your experience?', style: KText.headingXSmall)),
            const SizedBox(height: 6),
            Text('Your feedback helps event organisers improve and create even better experiences for our community.', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  iconSize: 40,
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(i <= _stars ? PhosphorIconsFill.star : PhosphorIconsRegular.star, color: const Color(0xFFFFC21A)),
                ),
            ]),
            Row(children: [
              Expanded(child: Text('Share your feedback', style: KText.paragraphMediumLarge)),
              Text('${_text.text.length}/400', style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              maxLength: 400,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Tell us what you loved or what could be better',
                filled: true,
                fillColor: KColors.surfaceSubtle,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.sm), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            KeysButton('Submit', loading: busy, onPressed: _stars == 0 ? null : _submit),
          ]),
        ),
      );
}

/// EVT-20: ticket with QR code, seat, download (PDF), share and cancel.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.id});
  final String id;
  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  Map<String, dynamic>? _t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/tickets/${widget.id}');
      if (mounted) setState(() => _t = Map<String, dynamic>.from(r['ticket']));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  String _when(Map t) {
    final s = DateTime.parse(t['startAt']).toLocal();
    final e = DateTime.parse(t['endAt']).toLocal();
    return '${DateFormat('EEE, d MMM').format(s)} (${eventTime(s)} - ${eventTime(e)})';
  }

  Future<void> _download() async {
    final t = _t!;
    final sharer = context.deps.sharer;
    showToast(context, 'Downloading...');
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(t['eventTitle'], style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Text('Ordered by: ${t['holder']?['name'] ?? ''}'),
        pw.Text('Ticket no.: ${t['seat']}'),
        pw.Text('Price: Free'),
        pw.Text('Date: ${_when(t)}'),
        pw.Text(t['format'] == 'online' ? 'Online: ${t['platform'] ?? ''} ${t['link'] ?? ''}' : 'Location: ${t['locationName'] ?? ''}'),
        pw.SizedBox(height: 24),
        pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: t['qr'], width: 180, height: 180)),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('Show qrcode and scan upon arrival to event')),
      ]),
    ));
    await sharer.shareFile(await doc.save(), 'ticket-${t['seat']}.pdf', 'application/pdf');
  }

  Future<void> _cancel() async {
    final api = context.api;
    final ok = await confirmSheet(context, title: 'Cancel ticket', body: 'Your place will be released and your QR code will no longer work.', confirm: 'Cancel ticket', cancel: 'Keep ticket', destructive: true);
    if (!ok) return;
    try {
      final r = await api.post('/tickets/${widget.id}/cancel');
      if (!mounted) return;
      setState(() => _t = Map<String, dynamic>.from(r['ticket']));
      showToast(context, r['message']);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final active = t?['status'] == 'active';
    Widget field(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value, style: KText.paragraphLarge),
          ]),
        );
    return Scaffold(
      backgroundColor: KColors.surfaceSubtle,
      appBar: AppBar(
        backgroundColor: KColors.surfaceSubtle,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(tooltip: 'Close', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => context.pop()),
        actions: [if (active && t?['checkedInAt'] == null) TextButton(onPressed: _cancel, child: Text('Cancel ticket', style: TextStyle(color: KColors.error)))],
      ),
      body: t == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(KRadius.lg), border: Border.all(color: KColors.borderDefault)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!active)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(KRadius.sm)),
                      child: Column(children: [
                        Text(t['status'] == 'void' ? 'EVENT CANCELLED' : 'TICKET CANCELLED', style: KText.paragraphMediumLarge.copyWith(color: KColors.error)),
                        Text(t['status'] == 'void' ? 'This event has been cancelled by the host.' : 'Your ticket has been cancelled.', style: KText.paragraphSmall.copyWith(color: KColors.error)),
                      ]),
                    ),
                  Text(t['eventTitle'] ?? '', style: KText.headingSmall),
                  const SizedBox(height: 16),
                  Row(children: [field('Ordered by', t['holder']?['name'] ?? ''), if (active) field('Ticket no.', t['seat'])]),
                  const SizedBox(height: 12),
                  Row(children: [field('Ticket type', 'Regular'), field('Price', 'Free')]),
                  const SizedBox(height: 12),
                  Row(children: [field('Date', _when(t))]),
                  const SizedBox(height: 12),
                  Row(children: [field(t['format'] == 'online' ? 'Platform' : 'Location', t['format'] == 'online' ? (t['platform'] ?? 'Online') : (t['locationName'] ?? ''))]),
                  if (active && t['link'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InkWell(onTap: () => launchUrl(Uri.parse(t['link']), mode: LaunchMode.externalApplication), child: Text(t['link'], style: KText.paragraphMedium.copyWith(color: KColors.textLink))),
                    ),
                  if (active) ...[
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
                    Center(child: Semantics(label: 'Ticket QR code', child: QrImageView(data: t['qr'], size: 180))),
                    const SizedBox(height: 8),
                    Center(child: Text(t['checkedInAt'] != null ? 'Checked in' : 'Show qrcode and scan upon arrival to event', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
                  ],
                ]),
              ),
            ]),
      bottomNavigationBar: active
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Expanded(child: KeysButton('Download', icon: const Icon(PhosphorIconsRegular.downloadSimple, color: Colors.white, size: 18), onPressed: _download)),
                  const SizedBox(width: 12),
                  Expanded(child: KeysButton('Share', variant: ButtonVariant.outline, onPressed: () => showShareSheet(context, t!['shareLink']))),
                ]),
              ),
            )
          : null,
    );
  }
}

/// EVT-16: tickets taken vs capacity, recent and all, searchable.
class AttendeesScreen extends StatefulWidget {
  const AttendeesScreen({super.key, required this.id});
  final String id;
  @override
  State<AttendeesScreen> createState() => _AttendeesScreenState();
}

class _AttendeesScreenState extends State<AttendeesScreen> {
  Map<String, dynamic>? _d;
  final _q = TextEditingController();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(() {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), _load);
    });
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/events/${widget.id}/attendees', query: _q.text.trim().isEmpty ? null : {'q': _q.text.trim()});
      if (mounted) setState(() => _d = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    Widget row(Map<String, dynamic> a) => ListTile(
          leading: Avatar(a['person']?['photoUrl'], size: 40),
          title: Text(a['person']?['name'] ?? ''),
          subtitle: Text('${DateFormat('d MMM, y').format(DateTime.parse(a['takenAt']).toLocal())}${a['checkedInAt'] != null ? ' • Checked in' : ''}'),
          trailing: Text(a['seat'], style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w700)),
        );
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('Tickets', style: KText.headingXSmall)),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  SizedBox(
                    width: 110,
                    height: 110,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox(
                        width: 110,
                        height: 110,
                        child: CircularProgressIndicator(
                          value: d['capacity'] == null ? (d['taken'] > 0 ? 1 : 0) : (d['taken'] / d['capacity']).clamp(0.0, 1.0),
                          strokeWidth: 14,
                          color: const Color(0xFFA78BFA),
                          backgroundColor: KColors.surfaceMuted,
                        ),
                      ),
                      Text(d['capacity'] == null ? '${d['taken']}' : '${((d['taken'] / d['capacity']) * 100).round()}%', style: KText.headingSmall),
                    ]),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Tickets taken', style: KText.paragraphMediumLarge),
                      Text(d['capacity'] == null ? '${d['taken']} tickets (unlimited)' : '${d['taken']}/${d['capacity']} tickets', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                      Text('${d['checkedIn']} checked in', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                    ]),
                  ),
                ]),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SearchField(controller: _q, hint: 'Search by name or seat number')),
              if ((d['all'] as List).isEmpty && _q.text.isEmpty)
                EmptyState(
                  title: 'No tickets sold yet',
                  body: 'Your ticket sales will appear here once people start booking.',
                  action: KeysButton('Share your event', onPressed: () async {
                    final r = await context.api.get('/events/${widget.id}');
                    if (context.mounted) showShareSheet(context, r['event']['shareLink']);
                  }),
                )
              else ...[
                if (_q.text.isEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Recent sales', style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
                  for (final a in List<Map<String, dynamic>>.from(d['recent'])) row(a),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('All tickets', style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
                ],
                for (final a in List<Map<String, dynamic>>.from(d['all'])) row(a),
                if ((d['all'] as List).isEmpty) const EmptyState(title: 'No results found', body: 'Try another keyword.'),
              ],
            ]),
    );
  }
}

/// EVT-23: scan QR codes; the code can also be typed.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.id});
  final String id;
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  Map<String, dynamic>? _result;
  Map<String, dynamic>? _counts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.api.get('/events/${widget.id}/checkins').then((r) {
      if (mounted) setState(() => _counts = r);
    }).catchError((_) {});
  }

  Future<void> _check(String code) async {
    if (_busy || _result != null) return;
    setState(() => _busy = true);
    try {
      final r = await context.api.post('/events/${widget.id}/scan', {'code': code});
      if (mounted) {
        setState(() {
          _result = r;
          _counts = r;
        });
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _type() async {
    final c = TextEditingController();
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Enter ticket code', style: KText.headingSmall),
          const SizedBox(height: 12),
          KeysTextField(controller: c, hint: 'KEYS-...', autofocus: true),
          const SizedBox(height: 12),
          KeysButton('Check', onPressed: () => Navigator.pop(s, c.text.trim())),
        ]),
      ),
    );
    if (code != null && code.isNotEmpty) _check(code);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final counts = _counts == null ? '' : '${_counts!['checkedIn']} / ${_counts!['total']} checked in';
    final ok = r?['result'] == 'valid';
    final color = ok ? KColors.success : KColors.error;
    return Scaffold(
      backgroundColor: KColors.surfaceInverted,
      appBar: AppBar(
        backgroundColor: KColors.surfaceInverted,
        foregroundColor: Colors.white,
        leading: IconButton(tooltip: 'Close', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => context.pop()),
        title: Text('Scan Tickets', style: KText.headingXSmall.copyWith(color: Colors.white)),
        titleSpacing: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text(counts, style: KText.paragraphMedium.copyWith(color: Colors.white70)),
          const SizedBox(height: 12),
          Expanded(
            child: r == null
                ? Column(children: [
                    Text('Point the camera at the attendees ticket QR code', textAlign: TextAlign.center, style: KText.paragraphLarge.copyWith(color: Colors.white)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(KRadius.lg),
                        child: context.deps.cameraScanner
                            ? MobileScanner(onDetect: (cap) {
                                final v = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
                                if (v != null) _check(v);
                              })
                            : Container(color: Colors.black, child: const Center(child: Icon(PhosphorIconsRegular.scan, color: Colors.white38, size: 96))),
                      ),
                    ),
                    TextButton(onPressed: _type, child: const Text('Enter code instead', style: TextStyle(color: Colors.white))),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 4)),
                      child: Icon(ok ? PhosphorIconsRegular.checks : PhosphorIconsRegular.x, color: color, size: 56),
                    ),
                    const SizedBox(height: 20),
                    Text(r['title'], style: KText.headingSmall.copyWith(color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(r['message'], textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: Colors.white70)),
                    if (r['ticket'] != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: Colors.white54)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Ordered by', style: KText.paragraphSmall.copyWith(color: Colors.white54)),
                              Text(r['ticket']['holder']?['name'] ?? '', style: KText.paragraphLarge.copyWith(color: Colors.white)),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('Ticket no.', style: KText.paragraphSmall.copyWith(color: Colors.white54)),
                            Text(r['ticket']['seat'], style: KText.paragraphLarge.copyWith(color: Colors.white)),
                            if (r['checkedInLabel'] != null) Text(r['checkedInLabel'], style: KText.paragraphSmall.copyWith(color: Colors.white54)),
                          ]),
                        ]),
                      ),
                    ],
                  ]),
          ),
          if (r != null) KeysButton('Scan next', variant: ButtonVariant.light, icon: const Icon(PhosphorIconsRegular.scan, size: 18), onPressed: () => setState(() => _result = null)),
        ]),
      ),
    );
  }
}

/// EVT-24.4: average, breakdown and reviews with sorting.
class RatingsScreen extends StatefulWidget {
  const RatingsScreen({super.key, required this.id});
  final String id;
  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  String _sort = 'newest';
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.get('/events/${widget.id}/ratings', query: {'sort': _sort});
      if (mounted) setState(() => _d = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, titleSpacing: 0, title: Text('Ratings', style: KText.headingXSmall)),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Text(d['average'] == null ? '–' : '${d['average']}', style: KText.headingMedium),
                const SizedBox(width: 8),
                Text('(${plural(d['count'], 'review')})', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              ]),
              if (d['average'] != null) StarRow((d['average'] as num).toDouble(), size: 22),
              const SizedBox(height: 12),
              for (final b in List<Map<String, dynamic>>.from(d['breakdown']))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 20, child: Text('${b['stars']}')),
                    const Icon(PhosphorIconsFill.star, size: 16, color: Color(0xFFFFC21A)),
                    const SizedBox(width: 8),
                    Expanded(child: LinearProgressIndicator(value: d['count'] == 0 ? 0 : b['count'] / d['count'], minHeight: 8, color: const Color(0xFFFFC21A), backgroundColor: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(4))),
                    SizedBox(width: 36, child: Text('${b['count']}', textAlign: TextAlign.right)),
                  ]),
                ),
              const SizedBox(height: 16),
              Row(children: [
                Text('Reviews', style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                DropdownButton<String>(
                  value: _sort,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'newest', child: Text('Newest')),
                    DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                    DropdownMenuItem(value: 'highest', child: Text('Highest')),
                    DropdownMenuItem(value: 'lowest', child: Text('Lowest')),
                  ],
                  onChanged: (v) {
                    setState(() => _sort = v!);
                    _load();
                  },
                ),
              ]),
              for (final rv in List<Map<String, dynamic>>.from(d['reviews']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(rv['person']?['photoUrl'], size: 40),
                  title: Row(children: [Expanded(child: Text(rv['person']?['name'] ?? '')), StarRow((rv['stars'] as num).toDouble(), size: 14)]),
                  subtitle: Text([if ((rv['text'] ?? '').isNotEmpty) rv['text'], timeAgo(DateTime.parse(rv['createdAt']).toLocal())].join('\n')),
                ),
            ]),
    );
  }
}
