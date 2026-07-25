import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../services/auth/google_auth_service.dart';
import '../../services/soul/soul_service.dart';
import '../../services/storage/stores.dart';
import '../../services/update/update_service.dart';

/// Profile & Settings (design screen 15).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;
    final providerLabel = switch (settings.provider) {
      LlmProviderKind.openaiAccount || LlmProviderKind.openai => 'Gemini',
      LlmProviderKind.gemini => 'Gemini',
      LlmProviderKind.claude => 'Claude',
    };

    Future<void> editPersonality() async {
      final controller = TextEditingController(text: settings.personality);
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.pick(
                  ru: 'Характер ассистентки',
                  en: 'Assistant Personality',
                  uz: 'Yordamchi xarakteri',
                ),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.pick(
                  ru: 'Опишите, как MILA должна говорить и вести себя.',
                  en: 'Describe how MILA should talk and behave.',
                  uz: 'MILA qanday gapirishi va o\'zini tutishini yozing.',
                ),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(controller: controller, maxLines: 4, autofocus: true),
              const SizedBox(height: 14),
              GradientButton(
                label: l10n.pick(ru: 'Сохранить', en: 'Save', uz: 'Saqlash'),
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      );
      if (saved == true) {
        final updated = settings.copyWith(
          personalityId: 'custom',
          personality: controller.text.trim(),
        );
        ref.read(settingsProvider.notifier).update((_) => updated);
        ref.read(soulServiceProvider).save(updated, profile);
      }
    }

    Future<void> pickLanguage() async {
      const languages = supportedMilaLanguageNames;
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final l in languages)
                ListTile(
                  title: Text(l),
                  trailing: settings.language == l
                      ? const Icon(Icons.check_rounded, color: MilaColors.cyan)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, l),
                ),
            ],
          ),
        ),
      );
      if (choice != null) {
        final updated = settings.copyWith(language: choice);
        ref.read(settingsProvider.notifier).update((_) => updated);
        ref.read(soulServiceProvider).save(updated, profile);
      }
    }

    Future<void> checkUpdates() async {
      try {
        final update = await ref.read(updateServiceProvider).check();
        if (!context.mounted) return;
        if (!update.updateAvailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.pick(
                  ru: 'MILA уже обновлена.',
                  en: 'MILA is up to date.',
                  uz: 'MILA allaqachon yangilangan.',
                ),
              ),
            ),
          );
          return;
        }
        final open = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF141926),
            title: Text(
              l10n.pick(
                ru: 'Доступно обновление ${update.latestVersion}',
                en: 'Update ${update.latestVersion} available',
                uz: '${update.latestVersion} yangilanishi mavjud',
              ),
            ),
            content: Text(
              update.notes.isEmpty
                  ? l10n.pick(
                      ru: 'Доступна новая версия MILA.',
                      en: 'A newer version of MILA is available.',
                      uz: 'MILAning yangi versiyasi mavjud.',
                    )
                  : update.notes,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  l10n.pick(ru: 'Позже', en: 'Later', uz: 'Keyinroq'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  update.updateRequired
                      ? l10n.pick(ru: 'Обновить', en: 'Update', uz: 'Yangilash')
                      : l10n.pick(
                          ru: 'Скачать',
                          en: 'Download',
                          uz: 'Yuklab olish',
                        ),
                ),
              ),
            ],
          ),
        );
        if (open == true && update.apkUrl.isNotEmpty) {
          await launchUrl(
            Uri.parse(update.apkUrl),
            mode: LaunchMode.externalApplication,
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${l10n.pick(ru: 'Не удалось проверить обновления', en: 'Could not check updates', uz: 'Yangilanishlarni tekshirib bo\'lmadi')}: $e',
            ),
          ),
        );
      }
    }

    Widget tile({
      required IconData icon,
      required String title,
      String? value,
      Color? color,
      VoidCallback? onTap,
      Widget? trailing,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              TileIcon(icon: icon, color: color ?? MilaColors.violet, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: text.bodyLarge)),
              if (value != null)
                Text(
                  value,
                  style: text.bodySmall?.copyWith(color: MilaColors.cyan),
                ),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: MilaColors.textTertiary,
                  ),
            ],
          ),
        ),
      );
    }

    Future<void> editName() async {
      final controller = TextEditingController(text: profile.name);
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.pick(ru: 'Ваше имя', en: 'Your name', uz: 'Ismingiz'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.pick(
                  ru: 'MILA будет обращаться к вам по этому имени.',
                  en: 'MILA will address you by this name.',
                  uz: 'MILA sizga shu ism bilan murojaat qiladi.',
                ),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(controller: controller, autofocus: true),
              const SizedBox(height: 14),
              GradientButton(
                label: l10n.pick(ru: 'Сохранить', en: 'Save', uz: 'Saqlash'),
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      );
      if (saved == true && controller.text.trim().isNotEmpty) {
        final updated = profile.copyWith(name: controller.text.trim());
        ref.read(profileProvider.notifier).save(updated);
        ref.read(soulServiceProvider).save(settings, updated);
      }
    }

    Future<void> editAssistantName() async {
      final controller = TextEditingController(text: settings.assistantName);
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.pick(
                  ru: 'Имя ассистентки',
                  en: 'Assistant name',
                  uz: 'Yordamchi nomi',
                ),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.pick(
                  ru: 'Это имя станет частью личности ассистентки.',
                  en: 'This name becomes part of the assistant soul.',
                  uz: 'Bu nom yordamchining shaxsiyatiga kiradi.',
                ),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(controller: controller, autofocus: true),
              const SizedBox(height: 14),
              GradientButton(
                label: l10n.pick(ru: 'Сохранить', en: 'Save', uz: 'Saqlash'),
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      );
      if (saved == true && controller.text.trim().isNotEmpty) {
        final updated = settings.copyWith(
          assistantName: controller.text.trim(),
        );
        ref.read(settingsProvider.notifier).update((_) => updated);
        ref.read(soulServiceProvider).save(updated, profile);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.pick(
            ru: 'Профиль и настройки',
            en: 'Profile & Settings',
            uz: 'Profil va sozlamalar',
          ),
        ),
      ),
      body: MilaBackground(
        glowTop: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          physics: const BouncingScrollPhysics(),
          children: [
            GlassCard(
              onTap: editName,
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: MilaColors.orbGradient,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.name.isNotEmpty
                          ? profile.name[0].toUpperCase()
                          : 'M',
                      style: text.headlineSmall?.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.isEmpty
                              ? l10n.pick(
                                  ru: 'Пользователь MILA',
                                  en: 'MILA user',
                                  uz: 'MILA foydalanuvchisi',
                                )
                              : profile.name,
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(profile.email, style: text.bodySmall),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: MilaColors.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            l10n.pick(
                              ru: 'Локальный профиль',
                              en: 'Local profile',
                              uz: 'Mahalliy profil',
                            ),
                            style: text.labelSmall?.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            tile(
              icon: Icons.auto_awesome_rounded,
              color: MilaColors.cyan,
              title: l10n.pick(
                ru: 'AI-провайдеры',
                en: 'AI Providers',
                uz: 'AI provayderlar',
              ),
              value: providerLabel,
              onTap: () => context.push('/settings/providers'),
            ),
            tile(
              icon: Icons.badge_outlined,
              color: MilaColors.purple,
              title: l10n.pick(
                ru: 'Имя ассистентки',
                en: 'Assistant name',
                uz: 'Yordamchi nomi',
              ),
              value: settings.assistantName,
              onTap: editAssistantName,
            ),
            tile(
              icon: Icons.record_voice_over_outlined,
              color: MilaColors.violet,
              title: l10n.pick(
                ru: 'Голос и речь',
                en: 'Voice & Speech',
                uz: 'Ovoz va nutq',
              ),
              value: l10n.voiceGender(
                assistantVoiceGenderFromName(settings.voiceName).name,
              ),
              onTap: () => context.push('/settings/providers'),
            ),
            tile(
              icon: Icons.psychology_alt_outlined,
              color: MilaColors.purple,
              title: l10n.pick(
                ru: 'Характер ассистентки',
                en: 'Assistant Personality',
                uz: 'Yordamchi xarakteri',
              ),
              onTap: editPersonality,
            ),
            tile(
              icon: Icons.bookmark_outline_rounded,
              color: MilaColors.pink,
              title: l10n.pick(
                ru: 'Память и приватность',
                en: 'Memory & Privacy',
                uz: 'Xotira va maxfiylik',
              ),
              onTap: () => context.push('/memory'),
            ),
            tile(
              icon: Icons.auto_fix_high_rounded,
              color: MilaColors.violet,
              title: l10n.pick(
                ru: 'Автопамять',
                en: 'Auto Memory',
                uz: 'Avto xotira',
              ),
              trailing: Switch(
                value: settings.autoMemory,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(autoMemory: v)),
              ),
            ),
            tile(
              icon: Icons.extension_outlined,
              color: MilaColors.cyan,
              title: l10n.pick(
                ru: 'Интеграции',
                en: 'Integrations',
                uz: 'Integratsiyalar',
              ),
              onTap: () => context.push('/integrations'),
            ),
            tile(
              icon: Icons.notifications_none_rounded,
              color: MilaColors.violet,
              title: l10n.pick(
                ru: 'Уведомления',
                en: 'Notifications',
                uz: 'Bildirishnomalar',
              ),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.pick(
                      ru: 'Доступ к уведомлениям управляется в настройках системы.',
                      en: 'Manage notification access in system settings.',
                      uz: 'Bildirishnoma ruxsatlari tizim sozlamalarida boshqariladi.',
                    ),
                  ),
                ),
              ),
            ),
            tile(
              icon: Icons.language_rounded,
              color: MilaColors.cyan,
              title: l10n.pick(ru: 'Язык', en: 'Language', uz: 'Til'),
              value: settings.language,
              onTap: pickLanguage,
            ),
            tile(
              icon: Icons.info_outline_rounded,
              color: MilaColors.textSecondary,
              title: l10n.pick(
                ru: 'О MILA',
                en: 'About MILA',
                uz: 'MILA haqida',
              ),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'MILA',
                applicationVersion:
                    '${UpdateService.currentVersion}+${UpdateService.currentVersionCode}',
                applicationLegalese: l10n.pick(
                  ru: 'AI-голосовой помощник.\nГолос: Gemini Live API · Текст: Gemini.',
                  en: 'AI Voice Assistant.\nVoice: Gemini Live API · Text: Gemini.',
                  uz: 'AI ovozli yordamchi.\nOvoz: Gemini Live API · Matn: Gemini.',
                ),
              ),
            ),
            tile(
              icon: Icons.system_update_alt_rounded,
              color: MilaColors.cyan,
              title: l10n.pick(
                ru: 'Проверить обновления',
                en: 'Check for Updates',
                uz: 'Yangilanishlarni tekshirish',
              ),
              value: UpdateService.currentVersion,
              onTap: checkUpdates,
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: l10n.pick(ru: 'Выйти', en: 'Log Out', uz: 'Chiqish'),
              icon: Icons.logout_rounded,
              danger: true,
              onPressed: () async {
                unawaited(ref.read(googleAuthServiceProvider).signOut());
                final secure = ref.read(secureStoreProvider);
                await secure.write(SecureStore.agenticOsAccessToken, '');
                await secure.write(SecureStore.agenticOsAccountRole, '');
                await secure.write(SecureStore.openAiAccountToken, '');
                await secure.write(SecureStore.openAiAccountLabel, '');
                ref.read(profileProvider.notifier).signOut();
                if (!context.mounted) return;
                context.go('/signin');
              },
            ),
          ],
        ),
      ),
    );
  }
}
