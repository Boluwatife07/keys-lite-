import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import '../updates/updates_list.dart' show SearchField;
import 'events_tab.dart' show kTagIcons;

const kEventTitleMax = 60;
const kEventDescriptionMax = 500;
const kEventMediaMax = 6;
const kEventTagsMax = 3;
const kEventCapacityMin = 10;
const kEventCohostsMax = 5;
const kEventVideoBytes = 100 * 1024 * 1024;
const kEventTags = ['Music', 'Culture', 'Networking', 'Food & Drink', 'Fashion', 'Education', 'Tech', 'Social', 'Others'];
const kPlatforms = {'zoom': 'Zoom', 'google_meet': 'Google meet', 'facebook_live': 'Facebook live', 'other': 'Other'};
const kCategoryNames = {'residential': 'Residential', 'administrative': 'Administrative', 'club': 'Club'};

class _Media {
  _Media({this.id, this.url, this.file, required this.kind});
  String? id;
  final String? url;
  final PickedFile? file;
  final String kind;
}

class _Guest {
  _Guest({required this.name, required this.title, this.photoId, this.photoUrl, this.photo});
  String name;
  String title;
  String? photoId;
  String? photoUrl;
  PickedFile? photo;
}

class _Cohost {
  _Cohost({this.person, this.external});
  final PersonRef? person;
  final String? external;
  String get name => person?.name ?? external!;
}

