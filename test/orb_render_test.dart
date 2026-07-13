import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mila/core/widgets/voice_orb.dart';

/// Renders orb moods and skins to `build/orb_*.png` so look and motion can
/// be inspected without a device.
void main() {
  testWidgets('render orb moods and skins to png', (tester) async {
    Future<void> capture(String name, OrbMood mood, OrbSkin skin,
        {int pumpMs = 900}) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 340,
                height: 340,
                color: const Color(0xFF0D111B),
                child:
                    VoiceOrb(size: 340, mood: mood, level: 0.6, skin: skin),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration(milliseconds: pumpMs));
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/orb_$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }

    for (final mood in OrbMood.values) {
      await capture('mood_${mood.name}', mood, OrbSkin.nebula);
    }
    for (final skin in OrbSkin.values) {
      await capture('skin_${skin.name}', OrbMood.idle, skin);
    }
  });
}
