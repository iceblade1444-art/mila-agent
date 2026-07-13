import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../services/storage/stores.dart';
import 'orb_skin_picker.dart';
import '../../services/update/update_service.dart';

/// Profile & Settings (design screen 15).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    final settings = ref.watch(settingsProvider);
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
                'Assistant Personality',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Describe how MILA should talk and behave.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(controller: controller, maxLines: 4, autofocus: true),
              const SizedBox(height: 14),
              GradientButton(
                label: 'Save',
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      );
      if (saved == true) {
        ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(personality: controller.text.trim()));
      }
    }

    Future<void> pickLanguage() async {
      const languages = ['Русский', 'English', 'O\'zbekcha'];
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
        ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(language: choice));
      }
    }

    Future<void> checkUpdates() async {
      try {
        final update = await ref.read(updateServiceProvider).check();
        if (!context.mounted) return;
        if (!update.updateAvailable) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('MILA is up to date.')));
          return;
        }
        final open = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF141926),
            title: Text('Update ${update.latestVersion} available'),
            content: Text(
              update.notes.isEmpty
                  ? 'A newer version of MILA is available.'
                  : update.notes,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(update.updateRequired ? 'Update' : 'Download'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not check updates: $e')));
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
                'Your name',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'MILA will address you by this name.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(controller: controller, autofocus: true),
              const SizedBox(height: 14),
              GradientButton(
                label: 'Save',
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      );
      if (saved == true && controller.text.trim().isNotEmpty) {
        ref
            .read(profileProvider.notifier)
            .save(profile.copyWith(name: controller.text.trim()));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
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
                          profile.name.isEmpty ? 'MILA user' : profile.name,
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
                            'Local profile',
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
              title: 'AI Providers',
              value: providerLabel,
              onTap: () => context.push('/settings/providers'),
            ),
            tile(
              icon: Icons.record_voice_over_outlined,
              color: MilaColors.violet,
              title: 'Voice & Speech',
              value: settings.voiceName,
              onTap: () => context.push('/settings/providers'),
            ),
            tile(
              icon: Icons.psychology_alt_outlined,
              color: MilaColors.purple,
              title: 'Assistant Personality',
              onTap: editPersonality,
            ),
            tile(
              icon: Icons.bookmark_outline_rounded,
              color: MilaColors.pink,
              title: 'Memory & Privacy',
              onTap: () => context.push('/memory'),
            ),
            tile(
              icon: Icons.auto_fix_high_rounded,
              color: MilaColors.violet,
              title: 'Auto Memory',
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
              title: 'Integrations',
              onTap: () => context.push('/integrations'),
            ),
            tile(
              icon: Icons.notifications_none_rounded,
              color: MilaColors.violet,
              title: 'Notifications',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Manage notification access in system settings.',
                  ),
                ),
              ),
            ),
            tile(
              icon: Icons.blur_on_rounded,
              color: MilaColors.purple,
              title: 'Orb Skin',
              value: settings.orbSkin[0].toUpperCase() +
                  settings.orbSkin.substring(1),
              onTap: () => showOrbSkinPicker(context, ref),
            ),
            tile(
              icon: Icons.language_rounded,
              color: MilaColors.cyan,
              title: 'Language',
              value: settings.language,
              onTap: pickLanguage,
            ),
            tile(
              icon: Icons.info_outline_rounded,
              color: MilaColors.textSecondary,
              title: 'About MILA',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'MILA',
                applicationVersion: '1.0.0',
                applicationLegalese:
                    'AI Voice Assistant.\nVoice: Gemini Live API · Text: Gemini.',
              ),
            ),
            tile(
              icon: Icons.system_update_alt_rounded,
              color: MilaColors.cyan,
              title: 'Check for Updates',
              value: UpdateService.currentVersion,
              onTap: checkUpdates,
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Log Out',
              icon: Icons.logout_rounded,
              danger: true,
              onPressed: () {
                ref.read(profileProvider.notifier).signOut();
                context.go('/signin');
              },
            ),
          ],
        ),
      ),
    );
  }
}
