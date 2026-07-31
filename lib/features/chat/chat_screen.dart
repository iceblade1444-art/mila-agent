import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
import '../../services/llm/llm_service.dart';
import '../../services/agentic/agentic_os_service.dart';
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
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _imagePicker = ImagePicker();
  final List<ChatAttachment> _pendingAttachments = [];
  ChatMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(chatSyncProvider.notifier).sync());
  }

  @override
  void dispose() {
    for (final attachment in _pendingAttachments) {
      File(attachment.path).delete().catchError((_) => File(attachment.path));
    }
    _input.dispose();
    _inputFocus.dispose();
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
    final replyToText = _replyingTo?.text.trim() ?? '';
    _input.clear();
    setState(() {
      _pendingAttachments.clear();
      _replyingTo = null;
    });
    ref
        .read(llmServiceProvider)
        .send(
          value,
          attachments: attachments,
          replyToText: replyToText.length > 180
              ? '${replyToText.substring(0, 180)}…'
              : replyToText,
        );
  }

  void _replyTo(ChatMessage message) {
    setState(() => _replyingTo = message);
    _inputFocus.requestFocus();
  }

  void _sendSuggestion(String value) {
    if (ref.read(chatBusyProvider)) return;
    _input.text = value;
    _input.selection = TextSelection.collapsed(offset: value.length);
    _send();
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
          SnackBar(
            content: Text(
              context.l10n.pick(
                ru: 'Вложения должны быть меньше 15 МБ.',
                en: 'Attachments must be smaller than 15 MB.',
                uz: 'Ilovalar 15 MB dan kichik bo\'lishi kerak.',
              ),
            ),
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
                label: context.l10n.pick(
                  ru: 'Камера',
                  en: 'Camera',
                  uz: 'Kamera',
                ),
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              _AttachmentAction(
                icon: Icons.photo_library_outlined,
                label: context.l10n.pick(ru: 'Фото', en: 'Photo', uz: 'Rasm'),
                onTap: () => Navigator.pop(sheetContext, 'photo'),
              ),
              _AttachmentAction(
                icon: Icons.attach_file_rounded,
                label: context.l10n.pick(ru: 'Файл', en: 'File', uz: 'Fayl'),
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
    final l10n = context.l10n;

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
              _ConversationHeader(
                assistantName: assistantName,
                busy: busy,
                onVoice: () => context.push('/voice'),
                onClear: messages.isEmpty
                    ? null
                    : () => showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: const Color(0xFF141926),
                          title: Text(
                            l10n.pick(
                              ru: 'Очистить диалог?',
                              en: 'Clear conversation?',
                              uz: 'Suhbatni tozalaysizmi?',
                            ),
                          ),
                          content: Text(
                            l10n.pick(
                              ru: 'Вся переписка на этом устройстве будет удалена.',
                              en: 'This deletes the whole transcript on this device.',
                              uz: 'Bu qurilmadagi barcha yozishma o\'chiriladi.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: Text(
                                l10n.pick(
                                  ru: 'Отмена',
                                  en: 'Cancel',
                                  uz: 'Bekor qilish',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                ref.read(chatProvider.notifier).clear();
                                ref
                                    .read(chatSyncProvider.notifier)
                                    .clearRemote();
                                Navigator.pop(dialogContext);
                              },
                              child: Text(
                                l10n.pick(
                                  ru: 'Очистить',
                                  en: 'Clear',
                                  uz: 'Tozalash',
                                ),
                                style: const TextStyle(
                                  color: MilaColors.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        physics: const BouncingScrollPhysics(),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final message = messages[i];
                          final previous = i == 0 ? null : messages[i - 1];
                          final showDate =
                              previous == null ||
                              !DateUtils.isSameDay(
                                previous.createdAt,
                                message.createdAt,
                              );
                          return Column(
                            children: [
                              if (showDate)
                                _DateDivider(date: message.createdAt),
                              _MessageBubble(
                                message: message,
                                showSuggestions:
                                    i == messages.length - 1 && !busy,
                                onReply: () => _replyTo(message),
                                onSuggestion: _sendSuggestion,
                              ),
                            ],
                          );
                        },
                      ),
              ),
              _InputBar(
                controller: _input,
                focusNode: _inputFocus,
                assistantName: assistantName,
                attachments: _pendingAttachments,
                replyingTo: _replyingTo,
                busy: busy,
                onAttach: _showAttachmentMenu,
                onRemoveAttachment: _removePendingAttachment,
                onCancelReply: () => setState(() => _replyingTo = null),
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
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.pick(
              ru: 'Диалогов пока нет',
              en: 'No conversations yet',
              uz: 'Hali suhbatlar yo\'q',
            ),
            style: text.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pick(
              ru: 'Нажмите на сферу и скажите привет.\nЯ рядом, когда понадоблюсь.',
              en: 'Tap the orb and say hello.\nI\'m here whenever you need me.',
              uz: 'Sferani bosing va salom ayting.\nKerak bo\'lsam, shu yerdaman.',
            ),
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

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.assistantName,
    required this.busy,
    required this.onVoice,
    required this.onClear,
  });

  final String assistantName;
  final bool busy;
  final VoidCallback onVoice;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const _MilaAvatar(size: 42),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assistantName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: busy ? MilaColors.cyan : MilaColors.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (busy ? MilaColors.cyan : MilaColors.success)
                                .withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      busy
                          ? l10n.pick(
                              ru: 'печатает…',
                              en: 'typing…',
                              uz: 'yozmoqda…',
                            )
                          : l10n.pick(
                              ru: 'на связи',
                              en: 'online',
                              uz: 'aloqada',
                            ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.pick(
              ru: 'Голосовой разговор',
              en: 'Voice conversation',
              uz: 'Ovozli suhbat',
            ),
            onPressed: onVoice,
            icon: const Icon(Icons.graphic_eq_rounded, color: MilaColors.cyan),
          ),
          PopupMenuButton<String>(
            tooltip: l10n.pick(ru: 'Меню', en: 'Menu', uz: 'Menyu'),
            color: const Color(0xFF171D2B),
            onSelected: (value) {
              if (value == 'clear') onClear?.call();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                enabled: onClear != null,
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 19),
                    const SizedBox(width: 10),
                    Text(
                      l10n.pick(
                        ru: 'Очистить диалог',
                        en: 'Clear conversation',
                        uz: 'Suhbatni tozalash',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  String _calendarLabel(BuildContext context) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    if (DateUtils.isSameDay(date, now)) {
      return context.l10n.pick(ru: 'Сегодня', en: 'Today', uz: 'Bugun');
    }
    if (DateUtils.isSameDay(date, yesterday)) {
      return context.l10n.pick(ru: 'Вчера', en: 'Yesterday', uz: 'Kecha');
    }

    const ruMonths = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    const enMonths = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const uzMonths = [
      'yanvar',
      'fevral',
      'mart',
      'aprel',
      'may',
      'iyun',
      'iyul',
      'avgust',
      'sentabr',
      'oktabr',
      'noyabr',
      'dekabr',
    ];
    final month = context.l10n.pick(
      ru: ruMonths[date.month - 1],
      en: enMonths[date.month - 1],
      uz: uzMonths[date.month - 1],
    );
    return '${date.day} $month';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _calendarLabel(context),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _MilaAvatar extends StatefulWidget {
  const _MilaAvatar({this.size = 34});

  final double size;

  @override
  State<_MilaAvatar> createState() => _MilaAvatarState();
}

class _MilaAvatarState extends State<_MilaAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _avatar(double progress) {
    final pulse = Curves.easeInOut.transform(progress);
    final size = widget.size;
    return Transform.scale(
      scale: 0.97 + pulse * 0.05,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: MilaColors.orbGradient,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
          boxShadow: [
            BoxShadow(
              color: MilaColors.cyan.withValues(alpha: 0.16 + pulse * 0.18),
              blurRadius: 10 + pulse * 8,
              spreadRadius: pulse * 1.5,
            ),
          ],
        ),
        child: Container(
          margin: EdgeInsets.all(size * 0.12),
          decoration: BoxDecoration(
            color: const Color(0xFF11182A).withValues(alpha: 0.74),
            shape: BoxShape.circle,
          ),
          child: Transform.rotate(
            angle: (pulse - 0.5) * 0.16,
            child: Icon(Icons.auto_awesome_rounded, size: size * 0.44),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return _avatar(0.5);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => _avatar(_controller.value),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.showSuggestions,
    required this.onReply,
    required this.onSuggestion,
  });

  final ChatMessage message;
  final bool showSuggestions;
  final VoidCallback onReply;
  final ValueChanged<String> onSuggestion;

  Future<void> _showMessageMenu(BuildContext context) async {
    final l10n = context.l10n;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(
                  l10n.pick(ru: 'Ответить', en: 'Reply', uz: 'Javob'),
                ),
                onTap: () => Navigator.pop(sheetContext, 'reply'),
              ),
              if (message.text.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(
                    l10n.pick(ru: 'Копировать', en: 'Copy', uz: 'Nusxalash'),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'copy'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == 'reply') onReply();
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.pick(
                ru: 'Сообщение скопировано',
                en: 'Message copied',
                uz: 'Xabar nusxalandi',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final isUser = message.role == ChatRole.user;
    final time = DateFormat('h:mm a').format(message.createdAt);

    final bubble = GestureDetector(
      onLongPress: () => _showMessageMenu(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: isUser
              ? MilaColors.primaryGradient
              : const LinearGradient(
                  colors: [Color(0xFF18223A), Color(0xFF151B2B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 5),
            bottomRight: Radius.circular(isUser ? 5 : 18),
          ),
          border: Border.all(
            color: isUser
                ? MilaColors.cyan.withValues(alpha: 0.28)
                : MilaColors.violet.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: (isUser ? MilaColors.violet : MilaColors.cyan).withValues(
                alpha: 0.08,
              ),
              blurRadius: 18,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.replyToText.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: MilaColors.cyan, width: 2),
                  ),
                ),
                child: Text(
                  message.replyToText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 9),
            ],
            if (message.text.isEmpty && !isUser)
              const SizedBox(width: 38, child: _TypingDots())
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
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.viaVoice) ...[
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 12,
                    color: isUser ? Colors.white70 : MilaColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  time,
                  style: text.labelSmall?.copyWith(
                    fontSize: 10,
                    color: isUser ? Colors.white70 : MilaColors.textTertiary,
                  ),
                ),
                if (isUser) ...[
                  const SizedBox(width: 4),
                  Icon(
                    switch (message.deliveryStatus) {
                      ChatDeliveryStatus.sending => Icons.schedule_rounded,
                      ChatDeliveryStatus.failed => Icons.error_outline_rounded,
                      ChatDeliveryStatus.sent => Icons.check_rounded,
                      ChatDeliveryStatus.delivered => Icons.done_all_rounded,
                    },
                    size: 14,
                    color: message.deliveryStatus == ChatDeliveryStatus.failed
                        ? MilaColors.danger
                        : MilaColors.cyan,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[const _MilaAvatar(), const SizedBox(width: 9)],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                  ),
                  child: bubble,
                ),
              ),
            ],
          ),
          for (final card in message.cards)
            Padding(
              padding: EdgeInsets.only(top: 10, left: isUser ? 0 : 43),
              child: _RichMessageCard(card: card),
            ),
          // Structured action cards proposed by the assistant.
          for (final action in message.actions)
            Padding(
              padding: EdgeInsets.only(top: 10, left: isUser ? 0 : 43),
              child: _ActionCard(messageId: message.id, action: action),
            ),
          if (showSuggestions && message.suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 43),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in message.suggestions)
                    ActionChip(
                      label: Text(suggestion),
                      avatar: const Icon(Icons.arrow_outward_rounded, size: 15),
                      onPressed: () => onSuggestion(suggestion),
                      side: BorderSide(
                        color: MilaColors.cyan.withValues(alpha: 0.28),
                      ),
                      backgroundColor: const Color(0xFF151C2C),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RichMessageCard extends StatelessWidget {
  const _RichMessageCard({required this.card});

  final ChatRichCard card;

  Color get _accent => switch (card.accent) {
    'cyan' => MilaColors.cyan,
    'pink' => MilaColors.pink,
    'green' => MilaColors.success,
    _ => MilaColors.violet,
  };

  IconData get _icon => switch (card.type) {
    ChatCardType.task => Icons.task_alt_rounded,
    ChatCardType.reminder => Icons.notifications_active_outlined,
    ChatCardType.progress => Icons.insights_rounded,
    ChatCardType.report => Icons.analytics_outlined,
    ChatCardType.info => Icons.auto_awesome_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17223A), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.44)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.1), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TileIcon(icon: _icon, color: accent, size: 36),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (card.subtitle.isNotEmpty)
                      Text(
                        card.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (card.metric.isNotEmpty)
                Text(
                  card.metric,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (card.progress != null) ...[
            const SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: card.progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
          if (card.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final item in card.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: CircleAvatar(radius: 2.5, backgroundColor: accent),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: MilaColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
    final l10n = context.l10n;
    final (icon, color, cta) = switch (action.type) {
      ActionType.draftMessage => (
        Icons.mail_outline_rounded,
        MilaColors.cyan,
        l10n.pick(ru: 'Проверить', en: 'Review', uz: 'Ko\'rish'),
      ),
      ActionType.createTask => (
        Icons.check_circle_outline_rounded,
        MilaColors.purple,
        l10n.pick(ru: 'Добавить', en: 'Add', uz: 'Qo\'shish'),
      ),
      ActionType.reminder => (
        Icons.alarm_rounded,
        MilaColors.violet,
        l10n.pick(ru: 'Добавить', en: 'Add', uz: 'Qo\'shish'),
      ),
      ActionType.focusTime => (
        Icons.timelapse_rounded,
        MilaColors.pink,
        l10n.pick(ru: 'Добавить', en: 'Add', uz: 'Qo\'shish'),
      ),
      ActionType.saveMemory => (
        Icons.bookmark_add_outlined,
        MilaColors.violet,
        l10n.pick(ru: 'Сохранить', en: 'Save', uz: 'Saqlash'),
      ),
      ActionType.unknown => (
        Icons.bolt_rounded,
        MilaColors.textSecondary,
        l10n.pick(ru: 'ОК', en: 'OK', uz: 'OK'),
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
    required this.focusNode,
    required this.assistantName,
    required this.attachments,
    required this.replyingTo,
    required this.busy,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onCancelReply,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String assistantName;
  final List<ChatAttachment> attachments;
  final ChatMessage? replyingTo;
  final bool busy;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyingTo != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF151C2C),
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                  left: BorderSide(color: MilaColors.cyan, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          replyingTo!.role == ChatRole.user
                              ? context.l10n.pick(
                                  ru: 'Ответ себе',
                                  en: 'Reply to yourself',
                                  uz: 'O\'zingizga javob',
                                )
                              : context.l10n.pick(
                                  ru: 'Ответ MILA',
                                  en: 'Reply to MILA',
                                  uz: 'MILAga javob',
                                ),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: MilaColors.cyan),
                        ),
                        Text(
                          replyingTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onCancelReply,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
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
                tooltip: context.l10n.pick(
                  ru: 'Добавить фото или файл',
                  en: 'Add photo or file',
                  uz: 'Rasm yoki fayl qo\'shish',
                ),
                onPressed: busy ? null : onAttach,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: context.l10n.pick(
                      ru: 'Спросить $assistantName...',
                      en: 'Ask $assistantName...',
                      uz: '$assistantName’dan so\'rang...',
                    ),
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
