import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/home/home_shell.dart';
import '../harness.dart';
import 'catalog.dart';

void main() {
  for (var step = 0; step < 8; step++) {
    shot('tour_step_${step + 1}', () => const HomeShell(), me: Harness.me(learning: true), setup: (h) {
      h.fake.on('GET /feed', (_, _) => {'posts': [], 'nextCursor': null});
      h.fake.on('GET /calendar/upcoming', (_, _) => {'items': []});
      h.fake.on('GET /updates', (_, _) => {'updates': [], 'unseen': 0});
      h.fake.on('GET /notifications', (_, _) => {'items': [], 'unread': 0});
      h.fake.on('GET /chats', (_, _) => {'chats': [], 'unread': 0});
    }, act: (t, h) async {
      await t.pumpAndSettle();
      for (var i = 0; i < step; i++) {
        await t.tap(find.text('Next'));
        await t.pumpAndSettle();
      }
    });
  }
}
