import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
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
  // Figma 1300:187371 (empty) and 3155:314757 (filled).
  Widget build(BuildContext context) {
    return KeysScaffold(
      gradient: false,
      header: KeysHeader(progress: P.profile, showBack: false),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Intro(small: true, overline: 'Profile setup', title: 'Add a profile picture and bio', body: 'Your profile picture is required so neighbours can recognise you. Your bio is optional and can be edited later.'),
        const SizedBox(height: 36),
        Center(
          child: Semantics(
            container: true,
            button: true,
            label: _photo == null ? 'Add profile picture' : 'Change profile picture',
            child: GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context,
                builder: (c) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(leading: const Icon(PhosphorIconsRegular.images), title: const Text('Choose from library'), onTap: () { Navigator.pop(c); _pick(); }),
                    ListTile(leading: const Icon(PhosphorIconsRegular.camera), title: const Text('Take photo'), onTap: () { Navigator.pop(c); _pick(camera: true); }),
                  ]),
                ),
              ),
              child: SizedBox.square(
                dimension: 120,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KColors.surfaceSubtle,
                      border: Border.all(color: KColors.surfaceDefault, width: 3),
                      image: _photo == null ? null : DecorationImage(image: MemoryImage(_photo!.bytes), fit: BoxFit.cover),
                    ),
                    child: _photo == null ? Icon(PhosphorIconsRegular.user, size: 48, color: KColors.textTertiary) : null,
                  ),
                  // Figma: 44pt white ring holding a 36pt yellow camera button.
                  Positioned(
                    right: 0,
                    bottom: -1,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: KColors.surfaceDefault, shape: BoxShape.circle),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(color: Color(0xFFFFD12A), shape: BoxShape.circle),
                        child: const Icon(PhosphorIconsFill.camera, color: Color(0xFF171717), size: 18),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        Center(child: Text('JPG or PNG, up to 15MB', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
        if (_photoError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Center(child: FieldHint(_photoError!))),
        const SizedBox(height: 24),
        KeysTextField(label: 'Bio', controller: _bio, maxLength: kBioMax, maxLines: 4, minLines: 4),
      ]),
      // ONB-22.1 / ONB-22.6: needs a photo and the safety tick.
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Semantics(
              checked: _ack,
              label: 'I have read the Keys safety guidelines',
              child: GestureDetector(
                key: const Key('safety-checkbox'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _ack = !_ack),
                child: SizedBox(height: 40, child: KCheckbox(value: _ack)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(style: KText.paragraphMedium, children: [
                const TextSpan(text: 'I have read the '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => showSafetyGuidelines(context),
                    child: Text('Keys safety guidelines', style: KText.paragraphMedium.copyWith(color: KColors.textLink)),
                  ),
                ),
              ])),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        KeysButton('Continue', loading: busy, onPressed: _photo != null && _ack ? _continue : null),
      ]),
    );
  }
}

/// ONB-23: verify now or skip.
class VerifyPromptScreen extends StatelessWidget {
  const VerifyPromptScreen({super.key});
  @override
  // Figma 1300:186227.
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        fill: true,
        header: const KeysHeader(progress: P.verify, showBack: false),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(
            small: true,
            overline: 'You’re almost done',
            title: 'Verify your home address.',
            body: 'We need to verify your home address using your bank card. Your card will not be charged. Please ensure that your home address and billing address are exactly the same.',
          ),
          const SizedBox(height: 12),
          Semantics(
            link: true,
            child: InkWell(
              onTap: () => context.push('/verify/why'),
              child: SizedBox(
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Text('How does address verification protect me?',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, height: 15 / 14, color: KColors.textLink, decoration: TextDecoration.underline, decorationColor: KColors.textLink)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
          Expanded(child: Center(child: Image.asset('assets/images/verify_identification.png', width: 200))),
        ]),
        bottom: ButtonStack([
          KeysButton('Verify my address', onPressed: () => context.push('/verify', extra: 'onboarding')),
          // ONB-23.2: stays unverified with the "Unverified" badge.
          KeysButton('Skip for now', variant: ButtonVariant.secondary, onPressed: () => context.go('/onboarding/invite')),
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

  Future<void> _share(Map<String, dynamic> inv) async {
    await context.deps.sharer.share(inv['message']);
    if (mounted) setState(() => _shared = true);
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invite;
    final sharer = context.deps.sharer;
    void done() => context.go('/home');
    // Figma 1300:187763: close and Skip in the header, a dark share card.
    return KeysScaffold(
      gradient: false,
      header: KeysHeader(
        showBack: false,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            borderRadius: BorderRadius.circular(KRadius.pill),
            onTap: done,
            child: const SizedBox(
              height: 36,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(widthFactor: 1, child: Text('Skip', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600))),
              ),
            ),
          ),
        ]),
        leading: Semantics(
          button: true,
          label: 'Close',
          child: InkResponse(radius: 22, onTap: done, child: Icon(PhosphorIconsRegular.x, size: 26, color: KColors.iconDefault)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 52, 28, 20),
      body: Column(children: [
        Text('COMMUNITY INVITE', style: KText.overline, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('Bring your\nneighbors closer', textAlign: TextAlign.center, style: KText.headingMedium.copyWith(fontSize: 36, height: 48 / 36, letterSpacing: -0.8)),
        const SizedBox(height: 20),
        const SizedBox(height: 227, child: Center(child: CircleImage('assets/images/invite_neighbours.png', size: 200))),
        const SizedBox(height: 20),
        Text('Now that you are in the community, share your community link with your neighbours to further grow the community.', textAlign: TextAlign.center, style: KText.paragraphLarge.copyWith(color: KColors.textSecondary)),
        const SizedBox(height: 24),
        if (inv != null)
          Semantics(
            button: true,
            label: 'Tap to share ${inv['link']}',
            hint: 'Long press to copy',
            child: Material(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const Key('invite-card'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => _share(inv),
                onLongPress: () async {
                  await sharer.copy(inv['link']);
                  if (context.mounted) showToast(context, 'Link copied');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Tap to share', style: KText.paragraphMediumSmall.copyWith(color: const Color(0xFFA6A6A6))),
                          const SizedBox(height: 2),
                          Text(inv['link'], overflow: TextOverflow.ellipsis, style: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w500, color: Colors.white)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(PhosphorIconsRegular.shareFat, size: 24, color: Colors.white),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      bottom: _shared ? KeysButton('Continue', onPressed: done) : null,
    );
  }
}
