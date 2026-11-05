import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart' show plural;
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';
import '../verification/verification_screens.dart' show handleVerificationRequired;

/// An event card or page from the API.
class EventItem {
  EventItem(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get title => (json['title'] as String?)?.isNotEmpty == true ? json['title'] : 'Untitled event';
  String get category => json['category'] ?? 'residential';
  DateTime? get startAt => json['startAt'] == null ? null : DateTime.parse(json['startAt']).toLocal();
  DateTime? get endAt => json['endAt'] == null ? null : DateTime.parse(json['endAt']).toLocal();
  String? get format => json['format'];
  String? get locationName => json['locationName'];
  String? get platform => json['platform'];
  String? get coverUrl => json['cover']?['kind'] == 'photo' ? json['cover']['url'] : null;
  List<String> get tags => List<String>.from(json['tags'] ?? []);
  int get going => json['going'] ?? 0;
  int? get capacity => json['capacity'];
  bool get soldOut => json['soldOut'] == true;
  String get status => json['status'] ?? 'live';
  bool get saved => json['saved'] == true;
  bool get isDraft => status == 'draft';
  Map<String, dynamic>? get rating => json['rating'];
  String get where => format == 'online' ? (platform ?? 'Online') : (locationName ?? 'Location to be added');
}

String eventDay(DateTime d) => DateFormat('EEEE, d MMMM').format(d);
String eventShortDay(DateTime d) => DateFormat('EEE, d MMM').format(d);
String eventTime(DateTime d) => DateFormat('h:mma').format(d).toLowerCase();
String eventTimes(EventItem e) => e.startAt == null ? 'Date to be set' : '${eventTime(e.startAt!)} - ${e.endAt == null ? '' : eventTime(e.endAt!)}';

/// Teal date block on event covers; drafts show it in yellow (EVT-02.3).
class EventDateBlock extends StatelessWidget {
  const EventDateBlock(this.date, {super.key, this.draft = false});
  final DateTime? date;
  final bool draft;
  @override
  Widget build(BuildContext context) {
    final d = date;
    return Container(
      width: 50,
      height: 60,
      decoration: BoxDecoration(color: draft ? KColors.brand : KColors.selected, borderRadius: BorderRadius.circular(KRadius.sm)),
      alignment: Alignment.center,
      child: d == null
          ? Icon(PhosphorIconsRegular.calendarPlus, color: draft ? KColors.textPrimary : Colors.white)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${d.day}', style: KText.headingXSmall.copyWith(color: draft ? KColors.textPrimary : Colors.white, height: 1.1)),
              Text(DateFormat('MMM').format(d), style: KText.paragraphMediumSmall.copyWith(color: draft ? KColors.textPrimary : Colors.white)),
            ]),
    );
  }
}

class StarRow extends StatelessWidget {
  const StarRow(this.value, {super.key, this.size = 18});
  final double value;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '${value.toStringAsFixed(1)} out of 5 stars',
        child: ExcludeSemantics(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 1; i <= 5; i++)
              Icon(value >= i ? PhosphorIconsFill.star : value >= i - 0.5 ? PhosphorIconsFill.starHalf : PhosphorIconsRegular.star, size: size, color: const Color(0xFFFFC21A)),
          ]),
        ),
      );
}

/// Cover card used in lists (EVT-01.3 / EVT-02).
class EventCard extends StatelessWidget {
  const EventCard(this.e, {super.key, this.onTap, this.hosting = false, this.width});
  final EventItem e;
  final VoidCallback? onTap;
  final bool hosting;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cover = e.coverUrl;
    final r = e.rating;
    return Semantics(
      container: true,
      button: true,
      label: '${e.title}, ${e.startAt == null ? '' : eventShortDay(e.startAt!)}',
      child: SizedBox(
        width: width,
        child: Material(
          color: KColors.surfaceDefault,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md), side: const BorderSide(color: KColors.borderDefault)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap ?? () => context.push('/events/${e.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 144,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  cover == null
                      ? Container(color: KColors.surfaceSubtle, child: const Icon(PhosphorIconsRegular.calendarDots, size: 40, color: KColors.textTertiary))
                      : Image.network(context.api.absolute(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: KColors.surfaceSubtle)),
                  Positioned(left: 8, top: 8, child: EventDateBlock(e.startAt, draft: e.isDraft)),
                  if (e.status == 'cancelled' || e.soldOut)
                    Positioned(right: 8, top: 8, child: _Badge(e.status == 'cancelled' ? 'Cancelled' : 'Sold out', dark: true)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(e.title, style: KText.paragraphMediumLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const _Badge('Free'),
                  ]),
                  const SizedBox(height: 6),
                  _Line(PhosphorIconsRegular.clock, eventTimes(e)),
                  const SizedBox(height: 4),
                  _Line(e.format == 'online' ? PhosphorIconsRegular.videoCamera : PhosphorIconsRegular.mapPin, e.where),
                  const SizedBox(height: 8),
                  if (e.status == 'completed' && r != null && r['average'] != null)
                    Row(children: [
                      StarRow((r['average'] as num).toDouble()),
                      const SizedBox(width: 6),
                      Text('(${plural(r['count'] ?? 0, 'rating')})', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                    ])
                  else if (hosting)
                    Row(children: [
                      Text(e.isDraft ? 'Draft' : e.status == 'live' ? 'Launched' : e.status[0].toUpperCase() + e.status.substring(1),
                          style: KText.paragraphMediumSmall.copyWith(color: e.isDraft ? KColors.progressStart : KColors.success)),
                      const Spacer(),
                      Text(e.isDraft ? 'Edit event' : 'Manage event', style: KText.paragraphMediumSmall.copyWith(color: KColors.textLink)),
                    ])
                  else if (e.going > 0)
                    Text('+${e.going} going', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: KColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: KText.paragraphSmall.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]);
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.dark = false});
  final String text;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: dark ? Colors.black87 : KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
        child: Text(text, style: KText.paragraphMediumSmall.copyWith(color: dark ? Colors.white : KColors.textSecondary)),
      );
}

