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
    final lead = first.weekday % 7; // Figma: weeks start on Sunday
    final today = _d(DateTime.now());
    final byDay = <DateTime, List<CalItem>>{};
    for (final i in _items) {
      byDay.putIfAbsent(i.day, () => []).add(i);
    }
    final dayItems = byDay[_selected] ?? [];
    final rows = ((lead + days) / 7).ceil();
    Widget cell(int d) {
      final day = DateTime(_month.year, _month.month, d);
      final marks = byDay[day] ?? [];
      // One line per item colour, at most 4.
      final colors = {for (final m in marks) m.color}.take(4).toList();
      final sel = day == _selected;
      final isToday = day == today;
      return Semantics(
        button: true,
        selected: sel,
        label: '${DateFormat('EEEE d MMMM').format(day)}${marks.isEmpty ? '' : ', ${marks.length} item${marks.length == 1 ? '' : 's'}'}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = day),
          child: ExcludeSemantics(
            // Figma: selected day is a 44x48 yellow-outlined box; today is a
            // 38x24 yellow fill behind the number; items are 2pt lines.
            child: Center(
              child: Container(
                width: 44,
                height: 48,
                decoration: sel ? BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: KColors.brand, width: 1.5)) : null,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 38,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: isToday ? BoxDecoration(color: KColors.brand, borderRadius: BorderRadius.circular(6)) : null,
                    child: Text('$d', style: KText.paragraphMedium.copyWith(color: isToday ? KColors.staticBlack : null)),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 12,
                    child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
                      for (final c in colors) Container(width: 38, height: 2, margin: const EdgeInsets.only(bottom: 1), color: c),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: KColors.surfaceSubtle,
      appBar: PageHeader(widget.eventsOnly ? 'Event calendar' : 'Calendar'),
      body: ListView(padding: EdgeInsets.zero, children: [
        // Figma 3430:176484: white month panel with 20pt rounded bottom corners.
        Container(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 16),
          decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
              child: Row(children: [
                Expanded(child: Text(DateFormat('MMMM, y').format(_month), style: KText.paragraphLarge.copyWith(fontSize: 18, fontWeight: FontWeight.w600))),
                IconButton(tooltip: 'Previous month', visualDensity: VisualDensity.compact, icon: Icon(PhosphorIconsRegular.caretLeft, size: 20, color: KColors.iconDefault), onPressed: () => _go(DateTime(_month.year, _month.month - 1))),
                Semantics(
                  button: true,
                  child: InkWell(onTap: () => _go(today, today), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Text('Today', style: KText.paragraphMedium))),
                ),
                IconButton(tooltip: 'Next month', visualDensity: VisualDensity.compact, icon: Icon(PhosphorIconsRegular.caretRight, size: 20, color: KColors.iconDefault), onPressed: () => _go(DateTime(_month.year, _month.month + 1))),
              ]),
            ),
            Row(children: [
              for (final w in ['SUN', 'MON', 'TUE', 'WED', 'THUR', 'FRI', 'SAT'])
                Expanded(child: Text(w, textAlign: TextAlign.center, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
            ]),
            const SizedBox(height: 8),
            for (var r = 0; r < rows; r++)
              SizedBox(
                height: 50,
                child: Row(children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(child: () {
                      final d = r * 7 + c - lead + 1;
                      return d < 1 || d > days ? const SizedBox() : cell(d);
                    }()),
                ]),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
          child: Text(DateFormat('EEEE, MMMM d').format(_selected), style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w600)),
        ),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (dayItems.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
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
          for (final i in dayItems) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: _DayCard(i)),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Figma calendar card: white, 12pt corners, 6pt colour bar on the left,
/// type label with icon, title, grey subtitle, time chip.
class _DayCard extends StatelessWidget {
  const _DayCard(this.i);
  final CalItem i;

  static const _types = <String, (String, IconData)>{
    'event': ('Event', PhosphorIconsRegular.calendarBlank),
    'update': ('Update', PhosphorIconsRegular.megaphoneSimple),
    'post': ('Scheduled post', PhosphorIconsRegular.mailbox),
    'live': ('LIVE', PhosphorIconsRegular.broadcast),
    'service': ('Services', PhosphorIconsRegular.briefcase),
  };

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _types[i.type] ?? ('Event', PhosphorIconsRegular.calendarBlank);
    final sub = i.type == 'event' ? i.subtitle.split(' • ').skip(1).join(' • ') : i.subtitle;
    final timeText = i.type == 'event' ? i.subtitle.split(' • ').first : i.time;
    return Semantics(
      container: true,
      button: true,
      label: '$label: ${i.title}, ${i.time}',
      child: Material(
        color: KColors.surfaceDefault,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: KColors.borderDefault)),
        child: InkWell(
          onTap: () => i.open(context),
          child: ExcludeSemantics(
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 6, color: i.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(icon, size: 14, color: KColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(label, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                      ]),
                      const SizedBox(height: 8),
                      Text(i.title, style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (sub.isNotEmpty) Text(sub, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.pill)),
                        child: Text(timeText, style: KText.paragraphSmall),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
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
                            child: Text('today', style: KText.paragraphMediumSmall.copyWith(fontSize: 11, color: KColors.staticBlack)),
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
