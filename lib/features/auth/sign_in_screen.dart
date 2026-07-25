import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
import '../../services/auth/mila_account_service.dart';
import '../../services/soul/soul_service.dart';
import '../../services/storage/stores.dart';

/// Uses the same Agentic OS account as the web application.
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
    try {
      final secure = ref.read(secureStoreProvider);
      final baseUrl =
          await secure.read(SecureStore.milaBackendUrl) ??
          'https://agent.milanapremium.uz/mila';
      final service = const MilaAccountService();
      final session = _creating
          ? await service.register(
              baseUrl: baseUrl,
              name: _name.text,
              email: _email.text,
              password: _password.text,
            )
          : await service.signIn(
              baseUrl: baseUrl,
              email: _email.text,
              password: _password.text,
            );
      await secure.write(SecureStore.milaBackendUrl, baseUrl);
      await secure.write(
        SecureStore.agenticOsAccessToken,
        session.accountToken,
      );
      await secure.write(SecureStore.openAiAccountToken, session.token);
      await secure.write(SecureStore.openAiAccountLabel, session.label);
      final profile = UserProfile(
        name: session.ownerName,
        email: session.ownerEmail,
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('FormatException: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
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
                              ru: 'Один аккаунт для телефона и Agentic OS',
                              en: 'One account for mobile and Agentic OS',
                              uz: 'Telefon va Agentic OS uchun bitta akkaunt',
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
                  Text(
                    l10n.pick(ru: 'Пароль', en: 'Password', uz: 'Parol'),
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '••••••••••'),
                    validator: (v) => (v ?? '').length >= 10
                        ? null
                        : l10n.pick(
                            ru: 'Минимум 10 символов',
                            en: 'At least 10 characters',
                            uz: 'Kamida 10 belgi',
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
