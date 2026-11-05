import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// One calendar item (CAL-01.1): colour, time, title, subtitle and what a tap opens.
class CalItem {
  CalItem(this.json);
  final Map<String, dynamic> json;
  String get type => json['type'];
  Color get color => Color(int.parse((json['color'] as String).substring(1), radix: 16) | 0xFF000000);
  String get title => json['title'] ?? '';
  String get subtitle => json['subtitle'] ?? '';
  DateTime get at => DateTime.parse(json['at']).toLocal();
  DateTime get day => DateTime(at.year, at.month, at.day);
  String get time => json['time'] ?? '';
  void open(BuildContext context) {
    final o = json['open'];
    context.push(o['type'] == 'event' ? '/events/${o['id']}' : '/updates/${o['id']}');
  }
}

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

/// CAL-03: month view with markers and the day's items. [eventsOnly] for Events Discover (CAL-01.3).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.eventsOnly = false});
  final bool eventsOnly;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _d(DateTime.now());
  List<CalItem> _items = [];
  bool _loading = true;

  String get _types => widget.eventsOnly ? 'event' : 'event,update';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = DateTime(_month.year, _month.month);
    final to = DateTime(_month.year, _month.month + 1);
    try {
      final r = await context.api.get('/calendar', query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String(), 'types': _types});
      if (mounted) {
        setState(() {
          _items = (r['items'] as List).map((e) => CalItem(Map<String, dynamic>.from(e))).toList();
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showToast(context, e.message);
      }
    }
  }

  void _go(DateTime month, [DateTime? select]) {
    setState(() {
      _month = DateTime(month.year, month.month);
      if (select != null) _selected = _d(select);
    });
    _load();
  }

  Future<void> _nearest() async {
    try {
      final r = await context.api.get('/calendar/nearest', query: {'from': _selected.add(const Duration(days: 1)).toUtc().toIso8601String(), 'types': _types});
      if (!mounted) return;
      if (r['item'] == null) return showToast(context, widget.eventsOnly ? 'No upcoming events' : 'No upcoming schedule');
      final at = CalItem(Map<String, dynamic>.from(r['item'])).at;
      _go(at, at);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = (first.weekday + 6) % 7; // Monday first
    final today = _d(DateTime.now());
    final byDay = <DateTime, List<CalItem>>{};
    for (final i in _items) {
      byDay.putIfAbsent(i.day, () => []).add(i);
    }
    final dayItems = byDay[_selected] ?? [];
    return Scaffold(
      backgroundColor: KColors.surfaceDefault,
      appBar: AppBar(
        backgroundColor: KColors.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => Navigator.of(context).maybePop()),
        title: Text(widget.eventsOnly ? 'Event calendar' : 'Calendar', style: KText.headingXSmall),
        actions: [TextButton(onPressed: () => _go(today, today), style: TextButton.styleFrom(foregroundColor: KColors.textPrimary), child: const Text('Today'))],
      ),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Row(children: [
          IconButton(tooltip: 'Previous month', icon: const Icon(PhosphorIconsRegular.caretLeft), onPressed: () => _go(DateTime(_month.year, _month.month - 1))),
          Expanded(child: Text(DateFormat('MMMM y').format(_month), textAlign: TextAlign.center, style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Next month', icon: const Icon(PhosphorIconsRegular.caretRight), onPressed: () => _go(DateTime(_month.year, _month.month + 1))),
        ]),
        Row(children: [
          for (final w in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
            Expanded(child: Text(w, textAlign: TextAlign.center, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.9,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox(),
            for (var d = 1; d <= days; d++)
              Builder(builder: (_) {
                final day = DateTime(_month.year, _month.month, d);
                final marks = byDay[day] ?? [];
                final sel = day == _selected;
                final isToday = day == today;
                return Semantics(
                  button: true,
                  selected: sel,
                  label: '${DateFormat('EEEE d MMMM').format(day)}${marks.isEmpty ? '' : ', ${marks.length} item${marks.length == 1 ? '' : 's'}'}',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _selected = day),
                    child: ExcludeSemantics(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sel ? KColors.surfaceInverted : null,
                            border: isToday && !sel ? Border.all(color: KColors.surfaceInverted) : null,
                          ),
                          child: Text('$d', style: KText.paragraphMedium.copyWith(color: sel ? Colors.white : null, fontWeight: isToday ? FontWeight.w600 : null)),
                        ),
                        const SizedBox(height: 2),
                        // CAL-03.1: up to 4 markers per day.
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (final m in marks.take(4)) Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: m.color, shape: BoxShape.circle)),
                        ]),
                      ]),
                    ),
                  ),
                );
              }),
          ],
        ),
        const Divider(height: 24),
        Text(DateFormat('EEEE, MMMM d').format(_selected), style: KText.paragraphMediumLarge.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (dayItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              Text(widget.eventsOnly ? 'No event yet' : 'No schedule yet', style: KText.headingXSmall),
              const SizedBox(height: 6),
              Text(widget.eventsOnly ? 'There are no events scheduled for this day.' : 'You have no schedule to display on this day. Please select another date.',
                  textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              const SizedBox(height: 16),
              SizedBox(width: 220, child: KeysButton(widget.eventsOnly ? 'Go to next event' : 'Go to nearest schedule', variant: ButtonVariant.outline, onPressed: _nearest)),
            ]),
          )
        else
          for (final i in dayItems) Padding(padding: const EdgeInsets.only(bottom: 10), child: CalendarCard(i)),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class CalendarCard extends StatelessWidget {
  const CalendarCard(this.i, {super.key, this.today = false});
  final CalItem i;
  final bool today;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        label: '${i.type == 'event' ? 'Event' : 'Update'}: ${i.title}, ${i.time}',
        child: Material(
          color: i.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(KRadius.md),
            onTap: () => i.open(context),
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                child: Row(children: [
                  Container(width: 4, height: 44, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: i.color, borderRadius: BorderRadius.circular(2))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(i.title, style: KText.paragraphMediumLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (today)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: KColors.brand, borderRadius: BorderRadius.circular(4)),
                            child: Text('today', style: KText.paragraphMediumSmall.copyWith(fontSize: 11)),
                          ),
                      ]),
                      const SizedBox(height: 2),
                      Text(i.type == 'event' ? i.subtitle : '${i.time} • ${i.subtitle}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// CAL-02: "Upcoming" on Home: the nearest day with items within 4 weeks; collapses when empty.
class UpcomingPreview extends StatefulWidget {
  const UpcomingPreview({super.key});
  @override
  State<UpcomingPreview> createState() => UpcomingPreviewState();
}

class UpcomingPreviewState extends State<UpcomingPreview> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = await context.api.get('/calendar/upcoming');
      if (mounted) setState(() => _d = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null || d['day'] == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Text('Upcoming', style: KText.headingXSmall),
          const Spacer(),
          TextButton(onPressed: () => context.push('/calendar'), style: TextButton.styleFrom(foregroundColor: KColors.textPrimary), child: const Text('Calendar →')),
        ]),
      );
    }
    final items = (d['items'] as List).map((e) => CalItem(Map<String, dynamic>.from(e))).toList();
    final today = d['today'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Upcoming', style: KText.headingXSmall),
          if (!today) ...[const SizedBox(width: 8), Text(DateFormat('EEE, d MMM').format(DateTime.parse(d['day'])), style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))],
          const Spacer(),
          TextButton(onPressed: () => context.push('/calendar'), style: TextButton.styleFrom(foregroundColor: KColors.textPrimary), child: const Text('Calendar →')),
        ]),
        for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: CalendarCard(i, today: today)),
        if ((d['more'] ?? 0) > 0)
          Text('+${d['more']} ${today ? 'today' : 'more'}', style: KText.paragraphSmall.copyWith(color: KColors.textLink)),
      ]),
    );
  }
}
