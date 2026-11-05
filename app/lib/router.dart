import 'package:go_router/go_router.dart';
import 'core/models.dart';
import 'features/auth/auth_screens.dart';
import 'features/entry/entry_screens.dart';
import 'core/feed_models.dart';
import 'features/feed/compose.dart';
import 'features/feed/feed_screens.dart';
import 'features/feed/post_card.dart';
import 'features/community/board_screens.dart';
import 'features/community/proposals.dart';
import 'features/home/home_shell.dart';
import 'features/home/notifications_screen.dart';
import 'features/polls/create_poll.dart';
import 'features/profile/profile_screens.dart';
import 'features/profile/settings_screens.dart';
import 'features/onboarding/community_screens.dart';
import 'features/onboarding/profile_screens.dart';
import 'features/verification/verification_screens.dart';

Map<String, dynamic> _m(GoRouterState s) => Map<String, dynamic>.from((s.extra as Map?) ?? {});

GoRouter buildRouter({String initial = '/', List<RouteBase> extraRoutes = const []}) => GoRouter(
      initialLocation: initial,
      routes: [
        ...extraRoutes,
        GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/intro', builder: (_, _) => const IntroCarousel()),
        GoRoute(path: '/choose', builder: (_, _) => const ChooseAccountScreen()),
        GoRoute(path: '/vendor', builder: (_, _) => const VendorEntryScreen()),
        GoRoute(path: '/auth/email', builder: (_, _) => const EmailScreen()),
        GoRoute(path: '/auth/verify', builder: (_, s) => VerifyCodeScreen(email: _m(s)['email'], purpose: _m(s)['purpose'] ?? 'signup')),
        GoRoute(path: '/auth/details', builder: (_, s) => CreateAccountScreen(ticket: _m(s)['ticket'])),
        GoRoute(path: '/auth/password', builder: (_, s) => PasswordLoginScreen(email: _m(s)['email'], firstName: _m(s)['firstName'] ?? '')),
        GoRoute(path: '/auth/forgot', builder: (_, s) => ForgotPasswordScreen(email: _m(s)['email'])),
        GoRoute(path: '/auth/forgot/new', builder: (_, s) => NewPasswordScreen(ticket: _m(s)['ticket'])),
        GoRoute(path: '/auth/forgot/done', builder: (_, _) => const PasswordResetDoneScreen()),
        GoRoute(path: '/onboarding/name', builder: (_, _) => const ConfirmNameScreen()),
        GoRoute(path: '/onboarding/address', builder: (_, _) => const AddressScreen()),
        GoRoute(path: '/onboarding/match', builder: (_, s) => MatchScreen(result: s.extra as MatchResult)),
        GoRoute(path: '/onboarding/area', builder: (_, _) => const AreaKindScreen()),
        GoRoute(path: '/onboarding/street', builder: (_, _) => const ConfirmStreetScreen()),
        GoRoute(path: '/onboarding/development', builder: (_, _) => const DevelopmentNameScreen()),
        GoRoute(path: '/onboarding/development/similar', builder: (_, s) => SimilarDevelopmentsScreen(name: _m(s)['name'], similar: List<Map<String, dynamic>>.from(_m(s)['similar']))),
        GoRoute(path: '/onboarding/development/join', builder: (_, s) => JoinDevelopmentScreen(developmentId: s.extra as String)),
        GoRoute(path: '/onboarding/development/shape', builder: (_, s) => ShapeDevelopmentScreen(name: s.extra as String)),
        GoRoute(path: '/onboarding/home-type', builder: (_, _) => const HomeTypeScreen()),
        GoRoute(path: '/onboarding/building/pick', builder: (_, s) => PickBuildingScreen(buildings: List<Map<String, dynamic>>.from(s.extra as List))),
        GoRoute(path: '/onboarding/building/name', builder: (_, _) => const NameBuildingScreen()),
        GoRoute(path: '/onboarding/live', builder: (_, s) => CommunityLiveScreen(screen: _m(s)['screen'], name: _m(s)['name'], building: _m(s)['building'] == true)),
        GoRoute(path: '/onboarding/profile', builder: (_, _) => const ProfileSetupScreen()),
        GoRoute(path: '/onboarding/verify', builder: (_, _) => const VerifyPromptScreen()),
        GoRoute(path: '/onboarding/invite', builder: (_, _) => const InviteScreen()),
        GoRoute(path: '/verify', builder: (_, s) => VerifyMethodScreen(from: s.extra as String?)),
        GoRoute(path: '/verify/card', builder: (_, s) => CardFormScreen(from: _m(s)['from'], homeAddress: _m(s)['home'] ?? '')),
        GoRoute(path: '/verify/success', builder: (_, s) => VerifySuccessScreen(from: s.extra as String?)),
        GoRoute(path: '/verify/mismatch', builder: (_, s) => VerifyMismatchScreen(result: _m(s))),
        GoRoute(path: '/verify/contest', builder: (_, s) => ContestScreen(from: s.extra as String?)),
        GoRoute(path: '/verify/review', builder: (_, s) => UnderReviewScreen(reviewCase: Map<String, dynamic>.from(_m(s)['case']), from: _m(s)['from'])),
        GoRoute(path: '/verify/why', builder: (_, _) => const VerifyExplainerScreen()),
        GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
        GoRoute(path: '/profile', builder: (_, _) => const MyProfileScreen()),
        GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
        GoRoute(path: '/profile/email', builder: (_, _) => const ChangeEmailScreen()),
        GoRoute(path: '/profile/address', builder: (_, _) => const ChangeAddressScreen()),
        GoRoute(path: '/users/:id', builder: (_, s) => OtherProfileScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/settings/account', builder: (_, _) => const AccountScreen()),
        GoRoute(path: '/settings/notifications', builder: (_, _) => const NotificationSettingsScreen()),
        GoRoute(path: '/settings/privacy', builder: (_, _) => const PrivacyScreen()),
        GoRoute(path: '/settings/blocked', builder: (_, _) => const PeopleListScreen(blocked: true)),
        GoRoute(path: '/settings/muted', builder: (_, _) => const PeopleListScreen(blocked: false)),
        GoRoute(path: '/settings/password', builder: (_, _) => const PasswordScreen(create: false)),
        GoRoute(path: '/settings/password/create', builder: (_, _) => const PasswordScreen(create: true)),
        GoRoute(path: '/settings/deactivate', builder: (_, _) => const DeactivateScreen()),
        GoRoute(path: '/feed/compose', builder: (_, s) => ComposeScreen(initialText: _m(s)['text'], edit: _m(s)['edit'] as Post?, welcomeImage: _m(s)['welcomeImage'] == true)),
        GoRoute(path: '/posts/:id', builder: (_, s) => PostDetailScreen(id: s.pathParameters['id']!, initial: s.extra is Post ? s.extra as Post : null)),
        GoRoute(path: '/posts/:id/likes', builder: (_, s) => LikesScreen(path: '/posts/${s.pathParameters['id']}/likes')),
        GoRoute(path: '/polls/create', builder: (_, _) => const CreatePollScreen()),
        GoRoute(path: '/polls/preview', builder: (_, s) => PollPreviewScreen(draft: _m(s))),
        GoRoute(path: '/media', builder: (_, s) => MediaViewer(urls: List<String>.from(_m(s)['urls']), index: _m(s)['index'] ?? 0, caption: _m(s)['caption'])),
        GoRoute(path: '/video', builder: (_, s) => VideoScreen(url: s.extra as String)),
        GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
        GoRoute(path: '/board', builder: (_, _) => const BoardScreen()),
        GoRoute(path: '/board/join', builder: (_, s) => JoinBoardScreen(create: _m(s)['create'] == true, role: _m(s)['role'], seatId: _m(s)['seatId'])),
        GoRoute(path: '/board/done', builder: (_, s) => BoardDoneScreen(title: _m(s)['title'], message: _m(s)['message'], pending: _m(s)['pending'] == true)),
        GoRoute(path: '/board/manage', builder: (_, _) => const ManageSeatsScreen()),
        GoRoute(path: '/board/tiers', builder: (_, _) => const TiersScreen()),
        GoRoute(path: '/board/exit', builder: (_, _) => const ExitBoardScreen()),
        GoRoute(path: '/board/invite', builder: (_, _) => const BoardInviteScreen()),
        GoRoute(path: '/board/propose', builder: (_, s) => ProposeScreen(type: _m(s)['type'], subject: Map<String, dynamic>.from(_m(s)['subject']), seats: List<Map<String, dynamic>>.from(_m(s)['seats']))),
        GoRoute(path: '/board/proposals/:id', builder: (_, s) => ProposalDetailScreen(id: s.pathParameters['id']!)),
      ],
    );
