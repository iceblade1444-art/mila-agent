import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/models.dart';

/// Single Hive box holding JSON-encoded app data (no codegen needed).
class LocalStore {
  LocalStore(this._box) : _scope = _box.get(_activeScopeKey) ?? _signedOutScope;

  final Box<String> _box;
  String _scope;
  static const _activeScopeKey = 'active_account_scope';
  static const _migrationKey = 'account_scope_migrated';
  static const _signedOutScope = 'signed-out';
  static const _privateKeys = {
    'chat',
    'tasks',
    'memories',
    'integrations',
    'soul.md',
  };

  String _key(String key) =>
      _privateKeys.contains(key) ? 'account:$_scope:$key' : key;

  /// Switches every account-owned store before its Riverpod controllers are
  /// recreated. Existing unscoped data is assigned once to the first account
  /// that signs in after this migration; later switches never copy it.
  Future<void> setAccountScope(String accountId) async {
    final normalized = accountId.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9@._-]'),
      '_',
    );
    final next = normalized.isEmpty ? _signedOutScope : normalized;
    if (_box.get(_migrationKey) != '1' && next != _signedOutScope) {
      for (final key in _privateKeys) {
        final legacy = _box.get(key);
        if (legacy != null) await _box.put('account:$next:$key', legacy);
      }
      await _box.deleteAll(_privateKeys);
      await _box.put(_migrationKey, '1');
    }
    _scope = next;
    await _box.put(_activeScopeKey, next);
  }

  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>('mila');
    return LocalStore(box);
  }

  List<Map<String, dynamic>> readList(String key) {
    final raw = _box.get(_key(key));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic>? readMap(String key) {
    final raw = _box.get(_key(key));
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  String? readString(String key) => _box.get(_key(key));

  Future<void> writeString(String key, String value) =>
      _box.put(_key(key), value);

  Future<void> writeJson(String key, Object value) =>
      _box.put(_key(key), jsonEncode(value));

  Future<void> delete(String key) => _box.delete(_key(key));
}

/// API keys live in the platform keystore/keychain, never in plain storage.
class SecureStore {
  SecureStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  final FlutterSecureStorage _storage;

  static const openAiKey = 'openai_api_key';
  static const milaBackendUrl = 'mila_backend_url';
  static const openAiAccountToken = 'openai_account_token';
  static const openAiAccountLabel = 'openai_account_label';
  static const agenticOsAccessToken = 'agentic_os_access_token';
  static const agenticOsAccountRole = 'agentic_os_account_role';
  static const pushDeviceId = 'push_device_id';
  static const geminiKey = 'gemini_api_key';
  static const anthropicKey = 'anthropic_api_key';
  static const integrationConfigs = 'integration_configs';

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) => value.trim().isEmpty
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value.trim());
}

// ---------------------------------------------------------------------------
// Riverpod wiring
// ---------------------------------------------------------------------------

/// Overridden in main() after async init.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError(),
);

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._store)
    : super(
        _store.readMap('settings') != null
            ? AppSettings.fromJson(_store.readMap('settings')!)
            : const AppSettings(),
      );

  final LocalStore _store;

  void update(AppSettings Function(AppSettings) fn) {
    state = fn(state);
    _store.writeJson('settings', state.toJson());
  }
}

final settingsProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(ref.watch(localStoreProvider)),
);

class ProfileController extends StateNotifier<UserProfile> {
  ProfileController(this._store)
    : super(
        _store.readMap('profile') != null
            ? UserProfile.fromJson(_store.readMap('profile')!)
            : const UserProfile(),
      );

  final LocalStore _store;

  void save(UserProfile profile) {
    state = profile;
    _store.writeJson('profile', profile.toJson());
  }

  void signOut() => save(state.copyWith(signedIn: false));
}

final profileProvider = StateNotifierProvider<ProfileController, UserProfile>(
  (ref) => ProfileController(ref.watch(localStoreProvider)),
);

class ChatController extends StateNotifier<List<ChatMessage>> {
  ChatController(this._store)
    : super(_store.readList('chat').map(ChatMessage.fromJson).toList());

  final LocalStore _store;

  void _persist() =>
      _store.writeJson('chat', state.map((m) => m.toJson()).toList());

  void add(ChatMessage message) {
    state = [...state, message];
    _persist();
  }

  /// Append streamed tokens to an existing assistant message.
  void appendText(String id, String delta) {
    state = [
      for (final m in state)
        if (m.id == id)
          (ChatMessage(
            id: m.id,
            role: m.role,
            text: m.text + delta,
            createdAt: m.createdAt,
            actions: m.actions,
            attachments: m.attachments,
            cards: m.cards,
            suggestions: m.suggestions,
            viaVoice: m.viaVoice,
            deliveryStatus: m.deliveryStatus,
            replyToText: m.replyToText,
          ))
        else
          m,
    ];
    _persist();
  }

