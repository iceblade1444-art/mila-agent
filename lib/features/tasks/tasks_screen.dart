import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
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
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isAutomation ? 'Create Automation' : 'Create Task',
                style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: title,
              autofocus: true,
              decoration: InputDecoration(
                  hintText: isAutomation
                      ? 'e.g. Daily Email Summary'
                      : 'e.g. Review Q2 report'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subtitle,
              decoration: InputDecoration(
                  hintText: isAutomation
                      ? 'Schedule, e.g. Every day at 8:00 AM'
                      : 'Details (optional)'),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Create',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (created == true && title.text.trim().isNotEmpty) {
      ref.read(tasksProvider.notifier).add(TaskItem(
            title: title.text.trim(),
            subtitle: subtitle.text.trim(),
            isAutomation: isAutomation,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final all = ref.watch(tasksProvider);
    final items = all.where((t) => t.isAutomation == _automations).toList();

    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              Center(
                  child:
                      Text('Tasks & Automations', style: text.headlineSmall)),
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
                      for (final (auto, label) in const [
                        (false, 'Tasks'),
                        (true, 'Automations'),
                      ])
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _automations = auto),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                gradient: _automations == auto
                                    ? MilaColors.primaryGradient
                                    : null,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Center(
                                child: Text(label,
                                    style: text.labelLarge?.copyWith(
                                        color: _automations == auto
                                            ? Colors.white
                                            : MilaColors.textSecondary)),
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
                                color: MilaColors.textTertiary),
                            const SizedBox(height: 12),
                            Text(
                              _automations
                                  ? 'No automations yet.\nAsk MILA to automate something.'
                                  : 'No tasks yet.\nAsk MILA to create one, or add it here.',
                              textAlign: TextAlign.center,
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 20, 180),
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final item = items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(item.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => ref
                                  .read(tasksProvider.notifier)
                                  .remove(item.id),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding:
                                    const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: MilaColors.danger
                                      .withValues(alpha: 0.2),
                                  borderRadius:
                                      BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: MilaColors.danger),
                              ),
                              child: GlassCard(
                                child: Row(
                                  children: [
                                    TileIcon(
                                      icon: _automations
                                          ? Icons.autorenew_rounded
                                          : Icons
                                              .check_circle_outline_rounded,
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
                                                  ? TextDecoration
                                                      .lineThrough
                                                  : null,
                                              color: item.done
                                                  ? MilaColors.textTertiary
                                                  : null,
                                            ),
                                          ),
                                          if (item.subtitle.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(item.subtitle,
                                                style: text.bodySmall),
                                          ],
                                        ],
                                      ),
                                    ),
                                    _automations
                                        ? Switch(
                                            value: item.enabled,
                                            onChanged: (v) => ref
                                                .read(
                                                    tasksProvider.notifier)
                                                .toggle(item.id, v),
                                          )
                                        : Checkbox(
                                            value: item.done,
                                            shape: const CircleBorder(),
                                            activeColor:
                                                MilaColors.violet,
                                            onChanged: (v) => ref
                                                .read(
                                                    tasksProvider.notifier)
                                                .setDone(
                                                    item.id, v ?? false),
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
          label: Text(_automations ? 'Create Automation' : 'Create Task',
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
