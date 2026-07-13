import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/mila_theme.dart';

/// Frosted glass card per the style guide (background blur + subtle border).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.onTap,
    this.borderColor,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? MilaColors.cardBorder),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}

/// Primary gradient pill button.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
    this.height = 52,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final button = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: MilaColors.primaryGradient,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [
            BoxShadow(
              color: MilaColors.violet.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(height / 2),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 19, color: Colors.white),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Secondary (outlined) pill button.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
    this.height = 52,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final double height;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? MilaColors.danger : Colors.white;
    final button = SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(height / 2)),
          textStyle: Theme.of(context).textTheme.titleSmall,
        ),
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: Text(label),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Small rounded chip; [active] renders the gradient state.
class MilaChip extends StatelessWidget {
  const MilaChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? MilaColors.primaryGradient : null,
          color: active ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? Colors.transparent : MilaColors.cardBorder),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: active ? Colors.white : MilaColors.textSecondary),
        ),
      ),
    );
  }
}

/// Rounded icon container with gradient tint, used in list tiles.
class TileIcon extends StatelessWidget {
  const TileIcon({super.key, required this.icon, this.color, this.size = 40});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MilaColors.violet;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, size: size * 0.5, color: c),
    );
  }
}

/// Ambient page background: deep navy with soft radial glows.
class MilaBackground extends StatelessWidget {
  const MilaBackground({super.key, required this.child, this.glowTop = true});

  final Widget child;
  final bool glowTop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: MilaColors.background),
      child: Stack(
        children: [
          if (glowTop)
            Positioned(
              top: -140,
              left: -60,
              right: -60,
              child: IgnorePointer(
                child: Container(
                  height: 380,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      MilaColors.violet.withValues(alpha: 0.16),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Animated waveform used on the listening screen. Driven by [level] 0..1.
class Waveform extends StatefulWidget {
  const Waveform({super.key, this.level = 0.4, this.height = 90});

  final double level;
  final double height;

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _WaveformPainter(
            t: _controller.value, level: widget.level.clamp(0.05, 1.0)),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.t, required this.level});

  final double t;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 48;
    final barWidth = size.width / (bars * 1.8);
    final rnd = math.Random(7);
    final gradient = const LinearGradient(colors: [
      MilaColors.cyan,
      MilaColors.violet,
      MilaColors.purple,
      MilaColors.pink,
    ]).createShader(Offset.zero & size);
    final paint = Paint()
      ..shader = gradient
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < bars; i++) {
      final x = (i + 0.5) * size.width / bars;
      final seed = rnd.nextDouble();
      final envelope =
          math.sin((i / bars) * math.pi); // taller in the center
      final wobble =
          0.5 + 0.5 * math.sin(t * 2 * math.pi * (1 + seed) + i * 0.7);
      final h = size.height *
          0.9 *
          envelope *
          (0.15 + 0.85 * level * (0.35 + 0.65 * wobble));
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.level != level;
}

/// Section header row with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              action!,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: MilaColors.cyan),
            ),
          ),
      ],
    );
  }
}
