import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/mila_theme.dart';
import 'router.dart';

class MilaApp extends ConsumerWidget {
  const MilaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MILA',
      debugShowCheckedModeBanner: false,
      theme: MilaTheme.dark(),
      darkTheme: MilaTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
