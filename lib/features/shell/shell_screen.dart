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
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: keyboardOpen
            ? const SizedBox.shrink(key: ValueKey('keyboard-hidden-nav'))
            : _BottomBar(key: const ValueKey('bottom-nav'), shell: shell),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({super.key, required this.shell});

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
        left: 18,
        right: 18,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF141926).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(24),
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
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: MilaColors.violet.withValues(alpha: 0.45),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: const AdaptiveOrb(size: 46),
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
        child: AnimatedScale(
          scale: selected ? 1.08 : 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: AnimatedSlide(
            offset: selected ? const Offset(0, -0.06) : Offset.zero,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: 32,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected
                        ? MilaColors.cyan.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: MilaColors.cyan.withValues(alpha: 0.14),
                              blurRadius: 10,
                            ),
                          ]
                        : const [],
                  ),
                  child: AnimatedRotation(
                    turns: selected ? 0 : -0.015,
                    duration: const Duration(milliseconds: 260),
                    child: Icon(
                      icon,
                      size: 21,
                      color: selected
                          ? MilaColors.cyan
                          : MilaColors.textTertiary,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
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
        ),
      ),
    );
  }
}
