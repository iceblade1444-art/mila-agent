import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../services/agentic/agentic_os_service.dart';
import '../../services/storage/stores.dart';

/// Memory Vault (design screen 13). Everything stored here is injected
/// into MILA's system prompt for both text and voice conversations.
class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  String _query = '';
  MemoryCategory? _filter;
  bool _syncing = false;
  bool _cloudConnected = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_sync);
  }

  Future<void> _sync() async {
    final agentic = ref.read(agenticOsServiceProvider);
    final connected = await agentic.isConnected();
    if (!connected) {
      if (mounted) setState(() => _cloudConnected = false);
      return;
    }
    if (mounted) setState(() => _syncing = true);
    try {
      final remote = await agentic.listMemory();
      ref.read(memoriesProvider.notifier).mergeRemote(remote);
      if (mounted) setState(() => _cloudConnected = true);
    } on AgenticOsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    var category = MemoryCategory.facts;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
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
                  ru: 'Добавить память',
                  en: 'Add Memory',
                  uz: 'Xotira qo\'shish',
                ),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration:
                    const InputDecoration(
                      hintText: 'e.g. Alex prefers concise summaries',
                    ).copyWith(
                      hintText: context.l10n.pick(
                        ru: 'Например: Бахадыр любит короткие резюме',
                        en: 'e.g. Alex prefers concise summaries',
                        uz: 'Masalan: Bahodir qisqa xulosalarni yoqtiradi',
                      ),
                    ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final c in MemoryCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MilaChip(
                        label: _categoryLabel(sheetContext, c),
                        active: category == c,
                        onTap: () => setSheetState(() => category = c),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: context.l10n.pick(
                  ru: 'Сохранить',
                  en: 'Save',
                  uz: 'Saqlash',
                ),
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      final item = MemoryItem(text: controller.text.trim(), category: category);
      ref.read(memoriesProvider.notifier).add(item);
      final agentic = ref.read(agenticOsServiceProvider);
      if (await agentic.isConnected()) {
        try {
          final remote = await agentic.appendMemory(item);
          ref.read(memoriesProvider.notifier).mergeRemote([remote]);
          if (mounted) setState(() => _cloudConnected = true);
        } on AgenticOsException catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${context.l10n.pick(ru: 'Сохранено локально.', en: 'Saved locally.', uz: 'Mahalliy saqlandi.')} ${error.message}',
                ),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _remove(MemoryItem item) async {
    final remoteId = RegExp(r'^[a-f0-9]{16}$').hasMatch(item.id);
    if (remoteId) {
      try {
        await ref.read(agenticOsServiceProvider).deleteMemory(item.id);
      } on AgenticOsException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
        return;
      }
    }
    ref.read(memoriesProvider.notifier).remove(item.id);
  }

  String _categoryLabel(BuildContext context, MemoryCategory c) => switch (c) {
    MemoryCategory.people => context.l10n.pick(
      ru: 'Люди',
      en: 'People',
      uz: 'Odamlar',
    ),
    MemoryCategory.preferences => context.l10n.pick(
      ru: 'Предпочтения',
      en: 'Preferences',
      uz: 'Afzalliklar',
    ),
    MemoryCategory.facts => context.l10n.pick(
      ru: 'Факты',
      en: 'Facts',
      uz: 'Faktlar',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final all = ref.watch(memoriesProvider);
    final items = all.where((m) {
      if (_filter != null && m.category != _filter) return false;
      if (_query.isNotEmpty &&
          !m.text.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.pick(
            ru: 'Библиотека памяти',
            en: 'Memory Vault',
            uz: 'Xotira ombori',
          ),
        ),
        actions: [
          IconButton(
            tooltip: _cloudConnected
                ? l10n.pick(
                    ru: 'Синхронизировано с Obsidian',
                    en: 'Synced with Obsidian',
                    uz: 'Obsidian bilan sinxron',
                  )
                : l10n.pick(
                    ru: 'Синхронизировать память',
                    en: 'Sync memory',
                    uz: 'Xotirani sinxronlash',
                  ),
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _cloudConnected
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_sync_outlined,
                    color: _cloudConnected
                        ? MilaColors.success
                        : MilaColors.textSecondary,
                  ),
          ),
        ],
      ),
      body: MilaBackground(
        glowTop: false,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  l10n.pick(
                    ru: 'MILA помнит важное',
                    en: 'MILA remembers what matters',
                    uz: 'MILA muhim narsalarni eslaydi',
                  ),
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration:
                      const InputDecoration(
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: MilaColors.textTertiary,
                        ),
                      ).copyWith(
                        hintText: l10n.pick(
                          ru: 'Поиск по памяти',
                          en: 'Search memories',
                          uz: 'Xotiradan qidirish',
                        ),
                      ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    MilaChip(
                      label: l10n.pick(ru: 'Все', en: 'All', uz: 'Hammasi'),
                      active: _filter == null,
                      onTap: () => setState(() => _filter = null),
                    ),
                    for (final c in MemoryCategory.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: MilaChip(
                          label: _categoryLabel(context, c),
                          active: _filter == c,
                          onTap: () => setState(() => _filter = c),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty
                              ? l10n.pick(
                                  ru: 'Пока ничего не сохранено.\nMILA будет хранить здесь проверенные факты.',
                                  en: 'Nothing saved yet.\nMILA will remember verified facts here.',
                                  uz: 'Hali hech narsa saqlanmagan.\nMILA tekshirilgan faktlarni shu yerda saqlaydi.',
                                )
                              : l10n.pick(
                                  ru: 'По запросу ничего не найдено.',
                                  en: 'No memories match your search.',
                                  uz: 'Qidiruvga mos xotira topilmadi.',
                                ),
                          textAlign: TextAlign.center,
                          style: text.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final m = items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlassCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(m.text, style: text.bodyMedium),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${_categoryLabel(context, m.category)} · ${DateFormat('MMM d, yyyy', Localizations.localeOf(context).languageCode).format(m.createdAt)}',
                                          style: text.labelSmall?.copyWith(
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: MilaColors.textTertiary,
                                    ),
                                    onPressed: () => _remove(m),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: GradientButton(
                  label: l10n.pick(
                    ru: 'Добавить память',
                    en: 'Add Memory',
                    uz: 'Xotira qo\'shish',
                  ),
                  icon: Icons.add_rounded,
                  onPressed: _add,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
