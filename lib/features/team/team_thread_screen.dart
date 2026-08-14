import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../services/agentic/agentic_os_service.dart';
import '../../services/agentic/team_chat_models.dart';

/// One thread of the corporate chat. Mentioning @mila in a channel makes her
/// answer — that logic lives on the server, the phone just sends the text.
class TeamThreadScreen extends ConsumerStatefulWidget {
  const TeamThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  @override
  ConsumerState<TeamThreadScreen> createState() => _TeamThreadScreenState();
}

class _TeamThreadScreenState extends ConsumerState<TeamThreadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  List<TeamMessage> _messages = const [];
  String _meId = '';
  String? _error;
  bool _loaded = false;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Who "mine" is comes from the server, once: the bubble side must match
    // the account that is actually signed in, not a guess from a cached name.
    ref
        .read(agenticOsServiceProvider)
        .teamChatHome()
        .then((home) {
          if (mounted) setState(() => _meId = home.meId);
        })
        .catchError((_) {});
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final service = ref.read(agenticOsServiceProvider);
      final messages = await service.teamMessages(widget.conversationId);
      if (!mounted) return;
      final grew = messages.length != _messages.length;
      setState(() {
        _messages = messages;
        _loaded = true;
        _error = null;
      });
      if (grew) {
        _jumpToEnd();
        // Read receipts follow what is actually on screen, and a failed
        // markRead must never break reading.
        unawaited(
          service.markTeamRead(widget.conversationId).catchError((_) {}),
        );
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loaded = true;
      });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(agenticOsServiceProvider)
          .sendTeamMessage(widget.conversationId, text);
      _composer.clear();
      await _load();
    } on Exception catch (error) {
      if (!mounted) return;
      // The message did not go: keeping it in the composer is the honest
      // outcome — nothing pretends it was delivered.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.transparent,
      ),
      body: MilaBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: _list(l10n)),
              _composerBar(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(MilaLocalizations l10n) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MilaColors.textTertiary),
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          l10n.pick(
            ru: 'Сообщений пока нет — напишите первым.',
            en: 'No messages yet — write the first one.',
            uz: 'Hozircha xabar yo‘q — birinchi bo‘lib yozing.',
          ),
          style: const TextStyle(color: MilaColors.textTertiary),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      itemCount: _messages.length,
      itemBuilder: (_, index) => _bubble(l10n, _messages[index]),
    );
  }

  Widget _bubble(MilaLocalizations l10n, TeamMessage message) {
    final mine = _meId.isNotEmpty && message.authorId == _meId;
    final agent = message.kind == 'agent';
    final body = message.deleted
        ? l10n.pick(
            ru: 'Сообщение удалено',
            en: 'Message deleted',
            uz: 'Xabar o‘chirildi',
          )
        : message.text.isNotEmpty
        ? message.text
        : l10n.pick(ru: '📎 Вложение', en: '📎 Attachment', uz: '📎 Ilova');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine
              ? MilaColors.violet.withValues(alpha: 0.32)
              : agent
              ? MilaColors.cyan.withValues(alpha: 0.12)
              : const Color(0xFF1B2232),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 5),
            bottomRight: Radius.circular(mine ? 5 : 16),
          ),
          border: agent
              ? Border.all(color: MilaColors.cyan.withValues(alpha: 0.35))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.authorName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: agent ? MilaColors.cyan : MilaColors.violet,
                  ),
                ),
              ),
            Text(
              body,
              style: TextStyle(
                fontStyle: message.deleted ? FontStyle.italic : null,
                color: message.deleted ? MilaColors.textTertiary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerBar(MilaLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 4,
              maxLength: 4000,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                counterText: '',
                hintText: l10n.pick(
                  ru: 'Сообщение… (@mila — спросить MILA)',
                  en: 'Message… (@mila to ask MILA)',
                  uz: 'Xabar… (@mila — MILA dan so‘rash)',
                ),
                filled: true,
                fillColor: const Color(0xFF1B2232),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
