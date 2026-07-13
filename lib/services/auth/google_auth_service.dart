import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (_) => GoogleAuthService(),
);

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GoogleAuthService {
  static const _serverClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const isConfigured = _serverClientId != '';
  bool _initialized = false;

  Future<GoogleSignInAccount> signIn() async {
    if (!isConfigured) {
      throw const GoogleAuthException(
        'Google Sign-In is not configured yet. Add GOOGLE_WEB_CLIENT_ID to the app build.',
      );
    }
    if (!_initialized) {
      await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
      _initialized = true;
    }
    try {
      return await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthException('Google Sign-In was cancelled.');
      }
      throw GoogleAuthException(
        error.description ?? 'Google could not complete sign-in.',
      );
    }
  }

  Future<void> signOut() async {
    if (_initialized) await GoogleSignIn.instance.signOut();
  }
}
