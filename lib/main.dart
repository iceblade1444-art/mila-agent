import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/storage/stores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D111B),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final store = await LocalStore.open();

  runApp(ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(store)],
    child: const MilaApp(),
  ));
}
