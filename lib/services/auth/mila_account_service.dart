import 'dart:convert';

import 'package:http/http.dart' as http;

class MilaAccountSession {
  const MilaAccountSession({required this.token, required this.label});

  final String token;
  final String label;
}

class MilaAccountService {
  const MilaAccountService();

  Future<MilaAccountSession> exchangeCode({
    required String baseUrl,
    required String code,
    http.Client? client,
  }) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (root.isEmpty) {
      throw const FormatException('MILA server URL is required.');
    }
    final normalizedCode = code.trim().toUpperCase();
    if (!RegExp(r'^[A-F0-9]{8}$').hasMatch(normalizedCode)) {
      throw const FormatException('Enter the 8-character connection code.');
    }

    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final response = await httpClient
          .post(
            Uri.parse('$root/v1/auth/device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': normalizedCode}),
          )
          .timeout(const Duration(seconds: 12));
      final json = _decode(response.body);
      final token = json['token'] as String? ?? '';
      final label = json['label'] as String? ?? 'MILA user';
      if (response.statusCode != 200 || token.isEmpty) {
        throw FormatException(
          json['error'] as String? ?? 'Could not connect the MILA account.',
        );
      }
      return MilaAccountSession(token: token, label: label);
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
