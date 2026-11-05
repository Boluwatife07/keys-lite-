import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/core/scope.dart';
import 'package:keys_lite/core/services.dart';
import 'package:keys_lite/core/session.dart';
import 'package:keys_lite/main.dart';
import 'package:keys_lite/router.dart';
import 'package:keys_lite/widgets/widgets.dart';

typedef Handler = Object? Function(Map<String, dynamic> body, Map<String, String> query);

/// Fake Keys API: register "METHOD /path" handlers; every call is recorded.
class FakeApi {
  final Map<String, Handler> routes = {};
  final List<(String, Map<String, dynamic>)> calls = [];

  void on(String key, Handler h) => routes[key] = h;

  http.Client client() => MockClient((req) async {
        final key = '${req.method} ${req.url.path}';
        Map<String, dynamic> body = {};
        if (req.headers['content-type']?.contains('json') == true && req.body.isNotEmpty) body = jsonDecode(req.body);
        calls.add((key, body));
        final h = routes[key];
        if (h == null) return http.Response(jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'no fake for $key'}}), 404);
        final out = h(body, req.url.queryParameters);
        if (out is ApiException) {
          return http.Response(jsonEncode({'error': {'code': out.code, 'message': out.message, ...out.data}}), out.status);
        }
        return http.Response(jsonEncode(out ?? {}), 200, headers: {'content-type': 'application/json'});
      });

  bool called(String key) => calls.any((c) => c.$1 == key);
  Map<String, dynamic> lastBody(String key) => calls.lastWhere((c) => c.$1 == key).$2;
}

class FakeMedia implements MediaPicker {
  PickedFile? photo;
  PickedFile? document;
  PickedFile? video;
  @override
  Future<PickedFile?> pickVideo() async => video;
  @override
  Future<PickedFile?> pickPhoto({bool camera = false}) async => photo;
  @override
  Future<PickedFile?> pickDocument({List<String> extensions = const []}) async => document;
}

class FakeSharer implements Sharer {
  final shared = <String>[];
  final copied = <String>[];
  @override
  Future<void> share(String text) async => shared.add(text);
  @override
  Future<void> copy(String text) async => copied.add(text);
  final files = <String>[];
  @override
  Future<void> shareFile(Uint8List bytes, String name, String mime) async => files.add(name);
}

class Harness {
  Harness() {
    api = ApiClient(baseUrl: 'http://test', client: fake.client())..token = 'tok';
    store.token = 'tok';
    deps = Deps(api: api, session: Session(api, store), media: media, social: MockSocialAuth(), cards: MockCardVerifier(), sharer: sharer, store: store);
  }
  final fake = FakeApi();
  final media = FakeMedia();
  final sharer = FakeSharer();
  final store = MemoryStore();
  late final ApiClient api;
  late final Deps deps;
  late GoRouter router;

  static Map<String, dynamic> me({String step = 'complete', String status = 'unverified', bool welcome = false, bool learning = false}) => {
        'id': 'u1',
        'email': 'amy@keys.test',
        'firstName': 'Amy',
        'lastName': 'Duncan',
        'onboardingStep': step,
        'verificationStatus': status,
        'photoUrl': null,
        'bio': 'Hello',
        'hasPassword': true,
        'address': {'line1': '12 Maple Road', 'formatted': '12 Maple Road, London SE1 7AA', 'postcode': 'SE1 7AA', 'street': 'Maple Road'},
        'community': {'id': 'c1', 'name': 'Maple Road', 'type': 'street', 'code': 'MAPLE1', 'level': 'house'},
        'showWelcomePrompt': welcome,
        'showLearning': learning,
      };

  /// Pumps [screen] as the first route, with every real route behind it.
  Future<void> pump(WidgetTester t, Widget screen, {Map<String, dynamic>? meJson}) async {
    // iPhone 15 frame used in the Figma designs.
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    fake.on('GET /me', (_, _) => meJson ?? me());
    if (meJson != null || fake.routes.containsKey('GET /me')) await deps.session.refresh();
    router = buildRouter(initial: '/test', extraRoutes: [GoRoute(path: '/test', builder: (_, _) => screen)]);
    await t.pumpWidget(KeysApp(deps: deps, router: router, listenForLinks: false));
    await t.pumpAndSettle();
  }

  /// Path of the top route, including pushed ones.
  String get location => router.routerDelegate.currentConfiguration.last.matchedLocation;
}

// A real 1x1 PNG, padded with zeros to the size a test needs.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
PickedFile fakePng(int bytes) {
  final b = Uint8List(bytes < _png.length ? _png.length : bytes);
  b.setAll(0, _png);
  return PickedFile(bytes: b, name: 'me.png', mime: 'image/png');
}

/// True when the KeysButton with [label] can be tapped.
bool buttonEnabled(WidgetTester t, String label) {
  final w = t.widget<KeysButton>(find.widgetWithText(KeysButton, label));
  return w.onPressed != null && !w.loading;
}
