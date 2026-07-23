import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mila/core/widgets/voice_orb.dart';
import 'package:mila/data/models.dart';
import 'package:mila/features/onboarding/assistant_setup_screen.dart';
import 'package:mila/services/llm/llm_service.dart';
import 'package:mila/services/soul/soul_service.dart';
import 'package:mila/services/storage/stores.dart';
import 'package:mila/services/voice/gemini_live_token_service.dart';

class _MemoryLocalStore implements LocalStore {
  final _maps = <String, Map<String, dynamic>>{};
  final _strings = <String, String>{};

  @override
  Future<void> delete(String key) async => _maps.remove(key);

  @override
  List<Map<String, dynamic>> readList(String key) => const [];

  @override
  Map<String, dynamic>? readMap(String key) => _maps[key];

  @override
  String? readString(String key) => _strings[key];

  @override
  Future<void> writeJson(String key, Object value) async {
    if (value is Map<String, dynamic>) _maps[key] = value;
  }

  @override
  Future<void> writeString(String key, String value) async {
    _strings[key] = value;
  }
}

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

  testWidgets('first run asks for names, personality and voice gender', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(_MemoryLocalStore())],
        child: const MaterialApp(home: AssistantSetupScreen()),
      ),
    );

    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Assistant name'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Female'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Male'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Warm & friendly'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Warm & friendly'), findsOneWidget);
    expect(find.text('ORB SKIN'), findsNothing);
    expect(find.text('Aoede'), findsNothing);
    expect(find.text('Puck'), findsNothing);
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

  test('assistant identity is persisted as soul markdown', () async {
    final store = _MemoryLocalStore();
    final service = SoulService(store);
    final settings = const AppSettings().copyWith(
      assistantName: 'Nova',
      personality: assistantPersonalities.last.prompt,
      personalityId: assistantPersonalities.last.id,
      voiceName: maleVoiceName,
    );
    await service.save(settings, const UserProfile(name: 'Alex'));

    final soul = store.readString(SoulService.storageKey)!;
    expect(soul, contains('Assistant name: Nova'));
    expect(soul, contains('User name: Alex'));
    expect(soul, contains('Voice: Male'));
    expect(soul, contains(assistantPersonalities.last.prompt));
  });

  test('chat attachments survive local serialization', () {
    final message = ChatMessage(
      role: ChatRole.user,
      text: 'What is in this image?',
      attachments: [
        ChatAttachment(
          name: 'photo.jpg',
          path: '/tmp/photo.jpg',
          mimeType: 'image/jpeg',
          type: ChatAttachmentType.image,
        ),
      ],
    );
    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.attachments.single.name, 'photo.jpg');
    expect(restored.attachments.single.type, ChatAttachmentType.image);
  });

  test('Hermes Kanban task keeps its remote lifecycle metadata', () {
    final task = AgenticTask.fromJson({
      'id': 't_sync1',
      'title': 'Prepare launch plan',
      'status': 'running',
      'assignee': 'scout',
      'latest_summary': 'Evidence collection started',
      'priority': 2,
      'created_at': 1784287000,
    });
    expect(task.id, 't_sync1');
    expect(task.active, isTrue);
    expect(task.assignee, 'scout');
    expect(task.summary, 'Evidence collection started');
    expect(task.createdAt, isNotNull);
  });

  test('secure voice token is requested with the MILA session', () async {
    const service = GeminiLiveTokenService(
      baseUrl: 'https://mila.test/',
      sessionToken: 'session-token',
    );
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://mila.test/v1/voice/token');
      expect(request.headers['Authorization'], 'Bearer session-token');
      expect(request.headers['Content-Type'], 'application/json');
      expect(jsonDecode(request.body), {'language': 'uz-UZ'});
      return http.Response('{"token":"short-lived"}', 200);
    });

    expect(
      await service.createToken(language: 'uz-UZ', client: client),
      'short-lived',
    );
  });
}
