import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mila/core/widgets/voice_orb.dart';
import 'package:mila/services/llm/llm_service.dart';
import 'package:mila/services/voice/gemini_live_token_service.dart';

void main() {
  testWidgets('voice orb renders in all moods', (tester) async {
    for (final mood in OrbMood.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VoiceOrb(mood: mood, level: 0.5)),
        ),
      );
      expect(find.byType(VoiceOrb), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  test('action block extraction', () {
    const raw =
        'Done! I drafted it.\n\n```actions\n'
        '[{"type":"create_task","title":"Review Q2","subtitle":"Due tomorrow"}]\n'
        '```';
    final (clean, actions) = LlmService.extractActions(raw);
    expect(clean, 'Done! I drafted it.');
    expect(actions, hasLength(1));
    expect(actions.first.title, 'Review Q2');
  });

  test('plain text passes through untouched', () {
    final (clean, actions) = LlmService.extractActions('Just an answer.');
    expect(clean, 'Just an answer.');
    expect(actions, isEmpty);
  });

  test('secure voice token is requested with the MILA session', () async {
    const service = GeminiLiveTokenService(
      baseUrl: 'https://mila.test/',
      sessionToken: 'session-token',
    );
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://mila.test/v1/voice/token');
      expect(request.headers['Authorization'], 'Bearer session-token');
      return http.Response('{"token":"short-lived"}', 200);
    });

    expect(await service.createToken(client: client), 'short-lived');
  });
}
