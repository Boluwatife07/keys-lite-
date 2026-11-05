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
      'update_new' => 'New update: ${n['data']?['title'] ?? ''}',
      'update_additional' => 'New additional update on ${n['data']?['title'] ?? 'an update'}',
      'event_published' => 'Your event "${n['data']?['title'] ?? ''}" is now live.',
      'event_updated' => 'Important update for ${n['data']?['title'] ?? 'an event'}',
      'event_cancelled' => '${n['data']?['title'] ?? 'An event'} has been canceled',
      'event_draft_reminder' => 'Still planning ${n['data']?['title'] ?? 'your event'}?',
      'event_volunteer_joined' => '$who volunteered for ${n['data']?['title'] ?? 'your event'}',
      'event_completed' => '${n['data']?['title'] ?? 'Your event'} is completed',
      'event_feedback' => 'Your event feedback is in',
      'event_cohost_invite' => 'You have been added as a co-host for ${n['data']?['title'] ?? 'an event'}',
      'event_cohost_accepted' => 'Co-host request accepted by $who',
      'event_cohost_declined' => 'Co-host request declined by $who',
      'event_ticket' => 'Your ticket for ${n['data']?['title'] ?? 'an event'}',
      'event_reminder' => n['data']?['text'] ?? 'Your event is tomorrow',
      'event_feedback_request' => 'How was ${n['data']?['title'] ?? 'the event'}? Rate your experience',
      'event_checked_in' => 'Check-in complete for ${n['data']?['title'] ?? 'your event'}',
      'club_invite' => "$who invited you to join ${n['data']?['club'] ?? 'a club'}",
      'club_welcome' => "You've joined ${n['data']?['club'] ?? 'a club'}",
      'club_announcement' => 'New announcement in ${n['data']?['club'] ?? 'your club'}',
      'club_event' => 'New club event: ${n['data']?['title'] ?? ''}',
      'club_role' => "You're now an admin of ${n['data']?['club'] ?? 'a club'}",
      'club_removed' => "You've been removed from ${n['data']?['club'] ?? 'a club'}",
      'club_closing' => '${n['data']?['club'] ?? 'A club'} will close in 48 hours',
      'club_closed' => '${n['data']?['club'] ?? 'A club'} has been closed',
      'club_transfer_offer' => '$who offered you ownership of ${n['data']?['club'] ?? 'a club'}',
      'club_transfer_declined' => '$who declined ownership of ${n['data']?['club'] ?? 'your club'}',
      'club_new_president' => '$who is the new President of ${n['data']?['club'] ?? 'your club'}',
      'club_full' || 'club_join_attempts' => n['data']?['text'] ?? 'Your club has reached its member limit',
      'club_milestone' => '${n['data']?['club'] ?? 'Your club'} is ${n['data']?['count'] ?? ''} members strong!',
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
                  onTap: switch (n['itemType']) {
                    'post' => () => context.push('/posts/${n['itemId']}'),
                    'update' => () => context.push('/updates/${n['itemId']}'),
                    'event' => () => context.push('/events/${n['itemId']}'),
                    'ticket' => () => context.push('/tickets/${n['itemId']}'),
                    'club' => () => context.push('/clubs/${n['itemId']}'),
                    _ => null,
                  },
                ),
            ]);
          },
        ),
      );
}
