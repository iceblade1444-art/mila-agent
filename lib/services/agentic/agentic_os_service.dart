import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../data/models.dart';
import '../storage/stores.dart';
import 'day_plan_models.dart';
import 'feed_models.dart';
import 'team_chat_models.dart';

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
    try {
      final token =
          await _ref
              .read(secureStoreProvider)
              .read(SecureStore.agenticOsAccessToken) ??
          '';
      return token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncPersonalOnboarding(AppSettings settings) async {
    final secure = _ref.read(secureStoreProvider);
    final role =
        await secure.read(SecureStore.agenticOsAccountRole) ?? 'Member';
    if (role == 'Creator' || role == 'Admin') {
      await _request('POST', '/api/onboarding/sync-context');
      return;
    }
    final language = settings.language.toLowerCase();
    final locale = language.contains('english')
        ? 'en-US'
        : language.contains('uzbek') ||
              language.contains('o‘zbek') ||
              language.contains("o'zbek")
        ? 'uz-UZ'
        : 'ru-RU';
    final assistantStyle = switch (settings.personalityId) {
      'professional' => 'operator',
      'playful' || 'warm' => 'friend',
      _ => 'assistant',
    };
    await _request(
      'PUT',
      '/api/onboarding',
      body: {
        'profile': {
          'locale': locale,
          'timezone': 'Asia/Tashkent',
          'roleFocus': 'MILA mobile user',
          'assistantStyle': assistantStyle,
          'responseLength': settings.conciseSummaries ? 'brief' : 'balanced',
        },
      },
    );
  }

  Future<AgenticDashboard> dashboard({http.Client? client}) async {
    final json = await _request('GET', '/api/member/dashboard', client: client);
    return AgenticDashboard.fromJson(json);
  }
  /// Answer something MILA is holding. Only the token travels — the arguments
  /// are the ones that were staged, so what runs is what the person read.
  Future<void> confirmAction(
    String token, {
    required bool approve,
    http.Client? client,
  }) async {
    await _request(
      'POST',
      '/api/mila/confirm',
      body: {'token': token, 'decision': approve ? 'approve' : 'decline'},
      client: client,
    );
  }

  /// What is blocked on this person, worst first. Server-scoped by role: a
  /// Member never has the fleet sources fetched for them at all.
  Future<NeedsYou> needsYou({http.Client? client}) async {
    final json = await _request('GET', '/api/needs-you', client: client);
    return NeedsYou.fromJson(json);
  }

  /// What MILA did for this person, newest first. The endpoint takes no user
  /// parameter, so there is nothing here that could ask for anyone else's.
  Future<List<ActivityEntry>> activity({http.Client? client}) async {
    // _request, not _requestList: the endpoint answers { items, count }, and
    // _requestList returns an empty list for anything that is not a bare
    // array — which would render as "nothing happened" instead of an error.
    final json = await _request('GET', '/api/activity', client: client);
    final raw = json['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => ActivityEntry.fromJson(item.cast<String, dynamic>()))
        .where((entry) => entry.title.isNotEmpty)
        .toList();
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

  Future<List<ChatMessage>> syncChat(
    List<ChatMessage> messages, {
    http.Client? client,
  }) async {
    final syncedAt = DateTime.now().toUtc().toIso8601String();
    final json = await _request(
      'POST',
      '/api/member/chat/sync',
      body: {
        'messages': messages
            .where((message) => !message.id.startsWith('inbox:'))
            .take(500)
            .map(
              (message) => {
                'id': message.id,
                'role': message.role.name,
                'text': message.text,
                'source': message.viaVoice ? 'voice' : 'mobile',
                'viaVoice': message.viaVoice,
                'replyToText': message.replyToText,
                'createdAt': message.createdAt.toUtc().toIso8601String(),
                'updatedAt': syncedAt,
              },
            )
            .toList(),
      },
      client: client,
    );
    return ((json['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((value) => ChatMessage.fromJson(value.cast<String, dynamic>()))
        .where((message) => message.text.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> clearChat({http.Client? client}) async {
    await _request('DELETE', '/api/member/chat', client: client);
  }

  /// Runs one MILA action on Agentic OS and returns its raw result.
  ///
  /// The server scopes every personal action to the signed-in account, so this
  /// only ever reaches the caller's own tasks, notes, reminders and calendar.
  /// An action the account may not run raises instead of returning an empty
  /// result, so the assistant can say plainly that it did not happen.
  Future<Map<String, dynamic>> runMilaAction(
    String name,
    Map<String, dynamic> args, {
    http.Client? client,
  }) async {
    return _request(
      'POST',
      '/api/mila/actions',
      body: {'name': name, 'args': args},
      client: client,
    );
  }

  Future<List<AgenticInboxItem>> unreadInbox({http.Client? client}) async {
    final json = await _request(
      'GET',
      '/api/member/inbox?status=unread&limit=50',
      client: client,
    );
    return ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (value) => AgenticInboxItem.fromJson(value.cast<String, dynamic>()),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> markInboxRead(String id, {http.Client? client}) async {
    await _request(
      'PATCH',
      '/api/member/inbox/${Uri.encodeComponent(id)}',
      body: {'status': 'read'},
      client: client,
    );
  }

  Future<void> registerPushDevice({
    required String deviceId,
    required String token,
    required String platform,
    required String locale,
    http.Client? client,
  }) async {
    await _request(
      'POST',
      '/api/member/push/devices',
      body: {
        'deviceId': deviceId,
        'token': token,
        'platform': platform,
        'locale': locale,
      },
      client: client,
    );
  }

  Future<void> unregisterPushDevice(
    String deviceId, {
    http.Client? client,
  }) async {
    await _request(
      'DELETE',
      '/api/member/push/devices/${Uri.encodeComponent(deviceId)}',
      client: client,
    );
  }

  Future<GoogleCalendarStatus> googleCalendarStatus({
    http.Client? client,
  }) async {
    final json = await _request(
      'GET',
      '/api/personal/google/status',
      client: client,
    );
    return GoogleCalendarStatus.fromJson(json);
  }

  Future<Uri> beginGoogleCalendarConnect({
    required String locale,
    http.Client? client,
  }) async {
    final json = await _request(
      'POST',
      '/api/personal/google/connect',
      body: {'client': 'mobile', 'locale': locale},
      client: client,
    );
    final value = Uri.tryParse(json['authorizationUrl'] as String? ?? '');
    if (value == null || value.scheme != 'https') {
      throw const AgenticOsException(
        'Agentic OS did not return a secure Google authorization URL.',
      );
    }
    return value;
  }

  Future<GoogleCalendarFeed> googleCalendarEvents({
    DateTime? from,
    DateTime? to,
    int limit = 30,
    http.Client? client,
  }) async {
    final query = <String, String>{
      'from': (from ?? DateTime.now()).toUtc().toIso8601String(),
      'to': (to ?? DateTime.now().add(const Duration(days: 30)))
          .toUtc()
          .toIso8601String(),
      'limit': limit.clamp(1, 100).toString(),
    };
    final path = Uri(
      path: '/api/personal/google/calendar/events',
      queryParameters: query,
    ).toString();
    final json = await _request('GET', path, client: client);
    return GoogleCalendarFeed.fromJson(json);
  }

  Future<void> disconnectGoogleCalendar({http.Client? client}) async {
    await _request('DELETE', '/api/personal/google', client: client);
  }

  // ---------- corporate chat ----------
  //
  // The same messenger the web dashboard uses, over the same routes. Membership
  // is the whole access model and it lives server-side: this client only ever
  // sees threads this account belongs to, and a thread it is not in returns
  // 403, not an empty list.

  Future<TeamChatHome> teamChatHome({http.Client? client}) async {
    final json = await _request('GET', '/api/messenger/', client: client);
    return TeamChatHome.fromJson(json);
  }

  Future<List<TeamMessage>> teamMessages(
    String conversationId, {
    int limit = 50,
    http.Client? client,
  }) async {
    final json = await _request(
      'GET',
      '/api/messenger/${Uri.encodeComponent(conversationId)}/messages?limit=$limit',
      client: client,
    );
    return ((json['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((value) => TeamMessage.fromJson(value.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> sendTeamMessage(
    String conversationId,
    String text, {
    http.Client? client,
  }) async {
    await _request(
      'POST',
      '/api/messenger/${Uri.encodeComponent(conversationId)}/messages',
      body: {'text': text},
      client: client,
    );
  }

  /// Moves this account's read watermark to the end of the thread. Fire and
  /// forget from the UI: a failed markRead must never break reading.
  Future<void> markTeamRead(
    String conversationId, {
    http.Client? client,
  }) async {
    await _request(
      'POST',
      '/api/messenger/${Uri.encodeComponent(conversationId)}/read',
      client: client,
    );
  }

  /// Opens (or returns the existing) direct thread with one colleague. The
  /// server keys direct threads by the pair, so calling this twice can never
  /// produce two threads with the same person.
  Future<TeamConversation> openDirectThread(
    String otherId, {
    http.Client? client,
  }) async {
    final json = await _request(
      'POST',
      '/api/messenger/direct',
      body: {'userId': otherId},
      client: client,
    );
    return TeamConversation.fromJson(json);
  }

  // ---------- personal day ----------

  /// The live day plan — calendar, focus blocks and alerts merged server-side.
  /// Goes through the same action MILA herself uses, so the screen and her
  /// spoken answer can never describe two different days.
  Future<DayPlan> dayPlan({bool refresh = false, http.Client? client}) async {
    final json = await runMilaAction('get_my_day_plan', {
      if (refresh) 'refresh': true,
    }, client: client);
    final plan = (json['plan'] as Map?)?.cast<String, dynamic>();
    if (plan == null) {
      throw const AgenticOsException('Agentic OS returned no day plan.');
    }
    return DayPlan.fromJson(plan);
  }

  Future<List<PersonalReminder>> pendingReminders({http.Client? client}) async {
    final json = await runMilaAction('list_my_reminders', {}, client: client);
    return ((json['reminders'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (value) => PersonalReminder.fromJson(value.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<void> cancelReminder(String reminderId, {http.Client? client}) async {
    await runMilaAction('cancel_reminder', {
      'reminderId': reminderId,
    }, client: client);
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

class AgenticInboxItem {
  const AgenticInboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  factory AgenticInboxItem.fromJson(Map<String, dynamic> json) =>
      AgenticInboxItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  ChatMessage asChatMessage() {
    final text = [title, body]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('\n\n');
    return ChatMessage(
      id: 'inbox:$id',
      role: ChatRole.assistant,
      text: text,
      createdAt: createdAt,
    );
  }
}

class GoogleCalendarStatus {
  const GoogleCalendarStatus({
    required this.configured,
    required this.connected,
    this.scopes = const [],
    this.connectedAt,
  });

  final bool configured;
  final bool connected;
  final List<String> scopes;
  final DateTime? connectedAt;

  factory GoogleCalendarStatus.fromJson(Map<String, dynamic> json) {
    return GoogleCalendarStatus(
      configured: json['configured'] == true,
      connected: json['connected'] == true,
      scopes: ((json['scopes'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      connectedAt: DateTime.tryParse(json['connectedAt']?.toString() ?? ''),
    );
  }
}

class GoogleCalendarEvent {
  const GoogleCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.description = '',
    this.location = '',
    this.htmlLink = '',
  });

  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String description;
  final String location;
  final String htmlLink;

  factory GoogleCalendarEvent.fromJson(Map<String, dynamic> json) {
    return GoogleCalendarEvent(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      start: DateTime.tryParse(json['start']?.toString() ?? ''),
      end: DateTime.tryParse(json['end']?.toString() ?? ''),
      allDay: json['allDay'] == true,
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      htmlLink: json['htmlLink'] as String? ?? '',
    );
  }
}

class GoogleCalendarFeed {
  const GoogleCalendarFeed({
    this.events = const [],
    this.timeZone = '',
    this.syncedAt,
  });

  final List<GoogleCalendarEvent> events;
  final String timeZone;
  final DateTime? syncedAt;

  factory GoogleCalendarFeed.fromJson(Map<String, dynamic> json) {
    final values = (json['events'] as List?) ?? const [];
    return GoogleCalendarFeed(
      events: values
          .whereType<Map>()
          .map(
            (value) =>
                GoogleCalendarEvent.fromJson(value.cast<String, dynamic>()),
          )
          .where((event) => event.id.isNotEmpty)
          .toList(growable: false),
      timeZone: json['timeZone'] as String? ?? '',
      syncedAt: DateTime.tryParse(json['syncedAt']?.toString() ?? ''),
    );
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

class ChatSyncState {
  const ChatSyncState({this.syncing = false, this.error = '', this.syncedAt});
  final bool syncing;
  final String error;
  final DateTime? syncedAt;
}

class ChatSyncController extends StateNotifier<ChatSyncState> {
  ChatSyncController(this._ref) : super(const ChatSyncState());
  final Ref _ref;
  Timer? _debounce;

  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(sync()),
    );
  }

  Future<void> sync() async {
    if (state.syncing) {
      schedule();
      return;
    }
    final service = _ref.read(agenticOsServiceProvider);
    if (!await service.isConnected()) return;
    state = const ChatSyncState(syncing: true);
    try {
      final remote = await service.syncChat(_ref.read(chatProvider));
      final inbox = await service.unreadInbox();
      _ref.read(chatProvider.notifier).mergeRemote([
        ...remote,
        ...inbox.map((item) => item.asChatMessage()),
      ]);
      await Future.wait(inbox.map((item) => service.markInboxRead(item.id)));
      state = ChatSyncState(syncedAt: DateTime.now());
    } on AgenticOsException catch (error) {
      state = ChatSyncState(error: error.message);
    }
  }

  Future<void> clearRemote() async {
    final service = _ref.read(agenticOsServiceProvider);
    if (!await service.isConnected()) return;
    try {
      await service.clearChat();
    } on AgenticOsException catch (error) {
      state = ChatSyncState(error: error.message);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final chatSyncProvider =
    StateNotifierProvider<ChatSyncController, ChatSyncState>(
      ChatSyncController.new,
    );

final agenticTasksProvider =
    StateNotifierProvider<AgenticTasksController, AgenticTasksState>(
      AgenticTasksController.new,
    );

final agenticDashboardProvider =
    StateNotifierProvider<AgenticDashboardController, AgenticDashboardState>(
      AgenticDashboardController.new,
    );

final googleCalendarStatusProvider =
    FutureProvider.autoDispose<GoogleCalendarStatus>(
      (ref) => ref.watch(agenticOsServiceProvider).googleCalendarStatus(),
    );
