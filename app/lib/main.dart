import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'core/api.dart';
import 'core/config.dart';
import 'core/scope.dart';
import 'core/services.dart';
import 'core/session.dart';
import 'router.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  final store = DeviceStore();
  final deps = Deps(
    api: api,
    session: Session(api, store),
    media: DeviceMediaPicker(),
    // Mocks until Apple/Google client IDs and Stripe keys are configured.
    social: MockSocialAuth(),
    cards: MockCardVerifier(),
    sharer: DeviceSharer(),
    store: store,
    videoLength: _videoLength,
  );
  runApp(KeysApp(deps: deps));
}

Future<Duration?> _videoLength(PickedFile f) async {
  if (f.path == null) return null;
  final c = VideoPlayerController.file(File(f.path!));
  try {
    await c.initialize();
    return c.value.duration;
  } catch (_) {
    return null;
  } finally {
    await c.dispose();
  }
}

class KeysApp extends StatefulWidget {
  const KeysApp({super.key, required this.deps, this.router, this.listenForLinks = true});
  final Deps deps;
  final GoRouter? router;
  final bool listenForLinks;
  @override
  State<KeysApp> createState() => _KeysAppState();
}

class _KeysAppState extends State<KeysApp> {
  late final GoRouter _router = widget.router ?? buildRouter();
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    if (widget.listenForLinks) _links = AppLinks().uriLinkStream.listen(_onLink, onError: (_) {});
  }

  /// XFR-02.1 / ONB-24.4: community invite links carry the code into
  /// sign-up, or re-run matching for a signed-in user still onboarding.
  void _onLink(Uri uri) {
    final seg = uri.pathSegments;
    if (seg.length == 2 && seg[0] == 'c') {
      widget.deps.session.pendingCommunityCode = seg[1].toUpperCase();
      final me = widget.deps.session.me;
      if (me != null && me.onboardingStep == 'community') _router.go('/');
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
        deps: widget.deps,
        child: MaterialApp.router(
          title: 'Keys',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          routerConfig: _router,
          locale: const Locale('en', 'GB'),
        ),
      );
}
