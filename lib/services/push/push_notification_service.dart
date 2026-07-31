import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/firebase_config.dart';
import '../agentic/agentic_os_service.dart';
import '../storage/stores.dart';

typedef PushOpenCallback = void Function();
typedef PushForegroundCallback = void Function(String title, String body);

@pragma('vm:entry-point')
Future<void> milaFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  final options = MilaFirebaseConfig.currentPlatform;
  if (options != null && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
}

Future<bool> initializeMilaFirebase() async {
  final options = MilaFirebaseConfig.currentPlatform;
  if (options == null) return false;
  if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
  FirebaseMessaging.onBackgroundMessage(milaFirebaseMessagingBackgroundHandler);
  return true;
}

class PushNotificationService {
  PushNotificationService(this._ref);

  final Ref _ref;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openSubscription;
  StreamSubscription<String>? _tokenSubscription;
  PushOpenCallback? _onOpen;
  PushForegroundCallback? _onForeground;
  bool _started = false;

  Future<void> start({
    required PushOpenCallback onOpen,
    required PushForegroundCallback onForeground,
  }) async {
    _onOpen = onOpen;
    _onForeground = onForeground;
    if (_started || !MilaFirebaseConfig.isConfigured) return;
    _started = true;

    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      unawaited(_refreshInbox());
      final title = message.notification?.title ?? 'MILA';
      final body = message.notification?.body ?? '';
      _onForeground?.call(title, body);
    });
    _openSubscription = FirebaseMessaging.onMessageOpenedApp.listen((_) {
      unawaited(_openInbox());
    });
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      unawaited(registerCurrentDevice(requestPermission: false));
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) await _openInbox();
    if (await _ref.read(agenticOsServiceProvider).isConnected()) {
      await registerCurrentDevice();
    }
  }

  Future<bool> registerCurrentDevice({bool requestPermission = true}) async {
    if (!MilaFirebaseConfig.isConfigured) return false;
    if (!await _ref.read(agenticOsServiceProvider).isConnected()) return false;
    if (requestPermission) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return false;
    final secure = _ref.read(secureStoreProvider);
    var deviceId = await secure.read(SecureStore.pushDeviceId) ?? '';
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await secure.write(SecureStore.pushDeviceId, deviceId);
    }
    final language = _ref.read(settingsProvider).language.toLowerCase();
    final locale = language.contains('uzbek') || language.contains('o‘zbek')
        ? 'uz'
        : language.contains('рус') || language.contains('russian')
        ? 'ru'
        : 'en';
    await _ref
        .read(agenticOsServiceProvider)
        .registerPushDevice(
          deviceId: deviceId,
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          locale: locale,
        );
    return true;
  }

  Future<void> unregisterCurrentDevice() async {
    if (!MilaFirebaseConfig.isConfigured) return;
    final secure = _ref.read(secureStoreProvider);
    final deviceId = await secure.read(SecureStore.pushDeviceId) ?? '';
    if (deviceId.isNotEmpty &&
        await _ref.read(agenticOsServiceProvider).isConnected()) {
      try {
        await _ref
            .read(agenticOsServiceProvider)
            .unregisterPushDevice(deviceId);
      } on AgenticOsException {
        // The local Firebase token is still revoked below.
      }
    }
    await FirebaseMessaging.instance.deleteToken();
  }

  Future<void> _refreshInbox() => _ref.read(chatSyncProvider.notifier).sync();

  Future<void> _openInbox() async {
    await _refreshInbox();
    _onOpen?.call();
  }

  void dispose() {
    _messageSubscription?.cancel();
    _openSubscription?.cancel();
    _tokenSubscription?.cancel();
  }
}

final pushNotificationProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(ref);
  ref.onDispose(service.dispose);
  return service;
});
