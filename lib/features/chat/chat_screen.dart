import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

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
  final _imagePicker = ImagePicker();
  final List<ChatAttachment> _pendingAttachments = [];

  @override
  void dispose() {
    for (final attachment in _pendingAttachments) {
      File(attachment.path).delete().catchError((_) => File(attachment.path));
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _removePendingAttachment(String id) {
    final matches = _pendingAttachments.where(
      (attachment) => attachment.id == id,
    );
    for (final attachment in matches) {
      File(attachment.path).delete().catchError((_) => File(attachment.path));
    }
    setState(
      () =>
          _pendingAttachments.removeWhere((attachment) => attachment.id == id),
    );
  }

  void _send() {
    final value = _input.text.trim();
    if (value.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = List<ChatAttachment>.from(_pendingAttachments);
    _input.clear();
    setState(_pendingAttachments.clear);
    ref.read(llmServiceProvider).send(value, attachments: attachments);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2048,
    );
    if (picked == null) return;
    await _addAttachment(picked.path, picked.name, 'image/jpeg');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'md', 'csv', 'json'],
    );
    final file = result?.files.singleOrNull;
    if (file?.path == null) return;
    await _addAttachment(
      file!.path!,
      file.name,
      lookupMimeType(file.path!) ?? 'application/octet-stream',
    );
  }

  Future<void> _addAttachment(
    String path,
    String name,
    String fallbackMime,
  ) async {
    final file = File(path);
    if (!await file.exists()) return;
    final existingSize = await Future.wait(
      _pendingAttachments.map((item) async => File(item.path).length()),
    ).then((sizes) => sizes.fold<int>(0, (sum, size) => sum + size));
    if (existingSize + await file.length() > 15 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attachments must be smaller than 15 MB.'),
          ),
        );
      }
      return;
    }
    final mimeType = lookupMimeType(path) ?? fallbackMime;
    final documents = await getApplicationDocumentsDirectory();
    final attachmentDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}chat_attachments',
    );
    await attachmentDirectory.create(recursive: true);
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final savedFile = await file.copy(
      '${attachmentDirectory.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}_$safeName',
    );
    setState(() {
      _pendingAttachments.add(
        ChatAttachment(
          name: name,
          path: savedFile.path,
          mimeType: mimeType,
          type: mimeType.startsWith('image/')
              ? ChatAttachmentType.image
              : ChatAttachmentType.file,
        ),
      );
    });
  }

  Future<void> _showAttachmentMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachmentAction(
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              _AttachmentAction(
                icon: Icons.photo_library_outlined,
                label: 'Photo',
                onTap: () => Navigator.pop(sheetContext, 'photo'),
              ),
              _AttachmentAction(
                icon: Icons.attach_file_rounded,
                label: 'File',
                onTap: () => Navigator.pop(sheetContext, 'file'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'camera') await _pickImage(ImageSource.camera);
    if (action == 'photo') await _pickImage(ImageSource.gallery);
    if (action == 'file') await _pickFile();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final busy = ref.watch(chatBusyProvider);
    final assistantName = ref.watch(settingsProvider).assistantName;

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
                  Text('Today', style: Theme.of(context).textTheme.titleMedium),
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
                                'This deletes the whole transcript on this device.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    ref.read(chatProvider.notifier).clear();
                                    Navigator.pop(dialogContext);
                                  },
                                  child: const Text(
                                    'Clear',
                                    style: TextStyle(color: MilaColors.danger),
                                  ),
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        physics: const BouncingScrollPhysics(),
                        itemCount: messages.length,
                        itemBuilder: (_, i) =>
                            _MessageBubble(message: messages[i]),
                      ),
              ),
              _InputBar(
                controller: _input,
                assistantName: assistantName,
                attachments: _pendingAttachments,
                busy: busy,
                onAttach: _showAttachmentMenu,
                onRemoveAttachment: _removePendingAttachment,
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
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                    const SizedBox(width: 34, child: _TypingDots())
                  else
                    Text(message.text, style: text.bodyMedium),
                  if (message.attachments.isNotEmpty) ...[
                    if (message.text.isNotEmpty) const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final attachment in message.attachments)
                          _AttachmentPreview(attachment: attachment),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.viaVoice) ...[
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 11,
                          color: isUser
                              ? Colors.white70
                              : MilaColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        time,
                        style: text.labelSmall?.copyWith(
                          fontSize: 10,
                          color: isUser
                              ? Colors.white70
                              : MilaColors.textTertiary,
                        ),
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
      ActionType.draftMessage => (
        Icons.mail_outline_rounded,
        MilaColors.cyan,
        'Review',
      ),
      ActionType.createTask => (
        Icons.check_circle_outline_rounded,
        MilaColors.purple,
        'Add',
      ),
      ActionType.reminder => (Icons.alarm_rounded, MilaColors.violet, 'Add'),
      ActionType.focusTime => (Icons.timelapse_rounded, MilaColors.pink, 'Add'),
      ActionType.saveMemory => (
        Icons.bookmark_add_outlined,
        MilaColors.violet,
        'Save',
      ),
      ActionType.unknown => (
        Icons.bolt_rounded,
        MilaColors.textSecondary,
        'OK',
      ),
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
                Text(
                  action.title,
                  style: text.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (action.subtitle.isNotEmpty)
                  Text(
                    action.subtitle,
                    style: text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          approved
              ? const Icon(
                  Icons.check_rounded,
                  color: MilaColors.success,
                  size: 22,
                )
              : GestureDetector(
                  onTap: () async {
                    if (action.type == ActionType.draftMessage) {
                      // Screen 16: review before sending.
                      final ok = await showApprovalSheet(context, ref, action);
                      if (ok == true) {
                        ref
                            .read(chatProvider.notifier)
                            .setActionStatus(
                              messageId,
                              action.id,
                              ActionStatus.approved,
                            );
                      }
                    } else {
                      final result = await ref
                          .read(llmServiceProvider)
                          .applyAction(messageId, action);
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(result.message)));
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: MilaColors.primaryGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      cta,
                      style: text.labelMedium?.copyWith(color: Colors.white),
                    ),
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
    required this.assistantName,
    required this.attachments,
    required this.busy,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final String assistantName;
  final List<ChatAttachment> attachments;
  final bool busy;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        MediaQuery.paddingOf(context).bottom + 96,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty) ...[
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) => _PendingAttachment(
                  attachment: attachments[index],
                  onRemove: () => onRemoveAttachment(attachments[index].id),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              IconButton(
                tooltip: 'Add photo or file',
                onPressed: busy ? null : onAttach,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Ask $assistantName…',
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.mic_none_rounded,
                        color: MilaColors.textSecondary,
                      ),
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
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentAction extends StatelessWidget {
  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TileIcon(icon: icon, color: MilaColors.cyan, size: 42),
          const SizedBox(height: 7),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    ),
  );
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.type == ChatAttachmentType.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(attachment.path),
          width: 150,
          height: 110,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              attachment.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachment extends StatelessWidget {
  const _PendingAttachment({required this.attachment, required this.onRemove});

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      SizedBox(width: 132, child: _AttachmentPreview(attachment: attachment)),
      Positioned(
        right: -5,
        top: -5,
        child: InkWell(
          onTap: onRemove,
          child: const CircleAvatar(
            radius: 10,
            backgroundColor: MilaColors.danger,
            child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
          ),
        ),
      ),
    ],
  );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

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
                opacity:
                    (0.3 +
                            0.7 *
                                (((_controller.value * 3 - i) % 3).clamp(0, 1)))
                        .clamp(0.2, 1.0),
                child: const CircleAvatar(
                  radius: 3,
                  backgroundColor: MilaColors.cyan,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
