import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/config/app_config.dart';
import '../../data/models.dart';
import '../llm/llm_service.dart';
import '../storage/stores.dart';
import 'gemini_live_client.dart';
import 'gemini_live_token_service.dart';
import 'pcm_stream_player.dart';

enum VoicePhase { idle, connecting, listening, thinking, speaking, error }

class VoiceState {
  const VoiceState({
    this.phase = VoicePhase.idle,
    this.inputLevel = 0,
    this.outputLevel = 0,
    this.userPartial = '',
    this.assistantPartial = '',
    this.error = '',
  });

  final VoicePhase phase;
  final double inputLevel;
  final double outputLevel;
  final String userPartial;
  final String assistantPartial;
  final String error;

  bool get active =>
      phase == VoicePhase.listening ||
      phase == VoicePhase.thinking ||
      phase == VoicePhase.speaking;

  VoiceState copyWith({
    VoicePhase? phase,
    double? inputLevel,
    double? outputLevel,
    String? userPartial,
    String? assistantPartial,
    String? error,
  }) => VoiceState(
    phase: phase ?? this.phase,
    inputLevel: inputLevel ?? this.inputLevel,
    outputLevel: outputLevel ?? this.outputLevel,
    userPartial: userPartial ?? this.userPartial,
    assistantPartial: assistantPartial ?? this.assistantPartial,
    error: error ?? this.error,
  );
}

final voiceControllerProvider =
    StateNotifierProvider<VoiceController, VoiceState>(
      (ref) => VoiceController(ref),
    );

/// Runs a live voice session against the Gemini Live API:
/// microphone (16 kHz PCM16) → WebSocket → speaker (24 kHz PCM16),
/// with automatic server-side VAD, barge-in and transcript capture.
class VoiceController extends StateNotifier<VoiceState> {
  VoiceController(this._ref) : super(const VoiceState());

  final Ref _ref;

  GeminiLiveClient? _client;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  final PcmStreamPlayer _player = PcmStreamPlayer();
  bool _playerReady = false;

  final Queue<Uint8List> _playQueue = Queue();
  bool _draining = false;
  int _feedGeneration = 0; // bumped on interruption to drop stale audio

  String _userText = '';
  String _assistantText = '';
  bool _userCommitted = false;
  final List<String> _sessionTranscript = [];

  DateTime _lastMicVoice = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOutputChunk = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _ticker;
  String _sessionResumptionHandle = '';
  bool _resumeInProgress = false;

  /// Plays a short sample using the currently configured Gemini voice. This
  /// uses the same secured Live connection as a conversation, so users hear
  /// the actual selected voice rather than an unrelated device TTS voice.
  Future<void> previewVoice(String voiceName) async {
    if (state.active || state.phase == VoicePhase.connecting) return;
    state = const VoiceState(phase: VoicePhase.connecting);
    try {
      final credentials = await _liveCredentials();
      await _openPlayer();
      final settings = _ref.read(settingsProvider);
      final ready = Completer<void>();
      final client = GeminiLiveClient(
        apiKey: credentials.apiKey,
        accessToken: credentials.accessToken,
        model: settings.geminiLiveModel,
        voiceName: voiceName,
        systemInstruction:
            'You are MILA. Speak only the requested short voice sample.',
      );
      _client = client;
      client
        ..onReady = () {
          if (!ready.isCompleted) ready.complete();
        }
        ..onAudio = _onAudio
        ..onTurnComplete = () async {
          // Live sends turnComplete after its response/playback boundary.
          await Future<void>.delayed(const Duration(milliseconds: 350));
          if (_client == client) {
            _teardown();
            if (mounted) state = const VoiceState();
          }
        }
        ..onClosed = (reason) {
          if (_client == client && state.phase == VoicePhase.connecting) {
            _teardown();
            state = VoiceState(
              phase: VoicePhase.error,
              error: reason.isEmpty
                  ? 'Voice preview ended unexpectedly.'
                  : reason,
            );
          }
        }
        ..onError = (error) {
          if (!ready.isCompleted) ready.completeError(error);
        };

      await client.connect();
      await ready.future.timeout(const Duration(seconds: 12));
      state = const VoiceState(phase: VoicePhase.speaking);
      client.sendText(
        'Say exactly this short sample in the user\'s primary language: "Hello, I am MILA. Nice to meet you."',
      );
    } on TimeoutException {
      _teardown();
      state = const VoiceState(
        phase: VoicePhase.error,
        error: 'Voice preview timed out. Check your voice connection.',
      );
    } catch (error) {
      _teardown();
      state = VoiceState(phase: VoicePhase.error, error: '$error');
    }
  }

