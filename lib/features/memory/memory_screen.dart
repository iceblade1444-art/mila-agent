import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
                'Add Memory',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'e.g. Alex prefers concise summaries',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final c in MemoryCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MilaChip(
                        label: _categoryLabel(c),
                        active: category == c,
                        onTap: () => setSheetState(() => category = c),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Save',
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
              SnackBar(content: Text('Saved locally. ${error.message}')),
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

  static String _categoryLabel(MemoryCategory c) => switch (c) {
    MemoryCategory.people => 'People',
    MemoryCategory.preferences => 'Preferences',
    MemoryCategory.facts => 'Facts',
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
        title: const Text('Memory Vault'),
        actions: [
          IconButton(
            tooltip: _cloudConnected ? 'Synced with Obsidian' : 'Sync memory',
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
                  'MILA remembers what matters',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search memories',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: MilaColors.textTertiary,
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
                      label: 'All',
                      active: _filter == null,
                      onTap: () => setState(() => _filter = null),
                    ),
                    for (final c in MemoryCategory.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: MilaChip(
                          label: _categoryLabel(c),
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
                              ? 'Nothing saved yet.\nMILA will remember verified facts here.'
                              : 'No memories match your search.',
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
                                          '${_categoryLabel(m.category)} · ${DateFormat('MMM d, yyyy').format(m.createdAt)}',
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
                  label: 'Add Memory',
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
