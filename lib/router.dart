import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/sign_in_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/command/command_center_screen.dart';
import 'features/home/home_screen.dart';
import 'features/integrations/integrations_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/onboarding/assistant_setup_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/permissions/permissions_screen.dart';
import 'features/settings/providers_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/shell_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/tasks/tasks_screen.dart';
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
      GoRoute(
        path: '/integrations',
        builder: (_, _) => const IntegrationsScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/providers',
        builder: (_, _) => const ProvidersScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ShellScreen(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/command',
                builder: (_, _) => const CommandCenterScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/tasks', builder: (_, _) => const TasksScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});