  Future<void> start() async {
    if (state.active || state.phase == VoicePhase.connecting) return;
    state = const VoiceState(phase: VoicePhase.connecting);

    try {
      if (!await _recorder.hasPermission()) {
        state = const VoiceState(
          phase: VoicePhase.error,
          error: 'Microphone permission is required for voice.',
        );
        return;
      }

      final credentials = await _liveCredentials();

      final settings = _ref.read(settingsProvider);
      final systemPrompt = _ref
          .read(llmServiceProvider)
          .buildSystemPrompt(forVoice: true);

      await _openPlayer();
      _sessionResumptionHandle = '';
      _resumeInProgress = false;

      final client = GeminiLiveClient(
        apiKey: credentials.apiKey,
        accessToken: credentials.accessToken,
        model: settings.geminiLiveModel,
        voiceName: settings.voiceName,
        systemInstruction: systemPrompt,
      );
      _client = client;

      final ready = Completer<void>();
      _wireConversationClient(client, ready);

      await client.connect();
      await ready.future.timeout(const Duration(seconds: 12));

      await _startMic();

      _userText = '';
      _assistantText = '';
      _userCommitted = false;
      _sessionTranscript.clear();
      state = const VoiceState(phase: VoicePhase.listening);
      _startTicker();
    } on TimeoutException {
      await stop();
      state = const VoiceState(
        phase: VoicePhase.error,
        error:
            'Could not establish the live session (timeout). Verify the Gemini key and Live model in Settings.',
      );
    } catch (e) {
      await stop();
      state = VoiceState(
        phase: VoicePhase.error,
        error: 'Could not start voice: $e',
      );
    }
  }

  Future<void> stop() async {
    _commitTranscripts(force: true);
    _teardown();
    state = const VoiceState();
    if (_sessionTranscript.isNotEmpty) {
      // Fire-and-forget: distill stable user facts into the Memory Vault.
      final transcript = List<String>.from(_sessionTranscript);
      _sessionTranscript.clear();
      unawaited(
        _ref.read(llmServiceProvider).mineMemoriesFromTranscript(transcript),
      );
    }
  }

  void dismissError() {
    if (state.phase == VoicePhase.error) state = const VoiceState();
  }