/// EVT-05 - EVT-13: create, edit a draft, or edit a live event.
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({super.key, this.category, this.clubs = const [], this.template, this.eventId, this.clubId});
  final String? category;
  final List<Map<String, dynamic>> clubs;
  final Map<String, dynamic>? template;
  /// Editing an existing draft or live event.
  final String? eventId;
  final String? clubId;
  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> with Busy {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _capacity = TextEditingController();
  final _link = TextEditingController();
  final _meetingId = TextEditingController();
  final _meetingPassword = TextEditingController();
  final _volunteers = TextEditingController();
  final List<_Media> _media = [];
  final List<_Guest> _lineup = [];
  final List<_Cohost> _cohosts = [];
  final Set<String> _tags = {};
  String _category = 'residential';
  String? _clubId;
  List<Map<String, dynamic>> _clubs = [];
  String _audience = 'all';
  DateTime? _start;
  DateTime? _end;
  String? _format;
  String? _placeId;
  String? _placeName;
  String? _platform;
  bool _acceptVolunteers = false;
  String? _id;
  String _status = 'draft';
  bool _loading = false;
  bool _dirty = false;
  String? _error;

  bool get _live => _status == 'live';

  @override
  void initState() {
    super.initState();
    _category = widget.category ?? 'residential';
    _clubs = widget.clubs;
    _clubId = widget.clubId ?? (widget.clubs.length == 1 ? widget.clubs.first['id'] : null);
    final t = widget.template;
    if (t != null) {
      _title.text = t['title'] ?? '';
      _description.text = t['description'] ?? '';
      _tags.addAll(List<String>.from(t['tags'] ?? []));
      if (t['capacity'] != null) _capacity.text = '${t['capacity']}';
      _format = t['format'];
      _platform = t['platform'];
      _acceptVolunteers = t['acceptVolunteers'] == true;
      if (t['volunteerCap'] != null) _volunteers.text = '${t['volunteerCap']}';
    }
    if (widget.eventId != null) _loadEvent();
    for (final c in [_title, _description, _capacity, _link, _meetingId, _meetingPassword, _volunteers]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  Future<void> _loadEvent() async {
    setState(() => _loading = true);
    try {
      final e = Map<String, dynamic>.from((await context.api.get('/events/${widget.eventId}'))['event']);
      if (!mounted) return;
      setState(() {
        _id = e['id'];
        _status = e['status'] == 'draft' ? 'draft' : 'live';
        _category = e['category'];
        _clubId = e['clubId'];
        if (_clubId != null) _clubs = [{'id': _clubId, 'name': e['clubName'] ?? 'Club'}];
        _audience = e['audience'] ?? 'all';
        _title.text = e['title'] ?? '';
        _description.text = e['description'] ?? '';
        for (final m in List<Map<String, dynamic>>.from(e['media'] ?? [])) {
          _media.add(_Media(id: m['id'], url: m['url'], kind: m['kind']));
        }
        _start = e['startAt'] == null ? null : DateTime.parse(e['startAt']).toLocal();
        _end = e['endAt'] == null ? null : DateTime.parse(e['endAt']).toLocal();
        _format = e['format'];
        _placeId = e['placeId'];
        _placeName = e['locationName'];
        _platform = e['platformKey'];
        _link.text = e['link'] ?? '';
        _meetingId.text = e['meetingId'] ?? '';
        _meetingPassword.text = e['meetingPassword'] ?? '';
        _tags.addAll(List<String>.from(e['tags'] ?? []));
        if (e['capacity'] != null) _capacity.text = '${e['capacity']}';
        for (final g in List<Map<String, dynamic>>.from(e['lineup'] ?? [])) {
          _lineup.add(_Guest(name: g['name'], title: g['title'] ?? '', photoId: g['photoMediaId'], photoUrl: g['photoUrl']));
        }
        for (final h in List<Map<String, dynamic>>.from(e['hosts'] ?? [])) {
          if (h['role'] != 'Co-host') continue;
          _cohosts.add(h['external'] == true ? _Cohost(external: h['name']) : _Cohost(person: PersonRef(Map<String, dynamic>.from(h['person']))));
        }
        _acceptVolunteers = e['acceptVolunteers'] == true;
        if (e['volunteerCap'] != null) _volunteers.text = '${e['volunteerCap']}';
        _loading = false;
        _dirty = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        showToast(context, e.message);
        context.pop();
      }
    }
  }

  void _touch(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  bool get _complete =>
      _title.text.trim().isNotEmpty &&
      _description.text.trim().isNotEmpty &&
      _media.isNotEmpty &&
      _start != null &&
      _end != null &&
      _end!.isAfter(_start!) &&
      _format != null &&
      (_format == 'physical' ? _placeId != null : _platform != null && _link.text.trim().isNotEmpty) &&
      _tags.isNotEmpty &&
      (!_acceptVolunteers || (int.tryParse(_volunteers.text) ?? 0) >= 1) &&
      (_category != 'club' || _clubId != null);

  String? _capacityProblem() {
    final t = _capacity.text.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n < kEventCapacityMin) return 'Minimum of $kEventCapacityMin';
    return null;
  }

  Future<void> _addMedia() async {
    if (_media.length >= kEventMediaMax) return setState(() => _error = 'You may upload a maximum of $kEventMediaMax media files');
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(PhosphorIconsRegular.image), title: const Text('Photo'), onTap: () => Navigator.pop(c, 'photo')),
          ListTile(leading: const Icon(PhosphorIconsRegular.videoCamera), title: const Text('Video'), onTap: () => Navigator.pop(c, 'video')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final media = context.deps.media;
    if (choice == 'photo') {
      final f = await media.pickPhoto();
      if (f == null) return;
      final p = photoProblem(f);
      if (p != null) return setState(() => _error = p);
      _touch(() {
        _media.add(_Media(file: f, kind: 'photo'));
        _error = null;
      });
    } else {
      final f = await media.pickVideo();
      if (f == null || !mounted) return;
      if (f.size > kEventVideoBytes) return setState(() => _error = 'The video you selected is too large. Please choose a video of 100 MB or less.');
      final len = await context.deps.videoLength?.call(f);
      if (len != null && len.inMilliseconds > 60500) return setState(() => _error = 'Videos can be up to 60 seconds long. Please trim your video.');
      _touch(() {
        _media.add(_Media(file: f, kind: 'video'));
        _error = null;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _start ?? now.add(const Duration(days: 1)), firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 730)));
    if (d == null) return;
    // EVT-07.2: single-day events; the end follows the start date.
    _touch(() {
      final st = _start ?? DateTime(d.year, d.month, d.day, 12);
      _start = DateTime(d.year, d.month, d.day, st.hour, st.minute);
      final en = _end ?? _start!.add(const Duration(hours: 2));
      _end = DateTime(d.year, d.month, d.day, en.hour, en.minute);
    });
  }

  Future<void> _pickTime(bool start) async {
    final base = (start ? _start : _end) ?? DateTime.now().add(const Duration(days: 1));
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base), helpText: start ? 'Choose when the event starts.' : 'Choose when the event ends.');
    if (t == null) return;
    _touch(() {
      final day = _start ?? base;
      final v = DateTime(day.year, day.month, day.day, t.hour, t.minute);
      if (start) {
        _start = v;
        _end ??= v.add(const Duration(hours: 2));
      } else {
        _end = v;
        _start ??= v.subtract(const Duration(hours: 2));
      }
    });
  }

  Future<void> _pickLocation() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _LocationSheet());
    if (r != null) {
      _touch(() {
        _placeId = r['placeId'];
        _placeName = r['primary'];
      });
    }
  }

  Future<void> _editGuest([int? i]) async {
    final g = await showModalBottomSheet<_Guest>(context: context, isScrollControlled: true, builder: (_) => _GuestSheet(guest: i == null ? null : _lineup[i]));
    if (g == null) return;
    _touch(() => i == null ? _lineup.add(g) : _lineup[i] = g);
  }

  Future<void> _addCohosts() async {
    final r = await Navigator.of(context).push<List<_Cohost>>(MaterialPageRoute(builder: (_) => _CohostPicker(initial: _cohosts)));
    if (r != null) {
      _touch(() {
        _cohosts
          ..clear()
          ..addAll(r);
      });
    }
  }

  Future<Map<String, dynamic>> _body() async {
    final api = context.api;
    for (final m in _media) {
      m.id ??= (await api.upload('/media', bytes: m.file!.bytes, filename: m.file!.name, mime: m.file!.mime, query: {'kind': m.kind}))['id'];
    }
    for (final g in _lineup) {
      if (g.photo != null && g.photoId == null) g.photoId = (await api.upload('/media', bytes: g.photo!.bytes, filename: g.photo!.name, mime: g.photo!.mime, query: {'kind': 'photo'}))['id'];
    }
    return {
      'category': _category,
      if (_category == 'club') 'clubId': _clubId,
      'audience': _category == 'club' ? _audience : 'all',
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'mediaIds': _media.map((m) => m.id).toList(),
      'startAt': _start?.toUtc().toIso8601String(),
      'endAt': _end?.toUtc().toIso8601String(),
      'format': _format,
      'placeId': _format == 'physical' ? _placeId : null,
      'platform': _format == 'online' ? _platform : null,
      'link': _format == 'online' && _link.text.trim().isNotEmpty ? _link.text.trim() : null,
      'meetingId': _platform == 'zoom' && _meetingId.text.trim().isNotEmpty ? _meetingId.text.trim() : null,
      'meetingPassword': _platform == 'zoom' && _meetingPassword.text.trim().isNotEmpty ? _meetingPassword.text.trim() : null,
      'tags': _tags.toList(),
      'capacity': _capacity.text.trim().isEmpty ? null : int.tryParse(_capacity.text.trim()),
      'lineup': [for (final g in _lineup) {'name': g.name, 'title': g.title, 'photoMediaId': g.photoId}],
      'cohostIds': [for (final c in _cohosts) if (c.person != null) c.person!.id],
      'externalCohosts': [for (final c in _cohosts) if (c.external != null) c.external],
      'acceptVolunteers': _acceptVolunteers,
      'volunteerCap': _acceptVolunteers ? int.tryParse(_volunteers.text.trim()) : null,
    };
  }

  /// Saves (creating the draft the first time). Returns the saved event.
  Future<Map<String, dynamic>?> _save() async {
    if (_capacityProblem() != null) {
      setState(() => _error = _capacityProblem());
      return null;
    }
    final api = context.api;
    return run(() async {
      final body = await _body();
      final r = _id == null ? await api.post('/events', body) : await api.patch('/events/$_id', body);
      final e = Map<String, dynamic>.from(r['event']);
      setState(() {
        _id = e['id'];
        _dirty = false;
        _error = null;
      });
      return {...r, 'event': e};
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong. Please try again.'));
  }

  Future<void> _saveDraft() async {
    final r = await _save();
    if (r == null || !mounted) return;
    final e = r['event'];
    if (_live) {
      showToast(context, r['message'] ?? 'Event updated!');
      context.pop(true);
      return;
    }
    // EVT-12.1
    final go = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 32, backgroundColor: KColors.brandSubtle, child: Icon(PhosphorIconsFill.bookmarkSimple, size: 32, color: KColors.textPrimary)),
            const SizedBox(height: 12),
            Text('Event saved as a draft', style: KText.headingSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('You can now plan with your team in the group chat and make any changes until your event is ready to go live.', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 20),
            KeysButton('Preview event', onPressed: () => Navigator.pop(c, 'preview')),
            const SizedBox(height: 8),
            if (e['chatId'] != null) ...[KeysButton('Enter group chat', variant: ButtonVariant.outline, onPressed: () => Navigator.pop(c, 'chat')), const SizedBox(height: 8)],
            KeysButton('View saved event', variant: ButtonVariant.ghost, onPressed: () => Navigator.pop(c, 'view')),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (go == 'preview' || go == 'view') context.pushReplacement('/events/${e['id']}');
    if (go == 'chat') context.pushReplacement('/chats/${e['chatId']}');
  }

  Future<void> _launch() async {
    final r = await _save();
    if (r == null || !mounted) return;
    final id = r['event']['id'];
    final ok = await launchEvent(context, id);
    if (ok && mounted) context.pop(true);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_live ? 'Unsaved changes' : 'Discard event', style: KText.headingSmall),
          const SizedBox(height: 8),
          Text('There are unsaved changes for this event. You can either save it to apply the updates or discard the changes.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: KeysButton('Discard', variant: ButtonVariant.secondary, onPressed: () => Navigator.pop(c, 'discard'))),
            const SizedBox(width: 12),
            Expanded(child: KeysButton('Save', onPressed: () => Navigator.pop(c, 'save'))),
          ]),
        ]),
      ),
    );
    if (r == 'save') {
      final s = await _save();
      return s != null;
    }
    return r == 'discard';
  }

  Widget _label(String text, {bool required = false, String? counter}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(children: [
          Text(text, style: KText.paragraphMediumLarge),
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

  Widget _locked(String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
        child: Row(children: [
          Expanded(child: Text(value, style: KText.paragraphLarge.copyWith(color: KColors.textTertiary))),
          const Icon(PhosphorIconsRegular.lock, size: 18, color: KColors.textTertiary),
        ]),
      );

  Widget _picker(String text, VoidCallback? onTap, {bool hint = false}) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
            child: Text(text, style: KText.paragraphMedium.copyWith(color: hint || onTap == null ? KColors.textTertiary : KColors.textPrimary)),
          ),
        ),
      );

  Widget _addButton(String label, VoidCallback? onTap) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(PhosphorIconsRegular.plus, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(foregroundColor: KColors.textPrimary, side: const BorderSide(color: KColors.borderDefault), shape: const StadiumBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final df = DateFormat('EEE, d MMM y');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => Navigator.of(context).maybePop()),
          title: Text(_id == null ? 'Create event' : 'Edit event', style: KText.headingXSmall),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          _label('Event title', required: true, counter: '${_title.text.length}/$kEventTitleMax'),
          _live
              ? _locked(_title.text)
              : TextField(controller: _title, maxLength: kEventTitleMax, decoration: _box('Enter event title'), style: KText.paragraphLarge),
          _label('Description', required: true, counter: '${_description.text.length}/$kEventDescriptionMax'),
          TextField(
            controller: _description,
            maxLength: kEventDescriptionMax,
            minLines: 3,
            maxLines: 8,
            style: KText.paragraphLarge,
            decoration: _box('What is your event about and what should attendeees expect?'),
          ),
          _label('Event gallery', required: true),
          if (_media.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _media.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = _media[i];
                  return Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(KRadius.sm),
                      child: m.kind == 'video'
                          ? Container(width: 80, height: 80, color: Colors.black87, child: const Icon(PhosphorIconsFill.videoCamera, color: Colors.white))
                          : m.file != null
                              ? Image.memory(m.file!.bytes, width: 80, height: 80, fit: BoxFit.cover)
                              : Image.network(context.api.absolute(m.url!), width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 80, color: KColors.surfaceSubtle)),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Semantics(
                        button: true,
                        label: 'Remove media ${i + 1}',
                        child: InkWell(
                          onTap: () => _touch(() => _media.removeAt(i)),
                          child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(2), child: const Icon(PhosphorIconsRegular.x, size: 14, color: Colors.white)),
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          const SizedBox(height: 8),
          _addButton('Add media', _media.length < kEventMediaMax ? _addMedia : null),
          const SizedBox(height: 4),
          Text('You may upload a maximum of 6 media files (.jpg, .png, .mp4), with videos limited to 60 seconds.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          _label('Category'),
          _locked(kCategoryNames[_category] ?? _category),
          if (_category == 'club') ...[
            _label('Select your club', required: true),
            _live || _id != null
                ? _locked(_clubs.firstWhere((c) => c['id'] == _clubId, orElse: () => {'name': 'Club'})['name'])
                : DropdownButtonFormField<String>(
                    initialValue: _clubId,
                    decoration: _box('Select your club'),
                    items: [for (final c in _clubs) DropdownMenuItem(value: c['id'] as String, child: Text(c['name']))],
                    onChanged: (v) => _touch(() => _clubId = v),
                  ),
          ],
          _label('Audience', required: true),
          if (_category != 'club')
            _locked('Everyone in this community')
          else if (_live)
            _locked(_audience == 'all' ? 'Everyone in this community' : 'Members only')
          else
            DropdownButtonFormField<String>(
              initialValue: _audience,
              decoration: _box('Audience'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Everyone in this community')),
                DropdownMenuItem(value: 'members', child: Text('Members only')),
              ],
              onChanged: (v) => _touch(() => _audience = v!),
            ),
          _label('Set date and time', required: true),
          Row(children: [
            SizedBox(width: 96, child: Text('Starting on', style: KText.paragraphMedium)),
            _picker(_start == null ? 'Date' : df.format(_start!), _live ? null : _pickDate, hint: _start == null),
            const SizedBox(width: 8),
            _picker(_start == null ? 'Time' : DateFormat('h:mm a').format(_start!).toLowerCase(), _live ? null : () => _pickTime(true), hint: _start == null),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 96, child: Text('Ending on', style: KText.paragraphMedium)),
            _picker(_end == null ? 'Date' : df.format(_end!), null, hint: _end == null),
            const SizedBox(width: 8),
            _picker(_end == null ? 'Time' : DateFormat('h:mm a').format(_end!).toLowerCase(), _live ? null : () => _pickTime(false), hint: _end == null),
          ]),
          if (_start != null && _end != null && !_end!.isAfter(_start!)) Padding(padding: const EdgeInsets.only(top: 6), child: ErrorLine('The end must be after the start')),
          _label('Event type', required: true),
          _live
              ? _locked(_format == 'online' ? 'Online' : 'Physical')
              : DropdownButtonFormField<String>(
                  initialValue: _format,
                  decoration: _box('Is this a physical or online event?'),
                  items: const [
                    DropdownMenuItem(value: 'physical', child: Text('Physical')),
                    DropdownMenuItem(value: 'online', child: Text('Online')),
                  ],
                  onChanged: (v) => _touch(() => _format = v),
                ),
          if (_format == 'physical') ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
                child: Row(children: [
                  const Icon(PhosphorIconsRegular.mapPin, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_placeName ?? 'Enter location of your event', style: KText.paragraphLarge.copyWith(color: _placeName == null ? KColors.textTertiary : null))),
                ]),
              ),
            ),
          ],
          if (_format == 'online') ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _platform,
              decoration: _box('Select event platform'),
              items: [for (final e in kPlatforms.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => _touch(() => _platform = v),
            ),
            const SizedBox(height: 8),
            TextField(controller: _link, keyboardType: TextInputType.url, decoration: _box('Add link to event')),
            if (_platform == 'zoom') ...[
              const SizedBox(height: 8),
              TextField(controller: _meetingId, decoration: _box('Meeting ID')),
              const SizedBox(height: 8),
              TextField(controller: _meetingPassword, decoration: _box('Password')),
            ],
          ],
          _label('Tags', required: true),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in kEventTags)
              FilterChip(
                avatar: Icon(kTagIcons[t], size: 16),
                label: Text(t == 'Tech' ? 'Technology' : t == 'Others' ? 'Other' : t),
                selected: _tags.contains(t),
                showCheckmark: false,
                selectedColor: KColors.surfaceInverted,
                labelStyle: KText.paragraphMedium.copyWith(color: _tags.contains(t) ? Colors.white : KColors.textPrimary),
                onSelected: (on) {
                  if (on && _tags.length >= kEventTagsMax) return showToast(context, 'You can add a maximum of 3 tags');
                  _touch(() => on ? _tags.add(t) : _tags.remove(t));
                },
              ),
          ]),
          _label('Event capacity'),
          TextField(controller: _capacity, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: _box('How many people can attend?')),
          const SizedBox(height: 4),
          Text(_capacityProblem() ?? 'Minimum of 10. Leave blank for unlimited', style: KText.paragraphSmall.copyWith(color: _capacityProblem() != null ? KColors.error : KColors.textSecondary)),
          _label('Lineup'),
          for (var i = 0; i < _lineup.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: KColors.surfaceSubtle,
                backgroundImage: _lineup[i].photo != null ? MemoryImage(_lineup[i].photo!.bytes) : _lineup[i].photoUrl != null ? NetworkImage(context.api.absolute(_lineup[i].photoUrl!)) as ImageProvider : null,
                child: _lineup[i].photo == null && _lineup[i].photoUrl == null ? const Icon(PhosphorIconsRegular.user) : null,
              ),
              title: Text(_lineup[i].name),
              subtitle: _lineup[i].title.isEmpty ? null : Text(_lineup[i].title),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(onPressed: () => _editGuest(i), child: const Text('Edit guest')),
                IconButton(tooltip: 'Remove ${_lineup[i].name}', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => _touch(() => _lineup.removeAt(i))),
              ]),
            ),
          _addButton('Add guest', () => _editGuest()),
          const SizedBox(height: 4),
          Text('Highlight your lineup of special guests', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          _label('Co-hosts'),
          if (_cohosts.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _cohosts)
                InputChip(
                  avatar: c.person != null ? Avatar(c.person!.photoUrl, size: 24) : const Icon(PhosphorIconsRegular.buildings, size: 18),
                  label: Text(c.external != null ? '${c.name} (External)' : c.name),
                  onDeleted: () => _touch(() => _cohosts.remove(c)),
                  deleteButtonTooltipMessage: 'Remove ${c.name}',
                ),
            ]),
          const SizedBox(height: 8),
          _addButton('Add co-host', _addCohosts),
          const SizedBox(height: 4),
          Text('You can add up to $kEventCohostsMax members of the community', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Accept volunteers', style: KText.paragraphMediumLarge),
            value: _acceptVolunteers,
            activeTrackColor: KColors.surfaceInverted,
            onChanged: (v) => _touch(() => _acceptVolunteers = v),
          ),
          if (_acceptVolunteers) ...[
            TextField(controller: _volunteers, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: _box('Number of volunteers')),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: ErrorLine(_error!)),
          const SizedBox(height: 24),
          if (_live)
            KeysButton('Save changes', loading: busy, onPressed: _dirty ? _saveDraft : null)
          else ...[
            KeysButton('Launch event', loading: busy, onPressed: _complete ? _launch : null),
            const SizedBox(height: 8),
            KeysButton('Save event', variant: ButtonVariant.secondary, onPressed: busy || _title.text.trim().isEmpty ? null : _saveDraft),
          ],
        ]),
      ),
    );
  }
}

