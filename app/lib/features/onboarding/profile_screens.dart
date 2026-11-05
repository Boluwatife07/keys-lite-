import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import '../../core/api.dart';
import '../../core/scope.dart';
import '../../core/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'community_screens.dart' show P;

const kMaxPhotoBytes = 15 * 1024 * 1024;
const kPhotoTooLarge = 'The image you selected is too large. Please choose a different image.';
const kBioMax = 160;

/// XFR-01.1 client check: JPG or PNG up to 15 MB.
String? photoProblem(PickedFile f) {
  if (f.mime != 'image/jpeg' && f.mime != 'image/png') return 'Please choose a JPG or PNG image.';
  if (f.size > kMaxPhotoBytes) return kPhotoTooLarge;
  return null;
}

class _CropArgs {
  _CropArgs(this.bytes, this.left, this.top, this.side);
  final Uint8List bytes;
  final double left, top, side; // fractions of the source image
}

Uint8List _cropSquare(_CropArgs a) {
  final src = img.decodeImage(a.bytes)!;
  final x = (a.left * src.width).round();
  final y = (a.top * src.height).round();
  final s = (a.side * src.width).round().clamp(1, src.width - x).clamp(1, src.height - y);
  final out = img.copyResize(img.copyCrop(src, x: x, y: y, width: s, height: s), width: s > 1080 ? 1080 : s);
  return Uint8List.fromList(img.encodeJpg(out, quality: 88));
}

/// ONB-22.2: crop the chosen photo to 1:1. Pinch and drag inside the square.
class SquareCropScreen extends StatefulWidget {
  const SquareCropScreen({super.key, required this.file});
  final PickedFile file;
  @override
  State<SquareCropScreen> createState() => _SquareCropScreenState();
}

class _SquareCropScreenState extends State<SquareCropScreen> {
  final _t = TransformationController();
  Size? _imgSize;
  bool _busy = false;
  bool _centred = false;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.file.bytes).then((i) => mounted ? setState(() => _imgSize = Size(i.width.toDouble(), i.height.toDouble())) : null);
  }

  Future<void> _done(double box) async {
    setState(() => _busy = true);
    final s = _imgSize!;
    // The image is laid out to cover the square box, then transformed.
    final cover = box / (s.width < s.height ? s.width : s.height);
    final laidW = s.width * cover, laidH = s.height * cover;
    final m = _t.value;
    final scale = m.getMaxScaleOnAxis();
    final tx = m.getTranslation();
    final left = (-tx.x / scale) / laidW;
    final top = (-tx.y / scale) / laidH;
    final side = (box / scale) / laidW;
    final cropped = await compute(_cropSquare, _CropArgs(widget.file.bytes, left.clamp(0, 1), top.clamp(0, 1), side.clamp(0.01, 1)));
    if (mounted) Navigator.pop(context, PickedFile(bytes: cropped, name: 'profile.jpg', mime: 'image/jpeg'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Crop photo')),
      body: LayoutBuilder(builder: (context, c) {
        final box = c.maxWidth - 32;
        final s = _imgSize;
        if (s != null && !_centred) {
          // Start with the crop square in the middle of the photo.
          final cover = box / (s.width < s.height ? s.width : s.height);
          _t.value = Matrix4.translationValues(-(s.width * cover - box) / 2, -(s.height * cover - box) / 2, 0);
          _centred = true;
        }
        return Column(children: [
          const Spacer(),
          Center(
            child: SizedBox(
              width: box,
              height: box,
              child: s == null
                  ? const Center(child: CircularProgressIndicator())
                  : ClipRect(
                      child: InteractiveViewer(
                        transformationController: _t,
                        minScale: 1,
                        maxScale: 5,
                        constrained: false,
                        child: SizedBox(
                          width: s.width * box / (s.width < s.height ? s.width : s.height),
                          height: s.height * box / (s.width < s.height ? s.width : s.height),
                          child: Image.memory(widget.file.bytes, fit: BoxFit.fill),
                        ),
                      ),
                    ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: KeysButton('Use photo', variant: ButtonVariant.light, loading: _busy, onPressed: s == null ? null : () => _done(box)),
          ),
        ]);
      }),
    );
  }
}

Future<void> showSafetyGuidelines(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Stay safe when interacting online', style: KText.headingSmall),
          const SizedBox(height: 12),
          Text(
            'At Keys, we’re all about building real connections in your neighborhood. But safety comes first. Be mindful when chatting with others, avoid sharing sensitive personal information and always trust your instincts. If something feels off, report it or speak to a committee member. Remember, communities are safer when we look out for each other, both online and offline. Stay safe. Stay connected.',
            style: KText.paragraphLarge.copyWith(color: KColors.textSecondary),
          ),
          const SizedBox(height: 24),
          KeysButton('Got it', onPressed: () => Navigator.pop(c)),
        ]),
      ),
    );

