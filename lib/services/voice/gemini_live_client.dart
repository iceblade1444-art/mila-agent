import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Low-level client for the Gemini Live API
/// (BidiGenerateContent over WebSocket).
///
/// Protocol: send a `setup` frame, wait for `setupComplete`, then stream
/// 16 kHz PCM16 microphone audio up and receive 24 kHz PCM16 audio plus
/// input/output transcriptions down. Server-side VAD handles turn taking
/// and barge-in (an `interrupted` signal tells us to flush playback).
class GeminiLiveClient {
  GeminiLiveClient({
    this.apiKey = '',
    this.accessToken = '',
    required this.model,
    this.voiceName = 'Aoede',
    this.systemInstruction = '',
  });

  /// A direct key is supported for local development / a user's own key.
  final String apiKey;

  /// A short-lived server-minted credential used for production sessions.
  final String accessToken;
  final String model;
  final String voiceName;
  final String systemInstruction;

  static const _keyEndpoint =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
  static const _tokenEndpoint =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _setupDone = false;

  // Callbacks wired by the voice controller.
  void Function()? onReady;
  void Function(Uint8List pcm24k)? onAudio;
  void Function(String text)? onInputTranscription;
  void Function(String text)? onOutputTranscription;
  void Function()? onTurnComplete;
  void Function()? onInterrupted;
  void Function(String reason)? onClosed;
  void Function(Object error)? onError;

  bool get isConnected => _channel != null && _setupDone;

  Future<void> connect() async {
    if (apiKey.isEmpty && accessToken.isEmpty) {
      throw StateError('A Gemini API key or short-lived access token is required.');
    }
    final uri = accessToken.isNotEmpty
        ? Uri.parse('$_tokenEndpoint?access_token=${Uri.encodeQueryComponent(accessToken)}')
        : Uri.parse('$_keyEndpoint?key=${Uri.encodeQueryComponent(apiKey)}');
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _setupDone = false;

    _subscription = channel.stream.listen(
      _handleFrame,
      onError: (Object e) => onError?.call(e),
      onDone: () {
        final reason = channel.closeReason ?? '';
        _setupDone = false;
        onClosed?.call(reason);
      },
      cancelOnError: false,
    );

    await channel.ready;

    _send({
      'setup': {
        'model': 'models/$model',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voiceName},
            },
          },
        },
        if (systemInstruction.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': systemInstruction},
            ],
          },
        'inputAudioTranscription': <String, dynamic>{},
        'outputAudioTranscription': <String, dynamic>{},
      },
    });
  }

  /// Streams a chunk of 16 kHz mono PCM16 microphone audio.
  void sendAudioChunk(Uint8List pcm16k) {
    if (!isConnected) return;
    _send({
      'realtimeInput': {
        'audio': {
          'data': base64Encode(pcm16k),
          'mimeType': 'audio/pcm;rate=16000',
        },
      },
    });
  }

  /// Sends a typed message into the live session.
  void sendText(String text) {
    if (!isConnected) return;
    _send({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    });
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } catch (e) {
      onError?.call(e);
    }
  }

  void _handleFrame(dynamic frame) {
    final String text;
    if (frame is String) {
      text = frame;
    } else if (frame is List<int>) {
      text = utf8.decode(frame, allowMalformed: true);
    } else {
      return;
    }

    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (msg.containsKey('setupComplete')) {
      _setupDone = true;
      onReady?.call();
      return;
    }

    final serverContent = msg['serverContent'] as Map<String, dynamic>?;
    if (serverContent != null) {
      if (serverContent['interrupted'] == true) {
        onInterrupted?.call();
      }

      final input =
          serverContent['inputTranscription'] as Map<String, dynamic>?;
      final inputText = input?['text'] as String?;
      if (inputText != null && inputText.isNotEmpty) {
        onInputTranscription?.call(inputText);
      }

      final output =
          serverContent['outputTranscription'] as Map<String, dynamic>?;
      final outputText = output?['text'] as String?;
      if (outputText != null && outputText.isNotEmpty) {
        onOutputTranscription?.call(outputText);
      }

      _emitAudioFrom(serverContent['modelTurn']);

      if (serverContent['turnComplete'] == true) {
        onTurnComplete?.call();
      }
    }

    if (msg.containsKey('goAway')) {
      onClosed?.call('Server requested disconnect');
    }
  }

  Future<void> close() async {
    _setupDone = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _emitAudioFrom(dynamic value) {
    if (value is List) {
      for (final item in value) {
        _emitAudioFrom(item);
      }
      return;
    }
    if (value is! Map) return;

    final inline = value['inlineData'] ?? value['inline_data'];
    if (inline is Map) {
      final mimeType = (inline['mimeType'] ?? inline['mime_type'] ?? '')
          .toString();
      final data = inline['data'] as String?;
      if (data != null &&
          data.isNotEmpty &&
          (mimeType.isEmpty || mimeType.contains('audio'))) {
        try {
          onAudio?.call(base64Decode(data));
        } catch (_) {}
      }
    }

    for (final child in value.values) {
      if (child is Map || child is List) _emitAudioFrom(child);
    }
  }
}
