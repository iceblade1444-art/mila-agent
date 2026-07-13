import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/voice/voice_controller.dart';

/// Live voice session (design screens 06–09): idle → listening →
/// thinking → speaking, with real-time transcripts from the Gemini Live API.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  bool _justCompleted = false;
  Timer? _completeTimer;

  @override
  void deactivate() {
    // Leaving the screen ends the session.
    ref.read(voiceControllerProvider.notifier).stop();
    super.deactivate();
  }

  @override
  void dispose() {
    _completeTimer?.cancel();
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
    final text = Theme.of(context).textTheme;

    final (title, subtitle) = _justCompleted
        ? ('Done!', 'Conversation saved')
        : switch (state.phase) {
            VoicePhase.idle => ('How can I help?', 'Tap to speak'),
            VoicePhase.connecting => (
                'Connecting…',
                'Setting up the live session'
              ),
            VoicePhase.listening => ('I\'m listening…', 'Speak naturally'),
            VoicePhase.thinking => ('Thinking…', 'Analyzing your request'),
            VoicePhase.speaking => (
                'MILA is speaking',
                'Tap the orb to interrupt'
              ),
            VoicePhase.error => ('Something went wrong', ''),
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
              GestureDetector(
                onTap: () =>
                    state.active ? _endConversation() : controller.start(),
                child: AdaptiveOrb(
                  size: 230,
                  mood: mood,
                  level: state.phase == VoicePhase.speaking
                      ? state.outputLevel
                      : state.inputLevel,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 120,
                child: SingleChildScrollView(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 8),
                  child: Column(
                    children: [
                      if (state.userPartial.isNotEmpty)
                        Text(
                          state.userPartial,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium
                              ?.copyWith(color: MilaColors.textSecondary),
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
                          borderColor:
                              MilaColors.danger.withValues(alpha: 0.4),
                          child: Text(state.error,
                              textAlign: TextAlign.center,
                              style: text.bodyMedium),
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
                            ? 'Cancel'
                            : 'End conversation',
                        icon: Icons.stop_rounded,
                        onPressed: _endConversation,
                      )
                    : GradientButton(
                        label: state.phase == VoicePhase.error
                            ? 'Try again'
                            : 'Start talking',
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
