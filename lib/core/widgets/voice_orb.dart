import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual states shared by every MILA orb in the app.
enum OrbMood {
  idle,
  listening,
  thinking,
  speaking,
  error,
  offline,
  complete,
  sleep,
  attention,
}

/// The app now has one visual identity, so this wrapper no longer reads a
/// user-selected skin. It remains as the common entry point for app screens.
class AdaptiveOrb extends StatelessWidget {
  const AdaptiveOrb({
    super.key,
    this.size = 220,
    this.mood = OrbMood.idle,
    this.level = 0,
  });

  final double size;
  final OrbMood mood;
  final double level;

  @override
  Widget build(BuildContext context) =>
      VoiceOrb(size: size, mood: mood, level: level);
}

/// A lightweight living light aperture.
///
/// A single painter owns the animation, and [RepaintBoundary] isolates its
/// frames from the rest of the screen. There are no image filters, particles,
/// saveLayer calls or bitmap assets in the animation.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    this.size = 220,
    this.mood = OrbMood.idle,
    this.level = 0,
  });

  final double size;
  final OrbMood mood;
  final double level;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion && _motion.isAnimating) return;
    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      _motion.stop();
      _motion.value = 0.18;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: _moodLabel(widget.mood),
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _LivingOrbPainter(
              motion: _motion,
              mood: widget.mood,
              level: widget.level.clamp(0.0, 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

String _moodLabel(OrbMood mood) => switch (mood) {
  OrbMood.listening => 'MILA is listening',
  OrbMood.thinking => 'MILA is thinking',
  OrbMood.speaking => 'MILA is speaking',
  OrbMood.error => 'MILA needs attention',
  OrbMood.offline => 'MILA is offline',
  OrbMood.complete => 'MILA completed the task',
  OrbMood.sleep => 'MILA is sleeping',
  OrbMood.attention => 'MILA is ready',
  OrbMood.idle => 'MILA is idle',
};

class _LivingOrbPainter extends CustomPainter {
  _LivingOrbPainter({
    required this.motion,
    required this.mood,
    required this.level,
  }) : super(repaint: motion);

  final Animation<double> motion;
  final OrbMood mood;
  final double level;

  static const _ink = Color(0xFF060A14);
  static const _deep = Color(0xFF0B1326);
  static const _cyan = Color(0xFF55E7FF);
  static const _blue = Color(0xFF5578FF);
  static const _violet = Color(0xFF9B6CFF);
  static const _pink = Color(0xFFFF68C7);
  static const _teal = Color(0xFF42F0D0);
  static const _red = Color(0xFFFF536B);
  static const _grey = Color(0xFF758096);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final dimension = math.min(size.width, size.height);
    final phase = motion.value * math.pi * 2;
    final energy = _energy;
    final breathe = 1 + math.sin(phase * 1.35) * 0.018 * energy;
    final radius = dimension * 0.322 * breathe;
    final color = _primary;
    final accent = _accent;

    _drawHalo(canvas, center, radius, color, energy);
    _drawOrbits(canvas, center, radius, phase, color, accent, energy);
    _drawBody(canvas, center, radius, phase, color, accent, energy);
    _drawActivity(canvas, center, radius, phase, color, energy);
    _drawStatusGlyph(canvas, center, radius);
  }

  double get _energy => switch (mood) {
    OrbMood.speaking => 0.72 + level * 0.28,
    OrbMood.listening => 0.70 + level * 0.22,
    OrbMood.thinking => 0.78,
    OrbMood.attention => 0.82,
    OrbMood.complete => 0.72,
    OrbMood.error => 0.62,
    OrbMood.offline => 0.22,
    OrbMood.sleep => 0.12,
    OrbMood.idle => 0.52,
  };

  Color get _primary => switch (mood) {
    OrbMood.listening => _cyan,
    OrbMood.thinking => _violet,
    OrbMood.speaking => Color.lerp(_violet, _pink, level)!,
    OrbMood.error => _red,
    OrbMood.offline || OrbMood.sleep => _grey,
    OrbMood.complete => _teal,
    OrbMood.attention => _cyan,
    OrbMood.idle => _blue,
  };

  Color get _accent => switch (mood) {
    OrbMood.listening => _teal,
    OrbMood.thinking => _cyan,
    OrbMood.speaking => _cyan,
    OrbMood.error => const Color(0xFFFFA0AC),
    OrbMood.offline || OrbMood.sleep => const Color(0xFF4B5368),
    OrbMood.complete => _cyan,
    OrbMood.attention => _pink,
    OrbMood.idle => _violet,
  };

  void _drawHalo(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double energy,
  ) {
    final rect = Rect.fromCircle(center: center, radius: radius * 1.58);
    canvas.drawCircle(
      center,
      radius * 1.58,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.15 * energy),
            color.withValues(alpha: 0.055 * energy),
            Colors.transparent,
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(rect),
    );
  }

  void _drawOrbits(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Color color,
    Color accent,
    double energy,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(phase * 0.12);
    canvas.translate(-center.dx, -center.dy);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, radius * 0.009);
    for (var i = 0; i < 3; i++) {
      final orbitRadius = radius * (1.10 + i * 0.105);
      final rect = Rect.fromCenter(
        center: center,
        width: orbitRadius * 2,
        height: orbitRadius * (1.50 + i * 0.08),
      );
      orbitPaint.color = Color.lerp(
        color,
        accent,
        i / 2,
      )!.withValues(alpha: (0.16 - i * 0.035) * energy);
      canvas.drawArc(
        rect,
        phase * (0.20 + i * 0.05) + i * 1.7,
        math.pi * (0.48 + i * 0.10),
        false,
        orbitPaint,
      );
    }
    canvas.restore();
  }

  void _drawBody(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Color color,
    Color accent,
    double energy,
  ) {
    final bodyRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.32, -0.38),
          radius: 1.08,
          colors: [Color.lerp(_deep, color, 0.26)!, _deep, _ink],
          stops: const [0.0, 0.56, 1.0],
        ).createShader(bodyRect),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(bodyRect));
    _drawRibbon(
      canvas,
      center,
      radius,
      phase,
      color,
      accent,
      energy,
      verticalOffset: -0.05,
      thickness: 0.22,
    );
    _drawRibbon(
      canvas,
      center,
      radius,
      -phase * 0.78 + 2.2,
      accent,
      color,
      energy * 0.78,
      verticalOffset: 0.24,
      thickness: 0.14,
    );

    final coreCenter =
        center +
        Offset(
          math.cos(phase * 0.72) * radius * 0.08,
          math.sin(phase * 0.58) * radius * 0.06,
        );
    final coreRect = Rect.fromCircle(center: coreCenter, radius: radius * 0.58);
    canvas.drawCircle(
      coreCenter,
      radius * 0.58,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.28 * energy),
            color.withValues(alpha: 0.10 * energy),
            Colors.transparent,
          ],
        ).createShader(coreRect),
    );

    final pulse = 0.82 + math.sin(phase * 1.7) * 0.12 * energy;
    final irisRadius = radius * 0.30 * pulse;
    final irisRect = Rect.fromCircle(center: coreCenter, radius: irisRadius);
    canvas.drawCircle(
      coreCenter,
      irisRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.34 * energy),
            accent.withValues(alpha: 0.28 * energy),
            color.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.24, 0.62, 1.0],
        ).createShader(irisRect),
    );
    canvas.drawCircle(
      coreCenter,
      radius * 0.052,
      Paint()..color = Colors.white.withValues(alpha: 0.72 * energy),
    );
    canvas.restore();

    final rimRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, radius * 0.014)
        ..shader = SweepGradient(
          transform: GradientRotation(phase * 0.16),
          colors: [
            color.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.88 * energy),
            Colors.white.withValues(alpha: 0.16),
            color.withValues(alpha: 0.62 * energy),
            color.withValues(alpha: 0.18),
          ],
        ).createShader(rimRect),
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      -2.65,
      1.15,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, radius * 0.018)
        ..color = Colors.white.withValues(alpha: 0.12 + energy * 0.08),
    );
  }

  void _drawRibbon(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Color start,
    Color end,
    double energy, {
    required double verticalOffset,
    required double thickness,
  }) {
    const segments = 14;
    final top = <Offset>[];
    final bottom = <Offset>[];
    for (var i = 0; i <= segments; i++) {
      final unit = i / segments;
      final x = center.dx + (unit * 2 - 1) * radius * 1.12;
      final wave = math.sin(unit * math.pi * 2.1 + phase) * radius * 0.17;
      final secondary =
          math.cos(unit * math.pi * 3.2 - phase * 0.6) * radius * 0.045;
      final y = center.dy + radius * verticalOffset + wave + secondary;
      final half =
          radius * thickness * (0.42 + math.sin(unit * math.pi) * 0.58);
      top.add(Offset(x, y - half));
      bottom.add(Offset(x, y + half));
    }

    final path = Path()..moveTo(top.first.dx, top.first.dy);
    for (final point in top.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    for (final point in bottom.reversed) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                Colors.transparent,
                start.withValues(alpha: 0.46 * energy),
                Colors.white.withValues(alpha: 0.42 * energy),
                end.withValues(alpha: 0.54 * energy),
                Colors.transparent,
              ],
              stops: const [0.0, 0.24, 0.50, 0.76, 1.0],
            ).createShader(
              Rect.fromCenter(
                center: center,
                width: radius * 2.3,
                height: radius,
              ),
            ),
    );
  }

  void _drawActivity(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Color color,
    double energy,
  ) {
    if (mood != OrbMood.listening && mood != OrbMood.attention) return;
    final cycle = (motion.value * 2.4) % 1.0;
    for (var i = 0; i < 2; i++) {
      final progress = (cycle + i * 0.5) % 1.0;
      canvas.drawCircle(
        center,
        radius * (1.08 + progress * 0.48),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, radius * 0.009)
          ..color = color.withValues(alpha: (1 - progress) * 0.22 * energy),
      );
    }
  }

  void _drawStatusGlyph(Canvas canvas, Offset center, double radius) {
    final (IconData? icon, Color color) = switch (mood) {
      OrbMood.error => (Icons.priority_high_rounded, _red),
      OrbMood.offline => (Icons.cloud_off_rounded, _grey),
      OrbMood.complete => (Icons.check_rounded, _teal),
      OrbMood.sleep => (Icons.bedtime_outlined, _grey),
      _ => (null, Colors.transparent),
    };
    if (icon == null) return;

    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color.withValues(alpha: 0.94),
          fontSize: radius * 0.43,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_LivingOrbPainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.level != level;
}
