import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../onboarding/profile_screens.dart' show photoProblem;
import 'updates_list.dart' show SearchField;

const kUpdateTitleMax = 100;
const kUpdateDetailsMax = 700;
const kUpdateImagesMax = 10;
const kUpdateDocBytes = 25 * 1024 * 1024;

/// An image on the form: already uploaded (editing) or picked now.
class _Img {
  _Img.remote(this.id, this.url) : file = null;
  _Img.local(this.file)
      : id = null,
        url = null;
  final String? id;
  final String? url;
  final PickedFile? file;
}

/// UPD-02 - UPD-04 and UPD-11: create or edit an update (committee only).
class UpdateFormScreen extends StatefulWidget {
  const UpdateFormScreen({super.key, this.edit});
  final Map<String, dynamic>? edit;
  @override
  State<UpdateFormScreen> createState() => _UpdateFormScreenState();
}

class _UpdateFormScreenState extends State<UpdateFormScreen> with Busy {
  late final _title = TextEditingController(text: widget.edit?['title'] ?? '');
  late final _details = TextEditingController(text: widget.edit?['details'] ?? '');
  final List<_Img> _images = [];
  PickedFile? _doc;
  String? _docId; // kept from the update being edited
  String? _docName;
  String _audience = 'all';
  final Map<String, String> _streets = {}; // id -> name
  final Map<String, String> _buildings = {};
  bool _chat = false;
  String? _error;

