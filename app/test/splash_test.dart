import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/main.dart';
import 'package:keys_lite/router.dart';
import 'harness.dart';

Future<String> runSplash(WidgetTester t, Harness h) async {
  t.view.physicalSize = const Size(1179, 2556);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final router = buildRouter(initial: '/');
  await t.pumpWidget(KeysApp(deps: h.deps, router: router, listenForLinks: false));
  await t.pump(const Duration(seconds: 3));
  await t.pump(const Duration(milliseconds: 100));
  return router.routerDelegate.currentConfiguration.last.matchedLocation;
}

void main() {
  testWidgets('Splash leaves after 3 s when the server is slow to wake', (t) async {
    final h = Harness();
    h.fake.on('GET /me', (_, _) => Future.delayed(const Duration(seconds: 30), Harness.me));
    expect(await runSplash(t, h), '/intro');
    expect(find.text("We couldn't reach Keys. Please check your connection and sign in again."), findsOneWidget);
    // Let the slow request finish so no timer is left running.
    await t.pump(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('Splash goes straight to Home when the server answers', (t) async {
    final h = Harness();
    h.fake.on('GET /me', (_, _) => Harness.me());
    h.fake.on('GET /feed', (_, _) => {'posts': [], 'nextCursor': null});
    h.fake.on('GET /calendar/upcoming', (_, _) => {'items': []});
    h.fake.on('GET /updates', (_, _) => {'updates': [], 'unseen': 0});
    h.fake.on('GET /chats', (_, _) => {'chats': [], 'unread': 0});
    expect(await runSplash(t, h), '/home');
  });
}
