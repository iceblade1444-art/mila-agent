import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class MilaFirebaseConfig {
  const MilaFirebaseConfig._();

  static const apiKey = String.fromEnvironment('MILA_FIREBASE_API_KEY');
  static const projectId = String.fromEnvironment('MILA_FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment(
    'MILA_FIREBASE_MESSAGING_SENDER_ID',
  );
  static const androidAppId = String.fromEnvironment(
    'MILA_FIREBASE_ANDROID_APP_ID',
  );
  static const iosAppId = String.fromEnvironment('MILA_FIREBASE_IOS_APP_ID');
  static const iosBundleId = String.fromEnvironment(
    'MILA_FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'app.milaai.mila',
  );

  static bool get isConfigured {
    if (kIsWeb) return false;
    final appId = Platform.isIOS ? iosAppId : androidAppId;
    return apiKey.isNotEmpty &&
        projectId.isNotEmpty &&
        senderId.isNotEmpty &&
        appId.isNotEmpty;
  }

  static FirebaseOptions? get currentPlatform {
    if (!isConfigured) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: Platform.isIOS ? iosAppId : androidAppId,
      messagingSenderId: senderId,
      projectId: projectId,
      iosBundleId: Platform.isIOS ? iosBundleId : null,
    );
  }
}
