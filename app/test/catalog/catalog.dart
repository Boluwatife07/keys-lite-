// Screen catalogue for design audits: renders a screen at the iPhone 15
// frame used in Figma (393 x 852 with status bar and home indicator insets)
// and saves it as a PNG next to this file (out/<name>.png).
//
// Run: flutter test --update-goldens test/catalog
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/theme/theme_controller.dart';
import 'package:keys_lite/theme/tokens.dart';
import '../harness.dart';

typedef Setup = void Function(Harness h);
typedef Act = Future<void> Function(WidgetTester t, Harness h);

/// Renders [screen] (light, then dark) and saves out/<name>.png and out/<name>_dark.png.
void shot(String name, Widget Function() screen, {Setup? setup, Act? act, Map<String, dynamic>? me, bool dark = true}) {
  for (final mode in [ThemeChoice.light, if (dark) ThemeChoice.dark]) {
    testWidgets('$name ${mode.name}', (t) async {
      t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      t.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      final h = Harness();
      await h.deps.theme.set(mode);
      addTearDown(() => KColors.palette = KPalette.light);
      setup?.call(h);
      await h.pump(t, screen(), meJson: me ?? Harness.me());
      if (act != null) await act(t, h);
      await t.pumpAndSettle();
      // Decode asset images before the capture.
      await t.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name${mode == ThemeChoice.dark ? '_dark' : ''}.png'));
    });
  }
}
