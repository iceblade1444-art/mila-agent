import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import 'composer_bar.dart';

/// App shell: an indexed tab stack, the composer, and four named destinations.
///
/// Three things were wrong with what this replaced, and all three were visible
/// on a screenshot:
///
///   * The bar drew icons only. The label existed in the code — destructured
///     out of the tuple on the first line of the item builder — and was passed
///     to nothing. Five glyphs and no words is a memory test, and it is the
///     same mistake the web rail made until it was fixed there.
///   * The centre slot held an orb, and the home screen held a second one at
///     150px. Two doors to the same room, one of them taking up most of the
///     first screen.
///   * It was a hand-rolled Row, so none of Material 3's spring motion, ink or
///     accessible sizing applied. NavigationBar gives all of that away for free
///     and takes the labels seriously.
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    // While the keyboard is up the composer would sit on top of it and the bar
    // would eat a third of what is left. Both step aside; the field being typed
    // into is the only thing that matters at that moment.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: MilaColors.background,
      body: shell,
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: keyboardOpen
            ? const SizedBox(width: double.infinity)
            : _Bottom(shell: shell),
      ),
    );
  }
}

class _Bottom extends StatelessWidget {
  const _Bottom({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Same words and same order as the web console's bottom tabs. A floor
    // manager who learns one surface should not have to learn the other.
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.today_outlined),
        selectedIcon: const Icon(Icons.today),
        label: l10n.pick(ru: 'Лента', en: 'Feed', uz: 'Lenta'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.check_circle_outline),
        selectedIcon: const Icon(Icons.check_circle),
        label: l10n.pick(ru: 'Задачи', en: 'Tasks', uz: 'Vazifalar'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.wb_sunny_outlined),
        selectedIcon: const Icon(Icons.wb_sunny),
        label: l10n.pick(ru: 'День', en: 'Day', uz: 'Kun'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.menu_rounded),
        selectedIcon: const Icon(Icons.menu_open_rounded),
        label: l10n.pick(ru: 'Ещё', en: 'More', uz: 'Yana'),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ComposerBar(),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: MilaColors.cardBorder)),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: MilaColors.surface,
              indicatorColor: MilaColors.violetFill.withValues(alpha: 0.22),
              // Always, on both states. A label that appears only under the
              // selected item still leaves the other three unnamed, which is
              // the problem this is here to solve.
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  size: 22,
                  color: states.contains(WidgetState.selected)
                      ? MilaColors.violet
                      : MilaColors.textTertiary,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: states.contains(WidgetState.selected)
                      ? MilaColors.violet
                      : MilaColors.textTertiary,
                ),
              ),
            ),
            child: NavigationBar(
              height: 62,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (index) => shell.goBranch(
                index,
                // Tapping the tab you are already on returns to the top of that
                // branch rather than doing nothing — the standard gesture for
                // getting out of a stack you have wandered into.
                initialLocation: index == shell.currentIndex,
              ),
              destinations: destinations,
            ),
          ),
        ),
      ],
    );
  }
}
