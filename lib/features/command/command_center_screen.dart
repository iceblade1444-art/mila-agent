import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
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
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.pick(
                ru: 'Что должна сделать MILA?',
                en: 'What should MILA do?',
                uz: 'MILA nima qilsin?',
              ),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: context.l10n.pick(
                  ru: 'Напишите детали...',
                  en: 'Type the details...',
                  uz: 'Tafsilotlarni yozing...',
                ),
              ),
              onSubmitted: (v) => Navigator.pop(sheetContext, v),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: context.l10n.pick(
                ru: 'Запустить',
                en: 'Run',
                uz: 'Ishga tushirish',
              ),
              onPressed: () => Navigator.pop(sheetContext, controller.text),
            ),
          ],
        ),
      ),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    context.go('/chat');
    Future.microtask(
      () => ref.read(llmServiceProvider).send('$promptPrefix${value.trim()}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final shortcuts = <(IconData, Color, String, String, String, int)>[
      (
        Icons.summarize_outlined,
        MilaColors.cyan,
        l10n.pick(ru: 'Резюме', en: 'Summarize', uz: 'Xulosa'),
        l10n.pick(
          ru: 'Кратко пересказать письма, документы или страницы',
          en: 'Summarize emails, docs, or web pages',
          uz: 'Xatlar, hujjatlar yoki sahifalarni jamlash',
        ),
        l10n.pick(
          ru: 'Сделай краткое резюме: ',
          en: 'Summarize this for me: ',
          uz: 'Buni qisqa jamlab ber: ',
        ),
        0,
      ),
      (
        Icons.add_task_rounded,
        MilaColors.violet,
        l10n.pick(
          ru: 'Создать задачу',
          en: 'Create Task',
          uz: 'Vazifa yaratish',
        ),
        l10n.pick(
          ru: 'Добавить задачу или напоминание',
          en: 'Add a task or reminder',
          uz: 'Vazifa yoki eslatma qo\'shish',
        ),
        l10n.pick(
          ru: 'Создай задачу: ',
          en: 'Create a task: ',
          uz: 'Vazifa yarat: ',
        ),
        0,
      ),
      (
        Icons.edit_note_rounded,
        MilaColors.purple,
        l10n.pick(
          ru: 'Написать сообщение',
          en: 'Write Message',
          uz: 'Xabar yozish',
        ),
        l10n.pick(
          ru: 'Черновик письма или сообщения',
          en: 'Draft emails or messages',
          uz: 'Email yoki xabar drafti',
        ),
        l10n.pick(
          ru: 'Напиши сообщение: ',
          en: 'Draft a message: ',
          uz: 'Xabar draftini yoz: ',
        ),
        1,
      ),
      (
        Icons.event_available_outlined,
        MilaColors.cyan,
        l10n.pick(
          ru: 'Запланировать встречу',
          en: 'Schedule Meeting',
          uz: 'Uchrashuv rejalash',
        ),
        l10n.pick(
          ru: 'Помочь найти время и расписание',
          en: 'Find time and schedule',
          uz: 'Vaqt topish va jadval tuzish',
        ),
        l10n.pick(
          ru: 'Помоги запланировать встречу: ',
          en: 'Help me schedule a meeting: ',
          uz: 'Uchrashuvni rejalashga yordam ber: ',
        ),
        1,
      ),
      (
        Icons.search_rounded,
        MilaColors.violet,
        l10n.pick(
          ru: 'Поиск знаний',
          en: 'Search Knowledge',
          uz: 'Bilimdan qidirish',
        ),
        l10n.pick(
          ru: 'Искать в вашей памяти',
          en: 'Search your memory vault',
          uz: 'Xotira omboridan qidirish',
        ),
        l10n.pick(
          ru: 'Что ты помнишь про ',
          en: 'What do you remember about ',
          uz: 'Sen nima eslaysan: ',
        ),
        2,
      ),
      (
        Icons.wb_sunny_outlined,
        MilaColors.pink,
        l10n.pick(ru: 'Дневной бриф', en: 'Daily Briefing', uz: 'Kunlik brif'),
        l10n.pick(
          ru: 'Краткая сводка на день',
          en: 'Get your day summary',
          uz: 'Kun bo\'yicha qisqa xulosa',
        ),
        l10n.pick(
          ru: 'Дай короткий дневной бриф по моим задачам и тому, что ты обо мне знаешь.',
          en: 'Give me a short daily briefing based on my tasks and what you know about me.',
          uz: 'Vazifalarim va men haqimda bilganlaring asosida qisqa kunlik brif ber.',
        ),
        2,
      ),
    ];
    final visible = shortcuts.where((s) => _tab == 0 || s.$6 == _tab).toList();

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
                    ru: 'Командный центр',
                    en: 'Command Center',
                    uz: 'Buyruqlar markazi',
                  ),
                  style: text.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  l10n.pick(
                    ru: 'Быстрые действия для работы',
                    en: 'Shortcuts to get things done',
                    uz: 'Ishlarni bajarish uchun tezkor tugmalar',
                  ),
                  style: text.bodySmall,
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final (i, label) in const [
                      (0, 'popular'),
                      (1, 'work'),
                      (2, 'personal'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: MilaChip(
                          label: switch (label) {
                            'work' => l10n.pick(
                              ru: 'Работа',
                              en: 'Work',
                              uz: 'Ish',
                            ),
                            'personal' => l10n.pick(
                              ru: 'Личное',
                              en: 'Personal',
                              uz: 'Shaxsiy',
                            ),
                            _ => l10n.pick(
                              ru: 'Популярное',
                              en: 'Popular',
                              uz: 'Mashhur',
                            ),
                          },
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: text.titleSmall),
                                    const SizedBox(height: 3),
                                    Text(subtitle, style: text.bodySmall),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: MilaColors.textTertiary,
                              ),
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
                            color: MilaColors.purple,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.pick(
                                    ru: 'Библиотека памяти',
                                    en: 'Memory Vault',
                                    uz: 'Xotira ombori',
                                  ),
                                  style: text.titleSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  l10n.pick(
                                    ru: 'MILA помнит важное',
                                    en: 'MILA remembers what matters',
                                    uz: 'MILA muhim narsalarni eslaydi',
                                  ),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: MilaColors.textTertiary,
                          ),
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
                            color: MilaColors.cyan,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.pick(
                                    ru: 'Интеграции',
                                    en: 'Integrations',
                                    uz: 'Integratsiyalar',
                                  ),
                                  style: text.titleSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  l10n.pick(
                                    ru: 'Подключите нужные инструменты',
                                    en: 'Connect your favorite tools',
                                    uz: 'Kerakli vositalarni ulang',
                                  ),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: MilaColors.textTertiary,
                          ),
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
