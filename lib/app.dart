import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/i18n/mila_localizations.dart';
import 'core/theme/mila_theme.dart';
import 'router.dart';
import 'services/storage/stores.dart';

class MilaApp extends ConsumerWidget {
  const MilaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
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