  void replace(ChatMessage message) {
    state = [for (final m in state) m.id == message.id ? message : m];
    _persist();
  }

  void mergeRemote(Iterable<ChatMessage> messages) {
    final byId = <String, ChatMessage>{
      for (final message in state) message.id: message,
    };
    for (final message in messages) {
      final local = byId[message.id];
      if (local == null) {
        byId[message.id] = message;
      } else if (local.text.isEmpty && message.text.isNotEmpty) {
        byId[message.id] = message;
      }
    }
    state = byId.values.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    if (state.length > 500) state = state.sublist(state.length - 500);
    _persist();
  }

  void setDeliveryStatus(String id, ChatDeliveryStatus status) {
    state = [
      for (final message in state)
        if (message.id == id)
          ChatMessage(
            id: message.id,
            role: message.role,
            text: message.text,
            createdAt: message.createdAt,
            actions: message.actions,
            attachments: message.attachments,
            cards: message.cards,
            suggestions: message.suggestions,
            viaVoice: message.viaVoice,
            deliveryStatus: status,
            replyToText: message.replyToText,
          )
        else
          message,
    ];
    _persist();
  }

  void setActionStatus(String messageId, String actionId, ActionStatus status) {
    for (final m in state) {
      if (m.id == messageId) {
        for (final a in m.actions) {
          if (a.id == actionId) a.status = status;
        }
      }
    }
    state = [...state];
    _persist();
  }

  void clear() {
    for (final message in state) {
      for (final attachment in message.attachments) {
        File(attachment.path).delete().catchError((_) => File(attachment.path));
      }
    }
    state = [];
    _persist();
  }
}

final chatProvider = StateNotifierProvider<ChatController, List<ChatMessage>>(
  (ref) => ChatController(ref.watch(localStoreProvider)),
);

class TasksController extends StateNotifier<List<TaskItem>> {
  TasksController(this._store)
    : super(_store.readList('tasks').map(TaskItem.fromJson).toList());

  final LocalStore _store;

  void _persist() =>
      _store.writeJson('tasks', state.map((t) => t.toJson()).toList());

  void add(TaskItem task) {
    state = [task, ...state];
    _persist();
  }

  void toggle(String id, bool enabled) {
    state = [
      for (final t in state)
        if (t.id == id) (t..enabled = enabled) else t,
    ];
    _persist();
  }

  void setDone(String id, bool done) {
    state = [
      for (final t in state)
        if (t.id == id) (t..done = done) else t,
    ];
    _persist();
  }

  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
    _persist();
  }
}

final tasksProvider = StateNotifierProvider<TasksController, List<TaskItem>>(
  (ref) => TasksController(ref.watch(localStoreProvider)),
);

class MemoryController extends StateNotifier<List<MemoryItem>> {
  MemoryController(this._store)
    : super(_store.readList('memories').map(MemoryItem.fromJson).toList());

  final LocalStore _store;

  void _persist() =>
      _store.writeJson('memories', state.map((m) => m.toJson()).toList());

  void add(MemoryItem item) {
    final normalized = item.text.trim().toLowerCase();
    if (state.any((m) => m.text.trim().toLowerCase() == normalized)) return;
    state = [item, ...state];
    _persist();
  }

  void remove(String id) {
    state = state.where((m) => m.id != id).toList();
    _persist();
  }

  void mergeRemote(List<MemoryItem> remote) {
    final remoteText = remote
        .map((item) => item.text.trim().toLowerCase())
        .toSet();
    state = [
      ...remote,
      ...state.where(
        (item) => !remoteText.contains(item.text.trim().toLowerCase()),
      ),
    ];
    _persist();
  }
}

final memoriesProvider =
    StateNotifierProvider<MemoryController, List<MemoryItem>>(
      (ref) => MemoryController(ref.watch(localStoreProvider)),
    );

/// Integration connection flags (UI-level; real OAuth flows are backend work).
class IntegrationsController extends StateNotifier<Map<String, bool>> {
  IntegrationsController(this._store)
    : super((_store.readMap('integrations') ?? {}).cast<String, bool>());

  final LocalStore _store;

  void toggle(String name) {
    state = {...state, name: !(state[name] ?? false)};
    _store.writeJson('integrations', state);
  }
}

final integrationsProvider =
    StateNotifierProvider<IntegrationsController, Map<String, bool>>(
      (ref) => IntegrationsController(ref.watch(localStoreProvider)),
    );
