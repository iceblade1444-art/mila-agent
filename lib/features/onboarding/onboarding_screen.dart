import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/storage/stores.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final features = [
      (
        Icons.forum_outlined,
        MilaColors.cyan,
        l10n.pick(
          ru: 'Живое общение',
          en: 'Natural Conversations',
          uz: 'Tabiiy suhbat',
        ),
        l10n.pick(
          ru: 'Говорите естественно, а MILA помогает делать дела.',
          en: 'Talk naturally, get things done.',
          uz: 'Tabiiy gapiring, MILA ishlarni bajarishga yordam beradi.',
        ),
      ),
      (
        Icons.auto_awesome_rounded,
        MilaColors.violet,
        l10n.pick(
          ru: 'Умные действия',
          en: 'Smart Actions',
          uz: 'Aqlli amallar',
        ),
        l10n.pick(
          ru: 'Создавайте задачи, сообщения и напоминания.',
          en: 'Create tasks, send messages, set reminders.',
          uz: 'Vazifalar, xabarlar va eslatmalar yarating.',
        ),
      ),
      (
        Icons.bookmark_outline_rounded,
        MilaColors.purple,
        l10n.pick(
          ru: 'Помнит важное',
          en: 'Remembers What Matters',
          uz: 'Muhim narsalarni eslaydi',
        ),
        l10n.pick(
          ru: 'MILA хранит проверенные факты, чтобы вы не держали всё в голове.',
          en: 'MILA remembers verified facts so you don\'t have to.',
          uz: 'MILA tekshirilgan faktlarni eslab qoladi.',
        ),
      ),
      (
        Icons.shield_outlined,
        MilaColors.pink,
        l10n.pick(
          ru: 'Безопасность внутри',
          en: 'Secure By Design',
          uz: 'Xavfsiz tuzilma',
        ),
        l10n.pick(
          ru: 'Ваши данные остаются приватными и под вашим контролем.',
          en: 'Your data stays private and under your control.',
          uz: 'Maʼlumotlaringiz maxfiy va sizning nazoratingizda.',
        ),
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
                Text(
                  l10n.pick(
                    ru: 'Знакомьтесь, MILA',
                    en: 'Meet MILA',
                    uz: 'MILA bilan tanishing',
                  ),
                  style: text.headlineLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.pick(
                    ru: 'Ваш голосовой AI-помощник',
                    en: 'Your AI Voice Assistant',
                    uz: 'Sizning ovozli AI yordamchingiz',
                  ),
                  style: text.bodyMedium?.copyWith(
                    color: MilaColors.textSecondary,
                  ),
                ),
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
                                      Text(subtitle, style: text.bodySmall),
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
                  label: l10n.pick(
                    ru: 'Начать',
                    en: 'Get Started',
                    uz: 'Boshlash',
                  ),
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
