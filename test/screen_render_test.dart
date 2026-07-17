import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mila/data/models.dart';
import 'package:mila/features/chat/chat_screen.dart';
import 'package:mila/features/onboarding/assistant_setup_screen.dart';
import 'package:mila/features/tasks/tasks_screen.dart';
import 'package:mila/services/agentic/agentic_os_service.dart';
import 'package:mila/services/storage/stores.dart';

class _RenderStore implements LocalStore {
  final _maps = <String, Map<String, dynamic>>{};
  final _strings = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _maps.remove(key);
    _strings.remove(key);
  }

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
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('render onboarding and multimodal chat at phone size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    final store = _RenderStore();

    Widget app(Widget child) => ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: RepaintBoundary(key: key, child: child),
      ),
    );

    await tester.pumpWidget(app(const AssistantSetupScreen()));
    await capture(tester, key, 'screen_assistant_setup');

    await tester.pumpWidget(app(const ChatScreen()));
    await capture(tester, key, 'screen_multimodal_chat');

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('agentic-task-render'),
        overrides: [
          localStoreProvider.overrideWithValue(store),
          agenticTasksProvider.overrideWith(
            (ref) => AgenticTasksController(
              ref,
              autoStart: false,
              initialState: AgenticTasksState(
                connected: true,
                syncedAt: DateTime.now(),
                tasks: const [
                  AgenticTask(
                    id: 't_demo1',
                    title: 'Prepare launch readiness report',
                    body: 'Check product, market and deployment readiness.',
                    status: 'running',
                    assignee: 'scout',
                    priority: 1,
                  ),
                  AgenticTask(
                    id: 't_demo2',
                    title: 'Write customer onboarding guide',
                    summary: 'Draft completed and waiting for review.',
                    status: 'review',
                    assignee: 'scribe',
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true),
          home: RepaintBoundary(key: key, child: const TasksScreen()),
        ),
      ),
    );
    await capture(tester, key, 'screen_agentic_tasks');
  });
}