/// Compact row: date block, title, Free, time, place, going (EVT-01.3).
class EventRow extends StatelessWidget {
  const EventRow(this.e, {super.key});
  final EventItem e;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        label: e.title,
        child: InkWell(
          onTap: () => context.push('/events/${e.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(KRadius.sm),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(fit: StackFit.expand, children: [
                    e.coverUrl == null ? Container(color: KColors.surfaceSubtle) : Image.network(context.api.absolute(e.coverUrl!), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: KColors.surfaceSubtle)),
                    Positioned(left: 4, top: 4, child: Transform.scale(scale: 0.7, alignment: Alignment.topLeft, child: EventDateBlock(e.startAt))),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(e.title, style: KText.paragraphMediumLarge, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      Text('Free', style: KText.paragraphMediumSmall.copyWith(color: KColors.success)),
                    ]),
                    const SizedBox(height: 4),
                    _Line(PhosphorIconsRegular.clock, eventTimes(e)),
                    const SizedBox(height: 2),
                    _Line(e.format == 'online' ? PhosphorIconsRegular.videoCamera : PhosphorIconsRegular.mapPin, e.where),
                    if (e.going > 0) ...[const SizedBox(height: 4), Text('+${e.going} going', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// EVT-04: category sheet, then the eligibility check. Returns the chosen category and club list.
Future<({String category, List<Map<String, dynamic>> clubs})?> pickEventCategory(BuildContext context) async {
  final api = context.api;
  final pick = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const _CategorySheet());
  if (pick == null || !context.mounted) return null;
  try {
    final r = await api.get('/events/create-check', query: {'category': pick});
    if (!context.mounted) return null;
    if (r['ok'] == true) return (category: pick, clubs: List<Map<String, dynamic>>.from(r['clubs'] ?? []));
    final code = r['code'];
    final action = code == 'NOT_COMMITTEE' && r['boardFull'] != true ? 'Apply for membership' : code == 'NO_CLUB' ? 'Go to club' : code == 'VENDOR' ? 'Continue to vendor dashboard' : null;
    final go = await confirmSheet(context, title: switch (code) { 'NOT_COMMITTEE' => 'Committee members only', 'NO_CLUB' => 'Club owners and admins only', _ => 'Vendor events' }, body: r['message'], confirm: action ?? 'OK');
    if (go && context.mounted) {
      if (code == 'NOT_COMMITTEE' && action != null) context.push('/board');
      if (code == 'NO_CLUB') context.push('/clubs');
      if (code == 'VENDOR') showToast(context, 'Vendor Hub is not available in this version of Keys.');
    }
  } catch (e) {
    if (context.mounted && !handleVerificationRequired(context, e)) showToast(context, e is ApiException ? e.message : 'Something went wrong. Please try again.');
  }
  return null;
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet();
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String? _v;
  static const _opts = [
    ('residential', 'Residential', 'Perfect for casual neighbourhood events.', ['Host single-day gatherings']),
    ('administrative', 'Administrative', 'For community-led initiatives or causes.', ['Host single-day events']),
    ('club', 'Club', 'Great for hobby groups and social clubs.', ['Host single-day events']),
    ('vendor', 'Vendor', 'Ideal for markets, expos, and business events.', ['Set up in Vendor Hub']),
  ];
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(children: [
              Expanded(child: Text('Category', style: KText.headingXSmall)),
              IconButton(tooltip: 'Close', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),
          RadioGroup<String>(
            groupValue: _v,
            onChanged: (v) => setState(() => _v = v),
            child: Column(children: [
              for (final o in _opts)
                RadioListTile<String>(
                  value: o.$1,
                  activeColor: KColors.surfaceInverted,
                  title: Text(o.$2, style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text('${o.$3}\n${o.$4.map((x) => '•  $x').join('\n')}', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                  isThreeLine: true,
                ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: KeysButton('Next', onPressed: _v == null ? null : () => Navigator.pop(context, _v))),
        ]),
      );
}
