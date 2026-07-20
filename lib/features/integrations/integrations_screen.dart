import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/config/app_config.dart';
import '../../services/integrations/integration_service.dart';
import '../../services/storage/stores.dart';

/// Which AI providers already have an API key saved.
final providerKeysProvider = FutureProvider<Set<String>>((ref) async {
  final secure = ref.watch(secureStoreProvider);
  final result = <String>{};
  if ((await secure.read(SecureStore.anthropicKey))?.isNotEmpty == true) {
    result.add('Claude');
  }
  if ((await secure.read(SecureStore.geminiKey))?.isNotEmpty == true) {
    result.add('Gemini');
  }
  if (AppConfig.hasBundledGeminiKey) {
    result.add('Gemini');
  }
  return result;
});

enum _Kind { telegram, webhook, mailApp, whatsApp, calendar, aiProvider }

class _Item {
  const _Item(this.name, this.icon, this.color, this.subtitle, this.kind);
  final String name;
  final IconData icon;
  final Color color;
  final String subtitle;
  final _Kind kind;
}

/// Integrations (design screen 14) — every row actually works:
/// Telegram sends through your bot, Slack/ERP post to webhooks, Gmail /
/// WhatsApp / Calendar run through the apps on the device, AI providers
/// link to the key settings.
class IntegrationsScreen extends ConsumerWidget {
  const IntegrationsScreen({super.key});

