import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Static score ring — center value + optional caption + colored arc.
///
/// **Design decision (Phase 1):** no entrance animation. The score is a
/// clinical reading; sweeping arcs read as "fitness app" rather than
/// "clinical report." If a celebratory reveal is wanted on scan-complete,
/// wrap this in a parent `FadeTransition` at the surface that owns the
/// emotional moment — don't bake animation into the score primitive
/// itself.
///
/// Wrapped in `RepaintBoundary` so when it lives next to animated content
/// (e.g. shimmer placeholders) it doesn't repaint with them.
///
/// Score range: 0–100. Color tracks the v2 severity tier bands.
class PGScoreRing extends StatelessWidget {
  /// Score value 0–100.
  final double score;

  /// Outer diameter in logical pixels.
  final double size;

  /// Ring stroke width.
  final double stroke;

  /// Optional caption rendered below the score number (e.g. "PG SCORE").
  final String? caption;

  const PGScoreRing({
    super.key,
    required this.score,
    this.size = 88,
    this.stroke = 4,
    this.caption,
  });

  Color _bandColor(double s) {
    if (s >= 80) return V2Colors.safe;
    if (s >= 60) return V2Colors.monitor;
    if (s >= 40) return V2Colors.caution;
    return V2Colors.avoid;
  }

  @override
  Widget build(BuildContext context) {
    final color = _bandColor(score);
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ScoreRingPainter(
            progress: (score / 100).clamp(0.0, 1.0),
            stroke: stroke,
            color: color,
            track: V2Colors.outline,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score.round().toString(),
                  style: V2Typography.title(color: V2Colors.fg).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: V2Spacing.space4),
                  Text(
                    caption!.toUpperCase(),
                    style: V2Typography.overline(color: V2Colors.fgMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  final Color color;
  final Color track;

  const _ScoreRingPainter({
    required this.progress,
    required this.stroke,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.stroke != stroke ||
      old.track != track;
}
