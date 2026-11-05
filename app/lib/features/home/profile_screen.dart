import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// My profile (first cut). AVW-08.2: unverified badge and "Get verified".
class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final me = s.me;
        if (me == null) return const SizedBox.shrink();
        return KeysScaffold(
          gradient: false,
          header: const KeysHeader(),
          body: Column(children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: KColors.surfaceSubtle,
              backgroundImage: me.photoUrl == null ? null : NetworkImage(context.api.absolute(me.photoUrl!)),
            ),
            const SizedBox(height: 12),
            Text(me.fullName, style: KText.headingSmall),
            const SizedBox(height: 4),
            Text(me.communityName, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            if (!me.isVerified) ...[
              const SizedBox(height: 12),
              UnverifiedBadge(underReview: me.underReview),
            ],
            if (me.bio != null && me.bio!.isNotEmpty) ...[const SizedBox(height: 16), Text(me.bio!, textAlign: TextAlign.center, style: KText.paragraphMedium)],
            const SizedBox(height: 24),
            if (!me.isVerified)
              KeysButton(me.underReview ? 'View review status' : 'Get verified', onPressed: () => context.push('/verify')),
            const SizedBox(height: 12),
            KeysButton('Share profile', variant: ButtonVariant.outline, onPressed: () => context.deps.sharer.share('https://keys.app/profile/${me.id}')),
            const SizedBox(height: 32),
            KeysButton('Log out', variant: ButtonVariant.ghost, onPressed: () async {
              await s.logout();
              if (context.mounted) context.go('/auth/email');
            }),
          ]),
        );
      },
    );
  }
}

/// AVW-09.3: the "Unverified" label.
class UnverifiedBadge extends StatelessWidget {
  const UnverifiedBadge({super.key, this.underReview = false});
  final bool underReview;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFFFF1E5), borderRadius: BorderRadius.circular(KRadius.pill)),
        child: Text(underReview ? 'Under review' : 'Unverified', style: KText.paragraphMediumSmall.copyWith(color: const Color(0xFFB54708))),
      );
}
