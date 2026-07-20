import 'dart:convert';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../storage/stores.dart';

/// Per-integration configuration (bot tokens, webhook URLs). Stored in the
/// platform keychain because these values are credentials.
class IntegrationConfigsController
    extends StateNotifier<Map<String, Map<String, String>>> {
  IntegrationConfigsController(this._secure) : super(const {}) {
    _load();
  }

  final SecureStore _secure;

  Future<void> _load() async {
    final raw = await _secure.read(SecureStore.integrationConfigs);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(k.toString(), (v as Map).cast<String, String>()),
      );
      if (mounted) state = map.cast<String, Map<String, String>>();
    } catch (_) {}
  }

  Future<void> save(String integration, Map<String, String> config) async {
    final cleaned = Map<String, String>.fromEntries(
      config.entries
          .map((e) => MapEntry(e.key, e.value.trim()))
          .where((e) => e.value.isNotEmpty),
    );
    final next = {...state};
    if (cleaned.isEmpty) {
      next.remove(integration);
    } else {
      next[integration] = cleaned;
    }
    state = next;
    await _secure.write(SecureStore.integrationConfigs, jsonEncode(next));
  }

  Map<String, String> of(String integration) => state[integration] ?? const {};
}

final integrationConfigsProvider =
    StateNotifierProvider<
      IntegrationConfigsController,
      Map<String, Map<String, String>>
    >((ref) => IntegrationConfigsController(ref.watch(secureStoreProvider)));

final integrationServiceProvider = Provider<IntegrationService>(
  (ref) => IntegrationService(ref),
);

class IntegrationResult {
  const IntegrationResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Executes real integration actions that work straight from the device —
/// no backend required: Telegram Bot API, incoming webhooks (Slack / ERP /
/// n8n / Zapier), the system mail app, WhatsApp and the device calendar.
class IntegrationService {
  IntegrationService(this._ref);

  final Ref _ref;

  Map<String, String> _config(String name) =>
      _ref.read(integrationConfigsProvider.notifier).of(name);

  bool isConfigured(String name) => switch (name) {
    'Telegram' =>
      _config(name)['botToken']?.isNotEmpty == true &&
          _config(name)['chatId']?.isNotEmpty == true,
    'Slack' || 'ERP / CRM' => _config(name)['webhookUrl']?.isNotEmpty == true,
    _ => false,
  };

  // ---------------------------------------------------------------- Telegram

  /// Sends [text] through the user's Telegram bot to the saved chat.
  /// Setup: create a bot with @BotFather, message it once, save the token
  /// and your chat id in the integration sheet.
  Future<IntegrationResult> sendTelegram(String text) async {
    final config = _config('Telegram');
    final token = config['botToken'] ?? '';
    final chatId = config['chatId'] ?? '';
    if (token.isEmpty || chatId.isEmpty) {
      return const IntegrationResult(
        false,
        'Telegram is not configured (bot token + chat id).',
      );
    }
    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chat_id': chatId, 'text': text}),
      );
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['ok'] == true) {
        return const IntegrationResult(true, 'Sent to Telegram ✓');
      }
      return IntegrationResult(
        false,
        'Telegram: ${json['description'] ?? response.statusCode}',
      );
    } catch (e) {
      return IntegrationResult(false, 'Telegram request failed: $e');
    }
  }

  // ---------------------------------------------------------------- Webhooks

  /// POSTs a JSON payload to the saved webhook (Slack incoming webhook,
  /// ERP/CRM endpoint, n8n/Zapier/Make…).
  Future<IntegrationResult> postWebhook(
    String integration,
    Map<String, dynamic> payload,
  ) async {
    final url = _config(integration)['webhookUrl'] ?? '';
    if (url.isEmpty) {
      return IntegrationResult(false, '$integration webhook URL is not set.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return IntegrationResult(
        false,
        '$integration webhook must use a valid HTTPS URL.',
      );
    }
    try {
      final body = integration == 'Slack'
          // Slack incoming webhooks expect {"text": "..."}.
          ? jsonEncode({'text': payload['text'] ?? jsonEncode(payload)})
          : jsonEncode(payload);
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return IntegrationResult(true, 'Delivered to $integration ✓');
      }
      return IntegrationResult(
        false,
        '$integration answered ${response.statusCode}',
      );
    } catch (e) {
      return IntegrationResult(false, '$integration request failed: $e');
    }
  }

  // ----------------------------------------------------------- App launchers

  /// Opens the system mail app with a prefilled draft (works with Gmail,
  /// Outlook or any default mail client — no OAuth needed).
  Future<IntegrationResult> composeEmail({
    String to = '',
    String subject = '',
    String body = '',
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      query: _encodeQuery({'subject': subject, 'body': body}),
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return IntegrationResult(
      ok,
      ok ? 'Opened your mail app' : 'No mail app available.',
    );
  }

  /// Opens WhatsApp with prefilled text ([phone] optional, digits only).
  Future<IntegrationResult> sendWhatsApp(
    String text, {
    String phone = '',
  }) async {
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(text)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return IntegrationResult(
      ok,
      ok ? 'Opened WhatsApp' : 'Could not open WhatsApp.',
    );
  }

  /// Opens the device calendar editor with a prefilled event (syncs to
  /// Google Calendar through the account already on the phone).
  Future<IntegrationResult> addCalendarEvent({
    required String title,
    String description = '',
    DateTime? start,
    Duration duration = const Duration(hours: 1),
  }) async {
    if (kIsWeb) {
      return const IntegrationResult(
        false,
        'Calendar events work in the phone app.',
      );
    }
    final startAt = start ?? DateTime.now().add(const Duration(hours: 1));
    final ok = await Add2Calendar.addEvent2Cal(
      Event(
        title: title,
        description: description,
        startDate: startAt,
        endDate: startAt.add(duration),
      ),
    );
    return IntegrationResult(
      ok,
      ok ? 'Calendar editor opened' : 'Could not open the calendar.',
    );
  }

  static String _encodeQuery(Map<String, String> params) => params.entries
      .where((e) => e.value.isNotEmpty)
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');
}
