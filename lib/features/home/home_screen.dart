import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/connectivity/connectivity_provider.dart';
import '../../services/llm/llm_service.dart';
import '../../services/storage/stores.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).value ?? true;
    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          bottom: false,
          child: online ? const _HomeBody() : const _OfflineBody(),
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';

    void ask(String prompt) {
      context.go('/chat');
      Future.microtask(() => ref.read(llmServiceProvider).send(prompt));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      physics: const BouncingScrollPhysics(),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.menu_rounded),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => context.push('/settings'),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: MilaColors.orbGradient,
                ),
                alignment: Alignment.center,
                child: Text(
                  profile.name.isNotEmpty
                      ? profile.name[0].toUpperCase()
                      : 'M',
                  style:
                      text.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('$greeting, ${profile.name.isEmpty ? 'there' : profile.name}',
            style: text.headlineSmall),
        const SizedBox(height: 4),
        Text('How can I help you today?', style: text.bodySmall),
        const SizedBox(height: 20),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 26),
          radius: 24,
          onTap: () => context.push('/voice'),
          child: Column(
            children: [
              Text('Ask MILA', style: text.titleLarge),
              const SizedBox(height: 4),
              Text('Tap the orb or speak', style: text.bodySmall),
              const SizedBox(height: 16),
              const AdaptiveOrb(size: 150),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionHeader(
            title: 'Suggestions',
            action: 'See all',
            onAction: () => context.go('/command')),
        const SizedBox(height: 12),
        for (final (icon, prompt) in [
          (Icons.mark_email_unread_outlined, 'Summarize my unread emails'),
          (
            Icons.event_note_outlined,
            'Create a task for product meeting tomorrow at 10 AM'
          ),
          (Icons.checklist_rounded, 'Give me a short briefing on my open tasks'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              onTap: () => ask(prompt),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: MilaColors.cyan),
                  const SizedBox(width: 12),
                  Expanded(child: Text(prompt, style: text.bodyMedium)),
                  const Icon(Icons.mic_none_rounded,
                      size: 18, color: MilaColors.textTertiary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Offline state (screen 17 of the design).
class _OfflineBody extends ConsumerWidget {
  const _OfflineBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: MilaColors.cardBorder, width: 1.5),
            ),
            child: const Icon(Icons.wifi_off_rounded,
                size: 36, color: MilaColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Text('No Internet Connection', style: text.headlineSmall),
          const SizedBox(height: 10),
          Text(
            'MILA is offline right now. Some features are unavailable until you\'re back online.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: 'Try Again',
            expanded: false,
            onPressed: () => ref.invalidate(onlineProvider),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => context.go('/tasks'),
            child: Text('Work Offline',
                style: text.labelLarge?.copyWith(color: MilaColors.cyan)),
          ),
          const Spacer(),
          const AdaptiveOrb(size: 150, mood: OrbMood.offline),
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}