/// EVT-12.3 / EVT-12.4 / EVT-11.4: launch confirmation and "Your event is live!".
Future<bool> launchEvent(BuildContext context, String id) async {
  final api = context.api;
  final router = GoRouter.of(context);
  final saveTemplate = await showModalBottomSheet<bool>(context: context, builder: (_) => const _LaunchSheet());
  if (saveTemplate == null || !context.mounted) return false;
  try {
    final r = await api.post('/events/$id/launch', {'saveAsTemplate': saveTemplate});
    if (!context.mounted) return true;
    final chatId = r['event']['chatId'];
    final go = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 32, backgroundColor: Color(0xFFE6F6EA), child: Icon(PhosphorIconsRegular.confetti, size: 32, color: KColors.success)),
            const SizedBox(height: 12),
            Text(r['title'] ?? 'Your event is live!', style: KText.headingSmall),
            const SizedBox(height: 8),
            Text(r['message'] ?? '', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 20),
            KeysButton('View event', onPressed: () => Navigator.pop(c, 'view')),
            if (chatId != null) ...[const SizedBox(height: 8), KeysButton('Enter group chat', variant: ButtonVariant.outline, onPressed: () => Navigator.pop(c, 'chat'))],
          ]),
        ),
      ),
    );
    if (go == 'view') router.push('/events/$id');
    if (go == 'chat') router.push('/chats/$chatId');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
    return false;
  }
}

