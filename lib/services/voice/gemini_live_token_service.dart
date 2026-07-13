import 'dart:convert';

import 'package:http/http.dart' as http;

/// Obtains a constrained, short-lived Gemini Live token from the MILA backend.
/// This keeps the long-lived Gemini provider key off the phone in production.
class GeminiLiveTokenService {
  const GeminiLiveTokenService({required this.baseUrl, required this.sessionToken});

  final String baseUrl;
  final String sessionToken;

  Uri get _endpoint {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root/v1/voice/token');
  }

  Future<String> createToken({http.Client? client}) async {
    if (baseUrl.trim().isEmpty || sessionToken.trim().isEmpty) {
      throw GeminiLiveTokenException('MILA account is not connected.');
    }
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final response = await httpClient
          .post(
            _endpoint,
            headers: {'Authorization': 'Bearer $sessionToken'},
          )
          .timeout(const Duration(seconds: 12));
      final json = _decode(response.body);
      if (response.statusCode == 401) {
        throw GeminiLiveTokenException(
          'MILA sign-in expired. Reconnect your account in Settings.',
        );
      }
      if (response.statusCode == 402) {
        throw GeminiLiveTokenException('An active subscription is required.');
      }
      final token = json['token'] as String?;
      if (response.statusCode != 200 || token == null || token.isEmpty) {
        final message = json['error'] as String? ?? 'Could not start secure voice.';
        throw GeminiLiveTokenException(message);
      }
      return token;
    } on GeminiLiveTokenException {
      rethrow;
    } catch (_) {
      throw GeminiLiveTokenException(
        'Could not reach the MILA voice service. Check your connection.',
      );
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }
}

class GeminiLiveTokenException implements Exception {
  const GeminiLiveTokenException(this.message);
  final String message;

  @override
  String toString() => message;
}
