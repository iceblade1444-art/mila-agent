import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../services/soul/soul_service.dart';
import '../../services/storage/stores.dart';
import '../../services/voice/voice_controller.dart';

/// AI provider configuration. For now MILA runs on Gemini only; the MILA
/// backend is still used for app updates and future server-side features.
class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  final _serverUrl = TextEditingController();
  final _geminiKey = TextEditingController();
  final _geminiModel = TextEditingController();
  final _liveModel = TextEditingController();

  bool _loaded = false;
  bool _showGeminiKey = false;

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

    await secure.write(SecureStore.openAiAccountToken, '');
    await secure.write(SecureStore.openAiAccountLabel, '');
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
    await secure.write(SecureStore.openAiAccountToken, '');
    await secure.write(SecureStore.openAiAccountLabel, '');
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
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved.')));
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    _geminiKey.dispose();
    _geminiModel.dispose();
    _liveModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);

    Widget geminiKeyField() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gemini API key', style: text.labelMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiKey,
            obscureText: !_showGeminiKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'AIza...',
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

    return Scaffold(
      appBar: AppBar(title: const Text('AI Providers')),
      body: MilaBackground(
        glowTop: false,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                physics: const BouncingScrollPhysics(),
                children: [
                  Text(
                    'TEXT INTELLIGENCE',
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
                                'MILA uses Gemini for text and Gemini Live for voice.',
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
                            'Active',
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
                    'MILA SERVER',
                    style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Text('Server URL', style: text.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _serverUrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://agent.milanapremium.uz',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'GEMINI',
                    style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Text chat and real-time voice both use your Gemini key.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  geminiKeyField(),
                  Text('Gemini text model', style: text.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _geminiModel,
                    decoration: const InputDecoration(
                      hintText: 'gemini-3.5-flash',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Live model', style: text.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _liveModel,
                    decoration: const InputDecoration(
                      hintText: 'gemini-3.1-flash-live-preview',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Voice', style: text.labelMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final gender in AssistantVoiceGender.values)
                        MilaChip(
                          label: voiceGenderLabel(gender),
                          active:
                              assistantVoiceGenderFromName(
                                settings.voiceName,
                              ) ==
                              gender,
                          onTap: () {
                            final updated = settings.copyWith(
                              voiceName: voiceNameForGender(gender),
                            );
                            ref
                                .read(settingsProvider.notifier)
                                .update((_) => updated);
                            ref
                                .read(soulServiceProvider)
                                .save(updated, ref.read(profileProvider));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GhostButton(
                    label:
                        'Listen to ${voiceGenderLabel(assistantVoiceGenderFromName(settings.voiceName)).toLowerCase()} voice',
                    icon: Icons.volume_up_outlined,
                    onPressed: () => _previewVoice(settings.voiceName),
                  ),
                  const SizedBox(height: 30),
                  GradientButton(label: 'Save', onPressed: _save),
                ],
              ),
      ),
    );
  }
}
