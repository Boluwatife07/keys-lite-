import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/features/feed/compose.dart';
import 'package:keys_lite/features/feed/feed_screens.dart';
import 'package:keys_lite/features/home/home_shell.dart';
import '../harness.dart';
import 'catalog.dart';

Map<String, dynamic> who(String id, String name, {String? role}) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': role};

Map<String, dynamic> post(String id, String text, {int likes = 12, int comments = 1}) => {
      'id': id, 'kind': 'post', 'author': who('u2', 'Jules Winnfield'), 'text': text, 'mentions': [], 'attachment': 'none', 'photos': [], 'poll': null,
      'likeCount': likes, 'commentCount': comments, 'likedByMe': false, 'isMine': false,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(), 'editedAt': null, 'shareLink': 'https://keys.app/post/$id',
    };

Map<String, dynamic> comment(String id, String name, String text, {int likes = 0, int replies = 0, int hoursAgo = 4}) => {
      'id': id, 'parentId': null, 'author': who('c$id', name), 'text': text, 'mentions': [], 'likeCount': likes, 'likedByMe': likes == 58, 'replyCount': replies,
      'isMine': false, 'editedAt': null, 'createdAt': DateTime.now().subtract(Duration(hours: hoursAgo)).toIso8601String(),
    };

void home(Harness h, List<Map<String, dynamic>> posts) {
  h.fake.on('GET /feed', (_, _) => {'posts': posts, 'nextCursor': null});
  h.fake.on('GET /calendar/upcoming', (_, _) => {'items': []});
  h.fake.on('GET /updates', (_, _) => {'updates': [], 'unseen': 2});
  h.fake.on('GET /notifications', (_, _) => {'items': [], 'unread': 2});
  h.fake.on('GET /chats', (_, _) => {'chats': [], 'unread': 2});
}

void main() {
  shot('feed_empty', () => const HomeShell(), setup: (h) => home(h, []));
  shot('feed_posts', () => const HomeShell(), setup: (h) => home(h, [
        post('p1', 'Hey Amy! Looks like I have your package, the postman must have dropped it off at my place by mistake. Let me know when you get home and I will drop it round.'),
        post('p2', 'Welcome runners! Our first group run is this Sunday at 9am from the park gates.', likes: 3, comments: 0),
      ]));
  shot('compose_typing', () => const ComposeScreen(), act: (t, h) async {
    await t.enterText(find.byType(EditableText).first, 'The committee is pleased to announce that the new car charging stations just went live on Brunswick Court!');
  });
  shot('comments_sheet', () => const HomeShell(), setup: (h) {
    home(h, [post('p1', 'Which café has the best latte art around here?', comments: 3)]);
    h.fake.on('GET /posts/p1/comments', (_, _) => {
          'comments': [
            comment('1', 'Tory Elston', 'I’d say Aromatique Café — not only is the coffee great, but the art is always Instagram-worthy.', likes: 58, replies: 41),
            comment('2', 'Omari Norris', 'Café Riverstone for me. Cozy vibes and the best cappuccinos.', likes: 12, hoursAgo: 12),
            comment('3', 'Roland Bourdon', 'There is a small cart by Maple Street that does amazing flat whites with cool designs.', likes: 89, hoursAgo: 22),
          ],
        });
  }, act: (t, h) async {
    await t.tap(find.text('Comment').first);
    await t.pumpAndSettle();
  });
  shot('post_options', () => const HomeShell(), setup: (h) => home(h, [post('p1', 'Hey everyone, I was wondering, what’s your go-to spot nearby for coffee?')]), act: (t, h) async {
    await t.tap(find.byTooltip('More options').first);
    await t.pumpAndSettle();
  });
  shot('report_sheet', () => const HomeShell(), setup: (h) {
    home(h, [post('p1', 'Hey everyone, I was wondering, what’s your go-to spot nearby for coffee?')]);
    h.fake.on('GET /reports/reasons', (_, _) => {'reasons': ['Misinformation', 'Violent or repulsive', 'Hateful or abusive content', 'Harassment or bullying', 'Sexual or nude activities', 'Suicide or self-harm', 'Scam, spam or fraudulent', 'Impersonation', 'Other']});
  }, act: (t, h) async {
    await t.tap(find.byTooltip('More options').first);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Report').first);
    await t.pumpAndSettle();
  });
  shot('share_sheet', () => const HomeShell(), setup: (h) => home(h, [post('p1', 'Which one of these projects would improve Thames street?')]), act: (t, h) async {
    await t.tap(find.text('Share').first);
    await t.pumpAndSettle();
  });
  shot('likes_list', () => const LikesScreen(path: '/posts/p1/likes'), setup: (h) {
    h.fake.on('GET /posts/p1/likes', (_, _) => {
          'people': [
            who('a', 'Jules Winnfield', role: 'Chair'), who('b', 'Tory Elsron'), who('c', 'Ajani Kimathi', role: 'Treasurer'), who('d', 'Roland Bourdon'), who('e', 'Ella White'),
            who('f', 'Alan Everette', role: 'Communications Lead'), who('g', 'Alana Devrow'), who('h', 'Omari Norris', role: 'Secretary'),
          ],
          'total': 143,
        });
  });
}
