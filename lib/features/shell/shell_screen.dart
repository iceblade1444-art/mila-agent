import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/voice_orb.dart';

/// App shell: indexed tab stack + floating bottom navigation with the
/// MILA orb as the center voice button.
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: _BottomBar(shell: shell),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (Icons.home_rounded, l10n.pick(ru: 'Главная', en: 'Home', uz: 'Bosh'), 0),
      (
        Icons.grid_view_rounded,
        l10n.pick(ru: 'Центр', en: 'Center', uz: 'Markaz'),
        1,
      ),
      (
        Icons.chat_bubble_outline_rounded,
        l10n.pick(ru: 'Чат', en: 'Chat', uz: 'Chat'),
        2,
      ),
      (
        Icons.check_circle_outline_rounded,
        l10n.pick(ru: 'Задачи', en: 'Tasks', uz: 'Vazifalar'),
        3,
      ),
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFF141926).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: MilaColors.cardBorder),
            ),
            child: Row(
              children: [
                _navItem(context, items[0]),
                _navItem(context, items[1]),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: () => context.push('/voice'),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: MilaColors.violet.withValues(alpha: 0.45),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: const AdaptiveOrb(size: 52),
                      ),
                    ),
                  ),
                ),
                _navItem(context, items[2]),
                _navItem(context, items[3]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, (IconData, String, int) item) {
    final (icon, label, index) = item;
    final selected = shell.currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? MilaColors.cyan : MilaColors.textTertiary,
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: selected ? 14 : 0,
              height: 3,
              decoration: BoxDecoration(
                gradient: MilaColors.primaryGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
