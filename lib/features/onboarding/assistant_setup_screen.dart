import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
import '../../features/settings/orb_skin_picker.dart';
import '../../services/storage/stores.dart';
import '../../services/voice/voice_controller.dart';

/// Shown once right after registration: pick the voice assistant's
/// defaults (voice, language, character). Everything stays editable
/// later in Settings.
class AssistantSetupScreen extends ConsumerStatefulWidget {
  const AssistantSetupScreen({super.key});

  @override
  ConsumerState<AssistantSetupScreen> createState() =>
      _AssistantSetupScreenState();
}

class _AssistantSetupScreenState extends ConsumerState<AssistantSetupScreen> {
  static const _voices = [
    'Aoede',
    'Puck',
    'Charon',
    'Kore',
    'Fenrir',
    'Leda',
    'Orus',
    'Zephyr',
  ];

  static const _languages = [
    'Русский',
    'English',
    'O\'zbekcha',
  ];

  static const _styles = <(String, String, String, IconData)>[
    (
      'Warm & friendly',
      'Casual, encouraging, a little playful.',
      'Warm, friendly and a little playful. Encouraging tone, casual wording, keep answers short and useful.',
      Icons.favorite_outline_rounded,
    ),
    (
      'Professional & brief',
      'To the point, no fluff, business tone.',
      'Professional and concise. Business tone, no filler words, answer first, details only when asked.',
      Icons.work_outline_rounded,
    ),
    (
      'Playful & energetic',
      'Upbeat, witty, loves a good joke.',
      'Playful, energetic and witty. Upbeat tone, light humor where appropriate, still helpful and clear.',
      Icons.celebration_outlined,
    ),
  ];

  String _voice = 'Aoede';
  String _language = 'Русский';
  int _style = 0;
  OrbSkin _skin = OrbSkin.nebula;
  final _addressName = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _addressName.text = ref.read(profileProvider).name;
    _voice = s.voiceName;
    _skin = orbSkinFromName(s.orbSkin);
    if (_languages.contains(s.language)) _language = s.language;
  }

  @override
  void dispose() {
    _addressName.dispose();
    super.dispose();
  }

  void _finish() {
    final name = _addressName.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tell MILA how to address you.')),
      );
      return;
    }
    final profile = ref.read(profileProvider);
    ref.read(profileProvider.notifier).save(
          UserProfile(
            name: name,
            email: profile.email,
            signedIn: profile.signedIn,
          ),
        );
    final settings = ref.read(settingsProvider.notifier);
    settings.update((s) => s.copyWith(
          voiceName: _voice,
          language: _language,
          personality: _styles[_style].$3,
          assistantSetupDone: true,
          orbSkin: _skin.name,
        ));
    final permissionsDone = ref.read(settingsProvider).permissionsDone;
    context.go(permissionsDone ? '/home' : '/permissions');
  }

  Future<void> _previewVoice() async {
    await ref.read(voiceControllerProvider.notifier).previewVoice(_voice);
    if (!mounted) return;
    final voice = ref.read(voiceControllerProvider);
    if (voice.phase == VoicePhase.error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(voice.error)));
      ref.read(voiceControllerProvider.notifier).dismissError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const SizedBox(height: 20),
                    Center(child: VoiceOrb(size: 110, skin: _skin)),
                    const SizedBox(height: 18),
                    Center(
                        child: Text('Set up your assistant',
                            style: text.headlineMedium)),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Pick MILA\'s defaults — you can change them anytime in Settings.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'HOW SHOULD MILA ADDRESS YOU?',
                      style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressName,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Your preferred name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('VOICE',
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in _voices)
                          MilaChip(
                            label: v,
                            active: _voice == v,
                            onTap: () => setState(() => _voice = v),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: 'Listen to $_voice',
                      icon: Icons.volume_up_outlined,
                      onPressed: _previewVoice,
                    ),
                    const SizedBox(height: 22),
                    Text('ORB SKIN',
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (final skin in OrbSkin.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: GestureDetector(
                                onTap: () => setState(() => _skin = skin),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: _skin == skin
                                          ? MilaColors.cyan
                                          : MilaColors.cardBorder,
                                      width: _skin == skin ? 1.6 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      VoiceOrb(
                                          size: 62,
                                          skin: skin,
                                          mood: OrbMood.idle),
                                      const SizedBox(height: 4),
                                      Text(
                                        orbSkinLabels[skin]!,
                                        style: text.labelSmall?.copyWith(
                                            fontSize: 10,
                                            color: _skin == skin
                                                ? MilaColors.cyan
                                                : MilaColors
                                                    .textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('LANGUAGE',
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in _languages)
                          MilaChip(
                            label: l,
                            active: _language == l,
                            onTap: () => setState(() => _language = l),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('CHARACTER',
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    for (final (i, style) in _styles.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          onTap: () => setState(() => _style = i),
                          borderColor: _style == i
                              ? MilaColors.violet
                              : MilaColors.cardBorder,
                          color: _style == i
                              ? MilaColors.violet.withValues(alpha: 0.10)
                              : null,
                          child: Row(
                            children: [
                              TileIcon(
                                  icon: style.$4,
                                  color: _style == i
                                      ? MilaColors.cyan
                                      : MilaColors.violet),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(style.$1, style: text.titleSmall),
                                    const SizedBox(height: 3),
                                    Text(style.$2, style: text.bodySmall),
                                  ],
                                ),
                              ),
                              if (_style == i)
                                const Icon(Icons.check_circle_rounded,
                                    color: MilaColors.cyan, size: 22),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: GradientButton(label: 'Continue', onPressed: _finish),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
