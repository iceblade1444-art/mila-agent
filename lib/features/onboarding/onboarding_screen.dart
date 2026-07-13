import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/storage/stores.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    const features = [
      (
        Icons.forum_outlined,
        MilaColors.cyan,
        'Natural Conversations',
        'Talk naturally, get things done.'
      ),
      (
        Icons.auto_awesome_rounded,
        MilaColors.violet,
        'Smart Actions',
        'Create tasks, send messages, set reminders.'
      ),
      (
        Icons.bookmark_outline_rounded,
        MilaColors.purple,
        'Remembers What Matters',
        'MILA remembers verified facts so you don\'t have to.'
      ),
      (
        Icons.shield_outlined,
        MilaColors.pink,
        'Secure By Design',
        'Your data stays private and under your control.'
      ),
    ];

    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text('Meet MILA', style: text.headlineLarge),
                const SizedBox(height: 4),
                Text('Your AI Voice Assistant',
                    style: text.bodyMedium
                        ?.copyWith(color: MilaColors.textSecondary)),
                const SizedBox(height: 8),
                const Expanded(
                  flex: 5,
                  child: Center(child: VoiceOrb(size: 180)),
                ),
                Expanded(
                  flex: 7,
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      for (final (icon, color, title, subtitle) in features)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            child: Row(
                              children: [
                                TileIcon(icon: icon, color: color),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: text.titleSmall),
                                      const SizedBox(height: 3),
                                      Text(subtitle,
                                          style: text.bodySmall),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                GradientButton(
                  label: 'Get Started',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(onboarded: true));
                    context.go('/assistant-setup');
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