  static const _items = <_Item>[
    _Item(
      'Telegram',
      Icons.send_rounded,
      Color(0xFF2AABEE),
      'Real send via your bot',
      _Kind.telegram,
    ),
    _Item(
      'Gmail',
      Icons.mail_outline_rounded,
      Color(0xFFEA4335),
      'Drafts open in your mail app',
      _Kind.mailApp,
    ),
    _Item(
      'Google Calendar',
      Icons.calendar_month_outlined,
      Color(0xFF4285F4),
      'Events in the device calendar',
      _Kind.calendar,
    ),
    _Item(
      'WhatsApp',
      Icons.chat_rounded,
      Color(0xFF25D366),
      'Prefilled messages',
      _Kind.whatsApp,
    ),
    _Item(
      'Slack',
      Icons.tag_rounded,
      Color(0xFFE01E5A),
      'Incoming webhook',
      _Kind.webhook,
    ),
    _Item(
      'ERP / CRM',
      Icons.business_center_outlined,
      Color(0xFF35D49B),
      'Webhook: n8n, Zapier, your API',
      _Kind.webhook,
    ),
    _Item(
      'Claude',
      Icons.brightness_7_rounded,
      Color(0xFFD97757),
      'AI provider',
      _Kind.aiProvider,
    ),
    _Item(
      'Gemini',
      Icons.star_border_rounded,
      Color(0xFF8E75F0),
      'AI provider · voice',
      _Kind.aiProvider,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final configs = ref.watch(integrationConfigsProvider);
    final service = ref.read(integrationServiceProvider);
    final keys = ref.watch(providerKeysProvider).value ?? const <String>{};

    bool connected(_Item item) => switch (item.kind) {
      _Kind.telegram || _Kind.webhook => service.isConfigured(item.name),
      _Kind.aiProvider => keys.contains(item.name),
      // Launcher-based integrations are always ready on a phone.
      _ => true,
    };

    String subtitleFor(_Item item) {
      if (connected(item) &&
          (item.kind == _Kind.telegram ||
              item.kind == _Kind.webhook ||
              item.kind == _Kind.aiProvider)) {
        return l10n.pick(ru: 'Подключено', en: 'Connected', uz: 'Ulangan');
      }
      return switch (item.name) {
        'Telegram' => l10n.pick(
          ru: 'Реальная отправка через вашего бота',
          en: 'Real send via your bot',
          uz: 'Bot orqali haqiqiy yuborish',
        ),
        'Gmail' => l10n.pick(
          ru: 'Черновики открываются в почтовом приложении',
          en: 'Drafts open in your mail app',
          uz: 'Draftlar email ilovasida ochiladi',
        ),
        'Google Calendar' => l10n.pick(
          ru: 'События в календаре устройства',
          en: 'Events in the device calendar',
          uz: 'Tadbirlar qurilma kalendarida',
        ),
        'WhatsApp' => l10n.pick(
          ru: 'Сообщения с готовым текстом',
          en: 'Prefilled messages',
          uz: 'Oldindan to\'ldirilgan xabarlar',
        ),
        'Slack' => l10n.pick(
          ru: 'Входящий webhook',
          en: 'Incoming webhook',
          uz: 'Kiruvchi webhook',
        ),
        'ERP / CRM' => l10n.pick(
          ru: 'Webhook: n8n, Zapier, ваш API',
          en: 'Webhook: n8n, Zapier, your API',
          uz: 'Webhook: n8n, Zapier, APIʼingiz',
        ),
        'Gemini' => l10n.pick(
          ru: 'AI-провайдер · голос',
          en: 'AI provider · voice',
          uz: 'AI provayder · ovoz',
        ),
        _ => l10n.pick(
          ru: 'AI-провайдер',
          en: 'AI provider',
          uz: 'AI provayder',
        ),
      };
    }

    void snack(String message) => ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

    Future<void> open(_Item item) async {
      switch (item.kind) {
        case _Kind.aiProvider:
          await context.push('/settings/providers');
          ref.invalidate(providerKeysProvider);
        case _Kind.telegram:
          await _configSheet(
            context,
            title: 'Telegram bot',
            hint: 'Create a bot with @BotFather, write to it once, then paste:',
            fields: const [
              ('botToken', 'Bot token (123456:ABC-…)'),
              ('chatId', 'Your chat id (e.g. 123456789)'),
            ],
            initial: configs['Telegram'] ?? const {},
            onSave: (values) => ref
                .read(integrationConfigsProvider.notifier)
                .save('Telegram', values),
            onTest: () async =>
                (await service.sendTelegram('MILA connected ✓')).message,
          );
        case _Kind.webhook:
          await _configSheet(
            context,
            title: '${item.name} webhook',
            hint: item.name == 'Slack'
                ? 'Paste a Slack Incoming Webhook URL:'
                : 'Any HTTPS endpoint that accepts JSON POST (your ERP, n8n, Zapier, Make…):',
            fields: const [('webhookUrl', 'https://…')],
            initial: configs[item.name] ?? const {},
            onSave: (values) => ref
                .read(integrationConfigsProvider.notifier)
                .save(item.name, values),
            onTest: () async => (await service.postWebhook(item.name, {
              'text': 'MILA connected ✓',
              'source': 'mila',
            })).message,
          );
        case _Kind.mailApp:
          snack(
            (await service.composeEmail(
              subject: 'MILA test',
              body: 'This draft was prepared by MILA.',
            )).message,
          );
        case _Kind.whatsApp:
          snack((await service.sendWhatsApp('MILA connected ✓')).message);
        case _Kind.calendar:
          snack(
            (await service.addCalendarEvent(
              title: 'MILA test event',
              description: 'Created from the MILA app',
            )).message,
          );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.pick(
            ru: 'Интеграции',
            en: 'Integrations',
            uz: 'Integratsiyalar',
          ),
        ),
      ),
      body: MilaBackground(
        glowTop: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          physics: const BouncingScrollPhysics(),
          children: [
            Center(
              child: Text(
                l10n.pick(
                  ru: 'Подключите нужные инструменты',
                  en: 'Connect your favorite tools',
                  uz: 'Kerakli vositalarni ulang',
                ),
                style: text.bodySmall,
              ),
            ),
            const SizedBox(height: 20),
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  onTap: () => open(item),
                  child: Row(
                    children: [
                      TileIcon(icon: item.icon, color: item.color),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, style: text.titleSmall),
                            const SizedBox(height: 3),
                            Text(
                              subtitleFor(item),
                              style: text.bodySmall?.copyWith(
                                color:
                                    connected(item) &&
                                        item.kind != _Kind.mailApp &&
                                        item.kind != _Kind.whatsApp &&
                                        item.kind != _Kind.calendar
                                    ? MilaColors.success
                                    : MilaColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient:
                              connected(item) &&
                                  item.kind != _Kind.mailApp &&
                                  item.kind != _Kind.whatsApp &&
                                  item.kind != _Kind.calendar
                              ? null
                              : MilaColors.primaryGradient,
                          color:
                              connected(item) &&
                                  item.kind != _Kind.mailApp &&
                                  item.kind != _Kind.whatsApp &&
                                  item.kind != _Kind.calendar
                              ? Colors.white.withValues(alpha: 0.07)
                              : null,
                          borderRadius: BorderRadius.circular(18),
                          border:
                              connected(item) &&
                                  item.kind != _Kind.mailApp &&
                                  item.kind != _Kind.whatsApp &&
                                  item.kind != _Kind.calendar
                              ? Border.all(color: MilaColors.cardBorder)
                              : null,
                        ),
                        child: Text(
                          switch (item.kind) {
                            _Kind.mailApp || _Kind.whatsApp || _Kind.calendar =>
                              l10n.pick(ru: 'Тест', en: 'Test', uz: 'Test'),
                            _ =>
                              connected(item)
                                  ? l10n.pick(
                                      ru: 'Управлять',
                                      en: 'Manage',
                                      uz: 'Boshqarish',
                                    )
                                  : l10n.pick(
                                      ru: 'Подключить',
                                      en: 'Connect',
                                      uz: 'Ulash',
                                    ),
                          },
                          style: text.labelMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              l10n.pick(
                ru: 'Telegram, Slack и ERP/CRM отправляют сообщения прямо из приложения. Gmail, WhatsApp и Calendar передают действие приложениям телефона. AI-провайдеры настраиваются в Настройки → AI-провайдеры.',
                en: 'Telegram, Slack and ERP/CRM deliver messages directly from the app. Gmail, WhatsApp and Calendar hand off to the apps on your phone. AI providers are configured in Settings → AI Providers.',
                uz: 'Telegram, Slack va ERP/CRM xabarlarni ilovadan yuboradi. Gmail, WhatsApp va Calendar ishni telefondagi ilovalarga uzatadi. AI provayderlar Sozlamalar → AI provayderlar ichida sozlanadi.',
              ),
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with credential fields, Save and Test.
Future<void> _configSheet(
  BuildContext context, {
  required String title,
  required String hint,
  required List<(String, String)> fields,
  required Map<String, String> initial,
  required Future<void> Function(Map<String, String>) onSave,
  required Future<String> Function() onTest,
}) {
  final controllers = {
    for (final (key, _) in fields)
      key: TextEditingController(text: initial[key] ?? ''),
  };
  var busy = false;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        final text = Theme.of(sheetContext).textTheme;
        final l10n = sheetContext.l10n;
        return Padding(
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
              Text(title, style: text.titleMedium),
              const SizedBox(height: 6),
              Text(hint, style: text.bodySmall),
              const SizedBox(height: 14),
              for (final (key, label) in fields) ...[
                TextField(
                  controller: controllers[key],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(hintText: label),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: l10n.pick(
                        ru: 'Сохранить и проверить',
                        en: 'Save & Test',
                        uz: 'Saqlash va tekshirish',
                      ),
                      icon: Icons.wifi_tethering_rounded,
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              await onSave({
                                for (final e in controllers.entries)
                                  e.key: e.value.text,
                              });
                              final message = await onTest();
                              setState(() => busy = false);
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: l10n.pick(
                        ru: 'Сохранить',
                        en: 'Save',
                        uz: 'Saqlash',
                      ),
                      busy: busy,
                      onPressed: () async {
                        await onSave({
                          for (final e in controllers.entries)
                            e.key: e.value.text,
                        });
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
