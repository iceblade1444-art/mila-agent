import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
import '../../services/auth/mila_account_service.dart';
import '../../services/agentic/agentic_os_service.dart';
import '../../services/soul/soul_service.dart';
import '../../services/storage/stores.dart';
import '../../services/push/push_notification_service.dart';

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
  final _mfaCode = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _creating = false;
  bool _localBusy = false;
  String? _mfaChallenge;
  DateTime? _mfaExpiresAt;
  String _mfaOwnerName = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _mfaCode.dispose();
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
      await _completeSignIn(session, baseUrl);
    } on MilaMfaRequiredException catch (challenge) {
      if (!mounted) return;
      setState(() {
        _mfaChallenge = challenge.challenge;
        _mfaExpiresAt = DateTime.now().add(
          Duration(seconds: challenge.expiresInSeconds),
        );
        _mfaOwnerName = challenge.ownerName;
        _mfaCode.clear();
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  Future<void> _verifyMfa() async {
    if (_localBusy || _mfaChallenge == null) return;
    final code = _mfaCode.text.trim().replaceAll(' ', '');
    if (code.length < 6) {
      _showError(
        FormatException(
          context.l10n.pick(
            ru: 'Введите 6-значный код или резервный код.',
            en: 'Enter the 6-digit code or a recovery code.',
            uz: '6 xonali kodni yoki tiklash kodini kiriting.',
          ),
        ),
      );
      return;
    }
    if (_mfaExpiresAt?.isBefore(DateTime.now()) ?? true) {
      _showError(
        FormatException(
          context.l10n.pick(
            ru: 'Срок проверки истёк. Войдите ещё раз.',
            en: 'The verification expired. Sign in again.',
            uz: 'Tasdiqlash muddati tugadi. Qayta kiring.',
          ),
        ),
      );
      _cancelMfa();
      return;
    }

    setState(() => _localBusy = true);
    try {
      final secure = ref.read(secureStoreProvider);
      final baseUrl =
          await secure.read(SecureStore.milaBackendUrl) ??
          'https://agent.milanapremium.uz/mila';
      final session = await const MilaAccountService().verifyMfa(
        baseUrl: baseUrl,
        challenge: _mfaChallenge!,
        code: code,
      );
      _mfaChallenge = null;
      await _completeSignIn(session, baseUrl);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  void _cancelMfa() {
    setState(() {
      _mfaChallenge = null;
      _mfaExpiresAt = null;
      _mfaOwnerName = '';
      _mfaCode.clear();
    });
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('FormatException: ', '')),
      ),
    );
  }

  Future<void> _completeSignIn(
    MilaAccountSession session,
    String baseUrl,
  ) async {
    final secure = ref.read(secureStoreProvider);
    await secure.write(SecureStore.milaBackendUrl, baseUrl);
    await secure.write(SecureStore.agenticOsAccessToken, session.accountToken);
    await secure.write(SecureStore.agenticOsAccountRole, session.ownerRole);
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
    try {
      await ref
          .read(agenticOsServiceProvider)
          .syncPersonalOnboarding(ref.read(settingsProvider));
    } on AgenticOsException {
      // Authentication succeeded; a later profile sync can retry SOUL.md.
    }
    try {
      await ref.read(pushNotificationProvider).registerCurrentDevice();
    } on Object {
      // Push can be enabled later without blocking a successful sign-in.
    }
    if (!mounted) return;
    context.go(
      ref.read(settingsProvider).assistantSetupDone
          ? '/permissions'
          : '/assistant-setup',
    );
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
                      _mfaChallenge != null
                          ? l10n.pick(
                              ru: 'Подтвердите вход',
                              en: 'Verify sign in',
                              uz: 'Kirishni tasdiqlang',
                            )
                          : _creating
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
                      _mfaChallenge != null
                          ? l10n.pick(
                              ru: 'Код для ${_mfaOwnerName.isEmpty ? 'аккаунта' : _mfaOwnerName}',
                              en: 'Code for ${_mfaOwnerName.isEmpty ? 'your account' : _mfaOwnerName}',
                              uz: '${_mfaOwnerName.isEmpty ? 'Akkauntingiz' : _mfaOwnerName} uchun kod',
                            )
                          : _creating
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
                  if (_mfaChallenge != null) ...[
                    Text(
                      l10n.pick(
                        ru: 'Код аутентификатора',
                        en: 'Authenticator code',
                        uz: 'Autentifikator kodi',
                      ),
                      style: text.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _mfaCode,
                      autofocus: true,
                      keyboardType: TextInputType.visiblePassword,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9 -]'),
                        ),
                        LengthLimitingTextInputFormatter(24),
                      ],
                      decoration: InputDecoration(
                        hintText: l10n.pick(
                          ru: '6 цифр или резервный код',
                          en: '6 digits or recovery code',
                          uz: '6 raqam yoki tiklash kodi',
                        ),
                      ),
                      onFieldSubmitted: (_) => unawaited(_verifyMfa()),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.pick(
                        ru: 'Откройте приложение-аутентификатор. Также можно использовать один из сохранённых резервных кодов.',
                        en: 'Open your authenticator app. You can also use one of your saved recovery codes.',
                        uz: 'Autentifikator ilovasini oching. Saqlangan tiklash kodlaridan birini ham ishlatishingiz mumkin.',
                      ),
                      style: text.bodySmall?.copyWith(
                        color: MilaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    GradientButton(
                      label: l10n.pick(
                        ru: 'Подтвердить',
                        en: 'Verify',
                        uz: 'Tasdiqlash',
                      ),
                      busy: _localBusy,
                      onPressed: _localBusy
                          ? null
                          : () => unawaited(_verifyMfa()),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: _localBusy ? null : _cancelMfa,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: Text(
                          l10n.pick(
                            ru: 'Вернуться к паролю',
                            en: 'Back to password',
                            uz: 'Parolga qaytish',
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
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
                    Text(
                      _creating
                          ? 'Email'
                          : l10n.pick(
                              ru: 'Email (оставьте пустым для Creator)',
                              en: 'Email (leave blank for Creator)',
                              uz: 'Email (Creator uchun bo‘sh qoldiring)',
                            ),
                      style: text.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        hintText: _creating
                            ? 'hello@milaai.app'
                            : l10n.pick(
                                ru: 'Email или пусто для Creator',
                                en: 'Email or blank for Creator',
                                uz: 'Email yoki Creator uchun bo‘sh',
                              ),
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (!_creating && value.isEmpty) return null;
                        return value.contains('@') && value.contains('.')
                            ? null
                            : l10n.pick(
                                ru: 'Введите корректный email',
                                en: 'Enter a valid email',
                                uz: 'To\'g\'ri email kiriting',
                              );
                      },
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
                  ],
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
