import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../services/agentic/agentic_os_service.dart';
import '../../services/storage/stores.dart';

/// Tasks & Automations (design screen 12).
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _automations = false;

  Future<void> _create() async {
    final title = TextEditingController();
    final subtitle = TextEditingController();
    final isAutomation = _automations;
    final created = await showModalBottomSheet<bool>(
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
              isAutomation
                  ? context.l10n.pick(
                      ru: 'Создать автоматизацию',
                      en: 'Create Automation',
                      uz: 'Avtomatlashtirish yaratish',
                    )
                  : context.l10n.pick(
                      ru: 'Создать задачу',
                      en: 'Create Task',
                      uz: 'Vazifa yaratish',
                    ),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: title,
              autofocus: true,
              decoration: InputDecoration(
                hintText: isAutomation
                    ? context.l10n.pick(
                        ru: 'Например: ежедневное резюме писем',
                        en: 'e.g. Daily Email Summary',
                        uz: 'Masalan: kundalik email xulosasi',
                      )
                    : context.l10n.pick(
                        ru: 'Например: проверить отчёт за квартал',
                        en: 'e.g. Review Q2 report',
                        uz: 'Masalan: chorak hisobotini ko\'rish',
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subtitle,
              decoration: InputDecoration(
                hintText: isAutomation
                    ? context.l10n.pick(
                        ru: 'Расписание, например: каждый день в 8:00',
                        en: 'Schedule, e.g. Every day at 8:00 AM',
                        uz: 'Jadval, masalan: har kuni 8:00 da',
                      )
                    : context.l10n.pick(
                        ru: 'Детали (необязательно)',
                        en: 'Details (optional)',
                        uz: 'Tafsilotlar (ixtiyoriy)',
                      ),
              ),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: context.l10n.pick(
                ru: 'Создать',
                en: 'Create',
                uz: 'Yaratish',
              ),
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (created == true && title.text.trim().isNotEmpty) {
      if (!isAutomation && ref.read(agenticTasksProvider).connected) {
        try {
          await ref
              .read(agenticTasksProvider.notifier)
              .create(title.text.trim(), subtitle.text.trim());
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.pick(
                    ru: 'Отправлено Hermes для планирования.',
                    en: 'Sent to Hermes for planning.',
                    uz: 'Rejalash uchun Hermesga yuborildi.',
                  ),
                ),
              ),
            );
          }
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }
      } else {
        ref
            .read(tasksProvider.notifier)
            .add(
              TaskItem(
                title: title.text.trim(),
                subtitle: subtitle.text.trim(),
                isAutomation: isAutomation,
              ),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final all = ref.watch(tasksProvider);
    final agentic = ref.watch(agenticTasksProvider);
    final items = _automations
        ? all.where((task) => task.isAutomation).map(_TaskView.local).toList()
        : agentic.connected
        ? agentic.tasks.map(_TaskView.agentic).toList()
        : all.where((task) => !task.isAutomation).map(_TaskView.local).toList();

    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              Center(
                child: Text(
                  l10n.pick(
                    ru: 'Задачи и автоматизации',
                    en: 'Tasks & Automations',
                    uz: 'Vazifalar va avtomatlashtirish',
                  ),
                  style: text.headlineSmall,
                ),
              ),
              if (!_automations) ...[
                const SizedBox(height: 8),
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: agentic.connected
                        ? () =>
                              ref.read(agenticTasksProvider.notifier).refresh()
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (agentic.connected
                                    ? MilaColors.success
                                    : MilaColors.textTertiary)
                                .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (agentic.loading)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          else
                            Icon(
                              agentic.connected
                                  ? Icons.sync_rounded
                                  : Icons.phone_android_rounded,
                              size: 15,
                              color: agentic.connected
                                  ? MilaColors.success
                                  : MilaColors.textTertiary,
                            ),
                          const SizedBox(width: 6),
                          Text(
                            agentic.connected
                                ? l10n.pick(
                                    ru: 'Hermes Kanban синхронизирован',
                                    en: 'Hermes Kanban synced',
                                    uz: 'Hermes Kanban sinxronlashdi',
                                  )
                                : l10n.pick(
                                    ru: 'Локальные задачи · подключите Agentic OS',
                                    en: 'Local tasks · connect Agentic OS',
                                    uz: 'Mahalliy vazifalar · Agentic OS ulang',
                                  ),
                            style: text.labelSmall?.copyWith(
                              color: agentic.connected
                                  ? MilaColors.success
                                  : MilaColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: MilaColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      for (final (auto, _) in const [
                        (false, 'tasks'),
                        (true, 'automations'),
                      ])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _automations = auto),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                gradient: _automations == auto
                                    ? MilaColors.primaryGradient
                                    : null,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Center(
                                child: Text(
                                  auto
                                      ? l10n.pick(
                                          ru: 'Автоматизации',
                                          en: 'Automations',
                                          uz: 'Avtomatika',
                                        )
                                      : l10n.pick(
                                          ru: 'Задачи',
                                          en: 'Tasks',
                                          uz: 'Vazifalar',
                                        ),
                                  style: text.labelLarge?.copyWith(
                                    color: _automations == auto
                                        ? Colors.white
                                        : MilaColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _automations
                                  ? Icons.autorenew_rounded
                                  : Icons.task_alt_rounded,
                              size: 44,
                              color: MilaColors.textTertiary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _automations
                                  ? l10n.pick(
                                      ru: 'Автоматизаций пока нет.\nПопросите MILA что-нибудь автоматизировать.',
                                      en: 'No automations yet.\nAsk MILA to automate something.',
                                      uz: 'Hali avtomatika yo\'q.\nMILA’dan nimanidir avtomatlashtirishni so\'rang.',
                                    )
                                  : agentic.connected
                                  ? l10n.pick(
                                      ru: 'Задач Hermes пока нет.\nПопросите MILA или создайте задачу здесь.',
                                      en: 'No Hermes tasks yet.\nAsk MILA or create a task here.',
                                      uz: 'Hermes vazifalari hali yo\'q.\nMILA’dan so\'rang yoki shu yerda yarating.',
                                    )
                                  : l10n.pick(
                                      ru: 'Задач пока нет.\nПодключите Agentic OS или добавьте локально.',
                                      en: 'No tasks yet.\nConnect Agentic OS or add one locally.',
                                      uz: 'Hali vazifalar yo\'q.\nAgentic OS ulang yoki mahalliy qo\'shing.',
                                    ),
                              textAlign: TextAlign.center,
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final item = items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(item.id),
                              direction: item.remote
                                  ? DismissDirection.none
                                  : DismissDirection.endToStart,
                              onDismissed: item.remote
                                  ? null
                                  : (_) => ref
                                        .read(tasksProvider.notifier)
                                        .remove(item.id),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: MilaColors.danger.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: MilaColors.danger,
                                ),
                              ),
                              child: GlassCard(
                                child: Row(
                                  children: [
                                    TileIcon(
                                      icon: _automations
                                          ? Icons.autorenew_rounded
                                          : Icons.check_circle_outline_rounded,
                                      color: _automations
                                          ? MilaColors.violet
                                          : MilaColors.purple,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            style: text.titleSmall?.copyWith(
                                              decoration: item.done
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              color: item.done
                                                  ? MilaColors.textTertiary
                                                  : null,
                                            ),
                                          ),
                                          if (item.subtitle.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              item.subtitle,
                                              style: text.bodySmall,
                                            ),
                                          ],
                                          if (item.remote) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 7,
                                              runSpacing: 6,
                                              children: [
                                                _TaskTag(
                                                  label: item.status,
                                                  color: _statusColor(
                                                    item.status,
                                                  ),
                                                ),
                                                _TaskTag(
                                                  label:
                                                      item.assignee == 'default'
                                                      ? 'Hermes'
                                                      : item.assignee,
                                                  color: MilaColors.cyan,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    _automations
                                        ? Switch(
                                            value: item.enabled,
                                            onChanged: (v) => ref
                                                .read(tasksProvider.notifier)
                                                .toggle(item.id, v),
                                          )
                                        : Checkbox(
                                            value: item.done,
                                            shape: const CircleBorder(),
                                            activeColor: MilaColors.violet,
                                            onChanged: item.remote
                                                ? item.done
                                                      ? null
                                                      : (value) async {
                                                          if (value != true) {
                                                            return;
                                                          }
                                                          try {
                                                            await ref
                                                                .read(
                                                                  agenticTasksProvider
                                                                      .notifier,
                                                                )
                                                                .markDone(
                                                                  item.id,
                                                                );
                                                          } catch (error) {
                                                            if (context
                                                                .mounted) {
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              ).showSnackBar(
                                                                SnackBar(
                                                                  content: Text(
                                                                    error
                                                                        .toString(),
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                          }
                                                        }
                                                : (value) => ref
                                                      .read(
                                                        tasksProvider.notifier,
                                                      )
                                                      .setDone(
                                                        item.id,
                                                        value ?? false,
                                                      ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 92),
        child: FloatingActionButton.extended(
          onPressed: _create,
          backgroundColor: MilaColors.violet,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text(
            _automations
                ? l10n.pick(
                    ru: 'Создать автоматизацию',
                    en: 'Create Automation',
                    uz: 'Avtomatika yaratish',
                  )
                : l10n.pick(
                    ru: 'Создать задачу',
                    en: 'Create Task',
                    uz: 'Vazifa yaratish',
                  ),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _TaskView {
  const _TaskView({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.enabled,
    required this.remote,
    this.status = '',
    this.assignee = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final bool done;
  final bool enabled;
  final bool remote;
  final String status;
  final String assignee;

  factory _TaskView.local(TaskItem task) => _TaskView(
    id: task.id,
    title: task.title,
    subtitle: task.subtitle,
    done: task.done,
    enabled: task.enabled,
    remote: false,
  );

  factory _TaskView.agentic(AgenticTask task) => _TaskView(
    id: task.id,
    title: task.title,
    subtitle: task.summary.isNotEmpty ? task.summary : task.body,
    done: task.complete,
    enabled: true,
    remote: true,
    status: task.status,
    assignee: task.assignee,
  );
}

class _TaskTag extends StatelessWidget {
  const _TaskTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.26)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}

Color _statusColor(String status) => switch (status) {
  'running' => MilaColors.cyan,
  'ready' || 'review' => MilaColors.success,
  'blocked' => MilaColors.danger,
  'done' => MilaColors.success,
  _ => MilaColors.violet,
};
