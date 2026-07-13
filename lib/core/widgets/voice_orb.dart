import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/storage/stores.dart';

/// Orb states — matches the MILA Orb UI kit sheet.
enum OrbMood {
  idle, // calm and ready
  listening, // actively listening (ripples)
  thinking, // processing: constellation network
  speaking, // delivering the response (audio-reactive)
  error, // something went wrong (red pulse + !)
  offline, // no internet (dim, cloud-off)
  complete, // task completed (teal check pop-in)
  sleep, // power saving (very dim + zZ)
  attention, // gently get user's attention (waves outward)
}

/// Orb visual skins — the "ORB VARIATIONS" row of the kit.
enum OrbSkin { nebula, ocean, cosmic, energy, minimal, holographic }

OrbSkin orbSkinFromName(String name) => OrbSkin.values
    .firstWhere((s) => s.name == name, orElse: () => OrbSkin.nebula);

/// Reads the user's chosen skin from settings and renders the orb with it.
/// Use this in app screens; use [VoiceOrb] directly for previews.
class AdaptiveOrb extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final skinName =
        ref.watch(settingsProvider.select((s) => s.orbSkin));
    return VoiceOrb(
      size: size,
      mood: mood,
      level: level,
      skin: orbSkinFromName(skinName),
    );
  }
}

