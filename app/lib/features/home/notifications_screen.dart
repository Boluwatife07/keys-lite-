import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../feed/feed_screens.dart' show EmptyState;
import '../feed/social.dart';

/// In-app notifications (FED-19). Final copy and grouping come from the Notifications task.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static String text(Map<String, dynamic> n) {
    final who = (n['actor']?['name'] as String?) ?? 'Someone';
    return switch (n['type']) {
      'post_like' => '$who liked your post',
      'comment_like' => '$who liked your comment',
      'post_comment' => '$who commented on your post',
      'comment_reply' => '$who replied to your comment',
      'mention' => '$who tagged you',
      'poll_closed' => 'A poll you took part in has closed. See the results.',
      _ => 'You have a new notification',
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KColors.surfaceDefault,
        appBar: AppBar(backgroundColor: KColors.surfaceDefault, surfaceTintColor: Colors.transparent, title: Text('Notifications', style: KText.headingXSmall)),
        body: FutureBuilder(
          future: context.api.get('/notifications'),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final list = List<Map<String, dynamic>>.from(s.data!['notifications']);
            if (list.isEmpty) return const EmptyState(title: 'No notifications yet', body: 'Likes, comments and tags will show here.');
            return ListView(children: [
              for (final n in list)
                ListTile(
                  leading: Avatar(n['actor']?['photoUrl']),
                  title: Text(text(n), style: KText.paragraphMedium),
                  subtitle: Text(timeAgo(DateTime.parse(n['createdAt']).toLocal())),
                  onTap: n['itemType'] == 'post' ? () => context.push('/posts/${n['itemId']}') : null,
                ),
            ]);
          },
        ),
      );
}
