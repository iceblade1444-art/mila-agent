import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/connectivity/connectivity_provider.dart';
import '../../services/agentic/agentic_os_service.dart';
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
    final l10n = context.l10n;
    final profile = ref.watch(profileProvider);
    final dashboardState = ref.watch(agenticDashboardProvider);
    final hour = DateTime.now().hour;
    final greeting = l10n.greeting(hour);

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
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'M',
                  style: text.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '$greeting, ${profile.name.isEmpty ? l10n.pick(ru: 'друг', en: 'there', uz: 'do\'stim') : profile.name}',
          style: text.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.pick(
            ru: 'Чем я могу помочь сегодня?',
            en: 'How can I help you today?',
            uz: 'Bugun qanday yordam bera olaman?',
          ),
          style: text.bodySmall,
        ),
        const SizedBox(height: 20),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 26),
          radius: 24,
          onTap: () => context.push('/voice'),
          child: Column(
            children: [
              Text(
                l10n.pick(
                  ru: 'Спросить MILA',
                  en: 'Ask MILA',
                  uz: 'MILA’dan so\'rang',
                ),
                style: text.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.pick(
                  ru: 'Нажмите на сферу или говорите',
                  en: 'Tap the orb or speak',
                  uz: 'Sferani bosing yoki gapiring',
                ),
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              const AdaptiveOrb(size: 150),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _AgenticDashboardCard(state: dashboardState),
        const SizedBox(height: 24),
        SectionHeader(
          title: l10n.pick(ru: 'Подсказки', en: 'Suggestions', uz: 'Takliflar'),
          action: l10n.pick(ru: 'Все', en: 'See all', uz: 'Hammasi'),
          onAction: () => context.go('/command'),
        ),
        const SizedBox(height: 12),
        for (final (icon, prompt) in [
          (
            Icons.mark_email_unread_outlined,
            l10n.pick(
              ru: 'Сделай краткое резюме непрочитанных писем',
              en: 'Summarize my unread emails',
              uz: 'O\'qilmagan xatlarimni qisqa jamla',
            ),
          ),
          (
            Icons.event_note_outlined,
            l10n.pick(
              ru: 'Создай задачу для встречи по продукту завтра в десять утра',
              en: 'Create a task for product meeting tomorrow at 10 AM',
              uz: 'Ertaga soat o\'nda mahsulot uchrashuvi uchun vazifa yarat',
            ),
          ),
          (
            Icons.checklist_rounded,
            l10n.pick(
              ru: 'Дай короткий бриф по открытым задачам',
              en: 'Give me a short briefing on my open tasks',
              uz: 'Ochiq vazifalarim bo\'yicha qisqa brif ber',
            ),
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              onTap: () => ask(prompt),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: MilaColors.cyan),
                  const SizedBox(width: 12),
                  Expanded(child: Text(prompt, style: text.bodyMedium)),
                  const Icon(
                    Icons.mic_none_rounded,
                    size: 18,
                    color: MilaColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AgenticDashboardCard extends ConsumerWidget {
  const _AgenticDashboardCard({required this.state});

  final AgenticDashboardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final dashboard = state.dashboard;
    final calendar = ref.watch(googleCalendarStatusProvider);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                state.connected
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                color: state.connected
                    ? MilaColors.success
                    : MilaColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Agentic OS', style: text.titleMedium),
                    Text(
                      dashboard == null
                          ? l10n.pick(
                              ru: 'Подключите аккаунт в AI Providers',
                              en: 'Connect your account in AI Providers',
                              uz: 'Hisobni AI Providers bo\'limida ulang',
                            )
                          : '${dashboard.ownerName.isEmpty ? dashboard.accountLabel : dashboard.ownerName} · ${dashboard.workspaceName}',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () =>
                    ref.read(agenticDashboardProvider.notifier).refresh(),
                icon: state.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (state.error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.error,
              style: text.bodySmall?.copyWith(color: MilaColors.danger),
            ),
          ],
          if (dashboard != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: l10n.pick(
                      ru: 'Готовность',
                      en: 'Readiness',
                      uz: 'Tayyorlik',
                    ),
                    value: '${dashboard.readinessScore}%',
                    icon: Icons.verified_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: l10n.pick(ru: 'Открыто', en: 'Open', uz: 'Ochiq'),
                    value: '${dashboard.openTasks}',
                    icon: Icons.view_kanban_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: l10n.pick(ru: 'Блоки', en: 'Blocked', uz: 'Blok'),
                    value: '${dashboard.blockedTasks}',
                    icon: Icons.report_gmailerrorred_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRow(
              icon: Icons.hub_rounded,
              label: l10n.pick(
                ru: 'Obsidian graph',
                en: 'Obsidian graph',
                uz: 'Obsidian grafigi',
              ),
              value:
                  '${dashboard.knowledgeNotes} notes · MCP ${dashboard.obsidianMcpStatus}',
            ),
            _StatusRow(
              icon: Icons.mic_rounded,
              label: l10n.pick(
                ru: 'MILA Live',
                en: 'MILA Live',
                uz: 'MILA Live',
              ),
              value: dashboard.milaVoiceConfigured
                  ? dashboard.liveModel
                  : l10n.pick(
                      ru: 'Gemini не настроен',
                      en: 'Gemini is not configured',
                      uz: 'Gemini sozlanmagan',
                    ),
            ),
            _StatusRow(
              icon: Icons.calendar_month_outlined,
              label: 'Google Calendar',
              value: calendar.asData?.value.connected == true
                  ? l10n.pick(
                      ru: 'Синхронизирован',
                      en: 'Synchronized',
                      uz: 'Sinxronlangan',
                    )
                  : l10n.pick(
                      ru: 'Не подключён',
                      en: 'Not connected',
                      uz: 'Ulanmagan',
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: l10n.pick(
                      ru: 'Открыть задачи',
                      en: 'Open tasks',
                      uz: 'Vazifalar',
                    ),
                    onPressed: () => context.go('/tasks'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: l10n.pick(
                    ru: 'Календарь',
                    en: 'Calendar',
                    uz: 'Kalendar',
                  ),
                  onPressed: () => context.push('/calendar'),
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => context.go('/chat'),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: .05),
        border: Border.all(color: MilaColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: MilaColors.cyan),
          const SizedBox(height: 8),
          Text(value, style: text.titleLarge),
          Text(label, overflow: TextOverflow.ellipsis, style: text.bodySmall),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: MilaColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: text.bodyMedium)),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline state (screen 17 of the design).
class _OfflineBody extends ConsumerWidget {
  const _OfflineBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
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
            child: const Icon(
              Icons.wifi_off_rounded,
              size: 36,
              color: MilaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.pick(
              ru: 'Нет подключения к интернету',
              en: 'No Internet Connection',
              uz: 'Internet aloqasi yo\'q',
            ),
            style: text.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.pick(
              ru: 'MILA сейчас офлайн. Часть функций станет доступна после подключения.',
              en: 'MILA is offline right now. Some features are unavailable until you\'re back online.',
              uz: 'MILA hozir oflayn. Baʼzi funksiyalar internet qaytganda ishlaydi.',
            ),
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: l10n.pick(
              ru: 'Повторить',
              en: 'Try Again',
              uz: 'Qayta urinish',
            ),
            expanded: false,
            onPressed: () => ref.invalidate(onlineProvider),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => context.go('/tasks'),
            child: Text(
              l10n.pick(
                ru: 'Работать офлайн',
                en: 'Work Offline',
                uz: 'Oflayn ishlash',
              ),
              style: text.labelLarge?.copyWith(color: MilaColors.cyan),
            ),
          ),
          const Spacer(),
          const AdaptiveOrb(size: 150, mood: OrbMood.offline),
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}
