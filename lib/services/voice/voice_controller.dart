import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:record/record.dart';

import '../../core/config/app_config.dart';
import '../../data/models.dart';
import '../agentic/agentic_os_service.dart';
import '../llm/llm_service.dart';
import '../storage/stores.dart';
import 'gemini_live_client.dart';
import 'gemini_live_token_service.dart';
import 'mila_live_tools.dart';
import 'mila_livekit_token_source.dart';
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
  lk.Session? _liveKitSession;
  bool _usingLiveKit = false;
  bool _liveKitWasSpeaking = false;
  Timer? _liveKitCommitTimer;
  final Set<String> _liveKitCommitted = {};
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  final PcmStreamPlayer _player = PcmStreamPlayer();
  bool _playerReady = false;

  final Queue<Uint8List> _playQueue = Queue();
  bool _draining = false;
  int _feedGeneration = 0; // bumped on interruption to drop stale audio
  bool _manualInterruption = false;
  bool _assistantActivitySeen = false;
  bool _audioStreamEndSent = false;

  String _userText = '';
  String _assistantText = '';
  bool _userCommitted = false;
  final List<String> _sessionTranscript = [];

  DateTime _lastMicVoice = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOutputChunk = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _ticker;
  Timer? _turnFallbackTimer;
  String _sessionResumptionHandle = '';
  bool _resumeInProgress = false;
  String _lastFallbackText = '';

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
      final assistantName = settings.assistantName;
      final ready = Completer<void>();
      final client = GeminiLiveClient(
        apiKey: credentials.apiKey,
        accessToken: credentials.accessToken,
        model: settings.geminiLiveModel,
        voiceName: voiceName,
        systemInstruction:
            'You are $assistantName. Speak only the requested short voice sample.',
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
        'Say exactly this short sample in the user\'s primary language: "Hello, I am $assistantName. Nice to meet you."',
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

      final settings = _ref.read(settingsProvider);
      final hasAgenticOsVoice = await _hasAgenticOsVoiceConfig();
      if (settings.voiceTransport == MilaVoiceTransport.livekit &&
          hasAgenticOsVoice) {
        if (await _startLiveKitIfAvailable()) {
          return;
        }
        state = const VoiceState(
          phase: VoicePhase.error,
          error:
              'Agentic OS voice bridge is unavailable. Check LiveKit and MILA server, then try again.',
        );
        return;
      }

      final credentials = await _liveCredentials();

      final basePrompt = _ref
          .read(llmServiceProvider)
          .buildSystemPrompt(forVoice: true);
      final erpPrompt = await _mobileErpVoiceContext();
      final systemPrompt = [
        basePrompt,
        erpPrompt,
      ].where((part) => part.trim().isNotEmpty).join('\n\n');

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
      _assistantActivitySeen = false;
      _audioStreamEndSent = false;
      _lastFallbackText = '';
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
    if (_usingLiveKit) {
      _commitLiveKitMessages(force: true);
      final session = _liveKitSession;
      _liveKitSession = null;
      _usingLiveKit = false;
      _liveKitCommitTimer?.cancel();
      _liveKitCommitTimer = null;
      if (session != null) {
        session
          ..removeListener(_onLiveKitChanged)
          ..agent.removeListener(_onLiveKitChanged);
        await session.end();
        session.dispose();
      }
      state = const VoiceState();
      if (_sessionTranscript.isNotEmpty) {
        final transcript = List<String>.from(_sessionTranscript);
        _sessionTranscript.clear();
        unawaited(
          _ref.read(llmServiceProvider).mineMemoriesFromTranscript(transcript),
        );
      }
      return;
    }
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

  void sendVideoFrame(Uint8List jpeg) {
    // Direct Gemini Live accepts inline video frames. LiveKit sessions publish
    // audio through the room; visual context is handled by Direct mode for now.
    if (state.active && !_usingLiveKit) _client?.sendVideoFrame(jpeg);
  }

  /// Stops the current answer and returns to listening. The microphone is
  /// intentionally gated while assistant audio is playing so the device
  /// speaker can never become a new user turn.
  Future<void> interrupt() async {
    if (_usingLiveKit) {
      await _liveKitSession?.room.localParticipant?.setMicrophoneEnabled(true);
      if (mounted) {
        state = state.copyWith(phase: VoicePhase.listening, outputLevel: 0);
      }
      return;
    }
    if (state.phase != VoicePhase.speaking) return;
    _manualInterruption = true;
    _feedGeneration++;
    _playQueue.clear();
    _lastOutputChunk = DateTime.fromMillisecondsSinceEpoch(0);
    _commitTranscripts();
    try {
      await _player.clear();
    } catch (_) {}
    if (mounted && state.active) {
      state = state.copyWith(
        phase: VoicePhase.listening,
        outputLevel: 0,
        assistantPartial: '',
      );
    }
  }

  Future<bool> _startLiveKitIfAvailable() async {
    lk.Session? session;
    try {
      final secure = _ref.read(secureStoreProvider);
      final backendUrl = AppConfig.configuredBackendUrl(
        await secure.read(SecureStore.milaBackendUrl),
      );
      final sessionToken =
          await secure.read(SecureStore.openAiAccountToken) ?? '';
      if (backendUrl.isEmpty || sessionToken.isEmpty) return false;

      final source = MilaLiveKitTokenSource(
        baseUrl: backendUrl,
        sessionToken: sessionToken,
        language: _liveLanguageCode(_ref.read(settingsProvider).language),
        profile: _liveProfile(
          _ref.read(settingsProvider),
          _ref.read(profileProvider),
        ),
      );
      session = lk.Session.fromFixedTokenSource(
        source,
        options: lk.SessionOptions(
          preConnectAudio: true,
          agentConnectTimeout: const Duration(seconds: 20),
        ),
      );
      _liveKitSession = session;
      _usingLiveKit = true;
      _liveKitWasSpeaking = false;
      _liveKitCommitted.clear();
      _sessionTranscript.clear();
      session
        ..addListener(_onLiveKitChanged)
        ..agent.addListener(_onLiveKitChanged);

      await session.start();
      if (session.error != null ||
          session.connectionState == lk.ConnectionState.disconnected) {
        await _discardLiveKitSession(session);
        return false;
      }

      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!session.agent.isConnected && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (session.error != null) break;
      }
      if (!session.agent.isConnected) {
        await _discardLiveKitSession(session);
        return false;
      }

      _onLiveKitChanged();
      return true;
    } catch (_) {
      if (session != null) {
        await _discardLiveKitSession(session);
      } else {
        _liveKitSession = null;
        _usingLiveKit = false;
      }
      return false;
    }
  }

  Future<bool> _hasAgenticOsVoiceConfig() async {
    final secure = _ref.read(secureStoreProvider);
    final backendUrl = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    );
    final sessionToken =
        await secure.read(SecureStore.openAiAccountToken) ?? '';
    return backendUrl.isNotEmpty && sessionToken.trim().isNotEmpty;
  }

  Future<void> _discardLiveKitSession(lk.Session session) async {
    session
      ..removeListener(_onLiveKitChanged)
      ..agent.removeListener(_onLiveKitChanged);
    try {
      await session.end();
    } catch (_) {
      // A failed ICE handshake can also make session shutdown throw.
    }
    session.dispose();
    if (identical(_liveKitSession, session)) {
      _liveKitSession = null;
    }
    _usingLiveKit = false;
    if (mounted) {
      state = const VoiceState(phase: VoicePhase.connecting);
    }
  }

  void _onLiveKitChanged() {
    final session = _liveKitSession;
    if (!mounted || !_usingLiveKit || session == null) return;
    final error = session.error;
    if (error != null) {
      state = VoiceState(phase: VoicePhase.error, error: error.message);
      return;
    }

    final agentState = session.agent.agentState;
    final phase = switch (agentState) {
      lk.AgentState.speaking => VoicePhase.speaking,
      lk.AgentState.thinking => VoicePhase.thinking,
      lk.AgentState.listening || lk.AgentState.idle => VoicePhase.listening,
      lk.AgentState.initializing || null => VoicePhase.connecting,
    };
    final messages = session.messages;
    final userPartial =
        messages
            .where((message) => message.content is lk.UserTranscript)
            .lastOrNull
            ?.content
            .text ??
        '';
    final assistantPartial =
        messages
            .where((message) => message.content is lk.AgentTranscript)
            .lastOrNull
            ?.content
            .text ??
        '';

    state = state.copyWith(
      phase: phase,
      userPartial: userPartial,
      assistantPartial: assistantPartial,
      error: '',
    );

    if (agentState == lk.AgentState.speaking) {
      _liveKitWasSpeaking = true;
      _commitLiveKitUsers();
    } else if (_liveKitWasSpeaking &&
        (agentState == lk.AgentState.listening ||
            agentState == lk.AgentState.idle)) {
      _liveKitWasSpeaking = false;
      _liveKitCommitTimer?.cancel();
      _liveKitCommitTimer = Timer(
        const Duration(milliseconds: 350),
        _commitLiveKitMessages,
      );
    }
  }

  void _commitLiveKitUsers() {
    final session = _liveKitSession;
    if (session == null) return;
    for (final message in session.messages) {
      if (message.content is! lk.UserTranscript &&
          message.content is! lk.UserInput) {
        continue;
      }
      _commitLiveKitMessage(message);
    }
  }

  void _commitLiveKitMessages({bool force = false}) {
    final session = _liveKitSession;
    if (session == null) return;
    for (final message in session.messages) {
      _commitLiveKitMessage(message);
    }
    if (mounted && state.active && !force) {
      state = state.copyWith(userPartial: '', assistantPartial: '');
    }
  }

  void _commitLiveKitMessage(lk.ReceivedMessage message) {
    if (_liveKitCommitted.contains(message.id)) return;
    final text = message.content.text.trim();
    if (text.isEmpty) return;
    final isUser =
        message.content is lk.UserTranscript || message.content is lk.UserInput;
    _ref
        .read(chatProvider.notifier)
        .add(
          ChatMessage(
            role: isUser ? ChatRole.user : ChatRole.assistant,
            text: text,
            viaVoice: true,
          ),
        );
    _sessionTranscript.add('${isUser ? 'User' : 'Assistant'}: $text');
    _liveKitCommitted.add(message.id);
    _ref.read(chatSyncProvider.notifier).schedule();
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
        accessToken =
            await GeminiLiveTokenService(
              baseUrl: backendUrl,
              sessionToken: sessionToken,
            ).createToken(
              language: _liveLanguageCode(_ref.read(settingsProvider).language),
            );
      } on GeminiLiveTokenException catch (error) {
        secureTokenError = error.message;
      }
    }
    if (accessToken.isEmpty && apiKey.isEmpty && sessionToken.isEmpty) {
      throw StateError(
        'MILA is not connected on this device. Open Settings > AI Providers, enter a new connection code, then tap Connect MILA account.',
      );
    }
    if (accessToken.isEmpty && apiKey.isEmpty) {
      throw StateError(
        'Secure voice is unavailable. ${secureTokenError ?? 'Gemini access is not included in this build.'}',
      );
    }
    return (apiKey: apiKey, accessToken: accessToken);
  }

  Future<String> _mobileErpVoiceContext() async {
    final secure = _ref.read(secureStoreProvider);
    final backendUrl = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    );
    final sessionToken =
        await secure.read(SecureStore.openAiAccountToken) ?? '';
    if (backendUrl.isEmpty || sessionToken.isEmpty) {
      return '''
MOBILE ERP CONTEXT
Agentic OS is not connected on this device. For Milana ERP questions, say you cannot verify live ERP data right now instead of guessing.''';
    }
    final root = backendUrl.endsWith('/')
        ? backendUrl.substring(0, backendUrl.length - 1)
        : backendUrl;
    try {
      final response = await http
          .get(
            Uri.parse('$root/v1/erp/context'),
            headers: {'Authorization': 'Bearer $sessionToken'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return '''
MOBILE ERP CONTEXT
Live ERP context could not be loaded from MILA server (${response.statusCode}). For ERP questions, say you cannot verify the data right now instead of guessing.''';
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return '';
      final instruction = (json['instruction'] as String? ?? '').trim();
      final context = instruction.isNotEmpty
          ? instruction
          : const JsonEncoder.withIndent('  ').convert(json);
      return '''
MOBILE ERP CONTEXT
Use this authoritative live ERP context for Milana business questions. If a requested fact is missing, say that it is not available right now. Never invent ERP facts.
Critical rule: готовые изделия / finished goods stock must come only from /warehouse-stock and /warehouse-map through finishedGoods / erp_finished_goods_stock. Do not answer finished-goods questions from production output, material inventory, GM summary, memory, or guesses.
Critical rule: this context covers the warehouse and near orders only — it does NOT contain the model catalogue. For any question about a model, an article code or what the factory makes, call find_models or get_model_details. Never say a model does not exist because it is absent from this context; it was never in it.
$context''';
    } catch (_) {
      return '''
MOBILE ERP CONTEXT
Live ERP context is temporarily unavailable. For ERP questions, say you cannot verify the data right now instead of guessing.''';
    }
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
      final level = _rms16(chunk);
      if (level > 0.06) {
        _lastMicVoice = DateTime.now();
        _audioStreamEndSent = false;
      }
      // Full-duplex speaker audio is easily picked up by the microphone on
      // phones without reliable hardware AEC. Keep listening visually, but
      // only transmit while the assistant is not speaking.
      final outputIsQuiet =
          DateTime.now().difference(_lastOutputChunk) >
          const Duration(milliseconds: 1400);
      if (state.phase != VoicePhase.speaking && outputIsQuiet) {
        _client?.sendAudioChunk(chunk);
      }
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
      ..onToolCall = _onToolCall
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

  /// Runs a personal action on Agentic OS and hands the raw result back to the
  /// model. These all touch the signed-in account's own desk and complete in one
  /// step, so there is nothing to confirm — the value of doing it by voice is
  /// that it happens while the user's hands are busy.
  Future<void> _runPersonalTool(
    String id,
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      final result = await _ref
          .read(agenticOsServiceProvider)
          .runMilaAction(name, args);
      _client?.sendToolResponse(id: id, name: name, response: result);
    } catch (error) {
      // The model has to know it failed, or it will report the reminder as set.
      _client?.sendToolResponse(
        id: id,
        name: name,
        response: {
          'ok': false,
          'error': error is AgenticOsException
              ? error.message
              : 'Agentic OS is unreachable',
          'rule':
              'This did not happen. Say so plainly instead of confirming it.',
        },
      );
    }
  }

  void _onToolCall(String id, String name, Map<String, dynamic> args) {
    if (milaPersonalToolNames.contains(name)) {
      unawaited(_runPersonalTool(id, name, args));
      return;
    }
    if (name != 'delegate_to_hermes') {
      _client?.sendToolResponse(
        id: id,
        name: name,
        response: const {'status': 'unsupported'},
      );
      return;
    }
    final title = args['title']?.toString().trim() ?? '';
    final details = args['details']?.toString().trim() ?? '';
    if (title.isEmpty) {
      _client?.sendToolResponse(
        id: id,
        name: name,
        response: const {'status': 'invalid', 'reason': 'title is required'},
      );
      return;
    }
    _ref
        .read(chatProvider.notifier)
        .add(
          ChatMessage(
            role: ChatRole.assistant,
            text: 'Review this task before I send it to Hermes.',
            viaVoice: true,
            actions: [
              MilaAction(
                type: ActionType.createTask,
                title: title,
                subtitle: details,
                payload: const {'source': 'voice'},
              ),
            ],
          ),
        );
    _client?.sendToolResponse(
      id: id,
      name: name,
      response: const {
        'status': 'pending_user_confirmation',
        'message': 'The task proposal is visible in MILA chat.',
      },
    );
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
    _assistantActivitySeen = true;
    _turnFallbackTimer?.cancel();
    _lastOutputChunk = DateTime.now();
    if (_manualInterruption) return;
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
    _manualInterruption = false;
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
    _scheduleTurnFallback();
  }

  void _onOutputTranscription(String text) {
    _turnFallbackTimer?.cancel();
    _assistantActivitySeen = true;
    _commitUserIfNeeded();
    _assistantText += text;
    if (state.active) {
      state = state.copyWith(assistantPartial: _assistantText);
    }
  }

  void _onTurnComplete() {
    _turnFallbackTimer?.cancel();
    _manualInterruption = false;
    if (_shouldFallbackToCompletedTextTurn()) {
      _sendCompletedTextFallback();
      return;
    }
    _commitTranscripts();
  }

  void _scheduleTurnFallback() {
    _turnFallbackTimer?.cancel();
    _turnFallbackTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || !state.active) return;
      final text = _userText.trim();
      if (text.isEmpty || text == _lastFallbackText) return;
      if (_assistantText.trim().isNotEmpty) return;
      if (DateTime.now().difference(_lastOutputChunk) <
          const Duration(milliseconds: 1200)) {
        return;
      }
      _sendCompletedTextFallback();
    });
  }

  bool _shouldFallbackToCompletedTextTurn() {
    final text = _userText.trim();
    if (text.isEmpty || text == _lastFallbackText) return false;
    if (_assistantActivitySeen || _assistantText.trim().isNotEmpty) {
      return false;
    }
    if (DateTime.now().difference(_lastOutputChunk) <
        const Duration(milliseconds: 800)) {
      return false;
    }
    return true;
  }

  void _sendCompletedTextFallback() {
    final text = _userText.trim();
    if (text.isEmpty || text == _lastFallbackText) return;
    _lastFallbackText = text;
    _audioStreamEndSent = true;
    _commitUserIfNeeded();
    _client?.sendClientTurn(text);
    if (mounted && state.active) {
      state = state.copyWith(phase: VoicePhase.thinking);
    }
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
    _ref.read(chatSyncProvider.notifier).schedule();
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
      _ref.read(chatSyncProvider.notifier).schedule();
    }
    _userText = '';
    _assistantText = '';
    _userCommitted = false;
    _assistantActivitySeen = false;
    _audioStreamEndSent = false;
    _lastFallbackText = '';
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
        if (!_audioStreamEndSent) {
          _audioStreamEndSent = true;
          _client?.sendAudioStreamEnd();
        }
        state = state.copyWith(phase: VoicePhase.thinking);
      } else if (state.phase == VoicePhase.thinking && sinceVoice < 300) {
        state = state.copyWith(phase: VoicePhase.listening);
      }
    });
  }

  // -------------------------------------------------------------------------

  void _teardown() {
    _turnFallbackTimer?.cancel();
    _turnFallbackTimer = null;
    _liveKitCommitTimer?.cancel();
    _liveKitCommitTimer = null;
    _ticker?.cancel();
    _ticker = null;
    _feedGeneration++;
    _resumeInProgress = false;
    _manualInterruption = false;
    _audioStreamEndSent = false;
    _sessionResumptionHandle = '';
    _playQueue.clear();
    _micSub?.cancel();
    _micSub = null;
    unawaited(_recorder.stop().catchError((_) => null));
    final client = _client;
    _client = null;
    _assistantActivitySeen = false;
    _lastFallbackText = '';
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

Map<String, dynamic> _liveProfile(AppSettings settings, UserProfile profile) =>
    {
      'voiceName': settings.voiceName,
      'style': settings.conversationStyle.name,
      'pace': settings.speakingPace.name,
      'delivery': settings.deliveryStyle.name,
      'listeningProfile': settings.listeningProfile.name,
      'responseLength': settings.responseLength.name,
      'transport': settings.voiceTransport.name,
      'persona': settings.personality,
      'voiceDirection': settings.voiceDirection,
      'affectiveDialog': settings.affectiveDialog,
      'proactiveAudio': settings.proactiveAudio,
      'userName': profile.name.trim().isEmpty ? 'Бахадыр' : profile.name.trim(),
    };

String _liveLanguageCode(String language) {
  final normalized = language.trim().toLowerCase();
  if (normalized.contains('uz') || normalized.contains('o\'zbek')) {
    return 'uz-UZ';
  }
  if (normalized.contains('english') || normalized == 'en') return 'en-US';
  if (normalized.contains('рус') || normalized == 'ru') return 'ru-RU';
  return 'auto';
}
