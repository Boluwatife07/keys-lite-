import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/core/feed_models.dart';
import 'package:keys_lite/features/feed/compose.dart';
import 'package:keys_lite/features/feed/feed_screens.dart';
import 'package:keys_lite/features/feed/post_card.dart';
import 'package:keys_lite/features/polls/create_poll.dart';
import 'package:keys_lite/features/polls/poll_block.dart';
import 'harness.dart';

Map<String, dynamic> author({String id = 'u2', String name = 'Jules Winnfield', bool verified = true, String? role}) =>
    {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': verified, 'role': role};

Map<String, dynamic> post({String id = 'p1', String text = 'Hello', bool mine = false, Map<String, dynamic>? a, Map<String, dynamic>? poll, int likes = 0, bool liked = false}) => {
      'id': id,
      'kind': poll == null ? 'post' : 'poll',
      'author': a ?? author(),
      'text': text,
      'mentions': [],
      'attachment': 'none',
      'photos': [],
      'poll': poll,
      'likeCount': likes,
      'commentCount': 0,
      'likedByMe': liked,
      'isMine': mine,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
      'editedAt': null,
      'shareLink': 'https://keys.app/post/$id',
    };

Map<String, dynamic> pollJson({bool voted = false, bool closed = false, bool multi = false}) => {
      'question': 'Bins on Tuesday?',
      'promise': 'Agree the day',
      'multi': multi,
      'closesAt': DateTime.now().add(const Duration(hours: 23, minutes: 30)).toIso8601String(),
      'closed': closed,
      'totalVotes': voted ? 4 : 0,
      'myVote': voted ? ['o1'] : null,
      'canVote': !voted && !closed,
      'resultsVisible': voted || closed,
      'options': [
        {'id': 'o1', 'text': 'Yes', 'votes': voted ? 3 : null, 'percent': voted ? 75 : null, 'winner': closed},
        {'id': 'o2', 'text': 'No', 'votes': voted ? 1 : null, 'percent': voted ? 25 : null, 'winner': false},
      ],
    };

void main() {
  testWidgets('FED-01.3 empty feed shows the empty state with Create post', (t) async {
    final h = Harness();
    h.fake.on('GET /feed', (_, _) => {'posts': [], 'nextCursor': null});
    await h.pump(t, const Scaffold(body: PostList(path: '/feed', empty: EmptyState(title: 'No posts yet', body: 'Posts and activities of your neighbors would be shown here'))));
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.text('Posts and activities of your neighbors would be shown here'), findsOneWidget);
  });

  testWidgets('FED-01.2 card: author, Unverified label, time, counts; like toggles', (t) async {
    final h = Harness();
    h.fake.on('POST /posts/p1/like', (_, _) => {'liked': true, 'likeCount': 1});
    await h.pump(t, Scaffold(body: ListView(children: [PostCard(post: Post(post(a: author(verified: false))), onChanged: (_) {})])));
    expect(find.text('Jules Winnfield'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
    expect(find.text('10m ago'), findsOneWidget);
    expect(find.text('0 likes'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Like'));
    await t.pumpAndSettle();
    expect(find.text('1 like'), findsOneWidget);
  });

  testWidgets('long text is cut with "...Read more"', (t) async {
    final h = Harness();
    await h.pump(t, Scaffold(body: ListView(children: [PostCard(post: Post(post(text: 'word ' * 39)), onChanged: (_) {})])));
    expect(find.text('...Read more'), findsOneWidget);
    await t.tap(find.text('...Read more'));
    await t.pump();
    expect(find.text('...Read more'), findsNothing);
  });

  testWidgets('FED-17.1 / FED-18.1 menus: others get mute/report/block, mine get edit/delete', (t) async {
    final h = Harness();
    await h.pump(t, Scaffold(body: ListView(children: [
      PostCard(post: Post(post()), onChanged: (_) {}),
      PostCard(post: Post(post(id: 'p2', mine: true)), onChanged: (_) {}),
    ])));
    await t.tap(find.byTooltip('More options').first);
    await t.pumpAndSettle();
    expect(find.text('Mute Jules'), findsOneWidget);
    expect(find.text('Stop seeing posts from this user for 30 days'), findsOneWidget);
    expect(find.text('Report this post'), findsOneWidget);
    expect(find.text('Block Jules'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More options').last);
    await t.pumpAndSettle();
    expect(find.text('Edit post'), findsOneWidget);
    expect(find.text('Delete post'), findsOneWidget);
  });

  testWidgets('XFR-03 report sheet: Submit inactive until a reason; Other needs text', (t) async {
    final h = Harness();
    h.fake.on('GET /reports/reasons', (_, _) => {'reasons': ['Spam or misleading', 'Other']});
    h.fake.on('POST /reports', (_, _) => {'ok': true});
    await h.pump(t, Scaffold(body: ListView(children: [PostCard(post: Post(post()), onChanged: (_) {})])));
    await t.tap(find.byTooltip('More options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Report this post'));
    await t.pumpAndSettle();
    expect(buttonEnabled(t, 'Submit'), isFalse);
    await t.tap(find.text('Other'));
    await t.pump();
    expect(buttonEnabled(t, 'Submit'), isFalse);
    await t.enterText(find.byType(TextField).last, 'Not a neighbour');
    await t.pump();
    expect(buttonEnabled(t, 'Submit'), isTrue);
    await t.tap(find.text('Submit'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /reports'), {'itemType': 'post', 'itemId': 'p1', 'reason': 'Other', 'text': 'Not a neighbour'});
    expect(find.text('Your report has been submitted'), findsOneWidget);
  });

  testWidgets('FED-02 compose: counter, Post inactive when empty, Everyone fixed, discard asks', (t) async {
    final h = Harness();
    h.fake.on('POST /posts', (b, _) => {'post': post(text: b['text'], mine: true), 'message': 'Your post has been sent'});
    await h.pump(t, const ComposeScreen());
    expect(find.text("What's happening?"), findsOneWidget);
    expect(find.text('0/200'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('post-button'))).onPressed, isNull);
    await t.enterText(find.byKey(const Key('compose-field')), 'x' * 250);
    await t.pump();
    expect(find.text('200/200'), findsOneWidget);
    await t.enterText(find.byKey(const Key('compose-field')), 'Hello street');
    await t.pump();
    expect(t.widget<FilledButton>(find.byKey(const Key('post-button'))).onPressed, isNotNull);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('By discarding, all your input would be lost.'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('post-button')));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /posts')['text'], 'Hello street');
  });

  testWidgets('FED-04.1 one attachment type: photos turn the others off; 15 MB photo refused', (t) async {
    final h = Harness();
    await h.pump(t, const ComposeScreen());
    h.media.photo = fakePng(15 * 1024 * 1024 + 1);
    await t.tap(find.byTooltip('Add photos'));
    await t.pumpAndSettle();
    expect(find.text('The image you selected is too large. Please choose a different image.'), findsOneWidget);
    h.media.photo = fakePng(100);
    await t.tap(find.byTooltip('Add photos'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Remove photo 1'), findsOneWidget);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, PhosphorIconsRegular.videoCamera)).onPressed, isNull);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, PhosphorIconsRegular.paperclip)).onPressed, isNull);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, PhosphorIconsRegular.link)).onPressed, isNull);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, PhosphorIconsRegular.image)).onPressed, isNotNull);
  });

  testWidgets('FED-05.2 failed post keeps the text and offers Retry', (t) async {
    final h = Harness();
    h.fake.on('POST /posts', (_, _) => ApiException(500, 'SERVER_ERROR', 'boom'));
    await h.pump(t, const ComposeScreen());
    await t.enterText(find.byKey(const Key('compose-field')), 'Keep me');
    await t.pump();
    await t.tap(find.byKey(const Key('post-button')));
    await t.pumpAndSettle();
    expect(find.text('Posting failed.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Keep me'), findsOneWidget);
  });

  testWidgets('POL-06 single select: Submit after picking; results after voting; "Already voted"', (t) async {
    final h = Harness();
    h.fake.on('POST /polls/p1/vote', (b, _) => {'post': post(poll: pollJson(voted: true))});
    Post? latest;
    await h.pump(t, Scaffold(body: ListView(children: [StatefulBuilder(builder: (c, set) => PollBlock(post: latest ?? Post(post(poll: pollJson())), onChanged: (p) => set(() => latest = p)))])));
    expect(find.text('Select one'), findsOneWidget);
    expect(find.text('23hours left'), findsOneWidget);
    expect(find.text('Poll promise'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Submit')).onPressed, isNull);
    await t.tap(find.text('Yes'));
    await t.pump();
    await t.tap(find.text('Submit'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /polls/p1/vote'), {'optionIds': ['o1']});
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('3 votes'), findsOneWidget);
    expect(find.text('Already voted'), findsOneWidget);
    expect(find.text('4 Votes'), findsOneWidget);
  });

  testWidgets('POL-06.4 unverified resident gets the verify sheet', (t) async {
    final h = Harness();
    h.fake.on('POST /polls/p1/vote', (_, _) => ApiException(403, 'VERIFICATION_REQUIRED', 'verify'));
    await h.pump(t, Scaffold(body: ListView(children: [PollBlock(post: Post(post(poll: pollJson())), onChanged: (_) {})])));
    await t.tap(find.text('No'));
    await t.pump();
    await t.tap(find.text('Submit'));
    await t.pumpAndSettle();
    expect(find.text('Verify your home address'), findsOneWidget);
  });

  testWidgets('POL-09 closed poll shows Closed and the winner', (t) async {
    final h = Harness();
    await h.pump(t, Scaffold(body: ListView(children: [PollBlock(post: Post(post(poll: pollJson(closed: true, voted: true))), onChanged: (_) {})])));
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('POL-02 / POL-03 create poll: inactive without a question, max 5 options, images all or none', (t) async {
    final h = Harness();
    await h.pump(t, const CreatePollScreen());
    expect(buttonEnabled(t, 'Preview poll'), isFalse);
    expect(find.text('All residents'), findsOneWidget);
    expect(find.text('24 hours'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Bins on Tuesday?');
    await t.pump();
    h.media.photo = fakePng(50);
    await t.tap(find.text('Add image').first);
    await t.pumpAndSettle();
    expect(find.text('Change image'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      final add = find.widgetWithText(OutlinedButton, 'Add option');
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pump();
    }
    expect(find.widgetWithText(OutlinedButton, 'Add option'), findsNothing);
    expect(find.text('Option 5 *'), findsOneWidget);
    await t.ensureVisible(find.text('Delete').last);
    await t.tap(find.text('Delete').last);
    await t.pump();
    expect(find.text('Option 4 *'), findsOneWidget);
    expect(find.text('Option 5 *'), findsNothing);
    for (var i = 0; i < 4; i++) {
      await t.enterText(find.byKey(Key('option-$i')), 'Choice $i');
    }
    await t.ensureVisible(find.text('Preview poll'));
    await t.tap(find.text('Preview poll'));
    await t.pumpAndSettle();
    expect(find.text('Please add an image'), findsNWidgets(3));
  });

  test('timeLeft copy matches the design', () {
    final now = DateTime(2026, 11, 5, 10);
    expect(timeLeft(now.add(const Duration(hours: 23, minutes: 10)), now: now), '23hours left');
    expect(timeLeft(now.add(const Duration(days: 4, hours: 2)), now: now), '4days left');
    expect(timeLeft(now.subtract(const Duration(minutes: 1)), now: now), 'Closed');
  });
}