  bool get _editing => widget.edit != null;
  bool get _chatLocked => _editing && widget.edit!['chatId'] != null;
  bool get _ready => _title.text.trim().isNotEmpty && _details.text.trim().isNotEmpty && (_audience == 'all' || _streets.isNotEmpty || _buildings.isNotEmpty);
  bool get _changed => _editing
      ? _title.text.trim() != widget.edit!['title'] || _details.text.trim() != widget.edit!['details']
      : _title.text.trim().isNotEmpty || _details.text.trim().isNotEmpty || _images.isNotEmpty || _doc != null;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _details.addListener(() => setState(() {}));
    final e = widget.edit;
    if (e != null) {
      for (final m in List<Map<String, dynamic>>.from(e['imageMedia'] ?? [])) {
        _images.add(_Img.remote(m['id'], m['url']));
      }
      _docId = e['documentId'];
      _docName = (e['document'] as Map?)?['name'];
      _audience = e['audience'] ?? 'all';
      _chat = e['chatId'] != null;
      if (_audience == 'sub') _loadTargets(List<String>.from(e['locationNames'] ?? []));
    }
  }

  /// Editing: match the saved location names back to street and building ids.
  Future<void> _loadTargets(List<String> names) async {
    try {
      final r = await context.api.get('/updates/audience-options');
      if (!mounted) return;
      setState(() {
        for (final s in r['streets']) {
          if (names.contains(s['name'])) _streets[s['id']] = s['name'];
        }
        for (final b in r['buildings']) {
          if (names.contains(b['name'])) _buildings[b['id']] = b['name'];
        }
      });
    } catch (_) {}
  }

  Future<bool> _confirmDiscard() async {
    if (!_changed) return true;
    final r = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_editing ? 'Discard changes?' : 'Discard update?', style: KText.headingSmall),
          const SizedBox(height: 8),
          Text('By discarding, all your input would be lost.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: KeysButton('Keep editing', variant: ButtonVariant.secondary, onPressed: () => Navigator.pop(c, false))),
            const SizedBox(width: 12),
            Expanded(child: KeysButton('Yes, discard', onPressed: () => Navigator.pop(c, true))),
          ]),
        ]),
      ),
    );
    return r == true;
  }

  Future<void> _addImage() async {
    if (_images.length >= kUpdateImagesMax) return setState(() => _error = 'You can add up to $kUpdateImagesMax images');
    final f = await context.deps.media.pickPhoto();
    if (f == null) return;
    final problem = photoProblem(f);
    setState(() {
      _error = problem;
      if (problem == null) _images.add(_Img.local(f));
    });
  }

  Future<void> _addDocument() async {
    final f = await context.deps.media.pickDocument(extensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']);
    if (f == null) return;
    if (f.size > kUpdateDocBytes) return setState(() => _error = 'The document you selected is too large. Please choose a file of 25 MB or less.');
    setState(() {
      _doc = f;
      _docId = null;
      _docName = f.name;
      _error = null;
    });
  }

  Future<void> _modifyAudience() async {
    final r = await showModalBottomSheet<_Audience>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AudienceSheet(initial: _Audience(_audience, Map.of(_streets), Map.of(_buildings))),
    );
    if (r == null) return;
    setState(() {
      _audience = r.kind;
      _streets
        ..clear()
        ..addAll(r.streets);
      _buildings
        ..clear()
        ..addAll(r.buildings);
    });
  }

  Future<void> _submit() async {
    final api = context.api;
    final router = GoRouter.of(context);
    await run(() async {
      final ids = <String>[];
      for (final i in _images) {
        ids.add(i.id ?? (await api.upload('/media', bytes: i.file!.bytes, filename: i.file!.name, mime: i.file!.mime, query: {'kind': 'photo'}))['id']);
      }
      String? docId = _docId;
      if (_doc != null) docId = (await api.upload('/media', bytes: _doc!.bytes, filename: _doc!.name, mime: _doc!.mime, query: {'kind': 'document'}))['id'];
      final body = {
        'title': _title.text.trim(),
        'details': _details.text.trim(),
        'imageIds': ids,
        'documentId': docId,
        'audience': _audience,
        'streetIds': _audience == 'sub' ? _streets.keys.toList() : [],
        'buildingIds': _audience == 'sub' ? _buildings.keys.toList() : [],
        'groupChat': _chat,
      };
      final r = _editing ? await api.patch('/updates/${widget.edit!['id']}', body) : await api.post('/updates', body);
      if (!mounted) return;
      showToast(context, r['message']);
      router.pop(r['update']);
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong. Please try again.'));
  }

  Widget _label(String text, {bool required = false, String? counter}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(text, style: KText.paragraphMediumLarge.copyWith(color: KColors.textSecondary)),
          if (required) Text(' *', style: KText.paragraphMediumLarge.copyWith(color: KColors.error)),
          const Spacer(),
          if (counter != null) Text(counter, style: KText.paragraphSmall.copyWith(color: KColors.textTertiary)),
        ]),
      );

  Widget _pillButton(String label, IconData icon, VoidCallback? onTap) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: KColors.textPrimary,
            side: const BorderSide(color: KColors.borderStrong),
            shape: const StadiumBorder(),
            textStyle: KText.labelSemibold.copyWith(fontSize: 13),
          ),
        ),
      );

  Widget _audienceChip(String text, {VoidCallback? onRemove}) => Container(
        padding: EdgeInsets.fromLTRB(14, 8, onRemove == null ? 14 : 6, 8),
        decoration: BoxDecoration(color: KColors.surfaceInverted, borderRadius: BorderRadius.circular(KRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: KText.paragraphMedium.copyWith(color: KColors.textInverse)),
          if (onRemove != null)
            InkWell(onTap: onRemove, child: Semantics(label: 'Remove $text', button: true, child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(PhosphorIconsRegular.x, size: 16, color: Colors.white)))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final names = {..._streets, ..._buildings};
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(
          backgroundColor: KColors.surfaceDefault,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Text(_editing ? 'Edit Update' : 'Create Update', style: KText.headingXSmall),
          leading: IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.caretLeft, size: 30), onPressed: () => Navigator.of(context).maybePop()),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          _label('Title of your update', required: true),
          TextField(
            controller: _title,
            maxLength: kUpdateTitleMax,
            maxLines: null,
            style: KText.headingXSmall.copyWith(fontSize: 20, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Add a title',
              counterText: '${_title.text.length}/$kUpdateTitleMax',
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: KColors.borderDefault)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: KColors.borderStrong)),
            ),
          ),
          const SizedBox(height: 16),
          _label('Details of the update', required: true, counter: '${_details.text.length}/$kUpdateDetailsMax'),
          TextField(
            controller: _details,
            maxLength: kUpdateDetailsMax,
            minLines: 5,
            maxLines: 10,
            style: KText.paragraphLarge,
            decoration: InputDecoration(
              counterText: '',
              hintText: 'What do residents need to know?',
              filled: true,
              fillColor: KColors.surfaceSubtle,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.md), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 24),
          _label('Relevant images'),
          if (_images.isNotEmpty) ...[
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final img = _images[i];
                  return Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(KRadius.sm),
                      child: img.file != null
                          ? Image.memory(img.file!.bytes, width: 76, height: 76, fit: BoxFit.cover)
                          : Image.network(context.api.absolute(img.url!), width: 76, height: 76, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 76, color: KColors.surfaceSubtle)),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Semantics(
                          button: true,
                          label: 'Remove image ${i + 1}',
                          child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(2), child: const Icon(PhosphorIconsRegular.x, size: 16, color: Colors.white)),
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          _pillButton('Upload image', PhosphorIconsRegular.uploadSimple, _images.length < kUpdateImagesMax ? _addImage : null),
          const SizedBox(height: 24),
          _label('Relevant documents'),
          if (_docName != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.md)),
              child: Row(children: [
                const Icon(PhosphorIconsRegular.fileText, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_docName!, style: KText.paragraphMedium, overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: 'Remove document',
                  icon: const Icon(PhosphorIconsRegular.x, size: 18),
                  onPressed: () => setState(() {
                    _doc = null;
                    _docId = null;
                    _docName = null;
                  }),
                ),
              ]),
            )
          else
            _pillButton('Upload document', PhosphorIconsRegular.uploadSimple, _addDocument),
          const SizedBox(height: 24),
          _label('Audience'),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (_audience == 'all' || names.isEmpty)
              _audienceChip('All residents')
            else
              for (final e in names.entries)
                _audienceChip(e.value, onRemove: () => setState(() {
                      _streets.remove(e.key);
                      _buildings.remove(e.key);
                      if (_streets.isEmpty && _buildings.isEmpty) _audience = 'all';
                    })),
            TextButton(
              onPressed: _modifyAudience,
              style: TextButton.styleFrom(foregroundColor: KColors.textLink, textStyle: KText.paragraphMedium.copyWith(decoration: TextDecoration.underline)),
              child: const Text('Modify'),
            ),
          ]),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Create a group chat for this update', style: KText.paragraphLarge),
            subtitle: _chatLocked ? Text('The group chat cannot be turned off.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)) : null,
            value: _chat,
            activeTrackColor: KColors.surfaceInverted,
            onChanged: _chatLocked ? null : (v) => setState(() => _chat = v),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorLine(_error!)),
        ]),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: KColors.borderDefault))),
            child: KeysButton(_editing ? 'Save changes' : 'Post update', loading: busy, onPressed: _ready ? _submit : null),
          ),
        ),
      ),
    );
  }
}

