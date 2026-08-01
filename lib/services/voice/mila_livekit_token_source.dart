import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

class MilaLiveKitTokenSource implements TokenSourceFixed {
  const MilaLiveKitTokenSource({
    required this.baseUrl,
    required this.sessionToken,
    required this.language,
    this.profile = const {},
    this.client,
  });

  final String baseUrl;
  final String sessionToken;
  final String language;
  final Map<String, dynamic> profile;
  final http.Client? client;

  @override
  Future<TokenSourceResponse> fetch() async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (root.isEmpty || sessionToken.trim().isEmpty) {
      throw StateError('MILA account is not connected.');
    }

    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final response = await httpClient
          .post(
            Uri.parse('$root/v1/voice/livekit-token'),
            headers: {
              'Authorization': 'Bearer $sessionToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'language': language, 'profile': profile}),
          )
          .timeout(const Duration(seconds: 12));
      final body = _decode(response.body);
      if (response.statusCode != 201) {
        throw StateError(
          body['error']?.toString() ?? 'LiveKit voice is unavailable.',
        );
      }
      return TokenSourceResponse.fromJson(body);
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  static Map<String, dynamic> _decode(String source) {
    try {
      return (jsonDecode(source) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }
}
