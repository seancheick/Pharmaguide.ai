import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Animated circular score ring — replaces the flat `Container + Text` score
/// circles used in product lists and detail pages.
///
/// - Tabular figures on the number (no reflow as score animates)
/// - Sweep-gradient progress arc
/// - Dashed track + "–" for `score == null` (insufficient data state)
/// - Animates from 0 → score on mount, and between values on update
///
/// ```dart
/// PGScoreRing(score: 87, size: 72, label: 'score')
/// PGScoreRing(score: null, size: 72, label: 'no data')
/// ```
class PGScoreRing extends StatefulWidget {
  final double? score; // 0..100, null = insufficient data
  final double size;
  final double strokeWidth;
  final String? label;

  const PGScoreRing({
    super.key,
    required this.score,
    this.size = 72,
    this.strokeWidth = 5,
    this.label,
  });

  @override
  State<PGScoreRing> createState() => _PGScoreRingState();
}

class _PGScoreRingState extends State<PGScoreRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  bool _reduceMotionChecked = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    // initState can't read MediaQuery; didChangeDependencies handles that.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionChecked) return;
    _reduceMotionChecked = true;
    // Respect Accessibility → Reduce Motion. When animations are disabled
    // we jump to the final value immediately — the ring still renders,
    // it just doesn't sweep.
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      _ctrl.value = 1.0;
    } else {
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant PGScoreRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnimations) {
        _ctrl.value = 1.0;
      } else {
        _ctrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Human-readable label for VoiceOver / TalkBack.
  String _semanticLabel(double? score) {
    if (score == null) {
      return 'Score unavailable. Not enough data to rate this product.';
    }
    final rounded = score.round();
    String tier;
    if (score >= 85) {
      tier = 'exceptional';
    } else if (score >= 70) {
      tier = 'excellent';
    } else if (score >= 55) {
      tier = 'good';
    } else if (score >= 40) {
      tier = 'fair';
    } else if (score >= 25) {
      tier = 'below average';
    } else {
      tier = 'poor';
    }
    return '$rounded out of 100, $tier score';
  }

  Color _colorFor(double? s) {
    if (s == null) return AppTheme.insufficientData;
    if (s >= 85) return AppTheme.scoreExceptional;
    if (s >= 70) return AppTheme.scoreExcellent;
    if (s >= 55) return AppTheme.scoreGood;
    if (s >= 40) return AppTheme.scoreFair;
    if (s >= 25) return AppTheme.scoreBelowAvg;
    return AppTheme.scoreLow;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasScore = widget.score != null;
    final targetFraction = hasScore
        ? (widget.score!.clamp(0.0, 100.0) / 100.0)
        : 0.0;
    final color = _colorFor(widget.score);

    return Semantics(
      label: _semanticLabel(widget.score),
      value: hasScore ? widget.score!.round().toString() : '—',
      container: true,
      // The inner painted text is decorative; the Semantics wrapper owns
      // the readable label.
      child: ExcludeSemantics(
        child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final progress = targetFraction * _anim.value;
          final displayNumber = hasScore
              ? (widget.score! * _anim.value).round().toString()
              : '–';

          return CustomPaint(
            painter: _RingPainter(
              progress: progress,
              color: color,
              trackColor: scheme.surfaceContainerHigh,
              stroke: widget.strokeWidth,
              dashed: !hasScore,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayNumber,
                    style: AppTheme.numeric(
                      TextStyle(
                        fontFamily: 'Inter',
                        fontSize: widget.size * 0.34,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: -0.6,
                        height: 1.0,
                      ),
                    ),
                  ),
                  if (widget.label != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        widget.label!.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: (widget.size * 0.13).clamp(9.0, 12.0),
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color trackColor;
  final double stroke;
  final bool dashed;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.stroke,
    required this.dashed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (dashed) {
      _drawDashedCircle(canvas, rect);
      return;
    }

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    // Progress arc
    if (progress > 0) {
      final sweep = math.pi * 2 * progress;
      const start = -math.pi / 2;
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [color.withValues(alpha: 0.75), color],
          tileMode: TileMode.clamp,
          transform: const GradientRotation(start),
        ).createShader(rect)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawArc(rect, start, sweep, false, progressPaint);
    }
  }

  void _drawDashedCircle(Canvas canvas, Rect rect) {
    const dash = 0.22;
    const gap = 0.14;
    double angle = 0;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    while (angle < math.pi * 2) {
      canvas.drawArc(rect, angle, dash, false, paint);
      angle += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.stroke != stroke ||
      old.dashed != dashed;
}