class _Audience {
  _Audience(this.kind, this.streets, this.buildings);
  final String kind;
  final Map<String, String> streets;
  final Map<String, String> buildings;
}

/// UPD-03: All residents or a sub-community of streets and buildings, with search.
class _AudienceSheet extends StatefulWidget {
  const _AudienceSheet({required this.initial});
  final _Audience initial;
  @override
  State<_AudienceSheet> createState() => _AudienceSheetState();
}

class _AudienceSheetState extends State<_AudienceSheet> {
  late String _kind = widget.initial.kind;
  late final _streets = Map.of(widget.initial.streets);
  late final _buildings = Map.of(widget.initial.buildings);
  late bool _picking = widget.initial.kind == 'sub';
  final _search = TextEditingController();
  List<Map<String, dynamic>> _optStreets = [];
  List<Map<String, dynamic>> _optBuildings = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() {
      setState(() {});
      _load();
    });
  }

  Future<void> _load() async {
    final q = _search.text.trim();
    try {
      final r = await context.api.get('/updates/audience-options', query: q.isEmpty ? null : {'q': q});
      if (!mounted || _search.text.trim() != q) return;
      setState(() {
        _optStreets = List<Map<String, dynamic>>.from(r['streets']);
        _optBuildings = List<Map<String, dynamic>>.from(r['buildings']);
        _loaded = true;
      });
    } catch (_) {}
  }

  Widget _option(String kind, String title, String subtitle) => RadioListTile<String>(
        value: kind,
        contentPadding: EdgeInsets.zero,
        activeColor: KColors.surfaceInverted,
        title: Text(title, style: KText.paragraphMediumLarge),
        subtitle: Text(subtitle, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        secondary: kind == 'sub' ? const Icon(PhosphorIconsRegular.caretRight) : null,
      );

  Widget _check(Map<String, dynamic> o, Map<String, String> into) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: into.containsKey(o['id']),
        activeColor: KColors.surfaceInverted,
        title: Text(o['name'], style: KText.paragraphLarge),
        onChanged: (v) => setState(() => v == true ? into[o['id']] = o['name'] : into.remove(o['id'])),
      );

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.85;
    if (!_picking) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Audience', style: KText.headingSmall),
            const SizedBox(height: 4),
            Text('Choose who receives this update.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _kind,
              onChanged: (v) => setState(() {
                _kind = v!;
                if (v == 'sub') _picking = true;
              }),
              child: Column(children: [
                _option('all', 'All residents', 'Everyone in your community'),
                _option('sub', 'Sub-community', 'Residents of specific community'),
              ]),
            ),
            const SizedBox(height: 12),
            KeysButton('Done', onPressed: () => Navigator.pop(context, _Audience('all', {}, {}))),
          ]),
        ),
      );
    }
    final ready = _streets.isNotEmpty || _buildings.isNotEmpty;
    return SizedBox(
      height: h,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
            child: Row(children: [
              IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.arrowLeft), onPressed: () => setState(() => _picking = false)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sub-community', style: KText.headingXSmall),
                  Text('Residents of specific community', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                ]),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SearchField(controller: _search, hint: 'Search street or building name')),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), children: [
                    if (_optStreets.isEmpty && _optBuildings.isEmpty)
                      Padding(padding: const EdgeInsets.all(24), child: Text('No results found', textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)))
                    else ...[
                      Text('Streets', style: KText.paragraphMediumLarge.copyWith(fontSize: 14)),
                      for (final s in _optStreets) _check(s, _streets),
                      const Divider(),
                      Text('Buildings', style: KText.paragraphMediumLarge.copyWith(fontSize: 14)),
                      if (_optBuildings.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No buildings in this community yet', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
                      for (final b in _optBuildings) _check(b, _buildings),
                    ],
                  ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: KeysButton('Done', onPressed: ready ? () => Navigator.pop(context, _Audience('sub', _streets, _buildings)) : null),
            ),
          ),
        ]),
      ),
    );
  }
}
