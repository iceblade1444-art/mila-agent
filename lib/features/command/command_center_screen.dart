import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../services/llm/llm_service.dart';

/// Command Center (design screen 11): one-tap shortcuts that run prompts.
class CommandCenterScreen extends ConsumerStatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  ConsumerState<CommandCenterScreen> createState() =>
      _CommandCenterScreenState();
}

class _CommandCenterScreenState extends ConsumerState<CommandCenterScreen> {
  int _tab = 0;

  static const _shortcuts = <(IconData, Color, String, String, String, int)>[
    (
      Icons.summarize_outlined,
      MilaColors.cyan,
      'Summarize',
      'Summarize emails, docs, or web pages',
      'Summarize this for me: ',
      0
    ),
    (
      Icons.add_task_rounded,
      MilaColors.violet,
      'Create Task',
      'Add a task or reminder',
      'Create a task: ',
      0
    ),
    (
      Icons.edit_note_rounded,
      MilaColors.purple,
      'Write Message',
      'Draft emails or messages',
      'Draft a message: ',
      1
    ),
    (
      Icons.event_available_outlined,
      MilaColors.cyan,
      'Schedule Meeting',
      'Find time and schedule',
      'Help me schedule a meeting: ',
      1
    ),
    (
      Icons.search_rounded,
      MilaColors.violet,
      'Search Knowledge',
      'Search your memory vault',
      'What do you remember about ',
      2
    ),
    (
      Icons.wb_sunny_outlined,
      MilaColors.pink,
      'Daily Briefing',
      'Get your day summary',
      'Give me a short daily briefing based on my tasks and what you know about me.',
      2
    ),
  ];

  void _run(String promptPrefix) async {
    // Prompts ending with a space ask for user input first.
    if (!promptPrefix.endsWith(' ')) {
      context.go('/chat');
      Future.microtask(() => ref.read(llmServiceProvider).send(promptPrefix));
      return;
    }
    final controller = TextEditingController();
    final value = await showModalBottomSheet<String>(
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
            Text('What should MILA do?',
                style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(hintText: 'Type the details…'),
              onSubmitted: (v) => Navigator.pop(sheetContext, v),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Run',
              onPressed: () => Navigator.pop(sheetContext, controller.text),
            ),
          ],
        ),
      ),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    context.go('/chat');
    Future.microtask(
        () => ref.read(llmServiceProvider).send('$promptPrefix${value.trim()}'));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final visible =
        _shortcuts.where((s) => _tab == 0 || s.$6 == _tab).toList();

    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              Center(child: Text('Command Center', style: text.headlineSmall)),
              const SizedBox(height: 4),
              Center(
                  child: Text('Shortcuts to get things done',
                      style: text.bodySmall)),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final (i, label) in const [
                      (0, 'Popular'),
                      (1, 'Work'),
                      (2, 'Personal'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: MilaChip(
                          label: label,
                          active: _tab == i,
                          onTap: () => setState(() => _tab = i),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    for (final (icon, color, title, subtitle, prompt, _)
                        in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          onTap: () => _run(prompt),
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
                              const Icon(Icons.chevron_right_rounded,
                                  color: MilaColors.textTertiary),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    GlassCard(
                      onTap: () => context.push('/memory'),
                      child: Row(
                        children: [
                          const TileIcon(
                              icon: Icons.bookmark_outline_rounded,
                              color: MilaColors.purple),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Memory Vault', style: text.titleSmall),
                                const SizedBox(height: 3),
                                Text('MILA remembers what matters',
                                    style: text.bodySmall),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: MilaColors.textTertiary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      onTap: () => context.push('/integrations'),
                      child: Row(
                        children: [
                          const TileIcon(
                              icon: Icons.extension_outlined,
                              color: MilaColors.cyan),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Integrations', style: text.titleSmall),
                                const SizedBox(height: 3),
                                Text('Connect your favorite tools',
                                    style: text.bodySmall),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: MilaColors.textTertiary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
