import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mila/services/voice/mila_livekit_token_source.dart';

void main() {
  test('fetches a private LiveKit room with the paired MILA session', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://agent.example.test/v1/voice/livekit-token',
      );
      expect(request.headers['authorization'], 'Bearer mobile-session');
      expect(jsonDecode(request.body), {'language': 'uz-UZ'});
      return http.Response(
        jsonEncode({
          'server_url': 'wss://agent.example.test',
          'participant_token': 'room-jwt',
          'room_name': 'mila-test-room',
        }),
        201,
        headers: {'Content-Type': 'application/json'},
      );
    });

    final token = await MilaLiveKitTokenSource(
      baseUrl: 'https://agent.example.test/',
      sessionToken: 'mobile-session',
      language: 'uz-UZ',
      client: client,
    ).fetch();

    expect(token.serverUrl, 'wss://agent.example.test');
    expect(token.participantToken, 'room-jwt');
    expect(token.roomName, 'mila-test-room');
  });

  test('does not hide a server-side LiveKit configuration error', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'error': 'LiveKit voice transport is not configured'}),
        503,
      ),
    );

    expect(
      () => MilaLiveKitTokenSource(
        baseUrl: 'https://agent.example.test',
        sessionToken: 'mobile-session',
        language: 'ru-RU',
        client: client,
      ).fetch(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('not configured'),
        ),
      ),
    );
  });
}