class _LaunchSheet extends StatefulWidget {
  const _LaunchSheet();
  @override
  State<_LaunchSheet> createState() => _LaunchSheetState();
}

class _LaunchSheetState extends State<_LaunchSheet> {
  bool _template = false;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Launch event', style: KText.headingSmall),
            const SizedBox(height: 8),
            Text("Your event becomes visible to your audience and they will be able to get tickets after it is launched. You won't be able to make certain changes after launch.",
                style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: KColors.surfaceInverted,
              value: _template,
              onChanged: (v) => setState(() => _template = v == true),
              title: Text('Save event as template', style: KText.paragraphMedium),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: KeysButton('Cancel', variant: ButtonVariant.secondary, onPressed: () => Navigator.pop(context))),
              const SizedBox(width: 12),
              Expanded(child: KeysButton('Launch', onPressed: () => Navigator.pop(context, _template))),
            ]),
          ]),
        ),
      );
}

/// EVT-07.3: address search with suggestions.
class _LocationSheet extends StatefulWidget {
  const _LocationSheet();
  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      setState(() {});
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), () async {
        final q = _q.text.trim();
        if (q.isEmpty) return setState(() => _results = []);
        try {
          final r = await context.api.get('/addresses/autocomplete', query: {'q': q});
          if (mounted) setState(() => _results = List<Map<String, dynamic>>.from(r['suggestions']));
        } catch (_) {}
      });
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom),
          child: Column(children: [
            Text('Location', style: KText.headingXSmall),
            const SizedBox(height: 12),
            SearchField(controller: _q, hint: 'Enter location of your event', autofocus: true),
            Expanded(
              child: ListView(children: [
                for (final s in _results)
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.mapPin),
                    title: Text(s['primary'] ?? ''),
                    subtitle: Text(s['secondary'] ?? ''),
                    onTap: () => Navigator.pop(context, s),
                  ),
              ]),
            ),
          ]),
        ),
      );
}

