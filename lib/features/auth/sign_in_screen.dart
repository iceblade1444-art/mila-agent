import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
import '../../services/auth/google_auth_service.dart';
import '../../services/soul/soul_service.dart';
import '../../services/storage/stores.dart';

/// Local account screen. MILA keeps all data on-device; if you later add a
/// backend, wire this form to it and keep the same profile store contract.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _creating = false;
  bool _localBusy = false;
  bool _googleBusy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_localBusy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _localBusy = true);
    final email = _email.text.trim();
    final existing = ref.read(profileProvider);
    // Keep the name chosen during first-run setup.
    var name = _name.text.trim();
    if (existing.name.isNotEmpty) name = existing.name;
    if (name.isEmpty) {
      final prefix = email.split('@').first;
      name = prefix[0].toUpperCase() + prefix.substring(1);
    }
    ref
        .read(profileProvider.notifier)
        .save(UserProfile(name: name, email: email, signedIn: true));
    await ref
        .read(soulServiceProvider)
        .save(ref.read(settingsProvider), ref.read(profileProvider));
    if (!mounted) return;
    context.go(
      ref.read(settingsProvider).assistantSetupDone
          ? '/permissions'
          : '/assistant-setup',
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_googleBusy) return;
    setState(() => _googleBusy = true);
    try {
      final account = await ref.read(googleAuthServiceProvider).signIn();
      final existing = ref.read(profileProvider);
      final profile = UserProfile(
        name: existing.name.isNotEmpty
            ? existing.name
            : (account.displayName ?? account.email.split('@').first),
        email: account.email,
        signedIn: true,
      );
      ref.read(profileProvider.notifier).save(profile);
      await ref
          .read(soulServiceProvider)
          .save(ref.read(settingsProvider), profile);
      if (!mounted) return;
      context.go(
        ref.read(settingsProvider).assistantSetupDone
            ? '/permissions'
            : '/assistant-setup',
      );
    } on GoogleAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    const googleConfigured = GoogleAuthService.isConfigured;
    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 36),
                  const Center(child: VoiceOrb(size: 130)),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      _creating
                          ? l10n.pick(
                              ru: 'Создать аккаунт',
                              en: 'Create account',
                              uz: 'Akkaunt yaratish',
                            )
                          : l10n.pick(
                              ru: 'С возвращением',
                              en: 'Welcome back',
                              uz: 'Xush kelibsiz',
                            ),
                      style: text.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      _creating
                          ? l10n.pick(
                              ru: 'Настройте локальный профиль MILA',
                              en: 'Set up your local MILA profile',
                              uz: 'Mahalliy MILA profilingizni sozlang',
                            )
                          : l10n.pick(
                              ru: 'Войдите, чтобы продолжить',
                              en: 'Sign in to continue',
                              uz: 'Davom etish uchun kiring',
                            ),
                      style: text.bodyMedium?.copyWith(
                        color: MilaColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_creating) ...[
                    Text(
                      l10n.pick(
                        ru: 'Ваше имя',
                        en: 'Your name',
                        uz: 'Ismingiz',
                      ),
                      style: text.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _name,
                      keyboardType: TextInputType.name,
                      autofillHints: const [AutofillHints.name],
                      decoration: InputDecoration(
                        hintText: l10n.pick(
                          ru: 'Как MILA должна вас называть?',
                          en: 'How should MILA call you?',
                          uz: 'MILA sizni qanday chaqirsin?',
                        ),
                      ),
                      validator: (v) => (v ?? '').trim().isNotEmpty
                          ? null
                          : l10n.pick(
                              ru: 'Введите имя',
                              en: 'Enter your name',
                              uz: 'Ismingizni kiriting',
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Email', style: text.labelMedium),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      hintText: 'hello@milaai.app',
                    ),
                    validator: (v) =>
                        v != null && v.contains('@') && v.contains('.')
                        ? null
                        : l10n.pick(
                            ru: 'Введите корректный email',
                            en: 'Enter a valid email',
                            uz: 'To\'g\'ri email kiriting',
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.pick(ru: 'Пароль', en: 'Password', uz: 'Parol'),
                        style: text.labelMedium,
                      ),
                      Text(
                        l10n.pick(
                          ru: 'Забыли?',
                          en: 'Forgot?',
                          uz: 'Unutdingizmi?',
                        ),
                        style: text.labelMedium?.copyWith(
                          color: MilaColors.cyan,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '••••••••••'),
                    validator: (v) => (v ?? '').length >= 6
                        ? null
                        : l10n.pick(
                            ru: 'Минимум 6 символов',
                            en: 'At least 6 characters',
                            uz: 'Kamida 6 belgi',
                          ),
                  ),
                  const SizedBox(height: 28),
                  GradientButton(
                    label: _creating
                        ? l10n.pick(
                            ru: 'Создать аккаунт',
                            en: 'Create Account',
                            uz: 'Akkaunt yaratish',
                          )
                        : l10n.pick(ru: 'Войти', en: 'Sign In', uz: 'Kirish'),
                    busy: _localBusy,
                    onPressed: _localBusy ? null : () => unawaited(_submit()),
                  ),
                  if (googleConfigured) ...[
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            l10n.pick(
                              ru: 'или продолжить через',
                              en: 'or continue with',
                              uz: 'yoki davom etish',
                            ),
                            style: text.labelSmall,
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GhostButton(
                      label: _googleBusy
                          ? l10n.pick(
                              ru: 'Подключаю Google...',
                              en: 'Connecting to Google...',
                              uz: 'Google ulanmoqda...',
                            )
                          : l10n.pick(
                              ru: 'Продолжить с Google',
                              en: 'Continue with Google',
                              uz: 'Google orqali davom etish',
                            ),
                      icon: Icons.g_mobiledata_rounded,
                      onPressed: _googleBusy ? null : _signInWithGoogle,
                    ),
                  ],
                  const SizedBox(height: 32),
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() => _creating = !_creating),
                      child: Text.rich(
                        TextSpan(
                          text: _creating
                              ? l10n.pick(
                                  ru: 'Уже есть аккаунт? ',
                                  en: 'Already have an account? ',
                                  uz: 'Akkauntingiz bormi? ',
                                )
                              : l10n.pick(
                                  ru: 'Впервые в MILA? ',
                                  en: 'New to MILA? ',
                                  uz: 'MILA’da yangimisiz? ',
                                ),
                          style: text.bodySmall,
                          children: [
                            TextSpan(
                              text: _creating
                                  ? l10n.pick(
                                      ru: 'Войти',
                                      en: 'Sign in',
                                      uz: 'Kirish',
                                    )
                                  : l10n.pick(
                                      ru: 'Создать аккаунт',
                                      en: 'Create account',
                                      uz: 'Akkaunt yaratish',
                                    ),
                              style: text.bodySmall?.copyWith(
                                color: MilaColors.cyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
