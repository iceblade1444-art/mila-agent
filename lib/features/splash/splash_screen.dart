import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/storage/stores.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1900), () => unawaited(_next()));
  }

  Future<void> _next() async {
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final profile = ref.read(profileProvider);
    final accountToken =
        await ref
            .read(secureStoreProvider)
            .read(SecureStore.agenticOsAccessToken) ??
        '';
    if (!mounted) return;
    if (!settings.onboarded) {
      context.go('/onboarding');
    } else if (!profile.signedIn || accountToken.isEmpty) {
      if (profile.signedIn) ref.read(profileProvider.notifier).signOut();
      context.go('/signin');
    } else if (!settings.assistantSetupDone) {
      context.go('/assistant-setup');
    } else if (!settings.permissionsDone) {
      context.go('/permissions');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                const AdaptiveOrb(size: 190, mood: OrbMood.idle),
                const SizedBox(height: 28),
                Text(
                  'MILA',
                  style: text.displayLarge?.copyWith(letterSpacing: 10),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.pick(
                    ru: 'AI ГОЛОСОВОЙ ПОМОЩНИК',
                    en: 'AI VOICE ASSISTANT',
                    uz: 'AI OVOZLI YORDAMCHI',
                  ),
                  style: text.labelSmall?.copyWith(
                    letterSpacing: 4,
                    color: MilaColors.cyan,
                  ),
                ),
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    l10n.pick(
                      ru: 'Умная голосовая помощница, которая слушает, понимает и помогает делать дела.',
                      en: 'Your intelligent voice companion that listens, understands, and gets things done.',
                      uz: 'Sizni tinglaydigan, tushunadigan va ishlarni bajarishga yordam beradigan ovozli yordamchi.',
                    ),
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: MilaColors.textSecondary,
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (icon, label) in [
                      (
                        Icons.graphic_eq_rounded,
                        l10n.pick(ru: 'Слушает', en: 'Listen', uz: 'Tinglaydi'),
                      ),
                      (
                        Icons.psychology_alt_outlined,
                        l10n.pick(
                          ru: 'Понимает',
                          en: 'Understand',
                          uz: 'Tushunadi',
                        ),
                      ),
                      (
                        Icons.bolt_rounded,
                        l10n.pick(ru: 'Делает', en: 'Act', uz: 'Bajaradi'),
                      ),
                      (
                        Icons.bookmark_outline_rounded,
                        l10n.pick(ru: 'Помнит', en: 'Remember', uz: 'Eslaydi'),
                      ),
                      (
                        Icons.shield_outlined,
                        l10n.pick(ru: 'Защищает', en: 'Protect', uz: 'Himoya'),
                      ),
                    ]) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: Column(
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: MilaColors.textSecondary,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              label,
                              style: text.labelSmall?.copyWith(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
