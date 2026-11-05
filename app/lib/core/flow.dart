import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'models.dart';
import 'scope.dart';

/// Sends the user to the screen for their saved onboarding step, so leaving
/// part-way resumes at the first unfinished step (ONB-26).
Future<void> goToCurrentStep(BuildContext context) async {
  final s = context.session;
  final me = await s.refresh();
  if (!context.mounted) return;
  switch (me.onboardingStep) {
    case 'account':
      context.go('/onboarding/name');
    case 'address':
      context.go('/onboarding/address');
    case 'community':
      final r = await context.api.post('/onboarding/match', {if (s.pendingCommunityCode != null) 'communityCode': s.pendingCommunityCode});
      if (!context.mounted) return;
      context.go('/onboarding/match', extra: MatchResult(Map<String, dynamic>.from(r['match'])));
    case 'home_type':
      context.go('/onboarding/home-type');
    case 'profile':
      context.go('/onboarding/profile');
    default:
      // ONB-26.2: joined but skipped verification -> Home, verification not forced.
      context.go('/home');
  }
}
