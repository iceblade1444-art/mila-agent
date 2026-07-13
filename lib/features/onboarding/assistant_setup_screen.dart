import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
import '../../services/soul/soul_service.dart';
import '../../services/storage/stores.dart';

/// A short first-run introduction shown before account sign-in.
class AssistantSetupScreen extends ConsumerStatefulWidget {
  const AssistantSetupScreen({super.key});

  @override
  ConsumerState<AssistantSetupScreen> createState() =>
      _AssistantSetupScreenState();
}

class _AssistantSetupScreenState extends ConsumerState<AssistantSetupScreen> {
  static const _languages = ['Русский', 'English', 'O\'zbekcha'];

  final _addressName = TextEditingController();
  final _assistantName = TextEditingController(text: 'MILA');
  final _formKey = GlobalKey<FormState>();
  AssistantVoiceGender _voiceGender = AssistantVoiceGender.female;
  String _personalityId = defaultAssistantPersonalityId;
  String _language = 'Русский';

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _addressName.text = ref.read(profileProvider).name;
    _assistantName.text = settings.assistantName;
    _voiceGender = assistantVoiceGenderFromName(settings.voiceName);
    _personalityId = settings.personalityId;
    if (_languages.contains(settings.language)) {
      _language = settings.language;
    }
  }

  @override
  void dispose() {
    _addressName.dispose();
    _assistantName.dispose();
    super.dispose();
  }

  void _finish() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final profile = ref.read(profileProvider);
    final updatedProfile = UserProfile(
      name: _addressName.text.trim(),
      email: profile.email,
      signedIn: profile.signedIn,
    );
    final personality = assistantPersonalityById(_personalityId);
    final updatedSettings = ref
        .read(settingsProvider)
        .copyWith(
          assistantName: _assistantName.text.trim(),
          voiceName: voiceNameForGender(_voiceGender),
          personalityId: personality.id,
          personality: personality.prompt,
          language: _language,
          assistantSetupDone: true,
        );
    ref.read(profileProvider.notifier).save(updatedProfile);
    ref.read(settingsProvider.notifier).update((_) => updatedSettings);
    ref.read(soulServiceProvider).save(updatedSettings, updatedProfile);

    if (!profile.signedIn) {
      context.go('/signin');
      return;
    }
    context.go(
      ref.read(settingsProvider).permissionsDone ? '/home' : '/permissions',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      const SizedBox(height: 18),
                      const Center(
                        child: VoiceOrb(size: 146, mood: OrbMood.attention),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Let\'s get acquainted',
                        textAlign: TextAlign.center,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Create an assistant that feels like yours.',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: MilaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _addressName,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          hintText: 'How MILA should address you',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Please enter your name'
                            : null,
                        onFieldSubmitted: (_) => _finish(),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _assistantName,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Assistant name',
                          hintText: 'For example: MILA, Nova, Atlas',
                          prefixIcon: Icon(Icons.auto_awesome_rounded),
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Please choose an assistant name'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'VOICE',
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _VoiceGenderCard(
                              label: 'Female',
                              subtitle: 'Warm and clear',
                              icon: Icons.female_rounded,
                              selected:
                                  _voiceGender == AssistantVoiceGender.female,
                              onTap: () => setState(
                                () =>
                                    _voiceGender = AssistantVoiceGender.female,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _VoiceGenderCard(
                              label: 'Male',
                              subtitle: 'Calm and confident',
                              icon: Icons.male_rounded,
                              selected:
                                  _voiceGender == AssistantVoiceGender.male,
                              onTap: () => setState(
                                () => _voiceGender = AssistantVoiceGender.male,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'PERSONALITY',
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 10),
                      for (final personality in assistantPersonalities) ...[
                        _PersonalityCard(
                          personality: personality,
                          selected: _personalityId == personality.id,
                          onTap: () =>
                              setState(() => _personalityId = personality.id),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'PRIMARY LANGUAGE',
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final language in _languages)
                            MilaChip(
                              label: language,
                              active: _language == language,
                              onTap: () => setState(() => _language = language),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: GradientButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _finish,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalityCard extends StatelessWidget {
  const _PersonalityCard({
    required this.personality,
    required this.selected,
    required this.onTap,
  });

  final AssistantPersonality personality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderColor: selected ? MilaColors.purple : MilaColors.cardBorder,
      color: selected ? MilaColors.purple.withValues(alpha: 0.09) : null,
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? MilaColors.purple : MilaColors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  personality.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  personality.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceGenderCard extends StatelessWidget {
  const _VoiceGenderCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      borderColor: selected ? MilaColors.cyan : MilaColors.cardBorder,
      color: selected ? MilaColors.cyan.withValues(alpha: 0.08) : null,
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 25,
                color: selected ? MilaColors.cyan : MilaColors.textSecondary,
              ),
              const Spacer(),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: selected ? MilaColors.cyan : MilaColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(label, style: text.titleSmall),
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(subtitle, style: text.bodySmall),
          ),
        ],
      ),
    );
  }
}
