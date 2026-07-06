import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';

/// Visual hierarchy for [EvidenceLevel] — uses signal bars (like cell
/// reception) so the trust level reads instantly, even for users who don't
/// know the difference between "established" and "probable."
///
/// - 3 bars = Strong evidence (RCT / meta-analysis)
/// - 2 bars = Good evidence (observational)
/// - 1 bar  = Theoretical (mechanism-only)
/// - 0 bars = Evidence not graded
class PGEvidenceBadge extends StatelessWidget {
  final EvidenceLevel level;

  const PGEvidenceBadge({super.key, required this.level});

  ({Color color, String label, int bars}) _style() {
    switch (level) {
      case EvidenceLevel.established:
        return (color: V2Colors.accent, label: 'Strong evidence', bars: 3);
      case EvidenceLevel.probable:
        return (color: V2Colors.monitor, label: 'Good evidence', bars: 2);
      case EvidenceLevel.moderate:
        return (color: V2Colors.monitor, label: 'Moderate evidence', bars: 2);
      case EvidenceLevel.limited:
        return (color: V2Colors.fgSubtle, label: 'Limited evidence', bars: 1);
      case EvidenceLevel.theoretical:
        return (color: V2Colors.fgSubtle, label: 'Theoretical', bars: 1);
      case EvidenceLevel.noData:
        return (color: V2Colors.fgMuted, label: 'No evidence data', bars: 0);
      case EvidenceLevel.ungraded:
        return (color: V2Colors.fgMuted, label: 'Evidence not graded', bars: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CustomPaint(
              painter: _SignalBarsPainter(
                activeBars: s.bars,
                color: s.color,
                trackColor: s.color.withValues(alpha: 0.22),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            s.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  final int activeBars;
  final Color color;
  final Color trackColor;

  _SignalBarsPainter({
    required this.activeBars,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 3;
    const barWidth = 2.5;
    const gap = 1.5;
    const totalWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = (size.width - totalWidth) / 2;

    for (var i = 0; i < barCount; i++) {
      final height = 4.0 + i * 2.5;
      final x = startX + i * (barWidth + gap);
      final y = size.height - height;
      final rect = RRect.fromLTRBR(
        x,
        y,
        x + barWidth,
        size.height,
        const Radius.circular(1),
      );
      final paint = Paint()
        ..color = i < activeBars ? color : trackColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_SignalBarsPainter old) =>
      old.activeBars != activeBars ||
      old.color != color ||
      old.trackColor != trackColor;
}
