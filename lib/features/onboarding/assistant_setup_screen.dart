import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
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
  static const _languages = supportedMilaLanguageNames;

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
    final l10n = context.l10n;
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
                        l10n.pick(
                          ru: 'Давайте познакомимся',
                          en: 'Let\'s get acquainted',
                          uz: 'Keling, tanishamiz',
                        ),
                        textAlign: TextAlign.center,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.pick(
                          ru: 'Настройте помощницу так, чтобы она была именно вашей.',
                          en: 'Create an assistant that feels like yours.',
                          uz: 'Yordamchini o\'zingizga mos qilib sozlang.',
                        ),
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: MilaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.pick(
                          ru: 'ЯЗЫК ИНТЕРФЕЙСА',
                          en: 'INTERFACE LANGUAGE',
                          uz: 'INTERFEYS TILI',
                        ),
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
                              onTap: () {
                                setState(() => _language = language);
                                ref
                                    .read(settingsProvider.notifier)
                                    .update(
                                      (s) => s.copyWith(language: language),
                                    );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _addressName,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.name],
                        decoration:
                            const InputDecoration(
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ).copyWith(
                              labelText: l10n.pick(
                                ru: 'Ваше имя',
                                en: 'Your name',
                                uz: 'Ismingiz',
                              ),
                              hintText: l10n.pick(
                                ru: 'Как MILA должна к вам обращаться',
                                en: 'How MILA should address you',
                                uz: 'MILA sizga qanday murojaat qilsin',
                              ),
                            ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? l10n.pick(
                                ru: 'Введите ваше имя',
                                en: 'Please enter your name',
                                uz: 'Ismingizni kiriting',
                              )
                            : null,
                        onFieldSubmitted: (_) => _finish(),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _assistantName,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(
                              prefixIcon: Icon(Icons.auto_awesome_rounded),
                            ).copyWith(
                              labelText: l10n.pick(
                                ru: 'Имя ассистентки',
                                en: 'Assistant name',
                                uz: 'Yordamchi nomi',
                              ),
                              hintText: l10n.pick(
                                ru: 'Например: MILA, Nova, Atlas',
                                en: 'For example: MILA, Nova, Atlas',
                                uz: 'Masalan: MILA, Nova, Atlas',
                              ),
                            ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? l10n.pick(
                                ru: 'Выберите имя ассистентки',
                                en: 'Please choose an assistant name',
                                uz: 'Yordamchi nomini tanlang',
                              )
                            : null,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.pick(ru: 'ГОЛОС', en: 'VOICE', uz: 'OVOZ'),
                        style: text.labelSmall?.copyWith(letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _VoiceGenderCard(
                              label: l10n.voiceGender('female'),
                              subtitle: l10n.pick(
                                ru: 'Тёплый и чистый',
                                en: 'Warm and clear',
                                uz: 'Iliq va aniq',
                              ),
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
                              label: l10n.voiceGender('male'),
                              subtitle: l10n.pick(
                                ru: 'Спокойный и уверенный',
                                en: 'Calm and confident',
                                uz: 'Xotirjam va ishonchli',
                              ),
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
                        l10n.pick(
                          ru: 'ХАРАКТЕР',
                          en: 'PERSONALITY',
                          uz: 'XARAKTER',
                        ),
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
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: GradientButton(
                    label: l10n.pick(
                      ru: 'Продолжить',
                      en: 'Continue',
                      uz: 'Davom etish',
                    ),
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
                  MilaLocalizations.of(
                    context,
                  ).personalityTitle(personality.id),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  MilaLocalizations.of(
                    context,
                  ).personalitySubtitle(personality.id),
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
