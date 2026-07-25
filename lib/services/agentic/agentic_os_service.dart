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
    final milaUrl = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    ).replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse(milaUrl);
    final baseUrl = uri
        .replace(
          path: uri.path.replaceFirst(RegExp(r'/mila$'), ''),
          query: null,
          fragment: null,
        )
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
    final token = await secure.read(SecureStore.agenticOsAccessToken) ?? '';
    if (baseUrl.isEmpty || token.isEmpty) {
      throw const AgenticOsException('Sign in to Agentic OS first.');
    }
    return (baseUrl: baseUrl, token: token);
  }

  Future<bool> isConnected() async {
    final token =
        await _ref
            .read(secureStoreProvider)
            .read(SecureStore.agenticOsAccessToken) ??
        '';
    return token.isNotEmpty;
  }

  Future<AgenticDashboard> dashboard({http.Client? client}) async {
    final json = await _request('GET', '/api/member/dashboard', client: client);
    return AgenticDashboard.fromJson(json);
  }

  Future<List<AgenticTask>> listTasks({http.Client? client}) async {
    final json = await _requestList('/api/member/tasks', client: client);
    return json
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
      '/api/member/tasks',
      body: {
        'title': title,
        'detail': body,
        'priority': switch (priority) {
          >= 2 => 'high',
          <= -1 => 'low',
          _ => 'normal',
        },
        'status': 'todo',
      },
      client: client,
    );
    return AgenticTask.fromJson(json);
  }

  Future<void> updateTask(
    String id, {
    required String status,
    String blockReason = '',
    http.Client? client,
  }) async {
    await _request(
      'PATCH',
      '/api/member/tasks/${Uri.encodeComponent(id)}',
      body: {
        'status': status == 'done' ? 'done' : 'doing',
        if (blockReason.isNotEmpty) 'detail': blockReason,
      },
      client: client,
    );
  }

  Future<List<MemoryItem>> listMemory({http.Client? client}) async {
    final json = await _requestList('/api/member/notes', client: client);
    return json
        .map((value) {
          final item = (value as Map).cast<String, dynamic>();
          return MemoryItem(
            id: item['id'] as String?,
            text: item['content'] as String? ?? '',
            category: MemoryCategory.facts,
          );
        })
        .where((item) => item.text.isNotEmpty)
        .toList();
  }

  Future<MemoryItem> appendMemory(
    MemoryItem item, {
    http.Client? client,
  }) async {
    final words = item.text.trim().split(RegExp(r'\s+')).take(8).join(' ');
    final title = words.length >= 2 ? words : 'MILA note';
    final json = await _request(
      'POST',
      '/api/member/notes',
      body: {'title': title, 'content': item.text},
      client: client,
    );
    return MemoryItem(
      id: json['id'] as String?,
      text: json['content'] as String? ?? item.text,
      category: item.category,
    );
  }

  Future<void> deleteMemory(String id, {http.Client? client}) async {
    await _request(
      'DELETE',
      '/api/member/notes/${Uri.encodeComponent(id)}',
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

  Future<List<dynamic>> _requestList(String path, {http.Client? client}) async {
    final credentials = await _credentials();
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final response = await httpClient
          .get(
            Uri.parse('${credentials.baseUrl}$path'),
            headers: {'Authorization': 'Bearer ${credentials.token}'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        throw const AgenticOsException(
          'Agentic OS session expired. Sign in again.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded is Map ? decoded['error'] : null;
        throw AgenticOsException(
          error is String ? error : 'Agentic OS request failed.',
        );
      }
      return decoded is List ? decoded : const [];
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

class AgenticDashboard {
  const AgenticDashboard({
    required this.connected,
    required this.accountLabel,
    required this.ownerName,
    required this.ownerEmail,
    required this.workspaceName,
    required this.readiness,
    required this.readinessScore,
    required this.openTasks,
    required this.runningTasks,
    required this.blockedTasks,
    required this.knowledgeNotes,
    required this.knowledgeFolders,
    required this.obsidianMcpStatus,
    required this.milaVoiceConfigured,
    required this.liveModel,
    this.syncedAt,
  });

  final bool connected;
  final String accountLabel;
  final String ownerName;
  final String ownerEmail;
  final String workspaceName;
  final String readiness;
  final int readinessScore;
  final int openTasks;
  final int runningTasks;
  final int blockedTasks;
  final int knowledgeNotes;
  final int knowledgeFolders;
  final String obsidianMcpStatus;
  final bool milaVoiceConfigured;
  final String liveModel;
  final DateTime? syncedAt;

  factory AgenticDashboard.fromJson(Map<String, dynamic> json) {
    final account = ((json['account'] as Map?) ?? const {})
        .cast<String, dynamic>();
    final counts = ((json['counts'] as Map?) ?? const {})
        .cast<String, dynamic>();
    final synced = json['updatedAt'];
    return AgenticDashboard(
      connected: true,
      accountLabel: account['email'] as String? ?? '',
      ownerName: account['name'] as String? ?? '',
      ownerEmail: account['email'] as String? ?? '',
      workspaceName: 'Personal workspace',
      readiness: 'ready',
      readinessScore: 100,
      openTasks: (counts['open'] as num?)?.toInt() ?? 0,
      runningTasks: (counts['doing'] as num?)?.toInt() ?? 0,
      blockedTasks: 0,
      knowledgeNotes: (counts['notes'] as num?)?.toInt() ?? 0,
      knowledgeFolders: 0,
      obsidianMcpStatus: 'personal',
      milaVoiceConfigured: true,
      liveModel: 'gemini-3.1-flash-live-preview',
      syncedAt: DateTime.tryParse(synced?.toString() ?? ''),
    );
  }
}

class AgenticDashboardState {
  const AgenticDashboardState({
    this.dashboard,
    this.connected = false,
    this.loading = false,
    this.error = '',
  });

  final AgenticDashboard? dashboard;
  final bool connected;
  final bool loading;
  final String error;

  AgenticDashboardState copyWith({
    AgenticDashboard? dashboard,
    bool? connected,
    bool? loading,
    String? error,
  }) => AgenticDashboardState(
    dashboard: dashboard ?? this.dashboard,
    connected: connected ?? this.connected,
    loading: loading ?? this.loading,
    error: error ?? this.error,
  );
}

class AgenticDashboardController extends StateNotifier<AgenticDashboardState> {
  AgenticDashboardController(this._ref) : super(const AgenticDashboardState()) {
    unawaited(refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  final Ref _ref;
  Timer? _timer;

  Future<void> refresh({bool silent = false}) async {
    final service = _ref.read(agenticOsServiceProvider);
    if (!await service.isConnected()) {
      state = const AgenticDashboardState();
      return;
    }
    if (!silent) {
      state = state.copyWith(connected: true, loading: true, error: '');
    }
    try {
      final dashboard = await service.dashboard();
      state = AgenticDashboardState(dashboard: dashboard, connected: true);
    } on AgenticOsException catch (error) {
      state = state.copyWith(
        connected: true,
        loading: false,
        error: error.message,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

final agenticDashboardProvider =
    StateNotifierProvider<AgenticDashboardController, AgenticDashboardState>(
      AgenticDashboardController.new,
    );
