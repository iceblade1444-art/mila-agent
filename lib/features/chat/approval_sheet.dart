import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../services/integrations/integration_service.dart';

/// Approval confirmation (design screen 16): review a drafted message,
/// then actually deliver it through a connected channel — Telegram bot,
/// the mail app, WhatsApp or a Slack webhook.
Future<bool?> showApprovalSheet(
  BuildContext context,
  WidgetRef ref,
  MilaAction action,
) {
  final payload = action.payload;
  final to = TextEditingController(text: payload['to'] as String? ?? '');
  final subject = TextEditingController(
    text: payload['subject'] as String? ?? action.title,
  );
  final body = TextEditingController(text: payload['body'] as String? ?? '');
  var editing = false;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        final text = Theme.of(sheetContext).textTheme;
        final l10n = sheetContext.l10n;
        Widget field(
          String label,
          TextEditingController controller, {
          int lines = 1,
        }) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.labelSmall),
              const SizedBox(height: 6),
              editing
                  ? TextField(controller: controller, maxLines: lines)
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MilaColors.cardBorder),
                      ),
                      child: Text(
                        controller.text.isEmpty ? '—' : controller.text,
                        style: text.bodyMedium,
                      ),
                    ),
              const SizedBox(height: 14),
            ],
          );
        }

        Future<void> send() async {
          final service = ref.read(integrationServiceProvider);
          final message = [
            if (subject.text.trim().isNotEmpty) subject.text.trim(),
            if (body.text.trim().isNotEmpty) body.text.trim(),
          ].join('\n\n');

          final channels =
              <(IconData, String, Future<IntegrationResult> Function())>[
                if (service.isConfigured('Telegram'))
                  (
                    Icons.send_rounded,
                    'Telegram',
                    () => service.sendTelegram(
                      '${to.text.trim().isNotEmpty ? 'To: ${to.text.trim()}\n' : ''}$message',
                    ),
                  ),
                (
                  Icons.mail_outline_rounded,
                  'Email app',
                  () => service.composeEmail(
                    to: to.text.trim(),
                    subject: subject.text.trim(),
                    body: body.text.trim(),
                  ),
                ),
                (
                  Icons.chat_rounded,
                  'WhatsApp',
                  () => service.sendWhatsApp(message),
                ),
                if (service.isConfigured('Slack'))
                  (
                    Icons.tag_rounded,
                    'Slack',
                    () => service.postWebhook('Slack', {'text': message}),
                  ),
              ];

          final choice =
              await showModalBottomSheet<Future<IntegrationResult> Function()>(
                context: sheetContext,
                builder: (chooserContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 14),
                      Text(
                        l10n.pick(
                          ru: 'Отправить через',
                          en: 'Send via',
                          uz: 'Yuborish',
                        ),
                        style: Theme.of(chooserContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      for (final (icon, name, run) in channels)
                        ListTile(
                          leading: Icon(icon, color: MilaColors.cyan),
                          title: Text(name),
                          onTap: () => Navigator.pop(chooserContext, run),
                        ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              );
          if (choice == null) return;

          final result = await choice();
          if (sheetContext.mounted) {
            Navigator.pop(sheetContext, result.ok);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(result.message)));
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    l10n.pick(
                      ru: 'Отправить сообщение?',
                      en: 'Send Message?',
                      uz: 'Xabar yuborilsinmi?',
                    ),
                    style: text.headlineSmall,
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    l10n.pick(
                      ru: 'Проверьте перед отправкой',
                      en: 'Review before sending',
                      uz: 'Yuborishdan oldin tekshiring',
                    ),
                    style: text.bodySmall,
                  ),
                ),
                const SizedBox(height: 22),
                field(l10n.pick(ru: 'Кому', en: 'To', uz: 'Kimga'), to),
                field(
                  l10n.pick(ru: 'Тема', en: 'Subject', uz: 'Mavzu'),
                  subject,
                ),
                field(
                  l10n.pick(ru: 'Сообщение', en: 'Message', uz: 'Xabar'),
                  body,
                  lines: 6,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: editing
                            ? l10n.pick(ru: 'Готово', en: 'Done', uz: 'Tayyor')
                            : l10n.pick(
                                ru: 'Править',
                                en: 'Edit',
                                uz: 'Tahrirlash',
                              ),
                        icon: editing
                            ? Icons.check_rounded
                            : Icons.edit_outlined,
                        onPressed: () => setState(() => editing = !editing),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GradientButton(
                        label: l10n.pick(
                          ru: 'Отправить',
                          en: 'Send',
                          uz: 'Yuborish',
                        ),
                        icon: Icons.send_rounded,
                        onPressed: send,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(
                      l10n.pick(ru: 'Отмена', en: 'Cancel', uz: 'Bekor qilish'),
                      style: text.labelLarge?.copyWith(
                        color: MilaColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
