import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
import '../../services/llm/llm_service.dart';
import '../../services/storage/stores.dart';
import 'approval_sheet.dart';

/// Chat transcript (design screens 09, 10, 18).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final value = _input.text.trim();
    if (value.isEmpty) return;
    _input.clear();
    ref.read(llmServiceProvider).send(value);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final busy = ref.watch(chatBusyProvider);

    // Keep pinned to the latest message while streaming.
    ref.listen(chatProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });

    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 12),
                  Text('Today',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 22),
                    tooltip: 'Clear conversation',
                    onPressed: messages.isEmpty
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                backgroundColor: const Color(0xFF141926),
                                title: const Text('Clear conversation?'),
                                content: const Text(
                                    'This deletes the whole transcript on this device.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('Cancel')),
                                  TextButton(
                                    onPressed: () {
                                      ref
                                          .read(chatProvider.notifier)
                                          .clear();
                                      Navigator.pop(dialogContext);
                                    },
                                    child: const Text('Clear',
                                        style: TextStyle(
                                            color: MilaColors.danger)),
                                  ),
                                ],
                              ),
                            ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              Expanded(
                child: messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.builder(
                        controller: _scroll,
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        physics: const BouncingScrollPhysics(),
                        itemCount: messages.length,
                        itemBuilder: (_, i) =>
                            _MessageBubble(message: messages[i]),
                      ),
              ),
              _InputBar(
                controller: _input,
                busy: busy,
                onSend: _send,
                onMic: () => context.push('/voice'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state (design screen 18).
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('No conversations yet', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Tap the orb and say hello.\nI\'m here whenever you need me.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: 24),
          const AdaptiveOrb(size: 160),
        ],
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final isUser = message.role == ChatRole.user;
    final time = DateFormat('h:mm a').format(message.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: isUser ? MilaColors.primaryGradient : null,
                color: isUser ? null : const Color(0xFF161C2B),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: MilaColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.text.isEmpty && !isUser)
                    const SizedBox(
                      width: 34,
                      child: _TypingDots(),
                    )
                  else
                    Text(message.text, style: text.bodyMedium),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.viaVoice) ...[
                        Icon(Icons.graphic_eq_rounded,
                            size: 11,
                            color: isUser
                                ? Colors.white70
                                : MilaColors.textTertiary),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        time,
                        style: text.labelSmall?.copyWith(
                            fontSize: 10,
                            color: isUser
                                ? Colors.white70
                                : MilaColors.textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Structured action cards proposed by the assistant.
          for (final action in message.actions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ActionCard(messageId: message.id, action: action),
            ),
        ],
      ),
    );
  }
}

class _ActionCard extends ConsumerWidget {
  const _ActionCard({required this.messageId, required this.action});

  final String messageId;
  final MilaAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final (icon, color, cta) = switch (action.type) {
      ActionType.draftMessage =>
        (Icons.mail_outline_rounded, MilaColors.cyan, 'Review'),
      ActionType.createTask =>
        (Icons.check_circle_outline_rounded, MilaColors.purple, 'Add'),
      ActionType.reminder =>
        (Icons.alarm_rounded, MilaColors.violet, 'Add'),
      ActionType.focusTime =>
        (Icons.timelapse_rounded, MilaColors.pink, 'Add'),
      ActionType.saveMemory =>
        (Icons.bookmark_add_outlined, MilaColors.violet, 'Save'),
      ActionType.unknown =>
        (Icons.bolt_rounded, MilaColors.textSecondary, 'OK'),
    };
    final approved = action.status == ActionStatus.approved;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          TileIcon(icon: icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.title,
                    style: text.titleSmall, overflow: TextOverflow.ellipsis),
                if (action.subtitle.isNotEmpty)
                  Text(action.subtitle,
                      style: text.bodySmall,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          approved
              ? const Icon(Icons.check_rounded,
                  color: MilaColors.success, size: 22)
              : GestureDetector(
                  onTap: () async {
                    if (action.type == ActionType.draftMessage) {
                      // Screen 16: review before sending.
                      final ok = await showApprovalSheet(context, ref, action);
                      if (ok == true) {
                        ref
                            .read(chatProvider.notifier)
                            .setActionStatus(messageId, action.id,
                                ActionStatus.approved);
                      }
                    } else {
                      final result = await ref
                          .read(llmServiceProvider)
                          .applyAction(messageId, action);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.message)),
                        );
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: MilaColors.primaryGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(cta,
                        style: text.labelMedium
                            ?.copyWith(color: Colors.white)),
                  ),
                ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, MediaQuery.paddingOf(context).bottom + 96),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Ask MILA…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic_none_rounded,
                      color: MilaColors.textSecondary),
                  onPressed: onMic,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: busy ? null : onSend,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: MilaColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: MilaColors.violet.withValues(alpha: 0.4),
                      blurRadius: 14),
                ],
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: (0.3 +
                        0.7 *
                            (((_controller.value * 3 - i) % 3).clamp(0, 1)))
                    .clamp(0.2, 1.0),
                child: const CircleAvatar(
                    radius: 3, backgroundColor: MilaColors.cyan),
              ),
            ),
        ],
      ),
    );
  }
}
