import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';

/// The way to reach MILA, on every tab, next to the thumb.
///
/// It used to be a 150px orb occupying the top forty percent of the home screen
/// under the caption "tap the orb or speak" — an instruction where content
/// belongs, reachable only from one tab, and duplicated by a second orb in the
/// navigation bar. Here it is a row: tap the text to write, tap the microphone
/// to talk. Both are one gesture from anywhere in the app.
///
/// Text and voice are deliberately equal in weight. The people using this are
/// on a factory floor, and a voice-only door closes whenever the room is loud.
class ComposerBar extends StatelessWidget {
  const ComposerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final write = l10n.pick(
      ru: 'Спросите или скажите…',
      en: 'Ask or say something…',
      uz: 'So‘rang yoki gapiring…',
    );
    final speak = l10n.pick(
      ru: 'Голосом',
      en: 'Voice',
      uz: 'Ovoz bilan',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: MilaColors.surface,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                onTap: () => context.push('/chat'),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: MilaColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 17,
                        color: MilaColors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          write,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: MilaColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // The orb, at the size it should always have been: a control, not a
          // hero image. 44 square is the floor for something used with one hand
          // while carrying a roll of fabric.
          Semantics(
            button: true,
            label: speak,
            child: Tooltip(
              message: speak,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/voice'),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: MilaColors.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: MilaColors.violetFill.withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic_none_rounded, size: 21, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
