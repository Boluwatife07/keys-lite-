import 'package:go_router/go_router.dart';
import 'core/models.dart';
import 'features/auth/auth_screens.dart';
import 'features/entry/entry_screens.dart';
import 'features/home/compose_placeholder.dart';
import 'features/home/home_shell.dart';
import 'features/home/profile_screen.dart';
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
        GoRoute(path: '/feed/compose', builder: (_, s) => ComposePlaceholder(text: _m(s)['text'])),
      ],
    );