/// ONB-22: profile picture (required), bio (optional, preset), safety ack.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> with Busy {
  final _bio = TextEditingController();
  PickedFile? _photo;
  String? _photoError;
  bool _ack = false;

  @override
  void initState() {
    super.initState();
    context.api.get('/onboarding/defaults').then((d) {
      if (mounted && _bio.text.isEmpty) setState(() => _bio.text = d['bio']);
    });
  }

  Future<void> _pick({bool camera = false}) async {
    final f = await context.deps.media.pickPhoto(camera: camera);
    if (f == null || !mounted) return;
    final problem = photoProblem(f);
    if (problem != null) return setState(() => _photoError = problem);
    final cropped = await Navigator.of(context).push<PickedFile>(MaterialPageRoute(builder: (_) => SquareCropScreen(file: f)));
    if (cropped != null) {
      setState(() {
        _photo = cropped;
        _photoError = null;
      });
    }
  }

  Future<void> _continue() async {
    final session = context.session;
    await run(() async {
      final api = session.api;
      final m = await api.upload('/media', bytes: _photo!.bytes, filename: _photo!.name, mime: _photo!.mime, query: {'kind': 'photo'});
      await api.post('/onboarding/profile', {'photoMediaId': m['id'], 'bio': _bio.text.trim(), 'safetyAccepted': true});
      await session.refresh();
      if (mounted) context.go('/onboarding/verify');
    }, onError: (e) => setState(() => _photoError = e is ApiException ? e.message : 'Something went wrong.'));
  }

  @override
  Widget build(BuildContext context) {
    return KeysScaffold(
      header: KeysHeader(progress: P.profile, showBack: false),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Intro(overline: 'Profile setup', title: 'Add a profile picture and bio', body: 'Your profile picture is required so neighbours can recognise you. Your bio is optional and can be edited later.'),
        const SizedBox(height: 24),
        Center(
          child: Semantics(
            button: true,
            label: _photo == null ? 'Add profile picture' : 'Change profile picture',
            child: GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context,
                builder: (c) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from library'), onTap: () { Navigator.pop(c); _pick(); }),
                    ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take photo'), onTap: () { Navigator.pop(c); _pick(camera: true); }),
                  ]),
                ),
              ),
              child: Stack(children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: KColors.surfaceSubtle,
                  backgroundImage: _photo == null ? null : MemoryImage(_photo!.bytes),
                  child: _photo == null ? const Icon(Icons.person_outline, size: 48, color: KColors.textTertiary) : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: KColors.surfaceInverted, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (_photoError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Center(child: ErrorLine(_photoError!))),
        const SizedBox(height: 24),
        KeysTextField(label: 'Bio', controller: _bio, maxLength: kBioMax, maxLines: 4),
        const SizedBox(height: 16),
        Row(children: [
          Checkbox(
            key: const Key('safety-checkbox'),
            value: _ack,
            activeColor: KColors.surfaceInverted,
            onChanged: (v) => setState(() => _ack = v ?? false),
          ),
          Expanded(
            child: Wrap(children: [
              Text('I have read the ', style: KText.paragraphMedium),
              GestureDetector(
                onTap: () => showSafetyGuidelines(context),
                child: Text('Keys safety guidelines', style: KText.paragraphMedium.copyWith(color: KColors.textLink)),
              ),
            ]),
          ),
        ]),
      ]),
      // ONB-22.1 / ONB-22.6: needs a photo and the safety tick.
      bottom: KeysButton('Continue', loading: busy, onPressed: _photo != null && _ack ? _continue : null),
    );
  }
}

/// ONB-23: verify now or skip.
class VerifyPromptScreen extends StatelessWidget {
  const VerifyPromptScreen({super.key});
  @override
  Widget build(BuildContext context) => KeysScaffold(
        header: const KeysHeader(progress: P.verify, showBack: false),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(
            overline: "You're almost done",
            title: 'Verify your home address.',
            body: 'We need to verify your home address using your bank card. Your card will not be charged. Please ensure that your home address and billing address are exactly the same.',
          ),
          const SizedBox(height: 24),
          Center(child: Image.asset('assets/images/verify_identification.png', width: 200)),
          Center(child: LinkText('How does address verification protect me?', onTap: () => context.push('/verify/why'))),
        ]),
        bottom: ButtonStack([
          KeysButton('Verify my address', onPressed: () => context.push('/verify', extra: 'onboarding')),
          // ONB-23.2: stays unverified with the "Unverified" badge.
          KeysButton('Skip for now', variant: ButtonVariant.ghost, onPressed: () => context.go('/onboarding/invite')),
        ]),
      );
}

/// ONB-24: invite neighbours with the community link.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});
  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  Map<String, dynamic>? _invite;
  bool _shared = false;

  @override
  void initState() {
    super.initState();
    context.api.get('/communities/mine/invite').then((r) => mounted ? setState(() => _invite = r) : null);
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invite;
    final sharer = context.deps.sharer;
    return KeysScaffold(
      header: const KeysHeader(progress: P.invite, showBack: false),
      body: Column(children: [
        const Intro(center: true, title: 'Bring your neighbors closer', body: 'Now that you are in the community, share your community link with your neighbours to further grow the community.'),
        const SizedBox(height: 24),
        const CircleImage('assets/images/invite_neighbours.png', size: 200),
        const SizedBox(height: 24),
        if (inv != null)
          Container(
            padding: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.sm)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 10),
                  Text('Community link', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                  Text(inv['link'], style: KText.paragraphMediumLarge, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                ]),
              ),
              IconButton(
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await sharer.copy(inv['link']);
                  if (context.mounted) showToast(context, 'Link copied');
                },
              ),
            ]),
          ),
      ]),
      bottom: ButtonStack([
        KeysButton(
          _shared ? 'Continue' : 'Tap to share',
          onPressed: inv == null
              ? null
              : _shared
                  ? () => context.go('/home')
                  : () async {
                      await sharer.share(inv['message']);
                      if (mounted) setState(() => _shared = true);
                    },
        ),
        if (!_shared) KeysButton('Skip', variant: ButtonVariant.ghost, onPressed: () => context.go('/home')),
      ]),
    );
  }
}
