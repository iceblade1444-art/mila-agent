import 'package:flutter/services.dart';

/// Thin bridge to Android's streaming AudioTrack player.
///
/// Gemini Live returns mono PCM16 at 24 kHz. Keeping one native AudioTrack
/// alive for the whole conversation avoids truncating audio that is still in
/// the device buffer when a model turn completes.
class PcmStreamPlayer {
  static const _channel = MethodChannel('app.milaai.mila/pcm_player');

  bool _started = false;

  bool get isStarted => _started;

  Future<void> start({int sampleRate = 24000}) async {
    await _channel.invokeMethod<void>('start', {'sampleRate': sampleRate});
    _started = true;
  }

  Future<void> write(Uint8List pcm) async {
    if (!_started || pcm.isEmpty) return;
    await _channel.invokeMethod<void>('write', pcm);
  }

  Future<void> clear() async {
    if (!_started) return;
    await _channel.invokeMethod<void>('clear');
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _channel.invokeMethod<void>('stop');
  }

  Future<void> dispose() => stop();
}
