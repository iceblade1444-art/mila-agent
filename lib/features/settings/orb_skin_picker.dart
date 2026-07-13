import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/storage/stores.dart';

const orbSkinLabels = <OrbSkin, String>{
  OrbSkin.nebula: 'Nebula',
  OrbSkin.ocean: 'Ocean',
  OrbSkin.cosmic: 'Cosmic',
  OrbSkin.energy: 'Energy',
  OrbSkin.minimal: 'Minimal',
  OrbSkin.holographic: 'Holographic',
};

/// Bottom sheet with live-animated previews of every orb skin
/// (the "ORB VARIATIONS" row of the UI kit).
Future<void> showOrbSkinPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (sheetContext, sheetRef, _) {
        final current = sheetRef.watch(
            settingsProvider.select((s) => orbSkinFromName(s.orbSkin)));
        final text = Theme.of(sheetContext).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Orb Skin', style: text.headlineSmall),
                const SizedBox(height: 4),
                Text('Pick how MILA looks. Live preview.',
                    style: text.bodySmall),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                  children: [
                    for (final skin in OrbSkin.values)
                      GestureDetector(
                        onTap: () {
                          sheetRef
                              .read(settingsProvider.notifier)
                              .update((s) => s.copyWith(orbSkin: skin.name));
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: current == skin
                                  ? MilaColors.cyan
                                  : MilaColors.cardBorder,
                              width: current == skin ? 1.6 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              VoiceOrb(
                                  size: 78,
                                  skin: skin,
                                  mood: OrbMood.idle),
                              const SizedBox(height: 6),
                              Text(
                                orbSkinLabels[skin]!,
                                style: text.labelSmall?.copyWith(
                                    color: current == skin
                                        ? MilaColors.cyan
                                        : MilaColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
