import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../services/agentic/agentic_os_service.dart';
import '../../services/auth/mila_account_service.dart';
import '../../services/soul/soul_service.dart';
import '../../services/storage/stores.dart';
import '../../services/voice/voice_controller.dart';
import '../../services/voice/gemini_live_token_service.dart';

/// AI provider configuration. For now MILA runs on Gemini only; the MILA
/// backend is still used for app updates and future server-side features.
class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

String _liveLanguageCode(String language) {
  final normalized = language.trim().toLowerCase();
  if (normalized.contains('uz') || normalized.contains('o\'zbek')) {
    return 'uz-UZ';
  }
  if (normalized.contains('english') || normalized == 'en') return 'en-US';
  if (normalized.contains('рус') || normalized == 'ru') return 'ru-RU';
  return 'auto';
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  final _serverUrl = TextEditingController();
  final _connectionCode = TextEditingController();
  final _geminiKey = TextEditingController();
  final _geminiModel = TextEditingController();
  final _liveModel = TextEditingController();
  final _voiceDirection = TextEditingController();

  bool _loaded = false;
  bool _showGeminiKey = false;
  String _accountLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final secure = ref.read(secureStoreProvider);
    final settings = ref.read(settingsProvider);
    _serverUrl.text = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    );
    _geminiKey.text = await secure.read(SecureStore.geminiKey) ?? '';
    _geminiModel.text = settings.geminiModel;
    _liveModel.text = settings.geminiLiveModel;
    _voiceDirection.text = settings.voiceDirection;
    final savedToken = await secure.read(SecureStore.openAiAccountToken) ?? '';
    _accountLabel = savedToken.isEmpty
        ? ''
        : await secure.read(SecureStore.openAiAccountLabel) ?? '';
    await secure.write(SecureStore.openAiKey, '');
    if (settings.provider != LlmProviderKind.gemini) {
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(provider: LlmProviderKind.gemini));
    }

    if (mounted) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _connectMilaAccount() async {
    final l10n = context.l10n;
    try {
      final session = await const MilaAccountService().exchangeCode(
        baseUrl: _serverUrl.text,
        code: _connectionCode.text,
      );
      final secure = ref.read(secureStoreProvider);
      await secure.write(SecureStore.milaBackendUrl, _serverUrl.text);
      await secure.write(SecureStore.openAiAccountToken, session.token);
      await secure.write(SecureStore.openAiAccountLabel, session.label);
      if (session.accountToken.isNotEmpty) {
        await secure.write(
          SecureStore.agenticOsAccessToken,
          session.accountToken,
        );
        await secure.write(SecureStore.agenticOsAccountRole, session.ownerRole);
      }
      if (session.ownerName.isNotEmpty || session.ownerEmail.isNotEmpty) {
        final currentProfile = ref.read(profileProvider);
        ref
            .read(profileProvider.notifier)
            .save(
              currentProfile.copyWith(
                name: session.ownerName.isNotEmpty
                    ? session.ownerName
                    : currentProfile.name,
                email: session.ownerEmail.isNotEmpty
                    ? session.ownerEmail
                    : currentProfile.email,
                signedIn: true,
              ),
            );
      }
      final storedToken =
          await secure.read(SecureStore.openAiAccountToken) ?? '';
      if (storedToken != session.token) {
        throw StateError(
          l10n.pick(
            ru: 'Не удалось сохранить сессию MILA на этом устройстве.',
            en: 'Could not save the MILA session on this device.',
            uz: 'Bu qurilmada MILA sessiyasini saqlab bo\'lmadi.',
          ),
        );
      }
      String voiceCheck = '';
      try {
        await GeminiLiveTokenService(
          baseUrl: AppConfig.configuredBackendUrl(
            await secure.read(SecureStore.milaBackendUrl),
          ),
          sessionToken: storedToken,
        ).createToken(
          language: _liveLanguageCode(ref.read(settingsProvider).language),
        );
      } on GeminiLiveTokenException catch (error) {
        voiceCheck =
            ' ${l10n.pick(ru: 'Подключено, но голос требует внимания', en: 'Connected, but voice needs attention', uz: 'Ulandi, lekin ovoz sozlamasi eʼtibor talab qiladi')}: ${error.message}';
      }
      if (!mounted) return;
      setState(() {
        _accountLabel = session.label;
        _connectionCode.clear();
      });
      await ref.read(agenticTasksProvider.notifier).refresh();
      await ref.read(agenticDashboardProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.pick(ru: 'Подключено как', en: 'Connected as', uz: 'Ulandi')}: ${session.label}.$voiceCheck',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('FormatException: ', '')),
        ),
      );
    }
  }

  Future<void> _disconnectMilaAccount() async {
    final secure = ref.read(secureStoreProvider);
    await secure.write(SecureStore.openAiAccountToken, '');
    await secure.write(SecureStore.openAiAccountLabel, '');
    await secure.write(SecureStore.agenticOsAccessToken, '');
    await secure.write(SecureStore.agenticOsAccountRole, '');
    await ref.read(agenticTasksProvider.notifier).refresh();
    if (mounted) setState(() => _accountLabel = '');
  }

  Future<void> _previewVoice(String voice) async {
    await ref.read(voiceControllerProvider.notifier).previewVoice(voice);
    if (!mounted) return;
    final state = ref.read(voiceControllerProvider);
    if (state.phase == VoicePhase.error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error)));
      ref.read(voiceControllerProvider.notifier).dismissError();
    }
  }

  Future<void> _save() async {
    final secure = ref.read(secureStoreProvider);
    await secure.write(SecureStore.milaBackendUrl, _serverUrl.text.trim());
    await secure.write(SecureStore.geminiKey, _geminiKey.text.trim());
    await secure.write(SecureStore.openAiKey, '');
    ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            provider: LlmProviderKind.gemini,
            geminiModel: _geminiModel.text.trim().isEmpty
                ? s.geminiModel
                : _geminiModel.text.trim(),
            geminiLiveModel: _liveModel.text.trim().isEmpty
                ? s.geminiLiveModel
                : _liveModel.text.trim(),
            voiceDirection: _voiceDirection.text
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim(),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.pick(ru: 'Сохранено.', en: 'Saved.', uz: 'Saqlandi.'),
          ),
        ),
      );
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    _connectionCode.dispose();
    _geminiKey.dispose();
    _geminiModel.dispose();
    _liveModel.dispose();
    _voiceDirection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;

    Widget geminiKeyField() {
      final hasOverride = _geminiKey.text.trim().isNotEmpty;
      final secureVoiceConnected = _accountLabel.isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pick(
              ru: 'Доступ Gemini',
              en: 'Gemini access',
              uz: 'Gemini ruxsati',
            ),
            style: text.labelMedium,
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            borderColor: secureVoiceConnected || AppConfig.hasBundledGeminiKey
                ? MilaColors.success.withValues(alpha: 0.34)
                : MilaColors.cardBorder,
            color: secureVoiceConnected || AppConfig.hasBundledGeminiKey
                ? MilaColors.success.withValues(alpha: 0.08)
                : null,
            child: Row(
              children: [
                Icon(
                  secureVoiceConnected || AppConfig.hasBundledGeminiKey
                      ? Icons.verified_user_outlined
                      : Icons.key_off_outlined,
                  color: secureVoiceConnected || AppConfig.hasBundledGeminiKey
                      ? MilaColors.success
                      : MilaColors.textTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    secureVoiceConnected
                        ? l10n.pick(
                            ru: 'Безопасный доступ Gemini через сервер MILA',
                            en: 'Secure Gemini access via MILA server',
                            uz: 'MILA serveri orqali xavfsiz Gemini ruxsati',
                          )
                        : AppConfig.hasBundledGeminiKey
                        ? l10n.pick(
                            ru: 'Встроенный ключ Gemini активен',
                            en: 'Integrated Gemini key is active',
                            uz: 'Ichki Gemini kaliti faol',
                          )
                        : l10n.pick(
                            ru: 'Подключите MILA для безопасного доступа Gemini',
                            en: 'Connect MILA to enable secure Gemini access',
                            uz: 'Xavfsiz Gemini uchun MILA’ni ulang',
                          ),
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasOverride
                ? l10n.pick(
                    ru: 'Прямой ключ Gemini переопределён',
                    en: 'Direct Gemini key override',
                    uz: 'To\'g\'ridan-to\'g\'ri Gemini kaliti ishlatiladi',
                  )
                : l10n.pick(
                    ru: 'Прямой ключ Gemini (необязательно)',
                    en: 'Direct Gemini key (optional)',
                    uz: 'To\'g\'ridan-to\'g\'ri Gemini kaliti (ixtiyoriy)',
                  ),
            style: text.labelSmall,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _geminiKey,
            obscureText: !_showGeminiKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: l10n.pick(
                ru: 'Только для отдельного developer-ключа',
                en: 'Only for a separate developer key',
                uz: 'Faqat alohida developer kaliti uchun',
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _showGeminiKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: MilaColors.textTertiary,
                ),
                onPressed: () =>
                    setState(() => _showGeminiKey = !_showGeminiKey),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    void updateVoiceProfile(AppSettings updated) {
      ref.read(settingsProvider.notifier).update((_) => updated);
      ref.read(soulServiceProvider).save(updated, ref.read(profileProvider));
    }

    Widget enumChips<T extends Enum>(
      List<T> values,
      T selected,
      String Function(T value) label,
      void Function(T value) onSelected,
    ) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          MilaChip(
            label: label(value),
            active: value == selected,
            onTap: () => onSelected(value),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.pick(
            ru: 'AI-провайдеры',
            en: 'AI Providers',
            uz: 'AI provayderlar',
          ),
        ),
      ),
      body: MilaBackground(
        glowTop: false,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                physics: const BouncingScrollPhysics(),
                children: [
                  Text(
                    l10n.pick(
                      ru: 'ТЕКСТОВЫЙ ИНТЕЛЛЕКТ',
                      en: 'TEXT INTELLIGENCE',
                      uz: 'MATN INTELLEKTI',
                    ),
                    style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 10),
                  GlassCard(
                    child: Row(
                      children: [
                        const TileIcon(
                          icon: Icons.star_border_rounded,
                          color: Color(0xFF8E75F0),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Google Gemini', style: text.titleSmall),
                              const SizedBox(height: 3),
                              Text(
                                l10n.pick(
                                  ru: 'MILA использует Gemini для текста и Gemini Live для голоса.',
                                  en: 'MILA uses Gemini for text and Gemini Live for voice.',
                                  uz: 'MILA matn uchun Gemini, ovoz uchun Gemini Live ishlatadi.',
                                ),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: MilaColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: MilaColors.success.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            l10n.pick(ru: 'Активно', en: 'Active', uz: 'Faol'),
                            style: text.labelMedium?.copyWith(
                              color: MilaColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.pick(
                      ru: 'СЕРВЕР MILA',
                      en: 'MILA SERVER',
                      uz: 'MILA SERVERI',
                    ),
                    style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.pick(
                      ru: 'Адрес сервера',
                      en: 'Server URL',
                      uz: 'Server URL',
                    ),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _serverUrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://agent.milanapremium.uz/mila',
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _accountLabel.isNotEmpty
                                  ? Icons.verified_user_outlined
                                  : Icons.link_outlined,
                              color: _accountLabel.isNotEmpty
                                  ? MilaColors.success
                                  : MilaColors.textTertiary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _accountLabel.isNotEmpty
                                    ? '${l10n.pick(ru: 'Подключено как', en: 'Connected as', uz: 'Ulandi')}: $_accountLabel'
                                    : l10n.pick(
                                        ru: 'Подключить Agentic OS',
                                        en: 'Connect to Agentic OS',
                                        uz: 'Agentic OS’ga ulanish',
                                      ),
                                style: text.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _accountLabel.isNotEmpty
                              ? l10n.pick(
                                  ru: 'Голос использует короткий серверный токен; ключ Gemini остаётся на сервере.',
                                  en: 'Voice uses a short-lived server token; the Gemini key stays on the server.',
                                  uz: 'Ovoz qisqa muddatli server tokenidan foydalanadi; Gemini kaliti serverda qoladi.',
                                )
                              : l10n.pick(
                                  ru: 'Создайте одноразовый код в Agentic OS → Integrations → MILA.',
                                  en: 'Create a one-time code in Agentic OS → Integrations → MILA.',
                                  uz: 'Agentic OS → Integrations → MILA ichida bir martalik kod yarating.',
                                ),
                          style: text.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (_accountLabel.isEmpty) ...[
                          TextField(
                            controller: _connectionCode,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 8,
                            decoration: InputDecoration(
                              hintText: l10n.pick(
                                ru: 'Код из 8 символов',
                                en: '8-character code',
                                uz: '8 belgili kod',
                              ),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _connectMilaAccount,
                            icon: const Icon(Icons.link),
                            label: Text(
                              l10n.pick(
                                ru: 'Подключить аккаунт MILA',
                                en: 'Connect MILA account',
                                uz: 'MILA akkauntini ulash',
                              ),
                            ),
                          ),
                        ] else
                          TextButton.icon(
                            onPressed: _disconnectMilaAccount,
                            icon: const Icon(Icons.link_off),
                            label: Text(
                              l10n.pick(
                                ru: 'Отключить аккаунт',
                                en: 'Disconnect account',
                                uz: 'Akkauntni uzish',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.pick(ru: 'GEMINI', en: 'GEMINI', uz: 'GEMINI'),
                    style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.pick(
                      ru: 'Текстовый чат и live-голос используют встроенный доступ Gemini через MILA.',
                      en: 'Text chat and real-time voice use MILA integrated Gemini access.',
                      uz: 'Matn chat va live ovoz MILA orqali Gemini ruxsatidan foydalanadi.',
                    ),
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  geminiKeyField(),
                  Text(
                    l10n.pick(
                      ru: 'Текстовая модель Gemini',
                      en: 'Gemini text model',
                      uz: 'Gemini matn modeli',
                    ),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _geminiModel,
                    decoration: const InputDecoration(
                      hintText: 'gemini-2.5-flash',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.pick(
                      ru: 'Live-модель',
                      en: 'Live model',
                      uz: 'Live model',
                    ),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _liveModel,
                    decoration: const InputDecoration(
                      hintText: 'gemini-3.1-flash-live-preview',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.pick(ru: 'Голос', en: 'Voice', uz: 'Ovoz'),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue:
                        milaLiveVoiceNames.contains(settings.voiceName)
                        ? settings.voiceName
                        : femaleVoiceName,
                    items: [
                      for (final voice in milaLiveVoiceNames)
                        DropdownMenuItem(value: voice, child: Text(voice)),
                    ],
                    onChanged: (voice) {
                      if (voice == null) return;
                      updateVoiceProfile(settings.copyWith(voiceName: voice));
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.pick(
                      ru: 'Режим слушания',
                      en: 'Listening',
                      uz: 'Eshitish rejimi',
                    ),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  enumChips(
                    MilaListeningProfile.values,
                    settings.listeningProfile,
                    (v) => switch (v) {
                      MilaListeningProfile.balanced => l10n.pick(
                        ru: 'Сбалансированный',
                        en: 'Balanced',
                        uz: 'Muvozanatli',
                      ),
                      MilaListeningProfile.noisy => l10n.pick(
                        ru: 'Шумная комната',
                        en: 'Noisy room',
                        uz: 'Shovqinli xona',
                      ),
                      MilaListeningProfile.deliberate => l10n.pick(
                        ru: 'Длинные паузы',
                        en: 'Long pauses',
                        uz: 'Uzoq pauzalar',
                      ),
                    },
                    (v) => updateVoiceProfile(
                      settings.copyWith(listeningProfile: v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.pick(
                      ru: 'Стиль разговора',
                      en: 'Conversation style',
                      uz: 'Suhbat uslubi',
                    ),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  enumChips(
                    MilaConversationStyle.values,
                    settings.conversationStyle,
                    (v) => switch (v) {
                      MilaConversationStyle.assistant => 'Assistant',
                      MilaConversationStyle.friend => 'Friend',
                      MilaConversationStyle.operator => 'Operator',
                      MilaConversationStyle.mentor => 'Mentor',
                    },
                    (v) => updateVoiceProfile(
                      settings.copyWith(conversationStyle: v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.pick(
                      ru: 'Темп речи',
                      en: 'Speaking pace',
                      uz: 'Nutq tezligi',
                    ),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  enumChips(
                    MilaSpeakingPace.values,
                    settings.speakingPace,
                    (v) => switch (v) {
                      MilaSpeakingPace.slow => l10n.pick(
                        ru: 'Медленно',
                        en: 'Slow',
                        uz: 'Sekin',
                      ),
                      MilaSpeakingPace.medium => l10n.pick(
                        ru: 'Средне',
                        en: 'Medium',
                        uz: 'O‘rtacha',
                      ),
                      MilaSpeakingPace.fast => l10n.pick(
                        ru: 'Быстро',
                        en: 'Fast',
                        uz: 'Tez',
                      ),
                    },
                    (v) =>
                        updateVoiceProfile(settings.copyWith(speakingPace: v)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.pick(ru: 'Подача', en: 'Delivery', uz: 'Ohang'),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  enumChips(
                    MilaDeliveryStyle.values,
                    settings.deliveryStyle,
                    (v) => switch (v) {
                      MilaDeliveryStyle.natural => l10n.pick(
                        ru: 'Естественно',
                        en: 'Natural',
                        uz: 'Tabiiy',
                      ),
                      MilaDeliveryStyle.warm => l10n.pick(
                        ru: 'Тепло',
                        en: 'Warm',
                        uz: 'Iliq',
                      ),
                      MilaDeliveryStyle.energetic => l10n.pick(
                        ru: 'Энергично',
                        en: 'Energetic',
                        uz: 'Jonli',
                      ),
                      MilaDeliveryStyle.quiet => l10n.pick(
                        ru: 'Тихо',
                        en: 'Quiet',
                        uz: 'Sokin',
                      ),
                      MilaDeliveryStyle.precise => l10n.pick(
                        ru: 'Точно',
                        en: 'Precise',
                        uz: 'Aniq',
                      ),
                    },
                    (v) =>
                        updateVoiceProfile(settings.copyWith(deliveryStyle: v)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.pick(
                      ru: 'Голосовые ответы',
                      en: 'Voice answers',
                      uz: 'Ovozli javoblar',
                    ),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  enumChips(
                    MilaResponseLength.values,
                    settings.responseLength,
                    (v) => switch (v) {
                      MilaResponseLength.brief => l10n.pick(
                        ru: 'Кратко',
                        en: 'Brief',
                        uz: 'Qisqa',
                      ),
                      MilaResponseLength.balanced => l10n.pick(
                        ru: 'Баланс',
                        en: 'Balanced',
                        uz: 'Muvozanat',
                      ),
                    },
                    (v) => updateVoiceProfile(
                      settings.copyWith(responseLength: v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _voiceDirection,
                    maxLength: 240,
                    decoration: InputDecoration(
                      labelText: l10n.pick(
                        ru: 'Направление голоса',
                        en: 'Voice direction',
                        uz: 'Ovoz yo‘nalishi',
                      ),
                      hintText: l10n.pick(
                        ru: 'Например: отвечай теплее, не спеши',
                        en: 'For example: warmer, do not hurry',
                        uz: 'Masalan: iliqroq, shoshilma',
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.affectiveDialog,
                    onChanged: (value) => updateVoiceProfile(
                      settings.copyWith(affectiveDialog: value),
                    ),
                    title: Text(
                      l10n.pick(
                        ru: 'Affective dialog',
                        en: 'Affective dialog',
                        uz: 'Hissiy dialog',
                      ),
                    ),
                    subtitle: Text(
                      l10n.pick(
                        ru: 'MILA слышит тон и отвечает живее, когда модель это поддерживает.',
                        en: 'MILA hears tone and answers more naturally when the model supports it.',
                        uz: 'Model qo‘llasa, MILA ohangni sezadi va tabiiyroq javob beradi.',
                      ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.proactiveAudio,
                    onChanged: (value) => updateVoiceProfile(
                      settings.copyWith(proactiveAudio: value),
                    ),
                    title: Text(
                      l10n.pick(
                        ru: 'Proactive audio',
                        en: 'Proactive audio',
                        uz: 'Proaktiv audio',
                      ),
                    ),
                    subtitle: Text(
                      l10n.pick(
                        ru: 'MILA меньше реагирует на шум и речь не к ней.',
                        en: 'MILA reacts less to noise and speech not aimed at her.',
                        uz: 'MILA shovqin va unga qaratilmagan gapga kamroq javob beradi.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GhostButton(
                    label: l10n.pick(
                      ru: 'Послушать голос',
                      en: 'Listen to voice',
                      uz: 'Ovozni tinglash',
                    ),
                    icon: Icons.volume_up_outlined,
                    onPressed: () => _previewVoice(settings.voiceName),
                  ),
                  const SizedBox(height: 30),
                  GradientButton(
                    label: l10n.pick(
                      ru: 'Сохранить',
                      en: 'Save',
                      uz: 'Saqlash',
                    ),
                    onPressed: _save,
                  ),
                ],
              ),
      ),
    );
  }
}
