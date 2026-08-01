import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/storage/stores.dart';
import '../../services/voice/voice_controller.dart';

/// Live voice session (design screens 06–09): idle → listening →
/// thinking → speaking, with real-time transcripts from the Gemini Live API.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen>
    with WidgetsBindingObserver {
  bool _justCompleted = false;
  Timer? _completeTimer;
  Timer? _cameraTimer;
  CameraController? _camera;
  bool _cameraStarting = false;
  bool _capturingFrame = false;
  bool _webLaunchAttempted = false;
  bool _useNativeVoice = false;
  String _webLaunchError = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openWebVoice());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _camera != null) {
      unawaited(
        _stopCamera().then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  Future<void> _toggleCamera() async {
    final noCameraMessage = context.l10n.pick(
      ru: 'Камера недоступна.',
      en: 'No camera is available.',
      uz: 'Kamera mavjud emas.',
    );
    if (_camera != null) {
      await _stopCamera();
      if (mounted) setState(() {});
      return;
    }
    if (_cameraStarting) return;
    setState(() => _cameraStarting = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError(noCameraMessage);
      }
      final preferred = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        preferred,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      _cameraTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _sendCameraFrame(),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10n.pick(ru: 'Не удалось включить камеру', en: 'Could not start camera', uz: 'Kamerani yoqib bo\'lmadi')}: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cameraStarting = false);
    }
  }

  Future<void> _sendCameraFrame() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        _capturingFrame ||
        !ref.read(voiceControllerProvider).active) {
      return;
    }
    _capturingFrame = true;
    try {
      final frame = await camera.takePicture();
      final bytes = await frame.readAsBytes();
      ref.read(voiceControllerProvider.notifier).sendVideoFrame(bytes);
      await File(frame.path).delete().catchError((_) => File(frame.path));
    } catch (_) {
      // A skipped frame is harmless; the next one is attempted in one second.
    } finally {
      _capturingFrame = false;
    }
  }

  Future<void> _stopCamera() async {
    _cameraTimer?.cancel();
    _cameraTimer = null;
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  Future<Uri> _webVoiceUri() async {
    final secure = ref.read(secureStoreProvider);
    final backendUrl = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    );
    final uri = Uri.parse(backendUrl);
    final path = uri.path.replaceFirst(RegExp(r'/mila/?$'), '');
    return uri.replace(
      path: path.isEmpty ? '/' : path,
      query: null,
      fragment: '/speech',
    );
  }

  Future<void> _openWebVoice() async {
    if (_webLaunchAttempted && _webLaunchError.isEmpty) return;
    setState(() {
      _webLaunchAttempted = true;
      _webLaunchError = '';
    });
    try {
      final uri = await _webVoiceUri();
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw StateError('Could not open $uri');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _webLaunchError = error.toString());
      }
    }
  }

  @override
  void deactivate() {
    // Leaving the screen ends the session.
    ref.read(voiceControllerProvider.notifier).stop();
    unawaited(_stopCamera());
    super.deactivate();
  }

  @override
  void dispose() {
    _completeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cameraTimer?.cancel();
    unawaited(_camera?.dispose());
    super.dispose();
  }

  /// Ends the session with a brief "task completed" beat (kit state
  /// COMPLETE) when a live conversation was running.
  void _endConversation() {
    final voiceState = ref.read(voiceControllerProvider);
    final hadConversation =
        voiceState.active && voiceState.phase != VoicePhase.connecting;
    ref.read(voiceControllerProvider.notifier).stop();
    if (hadConversation) {
      setState(() => _justCompleted = true);
      _completeTimer?.cancel();
      _completeTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _justCompleted = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);
    final assistantName = ref.watch(settingsProvider).assistantName;
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;

    if (!_useNativeVoice) {
      return Scaffold(
        body: MilaBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => context.push('/settings/providers'),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const AdaptiveOrb(
                    size: 184,
                    mood: OrbMood.attention,
                    level: 0.68,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    l10n.pick(
                      ru: 'MILA Live из Agentic OS',
                      en: 'Agentic OS MILA Live',
                      uz: 'Agentic OS MILA Live',
                    ),
                    textAlign: TextAlign.center,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.pick(
                      ru: 'Открываю веб-версию с тем же голосом, русской речью и настройками, что уже работают в Agentic OS.',
                      en: 'Opening the web version with the same voice, speech behavior and settings that already work in Agentic OS.',
                      uz: 'Agentic OS’da ishlayotgan bir xil ovoz va sozlamali web versiya ochilmoqda.',
                    ),
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: MilaColors.textSecondary,
                    ),
                  ),
                  if (_webLaunchError.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    GlassCard(
                      borderColor: MilaColors.danger.withValues(alpha: 0.4),
                      child: Text(
                        _webLaunchError,
                        textAlign: TextAlign.center,
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                  const Spacer(),
                  GradientButton(
                    label: l10n.pick(
                      ru: 'Открыть web MILA',
                      en: 'Open web MILA',
                      uz: 'Web MILA’ni ochish',
                    ),
                    icon: Icons.open_in_browser_rounded,
                    onPressed: () {
                      setState(() => _webLaunchAttempted = false);
                      unawaited(_openWebVoice());
                    },
                  ),
                  const SizedBox(height: 12),
                  GhostButton(
                    label: l10n.pick(
                      ru: 'Нативный Live как запасной',
                      en: 'Use native Live fallback',
                      uz: 'Native Live zaxira rejimi',
                    ),
                    icon: Icons.mic_rounded,
                    onPressed: () => setState(() => _useNativeVoice = true),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final (title, subtitle) = _justCompleted
        ? (
            l10n.pick(ru: 'Готово!', en: 'Done!', uz: 'Tayyor!'),
            l10n.pick(
              ru: 'Разговор сохранён',
              en: 'Conversation saved',
              uz: 'Suhbat saqlandi',
            ),
          )
        : switch (state.phase) {
            VoicePhase.idle => (
              l10n.pick(
                ru: 'Чем помочь?',
                en: 'How can I help?',
                uz: 'Qanday yordam beray?',
              ),
              l10n.pick(
                ru: 'Нажмите, чтобы говорить',
                en: 'Tap to speak',
                uz: 'Gapirish uchun bosing',
              ),
            ),
            VoicePhase.connecting => (
              l10n.pick(
                ru: 'Подключаюсь...',
                en: 'Connecting...',
                uz: 'Ulanmoqda...',
              ),
              l10n.pick(
                ru: 'Готовлю live-сессию',
                en: 'Setting up the live session',
                uz: 'Live sessiya tayyorlanmoqda',
              ),
            ),
            VoicePhase.listening => (
              l10n.pick(
                ru: 'Слушаю...',
                en: 'I\'m listening...',
                uz: 'Eshityapman...',
              ),
              l10n.pick(
                ru: 'Говорите естественно',
                en: 'Speak naturally',
                uz: 'Tabiiy gapiring',
              ),
            ),
            VoicePhase.thinking => (
              l10n.pick(
                ru: 'Думаю...',
                en: 'Thinking...',
                uz: 'O\'ylayapman...',
              ),
              l10n.pick(
                ru: 'Анализирую запрос',
                en: 'Analyzing your request',
                uz: 'So\'rovingiz tahlil qilinmoqda',
              ),
            ),
            VoicePhase.speaking => (
              l10n.pick(
                ru: '$assistantName говорит',
                en: '$assistantName is speaking',
                uz: '$assistantName gapiryapti',
              ),
              l10n.pick(
                ru: 'Нажмите на сферу, чтобы перебить',
                en: 'Tap the orb to interrupt',
                uz: 'To\'xtatish uchun sferani bosing',
              ),
            ),
            VoicePhase.error => (
              l10n.pick(
                ru: 'Что-то пошло не так',
                en: 'Something went wrong',
                uz: 'Nimadir xato ketdi',
              ),
              '',
            ),
          };

    final mood = _justCompleted
        ? OrbMood.complete
        : switch (state.phase) {
            VoicePhase.listening => OrbMood.listening,
            VoicePhase.thinking || VoicePhase.connecting => OrbMood.thinking,
            VoicePhase.speaking => OrbMood.speaking,
            VoicePhase.error => OrbMood.error,
            _ => OrbMood.idle,
          };

    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _camera == null
                        ? l10n.pick(
                            ru: 'Включить камеру',
                            en: 'Share camera',
                            uz: 'Kamerani ulash',
                          )
                        : l10n.pick(
                            ru: 'Остановить камеру',
                            en: 'Stop camera',
                            uz: 'Kamerani o\'chirish',
                          ),
                    icon: _cameraStarting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _camera == null
                                ? Icons.videocam_outlined
                                : Icons.videocam_rounded,
                            color: _camera == null ? null : MilaColors.cyan,
                          ),
                    onPressed: _cameraStarting ? null : _toggleCamera,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push('/settings/providers'),
                  ),
                ],
              ),
              const Spacer(),
              Text(title, style: text.headlineSmall),
              const SizedBox(height: 6),
              if (subtitle.isNotEmpty) Text(subtitle, style: text.bodySmall),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (state.phase == VoicePhase.speaking) {
                          controller.interrupt();
                        } else if (!state.active &&
                            state.phase != VoicePhase.connecting) {
                          controller.start();
                        }
                      },
                      child: AdaptiveOrb(
                        size: 230,
                        mood: mood,
                        level: state.phase == VoicePhase.speaking
                            ? state.outputLevel
                            : state.inputLevel,
                      ),
                    ),
                    if (_camera != null && _camera!.value.isInitialized)
                      Positioned(
                        right: 0,
                        top: 4,
                        child: Container(
                          width: 82,
                          height: 112,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: MilaColors.cyan),
                          ),
                          child: CameraPreview(_camera!),
                        ),
                      ),
                    if (_camera != null)
                      const Positioned(
                        right: 8,
                        bottom: 8,
                        child: _VisionBadge(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 120,
                child: SingleChildScrollView(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      if (state.userPartial.isNotEmpty)
                        Text(
                          state.userPartial,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: MilaColors.textSecondary,
                          ),
                        ),
                      if (state.assistantPartial.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          state.assistantPartial,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge,
                        ),
                      ],
                      if (state.phase == VoicePhase.error)
                        GlassCard(
                          borderColor: MilaColors.danger.withValues(alpha: 0.4),
                          child: Text(
                            state.error,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                child: state.active || state.phase == VoicePhase.connecting
                    ? GhostButton(
                        label: state.phase == VoicePhase.connecting
                            ? l10n.pick(
                                ru: 'Отмена',
                                en: 'Cancel',
                                uz: 'Bekor qilish',
                              )
                            : l10n.pick(
                                ru: 'Завершить разговор',
                                en: 'End conversation',
                                uz: 'Suhbatni tugatish',
                              ),
                        icon: Icons.stop_rounded,
                        onPressed: _endConversation,
                      )
                    : GradientButton(
                        label: state.phase == VoicePhase.error
                            ? l10n.pick(
                                ru: 'Повторить',
                                en: 'Try again',
                                uz: 'Qayta urinish',
                              )
                            : l10n.pick(
                                ru: 'Начать говорить',
                                en: 'Start talking',
                                uz: 'Gapirishni boshlash',
                              ),
                        icon: Icons.mic_rounded,
                        onPressed: () {
                          controller.dismissError();
                          controller.start();
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisionBadge extends StatelessWidget {
  const _VisionBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1422),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: MilaColors.cyan.withValues(alpha: 0.6)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility_rounded, size: 14, color: MilaColors.cyan),
        SizedBox(width: 5),
        Text('VISION LIVE', style: TextStyle(fontSize: 10)),
      ],
    ),
  );
}
