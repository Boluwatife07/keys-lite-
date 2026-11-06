import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/feed_models.dart';
import 'package:keys_lite/features/feed/feed_screens.dart';
import 'package:keys_lite/features/polls/create_poll.dart';
import 'catalog.dart';

const opts = ['Community e-bikes', 'Greener community garden or mini-park', 'Waste bins with recycling sections', 'A socialising community event', 'A new parking system'];
const votes = [825, 412, 412, 0, 1];

Map<String, dynamic> poll({bool voted = false, bool closed = false, bool multi = false}) => {
      'id': 'p1', 'kind': 'poll',
      'author': {'id': 'u2', 'name': 'Jules Winnfield', 'firstName': 'Jules', 'photoUrl': null, 'verified': true, 'role': 'Chair'},
      'text': '', 'mentions': [], 'attachment': 'none', 'photos': [],
      'poll': {
        'question': 'Which one of these project would improve Thames street?',
        'promise': 'Agree which project the committee takes to the council first.',
        'multi': multi,
        'closesAt': DateTime.now().add(const Duration(hours: 23, minutes: 30)).toIso8601String(),
        'closed': closed,
        'totalVotes': 1650,
        'myVote': voted ? ['o0'] : null,
        'canVote': !voted && !closed,
        'resultsVisible': voted || closed,
        'options': [
          for (var i = 0; i < opts.length; i++)
            {'id': 'o$i', 'text': opts[i], 'votes': voted || closed ? votes[i] : null, 'percent': voted || closed ? (votes[i] * 100 / 1650).round() : null, 'winner': closed && i == 0},
        ],
      },
      'likeCount': 273, 'commentCount': 89, 'likedByMe': false, 'isMine': false,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(), 'editedAt': null, 'shareLink': 'https://keys.app/post/p1',
    };

void detail(String name, Map<String, dynamic> p, {Act? act}) => shot(name, () => PostDetailScreen(id: 'p1', initial: Post(p)), setup: (h) {
      h.fake.on('GET /posts/p1', (_, _) => {'post': p});
      h.fake.on('GET /posts/p1/comments', (_, _) => {'comments': []});
    }, act: act);

void main() {
  shot('poll_create', () => const CreatePollScreen());
  detail('poll_no_vote', poll());
  detail('poll_option_selected', poll(), act: (t, h) async {
    await t.tap(find.text(opts[0]));
    await t.pump();
  });
  detail('poll_voted', poll(voted: true));
  detail('poll_closed', poll(closed: true));
}