  Future<({String apiKey, String accessToken})> _liveCredentials() async {
    final secure = _ref.read(secureStoreProvider);
    final backendUrl = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    );
    final sessionToken =
        await secure.read(SecureStore.openAiAccountToken) ?? '';
    final apiKey =
        await secure.read(SecureStore.geminiKey) ??
        const String.fromEnvironment('GEMINI_API_KEY');
    String accessToken = '';
    String? secureTokenError;
    if (backendUrl.isNotEmpty && sessionToken.isNotEmpty) {
      try {
        accessToken = await GeminiLiveTokenService(
          baseUrl: backendUrl,
          sessionToken: sessionToken,
        ).createToken();
      } on GeminiLiveTokenException catch (error) {
        secureTokenError = error.message;
      }
    }
    if (accessToken.isEmpty && apiKey.isEmpty) {
      throw StateError(
        'Secure voice is unavailable. ${secureTokenError ?? 'Connect your MILA account or add a Gemini API key in Settings → AI Providers.'}',
      );
    }
    return (apiKey: apiKey, accessToken: accessToken);
  }

  // -------------------------------------------------------------------------
  // Microphone
  // -------------------------------------------------------------------------

  Future<void> _startMic() async {
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _micSub = stream.listen((chunk) {
      _client?.sendAudioChunk(chunk);
      final level = _rms16(chunk);
      if (level > 0.06) _lastMicVoice = DateTime.now();
      if (mounted && state.active) {
        state = state.copyWith(inputLevel: level);
      }
    });
  }

  void _wireConversationClient(GeminiLiveClient client, Completer<void> ready) {
    client
      ..onReady = () {
        if (!ready.isCompleted) ready.complete();
      }
      ..onAudio = _onAudio
      ..onInputTranscription = _onInputTranscription
      ..onOutputTranscription = _onOutputTranscription
      ..onTurnComplete = _onTurnComplete
      ..onInterrupted = _onInterrupted
      ..onSessionResumption = (handle) {
        _sessionResumptionHandle = handle;
      }
      ..onGoAway = (_) {
        if (_client == client && _sessionResumptionHandle.isNotEmpty) {
          unawaited(_resumeLiveSession(client));
        }
      }
      ..onClosed = (reason) {
        if (_client == client &&
            (state.active || state.phase == VoicePhase.connecting)) {
          _teardown();
          state = VoiceState(
            phase: VoicePhase.error,
            error: reason.isEmpty
                ? 'Voice session ended unexpectedly. Check your connection and try again.'
                : 'Voice session closed: $reason',
          );
        }
      }
      ..onError = (error) {
        if (!ready.isCompleted) ready.completeError(error);
      };
  }

  Future<void> _resumeLiveSession(GeminiLiveClient previous) async {
    if (_resumeInProgress || _client != previous || !state.active) return;
    _resumeInProgress = true;
    try {
      final handle = _sessionResumptionHandle;
      if (handle.isEmpty) return;

      final credentials = await _liveCredentials();
      final settings = _ref.read(settingsProvider);
      final systemPrompt = _ref
          .read(llmServiceProvider)
          .buildSystemPrompt(forVoice: true);
      final resumed = GeminiLiveClient(
        apiKey: credentials.apiKey,
        accessToken: credentials.accessToken,
        model: settings.geminiLiveModel,
        voiceName: settings.voiceName,
        systemInstruction: systemPrompt,
        sessionResumptionHandle: handle,
      );
      final ready = Completer<void>();
      _wireConversationClient(resumed, ready);
      await resumed.connect();
      await ready.future.timeout(const Duration(seconds: 12));

      if (!state.active || _client != previous) {
        await resumed.close();
        return;
      }
      _client = resumed;
      await previous.close();
    } catch (_) {
      // The existing connection remains active until Gemini closes it. If that
      // happens, the normal onClosed path shows a retryable error to the user.
    } finally {
      _resumeInProgress = false;
    }
  }

  double _rms16(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final data = Int16List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.length ~/ 2,
    );
    var sum = 0.0;
    // Sample every 4th value: plenty for a UI level meter.
    for (var i = 0; i < data.length; i += 4) {
      final v = data[i] / 32768.0;
      sum += v * v;
    }
    final rms = math.sqrt(sum / (data.length / 4).clamp(1, double.infinity));
    return (rms * 4).clamp(0.0, 1.0);
  }

  // -------------------------------------------------------------------------
  // Playback
  // -------------------------------------------------------------------------

  Future<void> _openPlayer() async {
    await _player.start(sampleRate: 24000);
    _playerReady = true;
  }

  Future<void> _ensurePlayerStream() async {
    if (!_playerReady || !_player.isStarted) {
      await _openPlayer();
    }
  }

  void _onAudio(Uint8List pcm) {
    _lastOutputChunk = DateTime.now();
    if (state.active && state.phase != VoicePhase.speaking) {
      _commitUserIfNeeded();
      state = state.copyWith(phase: VoicePhase.speaking);
    }
    if (state.active) {
      state = state.copyWith(outputLevel: _rms16(pcm));
    }
    _playQueue.add(pcm);
    _drainQueue();
  }

  Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    final generation = _feedGeneration;
    try {
      while (_playQueue.isNotEmpty && generation == _feedGeneration) {
        final chunk = _playQueue.removeFirst();
        await _ensurePlayerStream();
        await _player.write(chunk);
      }
    } catch (_) {
      // Player torn down mid-feed; drop remaining audio.
      _playQueue.clear();
    } finally {
      _draining = false;
    }
  }

  Future<void> _onInterrupted() async {
    // User barged in: flush queued audio immediately.
    _feedGeneration++;
    _playQueue.clear();
    _commitTranscripts();
    try {
      await _player.clear();
    } catch (_) {}
    if (state.active) {
      state = state.copyWith(phase: VoicePhase.listening, outputLevel: 0);
    }
  }

  // -------------------------------------------------------------------------
  // Transcripts
  // -------------------------------------------------------------------------

  void _onInputTranscription(String text) {
    _userText += text;
    if (state.active) state = state.copyWith(userPartial: _userText);
  }

  void _onOutputTranscription(String text) {
    _commitUserIfNeeded();
    _assistantText += text;
    if (state.active) {
      state = state.copyWith(assistantPartial: _assistantText);
    }
  }

  void _onTurnComplete() {
    _commitTranscripts();
  }

  void _commitUserIfNeeded() {
    if (_userCommitted || _userText.trim().isEmpty) return;
    _ref
        .read(chatProvider.notifier)
        .add(
          ChatMessage(
            role: ChatRole.user,
            text: _userText.trim(),
            viaVoice: true,
          ),
        );
    _sessionTranscript.add('User: ${_userText.trim()}');
    _userCommitted = true;
  }

  void _commitTranscripts({bool force = false}) {
    _commitUserIfNeeded();
    if (_assistantText.trim().isNotEmpty) {
      _ref
          .read(chatProvider.notifier)
          .add(
            ChatMessage(
              role: ChatRole.assistant,
              text: _assistantText.trim(),
              viaVoice: true,
            ),
          );
      _sessionTranscript.add('Assistant: ${_assistantText.trim()}');
    }
    _userText = '';
    _assistantText = '';
    _userCommitted = false;
    if (mounted && state.active && !force) {
      state = state.copyWith(userPartial: '', assistantPartial: '');
    }
  }

  // -------------------------------------------------------------------------
  // Phase heuristics
  // -------------------------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!state.active) return;
      final now = DateTime.now();
      final sinceOutput = now.difference(_lastOutputChunk).inMilliseconds;
      final sinceVoice = now.difference(_lastMicVoice).inMilliseconds;

      if (state.phase == VoicePhase.speaking &&
          sinceOutput > 900 &&
          _playQueue.isEmpty) {
        state = state.copyWith(phase: VoicePhase.listening, outputLevel: 0);
      } else if (state.phase == VoicePhase.listening &&
          _userText.trim().isNotEmpty &&
          sinceVoice > 900 &&
          _assistantText.isEmpty) {
        state = state.copyWith(phase: VoicePhase.thinking);
      } else if (state.phase == VoicePhase.thinking && sinceVoice < 300) {
        state = state.copyWith(phase: VoicePhase.listening);
      }
    });
  }

  // -------------------------------------------------------------------------

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    _feedGeneration++;
    _resumeInProgress = false;
    _sessionResumptionHandle = '';
    _playQueue.clear();
    _micSub?.cancel();
    _micSub = null;
    unawaited(_recorder.stop().catchError((_) => null));
    final client = _client;
    _client = null;
    unawaited(client?.close());
    if (_playerReady) {
      _playerReady = false;
      unawaited(_player.stop().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _teardown();
    unawaited(_player.dispose().catchError((_) {}));
    _recorder.dispose();
    super.dispose();
  }
}
