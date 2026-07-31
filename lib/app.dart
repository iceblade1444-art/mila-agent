import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/i18n/mila_localizations.dart';
import 'core/theme/mila_theme.dart';
import 'router.dart';
import 'services/storage/stores.dart';
import 'services/push/push_notification_service.dart';

final milaScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class MilaApp extends ConsumerStatefulWidget {
  const MilaApp({super.key});

  @override
  ConsumerState<MilaApp> createState() => _MilaAppState();
}

class _MilaAppState extends ConsumerState<MilaApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(pushNotificationProvider)
          .start(
            onOpen: () => ref.read(routerProvider).go('/chat'),
            onForeground: (title, body) {
              final messenger = milaScaffoldMessengerKey.currentState;
              final language = ref
                  .read(settingsProvider)
                  .language
                  .toLowerCase();
              final openLabel =
                  language.contains('uzbek') || language.contains('o‘zbek')
                  ? 'Ochish'
                  : language.contains('рус') || language.contains('russian')
                  ? 'Открыть'
                  : 'Open';
              messenger?.hideCurrentSnackBar();
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(body.isEmpty ? title : '$title: $body'),
                  action: SnackBarAction(
                    label: openLabel,
                    onPressed: () => ref.read(routerProvider).go('/chat'),
                  ),
                ),
              );
            },
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      scaffoldMessengerKey: milaScaffoldMessengerKey,
      title: 'MILA',
      debugShowCheckedModeBanner: false,
      theme: MilaTheme.dark(),
      darkTheme: MilaTheme.dark(),
      themeMode: ThemeMode.dark,
      locale: milaLocaleFromLanguageName(settings.language),
      supportedLocales: MilaLocalizations.supportedLocales,
      localizationsDelegates: const [
        MilaLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