/// EVT-08.1: guest picture, name and title.
class _GuestSheet extends StatefulWidget {
  const _GuestSheet({this.guest});
  final _Guest? guest;
  @override
  State<_GuestSheet> createState() => _GuestSheetState();
}

class _GuestSheetState extends State<_GuestSheet> {
  late final _name = TextEditingController(text: widget.guest?.name ?? '');
  late final _title = TextEditingController(text: widget.guest?.title ?? '');
  PickedFile? _photo;
  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guest;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(g == null ? 'Add guest' : 'Edit guest', style: KText.headingSmall),
        const SizedBox(height: 16),
        Center(
          child: Semantics(
            button: true,
            label: 'Add guest picture',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                final f = await context.deps.media.pickPhoto();
                if (f == null || !context.mounted) return;
                final p = photoProblem(f);
                if (p != null) return showToast(context, p);
                setState(() => _photo = f);
              },
              child: CircleAvatar(
                radius: 40,
                backgroundColor: KColors.surfaceSubtle,
                backgroundImage: _photo != null ? MemoryImage(_photo!.bytes) : g?.photoUrl != null ? NetworkImage(context.api.absolute(g!.photoUrl!)) as ImageProvider : null,
                child: _photo == null && g?.photoUrl == null ? const Icon(PhosphorIconsRegular.camera) : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        KeysTextField(label: 'Guest name', controller: _name, maxLength: 60),
        const SizedBox(height: 8),
        KeysTextField(label: 'Guest title', controller: _title, maxLength: 60, hint: 'For example, CEO, Bryin & Co.'),
        const SizedBox(height: 16),
        KeysButton(g == null ? 'Add' : 'Save', onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _Guest(name: _name.text.trim(), title: _title.text.trim(), photo: _photo ?? g?.photo, photoId: _photo != null ? null : g?.photoId, photoUrl: _photo != null ? null : g?.photoUrl))),
      ]),
    );
  }
}

