import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../data/models.dart';
import '../storage/stores.dart';

class AgenticOsException implements Exception {
  const AgenticOsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AgenticOsService {
  const AgenticOsService(this._ref);
  final Ref _ref;

  Future<({String baseUrl, String token})> _credentials() async {
    final secure = _ref.read(secureStoreProvider);
    final baseUrl = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    ).replaceFirst(RegExp(r'/$'), '');
    final token = await secure.read(SecureStore.openAiAccountToken) ?? '';
    if (baseUrl.isEmpty || token.isEmpty) {
      throw const AgenticOsException('Connect MILA to Agentic OS first.');
    }
    return (baseUrl: baseUrl, token: token);
  }

  Future<bool> isConnected() async {
    final token =
        await _ref
            .read(secureStoreProvider)
            .read(SecureStore.openAiAccountToken) ??
        '';
    return token.isNotEmpty;
  }

  Future<List<AgenticTask>> listTasks({http.Client? client}) async {
    final json = await _request('GET', '/v1/tasks', client: client);
    return ((json['tasks'] as List?) ?? const [])
        .map(
          (item) => AgenticTask.fromJson((item as Map).cast<String, dynamic>()),
        )
        .where((task) => task.id.isNotEmpty)
        .toList();
  }

  Future<AgenticTask> createTask({
    required String title,
    String body = '',
    int priority = 0,
    http.Client? client,
  }) async {
    final json = await _request(
      'POST',
      '/v1/tasks',
      body: {
        'title': title,
        'body': body,
        'priority': priority,
        'initialStatus': 'triage',
        'assignee': 'default',
      },
      client: client,
    );
    return AgenticTask.fromJson(
      ((json['task'] as Map?) ?? const {}).cast<String, dynamic>(),
    );
  }

  Future<void> updateTask(
    String id, {
    required String status,
    String blockReason = '',
    http.Client? client,
  }) async {
    await _request(
      'PATCH',
      '/v1/tasks/${Uri.encodeComponent(id)}',
      body: {
        'status': status,
        if (blockReason.isNotEmpty) 'blockReason': blockReason,
      },
      client: client,
    );
  }

  Future<List<MemoryItem>> listMemory({http.Client? client}) async {
    final json = await _request('GET', '/v1/memory', client: client);
    return ((json['items'] as List?) ?? const [])
        .map((value) {
          final item = (value as Map).cast<String, dynamic>();
          return MemoryItem(
            id: item['id'] as String?,
            text: item['text'] as String? ?? '',
            category: switch (item['category']) {
              'people' => MemoryCategory.people,
              'preferences' => MemoryCategory.preferences,
              _ => MemoryCategory.facts,
            },
          );
        })
        .where((item) => item.text.isNotEmpty)
        .toList();
  }

  Future<MemoryItem> appendMemory(
    MemoryItem item, {
    http.Client? client,
  }) async {
    final json = await _request(
      'POST',
      '/v1/memory',
      body: {'text': item.text, 'category': item.category.name},
      client: client,
    );
    final saved = ((json['item'] as Map?) ?? const {}).cast<String, dynamic>();
    return MemoryItem(
      id: saved['id'] as String?,
      text: saved['text'] as String? ?? item.text,
      category: switch (saved['category']) {
        'people' => MemoryCategory.people,
        'preferences' => MemoryCategory.preferences,
        _ => MemoryCategory.facts,
      },
    );
  }

  Future<void> deleteMemory(String id, {http.Client? client}) async {
    await _request(
      'DELETE',
      '/v1/memory/${Uri.encodeComponent(id)}',
      client: client,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    http.Client? client,
  }) async {
    final credentials = await _credentials();
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final request =
          http.Request(method, Uri.parse('${credentials.baseUrl}$path'))
            ..headers.addAll({
              'Authorization': 'Bearer ${credentials.token}',
              if (body != null) 'Content-Type': 'application/json',
            });
      if (body != null) request.body = jsonEncode(body);
      final streamed = await httpClient
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      final json = _decode(response.body);
      if (response.statusCode == 401) {
        throw const AgenticOsException(
          'MILA session expired. Connect Agentic OS again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AgenticOsException(
          json['error'] as String? ?? 'Agentic OS request failed.',
        );
      }
      return json;
    } on AgenticOsException {
      rethrow;
    } catch (_) {
      throw const AgenticOsException(
        'Could not reach Agentic OS. Check the server connection.',
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

class AgenticTasksState {
  const AgenticTasksState({
    this.tasks = const [],
    this.connected = false,
    this.loading = false,
    this.error = '',
    this.syncedAt,
  });

  final List<AgenticTask> tasks;
  final bool connected;
  final bool loading;
  final String error;
  final DateTime? syncedAt;

  AgenticTasksState copyWith({
    List<AgenticTask>? tasks,
    bool? connected,
    bool? loading,
    String? error,
    DateTime? syncedAt,
  }) => AgenticTasksState(
    tasks: tasks ?? this.tasks,
    connected: connected ?? this.connected,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    syncedAt: syncedAt ?? this.syncedAt,
  );
}

class AgenticTasksController extends StateNotifier<AgenticTasksState> {
  AgenticTasksController(
    this._ref, {
    bool autoStart = true,
    AgenticTasksState initialState = const AgenticTasksState(),
  }) : super(initialState) {
    if (!autoStart) return;
    unawaited(refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  final Ref _ref;
  Timer? _timer;

  AgenticOsService get _service => _ref.read(agenticOsServiceProvider);

  Future<void> refresh({bool silent = false}) async {
    if (!await _service.isConnected()) {
      state = const AgenticTasksState();
      return;
    }
    if (!silent) {
      state = state.copyWith(connected: true, loading: true, error: '');
    }
    try {
      final tasks = await _service.listTasks();
      state = AgenticTasksState(
        tasks: tasks,
        connected: true,
        syncedAt: DateTime.now(),
      );
    } on AgenticOsException catch (error) {
      state = state.copyWith(
        connected: true,
        loading: false,
        error: error.message,
      );
    }
  }

  Future<AgenticTask> create(String title, String body) async {
    final task = await _service.createTask(title: title, body: body);
    await refresh(silent: true);
    return task;
  }

  Future<void> markDone(String id) async {
    await _service.updateTask(id, status: 'done');
    await refresh(silent: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final agenticOsServiceProvider = Provider<AgenticOsService>(
  (ref) => AgenticOsService(ref),
);

final agenticTasksProvider =
    StateNotifierProvider<AgenticTasksController, AgenticTasksState>(
      AgenticTasksController.new,
    );