/// The MILA orb: a dark glass sphere with flowing light. Skins change the
/// inner art (ribbons / wireframe / minimal ring); moods change the
/// animation. Mood changes cross-fade; [level] (0..1) is live audio.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    this.size = 220,
    this.mood = OrbMood.idle,
    this.level = 0,
    this.skin = OrbSkin.nebula,
  });

  final double size;
  final OrbMood mood;
  final double level;
  final OrbSkin skin;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late final AnimationController _flow;
  late final AnimationController _transition;
  OrbMood _prevMood = OrbMood.idle;
  double _smoothLevel = 0;

  @override
  void initState() {
    super.initState();
    _prevMood = widget.mood;
    _flow =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
    _transition = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500), value: 1);
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _prevMood = oldWidget.mood;
      _transition.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_flow, _transition]),
        builder: (context, _) {
          _smoothLevel += (widget.level.clamp(0.0, 1.0) - _smoothLevel) * 0.18;
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _OrbPainter(
              raw: _flow.value,
              level: _smoothLevel,
              mood: widget.mood,
              prevMood: _prevMood,
              moodMix: Curves.easeInOut.transform(_transition.value),
              skin: widget.skin,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skin palettes
// ---------------------------------------------------------------------------

class _SkinStyle {
  const _SkinStyle({
    required this.main,
    required this.loop,
    required this.back,
    required this.bloomA,
    required this.bloomB,
    required this.rim,
    required this.core,
    required this.dustDouble,
  });

  final List<Color> main; // main ribbon gradient
  final List<Color> loop; // bottom loop gradient
  final List<Color> back; // back arc gradient
  final Color bloomA;
  final Color bloomB;
  final List<Color> rim;
  final Color core;
  final bool dustDouble;

  static const _cyan = Color(0xFF4DD0FF);
  static const _ice = Color(0xFF9BE8FF);
  static const _blue = Color(0xFF3D7BFF);
  static const _violet = Color(0xFF7B61FF);
  static const _purple = Color(0xFFB673FF);
  static const _pink = Color(0xFFFF6AD5);

  static _SkinStyle of(OrbSkin skin) => switch (skin) {
        OrbSkin.nebula => const _SkinStyle(
            main: [Color(0x0D3D7BFF), _cyan, _ice, _blue, _violet],
            loop: [_pink, _pink, _purple, Color(0x0D7B61FF)],
            back: [Color(0x003D7BFF), _blue, _violet, Color(0x007B61FF)],
            bloomA: _violet,
            bloomB: _blue,
            rim: [_cyan, _violet, _pink, _blue],
            core: _ice,
            dustDouble: false,
          ),
        OrbSkin.ocean => const _SkinStyle(
            main: [Color(0x0D00E5FF), Color(0xFF3DFFC9), Color(0xFFB2FFF0), Color(0xFF00E5FF), Color(0xFF2F6BFF)],
            loop: [Color(0xFF00B8D9), Color(0xFF00E5FF), Color(0xFF3DFFC9), Color(0x0D2F6BFF)],
            back: [Color(0x0000E5FF), Color(0xFF2F6BFF), Color(0xFF00B8D9), Color(0x002F6BFF)],
            bloomA: Color(0xFF00B8D9),
            bloomB: Color(0xFF2F6BFF),
            rim: [Color(0xFF3DFFC9), Color(0xFF00E5FF), Color(0xFF2F6BFF), Color(0xFF00B8D9)],
            core: Color(0xFFD4FFF6),
            dustDouble: false,
          ),
        OrbSkin.cosmic => const _SkinStyle(
            main: [Color(0x0D7B61FF), _purple, Color(0xFFE1B8FF), _violet, Color(0xFF5B2EA6)],
            loop: [Color(0xFFFF4FD8), _pink, _purple, Color(0x0D7B61FF)],
            back: [Color(0x007B61FF), _violet, Color(0xFF5B2EA6), Color(0x005B2EA6)],
            bloomA: _purple,
            bloomB: _pink,
            rim: [_purple, _pink, _violet, Color(0xFFE1B8FF)],
            core: Color(0xFFF3E3FF),
            dustDouble: true,
          ),
        OrbSkin.energy => const _SkinStyle(
            main: [Color(0x0DFF8A3D), Color(0xFFFFD24D), Color(0xFFFFF3C2), Color(0xFFFF8A3D), Color(0xFFFF4F6A)],
            loop: [Color(0xFFFF4F6A), Color(0xFFFF6AD5), Color(0xFFFF8A3D), Color(0x0DFF4F6A)],
            back: [Color(0x00FF8A3D), Color(0xFFFF8A3D), Color(0xFFFF4F6A), Color(0x00FF4F6A)],
            bloomA: Color(0xFFFF6A3D),
            bloomB: Color(0xFFFF4F6A),
            rim: [Color(0xFFFFD24D), Color(0xFFFF8A3D), Color(0xFFFF4F6A), Color(0xFFFFD24D)],
            core: Color(0xFFFFF6D9),
            dustDouble: true,
          ),
        // Minimal & holographic don't use ribbons; palettes still tint
        // rim / bloom / states.
        OrbSkin.minimal => const _SkinStyle(
            main: [_violet, _violet],
            loop: [_violet, _violet],
            back: [_violet, _violet],
            bloomA: _violet,
            bloomB: Color(0xFF20263B),
            rim: [_violet, Color(0xFF3A4468), _violet, Color(0xFF3A4468)],
            core: _ice,
            dustDouble: false,
          ),
        OrbSkin.holographic => const _SkinStyle(
            main: [_cyan, _cyan],
            loop: [_cyan, _cyan],
            back: [_cyan, _cyan],
            bloomA: Color(0xFF00B8D9),
            bloomB: _blue,
            rim: [_cyan, _blue, _cyan, _blue],
            core: _ice,
            dustDouble: false,
          ),
      };
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _P3 {
  const _P3(this.x, this.y, this.z);
  final double x, y, z;
}

List<_P3>? _sphereCache;

List<_P3> _fibonacciSphere(int n) {
  final points = <_P3>[];
  final phi = math.pi * (3 - math.sqrt(5));
  for (var i = 0; i < n; i++) {
    final y = 1 - (i / (n - 1)) * 2;
    final r = math.sqrt(math.max(0, 1 - y * y));
    final theta = phi * i;
    points.add(_P3(math.cos(theta) * r, y, math.sin(theta) * r));
  }
  return points;
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.raw,
    required this.level,
    required this.mood,
    required this.prevMood,
    required this.moodMix,
    required this.skin,
  }) : style = _SkinStyle.of(skin);

  final double raw;
  final double level;
  final OrbMood mood;
  final OrbMood prevMood;
  final double moodMix;
  final OrbSkin skin;
  final _SkinStyle style;

  static const _errRed = Color(0xFFFF4B5C);
  static const _dim = Color(0xFF8A93A8);
  static const _teal = Color(0xFF35E8D9);

  bool _isQuiet(OrbMood m) =>
      m == OrbMood.offline || m == OrbMood.sleep || m == OrbMood.error;

  double _energyOf(OrbMood m) => switch (m) {
        OrbMood.speaking => 0.50 + 0.40 * level,
        OrbMood.listening => 0.55 + 0.25 * level,
        OrbMood.thinking => 0.60,
        OrbMood.attention => 0.75,
        OrbMood.complete => 0.70,
        OrbMood.error => 0.55,
        OrbMood.offline => 0.15,
        OrbMood.sleep => 0.10,
        OrbMood.idle => 0.42,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final baseR = size.width * 0.335;
    final flow = raw * 2 * math.pi;
    final breathe = 1 +
        (_isQuiet(mood) ? 0.012 : 0.030) * math.sin(flow * 2) +
        switch (mood) {
          OrbMood.speaking => 0.10 * level,
          OrbMood.listening => 0.05 * level,
          _ => 0.0,
        };
    final r = baseR * breathe;
    final energy =
        _energyOf(prevMood) * (1 - moodMix) + _energyOf(mood) * moodMix;

    _bloom(canvas, c, r, flow, energy);
    _glassBody(canvas, c, r);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    if (moodMix < 1) {
      _content(canvas, c, r, flow, energy, prevMood, 1 - moodMix);
    }
    _content(canvas, c, r, flow, energy, mood, moodMix);
    canvas.restore();

    final rippleAlpha = (mood == OrbMood.listening ? moodMix : 0.0) +
        (prevMood == OrbMood.listening ? 1 - moodMix : 0.0);
    if (rippleAlpha > 0.01) _ripples(canvas, c, r, rippleAlpha, style.rim[0]);

    final attentionAlpha = (mood == OrbMood.attention ? moodMix : 0.0) +
        (prevMood == OrbMood.attention ? 1 - moodMix : 0.0);
    if (attentionAlpha > 0.01) {
      _ripples(canvas, c, r, attentionAlpha, style.core);
    }

    _rim(canvas, c, r, flow, energy);
    if (!_isQuiet(mood) && skin != OrbSkin.minimal) {
      _orbitingSparks(canvas, c, r, flow, energy);
    }
    _specular(canvas, c, r);
  }

  void _content(Canvas canvas, Offset c, double r, double flow, double energy,
      OrbMood m, double opacity) {
    if (opacity < 0.02) return;
    final needsLayer = opacity < 0.98;
    if (needsLayer) {
      canvas.saveLayer(
        Rect.fromCircle(center: c, radius: r * 1.05),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    switch (m) {
      case OrbMood.thinking:
        _constellation(canvas, c, r, flow);
      case OrbMood.error:
        _errorContent(canvas, c, r, flow);
      case OrbMood.offline:
        _offlineContent(canvas, c, r, flow);
      case OrbMood.complete:
        _completeContent(canvas, c, r, flow, opacity);
      case OrbMood.sleep:
        _sleepContent(canvas, c, r, flow);
      default:
        switch (skin) {
          case OrbSkin.minimal:
            _minimalContent(canvas, c, r, flow, energy);
          case OrbSkin.holographic:
            _holographicContent(canvas, c, r, flow, energy);
          default:
            _ribbons(canvas, c, r, flow, energy);
        }
    }
    if (needsLayer) canvas.restore();
  }

  // ------------------------------------------------------------- ribbons

  void _ribbons(
      Canvas canvas, Offset c, double r, double flow, double energy) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.22 * math.sin(flow * 0.7));
    canvas.translate(-c.dx, -c.dy);

    List<Offset> animate(List<Offset> pts, double phase, double amount) {
      final out = <Offset>[];
      for (var i = 0; i < pts.length; i++) {
        out.add(pts[i] +
            Offset(
              math.sin(flow * 1.6 + phase + i * 2.1),
              math.cos(flow * 1.2 + phase + i * 1.4),
            ) *
            amount);
      }
      return out;
    }

    final back = animate(const [
      Offset(-1.05, -0.30),
      Offset(-0.45, -0.62),
      Offset(0.25, -0.68),
      Offset(1.02, -0.35),
    ], 2.2, 0.09);

    final loop = animate(const [
      Offset(-1.02, 0.08),
      Offset(-0.70, 0.60),
      Offset(0.00, 0.84),
      Offset(0.72, 0.62),
      Offset(1.06, 0.25),
    ], 1.1, 0.10);

    final main = animate(const [
      Offset(-1.08, 0.30),
      Offset(-0.40, 0.42),
      Offset(0.18, -0.05),
      Offset(0.65, -0.42),
      Offset(1.06, -0.40),
    ], 0.0, 0.11);

    _band(canvas, c, r, back,
        colors: style.back,
        maxWidth: r * 0.16,
        alpha: 0.35 * energy + 0.10,
        blur: r * 0.10,
        flowShift: flow * 0.9,
        core: false);
    _band(canvas, c, r, loop,
        colors: style.loop,
        maxWidth: r * 0.20 * (1 + 0.4 * level + 0.06 * math.sin(flow * 2.3)),
        alpha: math.min(0.75, 0.55 * energy + 0.15),
        blur: r * 0.075,
        flowShift: -flow * 1.2,
        core: true,
        coreColor: style.loop[1]);
    _band(canvas, c, r, main,
        colors: style.main,
        maxWidth: r * 0.24 * (1 + 0.5 * level + 0.08 * math.sin(flow * 2)),
        alpha: math.min(0.85, 0.75 * energy + 0.20),
        blur: r * 0.06,
        flowShift: flow * 1.5,
        core: true,
        coreColor: style.core);

    _dust(canvas, c, r, main, flow, style.core);
    _dust(canvas, c, r, loop, flow + 2.4, style.core);
    if (style.dustDouble) {
      _dust(canvas, c, r, back, flow + 4.1, style.core);
    }

    canvas.restore();
  }

  void _band(
    Canvas canvas,
    Offset c,
    double r,
    List<Offset> ctrl, {
    required List<Color> colors,
    required double maxWidth,
    required double alpha,
    required double blur,
    required double flowShift,
    required bool core,
    Color coreColor = Colors.white,
  }) {
    final line =
        _spline([for (final p in ctrl) c + Offset(p.dx, p.dy) * r], 40);
    if (line.length < 4) return;

    Path ribbon(double widthScale) {
      final left = <Offset>[];
      final right = <Offset>[];
      for (var i = 0; i < line.length; i++) {
        final s = i / (line.length - 1);
        final prev = line[math.max(0, i - 1)];
        final next = line[math.min(line.length - 1, i + 1)];
        final d = next - prev;
        final len = d.distance == 0 ? 1.0 : d.distance;
        final n = Offset(-d.dy / len, d.dx / len);
        final w = maxWidth *
            widthScale *
            (0.18 + 0.82 * math.pow(math.sin(math.pi * s), 0.8));
        left.add(line[i] + n * w);
        right.add(line[i] - n * w);
      }
      final path = Path()..moveTo(left.first.dx, left.first.dy);
      for (final p in left.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      for (final p in right.reversed) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      return path;
    }

    final dir = line.last - line.first;
    final dirLen = dir.distance == 0 ? 1.0 : dir.distance;
    final unit = Offset(dir.dx / dirLen, dir.dy / dirLen);
    final travel = unit * ((flowShift * r * 0.25) % (dirLen * 2));
    final gradient = LinearGradient(colors: colors, tileMode: TileMode.mirror)
        .createShader(Rect.fromPoints(line.first + travel, line.last + travel));

    canvas.drawPath(
      ribbon(1.7),
      Paint()
        ..shader = gradient
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: alpha * 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 2.2),
    );
    canvas.drawPath(
      ribbon(1.0),
      Paint()
        ..shader = gradient
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    if (core) {
      final start = (line.length * 0.15).floor();
      final end = (line.length * 0.88).floor();
      final corePath = Path()..moveTo(line[start].dx, line[start].dy);
      for (var i = start + 1; i < end; i++) {
        corePath.lineTo(line[i].dx, line[i].dy);
      }
      final pulsePos = (flowShift * 0.15) % 1.0;
      final coreShader = LinearGradient(colors: [
        coreColor.withValues(alpha: 0),
        coreColor.withValues(alpha: 0.5),
        Colors.white,
        coreColor.withValues(alpha: 0.5),
        coreColor.withValues(alpha: 0),
      ], stops: [
        0,
        (pulsePos * 0.8).clamp(0.01, 0.94),
        (pulsePos * 0.8 + 0.05).clamp(0.02, 0.96),
        (pulsePos * 0.8 + 0.10).clamp(0.03, 0.98),
        1,
      ]).createShader(Rect.fromPoints(line[start], line[end - 1]));
      canvas.drawPath(
        corePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = maxWidth * 0.16
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..shader = coreShader
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.5),
      );
    }
  }

  List<Offset> _spline(List<Offset> pts, int samples) {
    if (pts.length < 2) return pts;
    final out = <Offset>[];
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(0, i - 1)];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      final n = (samples / (pts.length - 1)).ceil();
      for (var j = 0; j < n; j++) {
        final t = j / n;
        final t2 = t * t;
        final t3 = t2 * t;
        out.add(Offset(
          0.5 *
              ((2 * p1.dx) +
                  (-p0.dx + p2.dx) * t +
                  (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
                  (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
          0.5 *
              ((2 * p1.dy) +
                  (-p0.dy + p2.dy) * t +
                  (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
                  (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
        ));
      }
    }
    out.add(pts.last);
    return out;
  }

  void _dust(Canvas canvas, Offset c, double r, List<Offset> ctrl,
      double flow, Color tint) {
    final line =
        _spline([for (final p in ctrl) c + Offset(p.dx, p.dy) * r], 40);
    final rnd = math.Random(31);
    for (var i = 0; i < 10; i++) {
      final speed = 0.25 + 0.35 * rnd.nextDouble();
      final drift = (rnd.nextDouble() + flow / (2 * math.pi) * speed) % 1.0;
      final idx = (drift * (line.length - 1)).floor();
      final jitter = Offset((rnd.nextDouble() - 0.5) * r * 0.16,
          (rnd.nextDouble() - 0.5) * r * 0.16);
      final twinkle = 0.4 + 0.6 * math.sin(flow * 4 + i * 2.4).abs();
      canvas.drawCircle(
        line[idx] + jitter,
        r * (0.008 + 0.010 * rnd.nextDouble()),
        Paint()
          ..color =
              (i.isEven ? Colors.white : tint).withValues(alpha: 0.6 * twinkle)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.008),
      );
    }
  }

  // ----------------------------------------------------- alternative skins

  /// MINIMAL: a thin ring and a breathing core light. Nothing else.
  void _minimalContent(
      Canvas canvas, Offset c, double r, double flow, double energy) {
    final pulse = 0.16 + 0.05 * math.sin(flow * 2) + 0.20 * level;
    canvas.drawCircle(
      c,
      r * pulse,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.9 * energy + 0.1),
          style.bloomA.withValues(alpha: 0.5),
          Colors.transparent,
        ], stops: const [0, 0.4, 1])
            .createShader(Rect.fromCircle(center: c, radius: r * pulse))
        ..blendMode = BlendMode.plus,
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.012
        ..color = style.bloomA.withValues(alpha: 0.35 + 0.25 * energy),
    );
    // One quiet dot orbiting the inner ring.
    final a = flow * 0.8;
    canvas.drawCircle(
      c + Offset(math.cos(a), math.sin(a)) * r * 0.62,
      r * 0.02,
      Paint()..color = Colors.white.withValues(alpha: 0.8 * energy),
    );
  }

  /// HOLOGRAPHIC: rotating wireframe globe.
  void _holographicContent(
      Canvas canvas, Offset c, double r, double flow, double energy) {
    final rr = r * 0.88;
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.006
      ..blendMode = BlendMode.plus;

    // Latitude circles (static under Y-rotation).
    for (final lat in const [-0.66, -0.33, 0.0, 0.33, 0.66]) {
      final y = rr * lat;
      final radius = math.sqrt(math.max(0, rr * rr - y * y));
      wire.color = style.rim[0]
          .withValues(alpha: 0.10 + 0.20 * energy * (1 - lat.abs()));
      canvas.drawOval(
        Rect.fromCenter(
            center: c.translate(0, y), width: radius * 2, height: radius * 0.5),
        wire,
      );
    }
    // Longitude ellipses sweep as the globe rotates.
    for (var i = 0; i < 6; i++) {
      final lon = flow * 0.6 + i * math.pi / 6;
      final w = (math.cos(lon)).abs();
      final front = math.sin(lon) > 0;
      wire.color = (front ? style.rim[0] : style.rim[1])
          .withValues(alpha: (front ? 0.30 : 0.12) * (0.5 + energy));
      canvas.drawOval(
        Rect.fromCenter(center: c, width: 2 * rr * w, height: 2 * rr),
        wire,
      );
    }
    // Twinkling nodes.
    final pts = _sphereCache ??= _fibonacciSphere(48);
    final cosA = math.cos(flow * 0.6);
    final sinA = math.sin(flow * 0.6);
    for (var i = 0; i < pts.length; i += 3) {
      final p = pts[i];
      final xr = p.x * cosA + p.z * sinA;
      final zr = -p.x * sinA + p.z * cosA;
      final depth = (zr + 1) / 2;
      final twinkle = 0.5 + 0.5 * math.sin(flow * 3 + i).abs();
      canvas.drawCircle(
        c.translate(xr * rr, p.y * rr),
        r * 0.012 * (0.5 + depth),
        Paint()
          ..color = style.core
              .withValues(alpha: (0.15 + 0.55 * depth) * twinkle * energy),
      );
    }
  }

  // ------------------------------------------------------- state contents

  void _errorContent(Canvas canvas, Offset c, double r, double flow) {
    final pulse = 0.75 + 0.25 * math.sin(flow * 6);
    canvas.drawCircle(
      c,
      r * 0.85,
      Paint()
        ..shader = RadialGradient(colors: [
          _errRed.withValues(alpha: 0.45 * pulse),
          _errRed.withValues(alpha: 0.10),
          Colors.transparent,
        ], stops: const [0, 0.6, 1])
            .createShader(Rect.fromCircle(center: c, radius: r * 0.85))
        ..blendMode = BlendMode.plus,
    );
    canvas.drawCircle(
      c,
      r * 0.55,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.025
        ..color = _errRed.withValues(alpha: 0.5 + 0.4 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.02),
    );
    _glyph(canvas, c, Icons.priority_high_rounded, r * 0.62,
        Colors.white.withValues(alpha: 0.85 + 0.15 * pulse));
  }

  void _offlineContent(Canvas canvas, Offset c, double r, double flow) {
    canvas.drawCircle(
      c,
      r * 0.8,
      Paint()
        ..shader = RadialGradient(colors: [
          _dim.withValues(alpha: 0.12),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r * 0.8)),
    );
    final drift = math.sin(flow) * r * 0.02;
    _glyph(canvas, c.translate(drift, 0), Icons.cloud_off_rounded, r * 0.55,
        _dim.withValues(alpha: 0.75));
  }

  void _completeContent(
      Canvas canvas, Offset c, double r, double flow, double opacity) {
    // Check pops in with the cross-fade.
    final pop = Curves.elasticOut.transform(opacity.clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      r * 0.85,
      Paint()
        ..shader = RadialGradient(colors: [
          _teal.withValues(alpha: 0.30),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r * 0.85))
        ..blendMode = BlendMode.plus,
    );
    canvas.drawCircle(
      c,
      r * 0.58 * pop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03
        ..color = _teal.withValues(alpha: 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.012),
    );
    _glyph(canvas, c, Icons.check_rounded, r * 0.62 * pop, _teal);
    // A few celebratory sparks flying outward as it lands.
    final rnd = math.Random(7);
    for (var i = 0; i < 8; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final d = r * (0.55 + 0.35 * pop) * (0.8 + 0.3 * rnd.nextDouble());
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * d,
        r * 0.015,
        Paint()
          ..color = (i.isEven ? _teal : Colors.white)
              .withValues(alpha: (1 - pop * 0.7) * 0.8),
      );
    }
  }

  void _sleepContent(Canvas canvas, Offset c, double r, double flow) {
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..shader = RadialGradient(colors: [
          style.bloomA.withValues(alpha: 0.10),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r * 0.5)),
    );
    for (var i = 0; i < 2; i++) {
      final phase = ((flow / (2 * math.pi)) * 0.5 + i * 0.5) % 1.0;
      final pos = c.translate(r * (0.30 + i * 0.14), -r * (0.15 + phase * 0.4));
      _glyphText(canvas, pos, 'z', r * (0.20 - i * 0.05),
          _dim.withValues(alpha: (1 - phase) * 0.7));
    }
  }

  // ---------------------------------------------------------- base layers

  void _bloom(Canvas canvas, Offset c, double r, double flow, double energy) {
    final pulse = 1 + 0.10 * math.sin(flow * 2) + 0.25 * level;
    final a = mood == OrbMood.error ? _errRed : style.bloomA;
    final b = mood == OrbMood.error ? _errRed : style.bloomB;
    canvas.drawCircle(
      c,
      r * 1.75 * pulse,
      Paint()
        ..shader = RadialGradient(colors: [
          a.withValues(alpha: 0.20 + 0.22 * energy),
          b.withValues(alpha: 0.08),
          Colors.transparent,
        ], stops: const [0, 0.55, 1])
            .createShader(Rect.fromCircle(center: c, radius: r * 1.75 * pulse))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
  }

  void _glassBody(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: const [
            Color(0xFF1E2540),
            Color(0xFF0A0E1B),
            Color(0xFF05070D)
          ],
          stops: const [0, 0.62, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          center: const Alignment(0.15, 0.75),
          radius: 1.0,
          colors: [style.bloomA.withValues(alpha: 0.14), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _constellation(Canvas canvas, Offset c, double r, double flow) {
    final pts = _sphereCache ??= _fibonacciSphere(48);
    final cosA = math.cos(flow);
    final sinA = math.sin(flow);
    final rr = r * 0.86;

    canvas.drawCircle(
      c,
      r * 0.9,
      Paint()
        ..shader = RadialGradient(colors: [
          style.bloomA.withValues(alpha: 0.24),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r * 0.9)),
    );

    final projected = <Offset>[];
    final depths = <double>[];
    for (final p in pts) {
      final xr = p.x * cosA + p.z * sinA;
      final zr = -p.x * sinA + p.z * cosA;
      projected.add(c.translate(xr * rr, p.y * rr));
      depths.add((zr + 1) / 2);
    }

    final linkPaint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        final dx = pts[i].x - pts[j].x;
        final dy = pts[i].y - pts[j].y;
        final dz = pts[i].z - pts[j].z;
        final d = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (d > 0.62) continue;
        final depth = (depths[i] + depths[j]) / 2;
        final alpha = (1 - d / 0.62) * depth * 0.5;
        if (alpha < 0.02) continue;
        linkPaint
          ..strokeWidth = r * 0.006
          ..color = Color.lerp(style.rim[0], style.bloomA, (i * 7 % 10) / 10)!
              .withValues(alpha: alpha);
        canvas.drawLine(projected[i], projected[j], linkPaint);
      }
    }

    for (var i = 0; i < pts.length; i++) {
      final depth = depths[i];
      final twinkle = 0.5 + 0.5 * math.sin(flow * 3 + i * 1.7).abs();
      canvas.drawCircle(
        projected[i],
        r * (0.012 + 0.022 * depth),
        Paint()
          ..color = Color.lerp(style.bloomA, style.rim[0], (i * 3 % 10) / 10)!
              .withValues(alpha: (0.25 + 0.6 * depth) * twinkle)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.01),
      );
    }
  }

  void _ripples(
      Canvas canvas, Offset c, double r, double opacity, Color color) {
    for (var i = 0; i < 3; i++) {
      final phase = (raw * 3 + i / 3) % 1;
      canvas.drawCircle(
        c,
        r * (1 + phase * 0.55),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.018
          ..color = color.withValues(alpha: (1 - phase) * 0.32 * opacity),
      );
    }
  }

  void _rim(Canvas canvas, Offset c, double r, double flow, double energy) {
    final colors = switch (mood) {
      OrbMood.error => [_errRed, _errRed.withValues(alpha: 0.2), _errRed],
      OrbMood.offline || OrbMood.sleep => [
          _dim.withValues(alpha: 0.4),
          _dim.withValues(alpha: 0.1),
          _dim.withValues(alpha: 0.4)
        ],
      OrbMood.complete => [_teal, _teal.withValues(alpha: 0.2), _teal],
      _ => [
          style.rim[0].withValues(alpha: 0.55 * energy + 0.15),
          style.rim[1].withValues(alpha: 0.10),
          style.rim[2].withValues(alpha: 0.45 * energy + 0.10),
          style.rim[3].withValues(alpha: 0.25),
          style.rim[0].withValues(alpha: 0.55 * energy + 0.15),
        ],
    };
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.02
        ..blendMode = BlendMode.plus
        ..shader = SweepGradient(
          transform: GradientRotation(flow),
          colors: colors,
        ).createShader(Rect.fromCircle(center: c, radius: r))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.015),
    );
  }

  void _orbitingSparks(
      Canvas canvas, Offset c, double r, double flow, double energy) {
    final palette = [style.rim[0], style.rim[2], style.bloomA];
    for (var i = 0; i < 3; i++) {
      final angle = flow * (i.isEven ? 1 : -0.7) + i * 2.1;
      final orbit = r * (1.04 + 0.03 * i);
      final pos = c + Offset(math.cos(angle), math.sin(angle)) * orbit;
      final color = palette[i];

      final tail = Path();
      const steps = 10;
      for (var s = 0; s <= steps; s++) {
        final a = angle - (i.isEven ? 1 : -1) * s * 0.035;
        final p = c + Offset(math.cos(a), math.sin(a)) * orbit;
        s == 0 ? tail.moveTo(p.dx, p.dy) : tail.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        tail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.012
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [
            color.withValues(alpha: 0.5 * energy),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: pos, radius: r * 0.35)),
      );
      canvas.drawCircle(
        pos,
        r * 0.018,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85 * energy)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.008),
      );
      canvas.drawCircle(
        pos,
        r * 0.035,
        Paint()
          ..color = color.withValues(alpha: 0.35 * energy)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.02),
      );
    }
  }

  void _specular(Canvas canvas, Offset c, double r) {
    final hi = c.translate(-r * 0.32, -r * 0.40);
    canvas.drawCircle(
      hi,
      r * 0.46,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.15),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: hi, radius: r * 0.46)),
    );
  }

  // ---------------------------------------------------------------- glyphs

  void _glyph(
      Canvas canvas, Offset c, IconData icon, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _glyphText(
      Canvas canvas, Offset c, String char, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: char,
        style: TextStyle(
            fontSize: size, fontWeight: FontWeight.w600, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.raw != raw ||
      old.level != level ||
      old.mood != mood ||
      old.moodMix != moodMix ||
      old.skin != skin;
}
