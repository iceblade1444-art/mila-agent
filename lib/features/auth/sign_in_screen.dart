import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../data/models.dart';
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

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    final existing = ref.read(profileProvider);
    // Priority: typed name → previously stored name → email prefix.
    var name = _name.text.trim();
    if (name.isEmpty) name = existing.name;
    if (name.isEmpty) {
      final prefix = email.split('@').first;
      name = prefix[0].toUpperCase() + prefix.substring(1);
    }
    ref.read(profileProvider.notifier).save(UserProfile(
          name: name,
          email: email,
          signedIn: true,
        ));
    context.go(ref.read(settingsProvider).assistantSetupDone
        ? '/permissions'
        : '/assistant-setup');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
                        _creating ? 'Create account' : 'Welcome back',
                        style: text.headlineMedium),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      _creating
                          ? 'Set up your local MILA profile'
                          : 'Sign in to continue',
                      style: text.bodyMedium
                          ?.copyWith(color: MilaColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_creating) ...[
                    Text('Your name', style: text.labelMedium),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _name,
                      keyboardType: TextInputType.name,
                      autofillHints: const [AutofillHints.name],
                      decoration:
                          const InputDecoration(hintText: 'How should MILA call you?'),
                      validator: (v) => (v ?? '').trim().isNotEmpty
                          ? null
                          : 'Enter your name',
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Email', style: text.labelMedium),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration:
                        const InputDecoration(hintText: 'hello@milaai.app'),
                    validator: (v) =>
                        v != null && v.contains('@') && v.contains('.')
                            ? null
                            : 'Enter a valid email',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Password', style: text.labelMedium),
                      Text('Forgot?',
                          style: text.labelMedium
                              ?.copyWith(color: MilaColors.cyan)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '••••••••••'),
                    validator: (v) => (v ?? '').length >= 6
                        ? null
                        : 'At least 6 characters',
                  ),
                  const SizedBox(height: 28),
                  GradientButton(
                      label: _creating ? 'Create Account' : 'Sign In',
                      onPressed: _submit),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or continue with',
                            style: text.labelSmall),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final icon in [
                        Icons.apple_rounded,
                        Icons.g_mobiledata_rounded,
                        Icons.window_rounded,
                      ])
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.all(14),
                            radius: 16,
                            onTap: () => ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Social sign-in needs your auth backend — see README.'))),
                            child: Icon(icon, size: 26),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() => _creating = !_creating),
                      child: Text.rich(
                        TextSpan(
                          text: _creating
                              ? 'Already have an account? '
                              : 'New to MILA? ',
                          style: text.bodySmall,
                          children: [
                            TextSpan(
                              text: _creating ? 'Sign in' : 'Create account',
                              style: text.bodySmall
                                  ?.copyWith(color: MilaColors.cyan),
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
