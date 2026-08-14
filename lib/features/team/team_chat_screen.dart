import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../services/agentic/agentic_os_service.dart';
import '../../services/agentic/team_chat_models.dart';

/// The corporate chat: channels and direct threads with colleagues — the same
/// messenger the web dashboard has, on the same server routes. The phone shows
/// what the account is a member of; membership itself is decided server-side.
class TeamChatScreen extends ConsumerStatefulWidget {
  const TeamChatScreen({super.key});

  @override
  ConsumerState<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends ConsumerState<TeamChatScreen> {
  TeamChatHome? _home;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Polling, not a socket: the screen is foreground-only and the list is
    // small, so a request every few seconds keeps unread counts honest without
    // holding a connection open through every network change a phone lives
    // through.
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final home = await ref.read(agenticOsServiceProvider).teamChatHome();
      if (!mounted) return;
      setState(() {
        _home = home;
        _error = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      // Keep showing the last good list; only lead with the error when there
      // is nothing better to show.
      setState(() => _error = error.toString());
    }
  }

  Future<void> _openDirect(TeamPerson person) async {
    try {
      final conversation = await ref
          .read(agenticOsServiceProvider)
          .openDirectThread(person.id);
      if (!mounted) return;
      unawaited(
        context.push('/team/${conversation.id}', extra: conversation.name),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _pickColleague() {
    final home = _home;
    if (home == null) return;
    final people = home.people
        .where((person) => person.id != home.meId)
        .toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                context.l10n.pick(
                  ru: 'Написать сотруднику',
                  en: 'Message a colleague',
                  uz: 'Hamkasbga yozish',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final person in people)
              ListTile(
                leading: _Avatar(name: person.name, online: person.online),
                title: Text(person.name),
                subtitle: Text(
                  person.isAgent ? 'MILA' : person.role,
                  style: const TextStyle(color: MilaColors.textTertiary),
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _openDirect(person);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final home = _home;
    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.pick(ru: 'Команда', en: 'Team', uz: 'Jamoa'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: home == null ? null : _pickColleague,
                      icon: const Icon(Icons.edit_square, size: 21),
                      tooltip: l10n.pick(
                        ru: 'Написать сотруднику',
                        en: 'Message a colleague',
                        uz: 'Hamkasbga yozish',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body(l10n, home)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(MilaLocalizations l10n, TeamChatHome? home) {
    if (home == null && _error != null) {
      return _Notice(
        icon: Icons.cloud_off_rounded,
        title: l10n.pick(
          ru: 'Чат недоступен',
          en: 'Chat is unavailable',
          uz: 'Chat mavjud emas',
        ),
        detail: _error!,
      );
    }
    if (home == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (home.conversations.isEmpty) {
      return _Notice(
        icon: Icons.forum_outlined,
        title: l10n.pick(
          ru: 'Переписок пока нет',
          en: 'No conversations yet',
          uz: 'Hozircha suhbat yo‘q',
        ),
        detail: l10n.pick(
          ru: 'Напишите сотруднику — или попросите добавить вас в канал.',
          en: 'Message a colleague — or ask to be added to a channel.',
          uz: 'Hamkasbga yozing — yoki kanalga qo‘shishlarini so‘rang.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: home.conversations.length,
        itemBuilder: (_, index) {
          final conversation = home.conversations[index];
          final last = conversation.lastMessage;
          final preview = last == null
              ? ''
              : last.deleted
              ? l10n.pick(
                  ru: 'Сообщение удалено',
                  en: 'Message deleted',
                  uz: 'Xabar o‘chirildi',
                )
              : last.text.isNotEmpty
              ? last.text
              : l10n.pick(ru: 'Вложение', en: 'Attachment', uz: 'Ilova');
          return ListTile(
            leading: conversation.kind == 'channel'
                ? const _ChannelBadge()
                : _Avatar(name: conversation.name, online: false),
            title: Text(
              conversation.kind == 'channel'
                  ? '#${conversation.name}'
                  : conversation.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: conversation.unread > 0
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
            subtitle: Text(
              last == null ? '' : '${last.authorName}: $preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MilaColors.textTertiary),
            ),
            trailing: conversation.unread > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: conversation.mentioned
                          ? MilaColors.pink
                          : MilaColors.cyan,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      conversation.mentioned
                          ? '@ ${conversation.unread}'
                          : '${conversation.unread}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : null,
            onTap: () => context.push(
              '/team/${conversation.id}',
              extra: conversation.kind == 'channel'
                  ? '#${conversation.name}'
                  : conversation.name,
            ),
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.online});

  final String name;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Stack(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: MilaColors.violet.withValues(alpha: 0.25),
          child: Text(letter, style: const TextStyle(color: Colors.white)),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFF3DDC84),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF141926), width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge();

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: MilaColors.cyan.withValues(alpha: 0.16),
      child: const Icon(Icons.tag_rounded, color: MilaColors.cyan, size: 20),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: MilaColors.textTertiary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MilaColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
