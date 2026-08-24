import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/sign_in_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/command/command_center_screen.dart';
import 'features/day/day_plan_screen.dart';
import 'features/home/home_screen.dart';
import 'features/integrations/integrations_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/more/more_screen.dart';
import 'features/onboarding/assistant_setup_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/permissions/permissions_screen.dart';
import 'features/settings/providers_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/shell_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/team/team_chat_screen.dart';
import 'features/team/team_thread_screen.dart';
import 'features/voice/voice_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/assistant-setup',
        builder: (_, _) => const AssistantSetupScreen(),
      ),
      GoRoute(
        path: '/permissions',
        builder: (_, _) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/voice',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const VoiceScreen(),
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: child,
            ),
          ),
        ),
      ),
      GoRoute(path: '/memory', builder: (_, _) => const MemoryScreen()),
      GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
      GoRoute(
        path: '/command',
        builder: (_, _) => const CommandCenterScreen(),
      ),
      GoRoute(path: '/team', builder: (_, _) => const TeamChatScreen()),
      GoRoute(
        path: '/team/:id',
        builder: (_, state) => TeamThreadScreen(
          conversationId: state.pathParameters['id'] ?? '',
          title: state.extra is String ? state.extra! as String : 'Chat',
        ),
      ),
      GoRoute(
        path: '/integrations',
        builder: (_, _) => const IntegrationsScreen(),
      ),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/providers',
        builder: (_, _) => const ProvidersScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ShellScreen(shell: shell),
        // Four named tabs. Chat and the command centre left the bar on
        // purpose: the composer sits above it on every screen and is how you
        // reach MILA, so a separate Chat tab was a second door to the same
        // room. Both are still routes, pushed from the composer and from More.
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/tasks', builder: (_, _) => const TasksScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/day', builder: (_, _) => const DayPlanScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});