/// EVT-09: residents (search, up to 5) and external co-hosts.
class _CohostPicker extends StatefulWidget {
  const _CohostPicker({required this.initial});
  final List<_Cohost> initial;
  @override
  State<_CohostPicker> createState() => _CohostPickerState();
}

class _CohostPickerState extends State<_CohostPicker> {
  late final List<_Cohost> _picked = [...widget.initial];
  final _q = TextEditingController();
  List<PersonRef> _people = [];
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
      final r = await context.api.get('/chats/people', query: {'q': _q.text.trim()});
      if (mounted) setState(() => _people = (r['people'] as List).map((e) => PersonRef(Map<String, dynamic>.from(e))).toList());
    } catch (_) {}
  }

  bool _has(PersonRef p) => _picked.any((c) => c.person?.id == p.id);

  void _toggle(PersonRef p) {
    if (_has(p)) return setState(() => _picked.removeWhere((c) => c.person?.id == p.id));
    if (_picked.length >= kEventCohostsMax) return showToast(context, 'You can add up to $kEventCohostsMax members of the community');
    setState(() => _picked.add(_Cohost(person: p)));
  }

  Future<void> _external() async {
    if (_picked.length >= kEventCohostsMax) return showToast(context, 'You can add up to $kEventCohostsMax co-hosts');
    final c = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add external co-host', style: KText.headingSmall),
          const SizedBox(height: 4),
          Text('Add users or organizations not on KEYS.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 16),
          KeysTextField(controller: c, hint: 'Host name', maxLength: 60, autofocus: true),
          const SizedBox(height: 16),
          KeysButton('Add', onPressed: () => Navigator.pop(s, c.text.trim())),
        ]),
      ),
    );
    if (name != null && name.isNotEmpty) setState(() => _picked.add(_Cohost(external: name)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add co-host', style: KText.headingXSmall),
            Text('${_picked.length}/$kEventCohostsMax selected', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          ]),
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SearchField(controller: _q, hint: 'Search residents')),
          ListTile(
            leading: const CircleAvatar(backgroundColor: KColors.surfaceSubtle, child: Icon(PhosphorIconsRegular.buildings, color: KColors.textPrimary)),
            title: const Text('Add external co-hosts'),
            subtitle: const Text('Add users or organizations not on KEYS.'),
            onTap: _external,
          ),
          for (final c in _picked.where((c) => c.external != null))
            ListTile(
              leading: const Icon(PhosphorIconsRegular.buildings),
              title: Text(c.external!),
              subtitle: const Text('External • This co-host is not on Keys.'),
              trailing: IconButton(tooltip: 'Remove ${c.external}', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => setState(() => _picked.remove(c))),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView(children: [
              for (final p in _people)
                CheckboxListTile(
                  value: _has(p),
                  activeColor: KColors.surfaceInverted,
                  secondary: Avatar(p.photoUrl, size: 40),
                  title: Text(p.name),
                  subtitle: p.role == null ? null : Text(p.role!),
                  onChanged: (_) => _toggle(p),
                ),
            ]),
          ),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: KeysButton('Done', onPressed: () => Navigator.pop(context, _picked)))),
      );
}
