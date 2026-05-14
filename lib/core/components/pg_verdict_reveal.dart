import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_score_chip.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Scan-verdict reveal card — the highest-emotion moment in the app.
///
/// Replaces the legacy full-screen color slam (a 70%-opacity tint with a
/// centered icon). The v2 reveal is a severity-tinted glass card that
/// scales up from below, holds briefly, then fades out so the caller can
/// navigate to product detail.
///
/// **Severity-driven motion:**
/// - SAFE: emphasized curve with slight overshoot (1.0 → 1.05 → 1.0) —
///   feels like a brief celebration, but restrained.
/// - All other tiers: decelerate curve, no overshoot — calmer, clinical.
///   Caution/avoid/contraindicated should land softly, not bounce.
///
/// **Performance:** one BackdropFilter (the card's glass blur) inside a
/// RepaintBoundary so the camera feed beneath doesn't re-rasterize.
/// Never animate the blur radius — that triggers a full-layer repaint.
///
/// Haptics are NOT fired here; the caller is expected to invoke
/// `PGHaptics.forVerdict()` at the same time it pushes this widget.
/// Decoupling keeps the visual reveal and the tactile reveal coordinated
/// at the orchestration layer.
class PGVerdictReveal extends StatefulWidget {
  /// Severity tier driving the card color, badge, and entrance curve.
  final PGSeverity severity;

  /// Optional override for the severity badge's display label.
  /// Defaults to the severity's canonical name (e.g. "Safe", "Caution").
  final String? severityLabel;

  /// Newsreader serif verdict line (e.g. "Worth a look.",
  /// "Worth a conversation with your doctor.").
  final String verdictLine;

  /// Optional product name shown beneath the verdict in Geist Sans.
  final String? productName;

  /// Optional brand label (mono caps eyebrow).
  final String? brand;

  /// PG Score for the product. When null, no chip renders.
  final double? score;

  /// Mono caps evidence overline (e.g. "ESTABLISHED").
  final String? evidence;

  /// How long the card stays visible before auto-fading.
  final Duration hold;

  /// Called once the card has finished its fade-out exit.
  final VoidCallback? onComplete;

  const PGVerdictReveal({
    super.key,
    required this.severity,
    required this.verdictLine,
    this.severityLabel,
    this.productName,
    this.brand,
    this.score,
    this.evidence,
    this.hold = const Duration(milliseconds: 1100),
    this.onComplete,
  });

  @override
  State<PGVerdictReveal> createState() => _PGVerdictRevealState();
}

class _PGVerdictRevealState extends State<PGVerdictReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _entrance;
  late final Animation<double> _opacity;

  bool _isCelebration() => widget.severity == PGSeverity.safe;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: V2Motion.slow,
    );
    _entrance = CurvedAnimation(
      parent: _ctrl,
      curve: _isCelebration() ? V2Motion.emphasized : V2Motion.decelerate,
    );
    _opacity = CurvedAnimation(
      parent: _ctrl,
      curve: V2Motion.smooth,
    );

    Future<void>.microtask(() async {
      if (!mounted) return;
      await _ctrl.forward();
      if (!mounted) return;
      await Future<void>.delayed(widget.hold);
      if (!mounted) return;
      await _ctrl.reverse();
      if (!mounted) return;
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Compute the scale for the entrance.
  /// Safe verdict slightly overshoots (1.0 → 1.05 → 1.0) for celebration.
  /// All other tiers ease in monotonically to 1.0.
  double _scale() {
    final t = _entrance.value;
    if (!_isCelebration()) {
      return 0.94 + 0.06 * t;
    }
    // Slight overshoot — peak at 1.05 mid-way, settle at 1.0.
    if (t < 0.6) {
      return 0.94 + (1.05 - 0.94) * (t / 0.6);
    }
    return 1.05 - (1.05 - 1.0) * ((t - 0.6) / 0.4);
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.severity.tint;
    final accent = widget.severity.color;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: _opacity.value,
          child: RepaintBoundary(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space24,
                ),
                child: Transform.scale(
                  scale: _scale(),
                  child: _VerdictCard(
                    tint: tint,
                    accent: accent,
                    severity: widget.severity,
                    severityLabel: widget.severityLabel,
                    verdictLine: widget.verdictLine,
                    productName: widget.productName,
                    brand: widget.brand,
                    score: widget.score,
                    evidence: widget.evidence,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final Color tint;
  final Color accent;
  final PGSeverity severity;
  final String? severityLabel;
  final String verdictLine;
  final String? productName;
  final String? brand;
  final double? score;
  final String? evidence;

  const _VerdictCard({
    required this.tint,
    required this.accent,
    required this.severity,
    required this.severityLabel,
    required this.verdictLine,
    required this.productName,
    required this.brand,
    required this.score,
    required this.evidence,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
      child: BackdropFilter(
        // Single blur layer per viewport — per the v2 perf contract.
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(V2Spacing.space24),
          decoration: BoxDecoration(
            // Tinted glass: surface @ 92% layered with severity tint so
            // colored severities tint the card; safe stays warm cream.
            color: V2Colors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: V2Shadows.lg,
            gradient: LinearGradient(
              colors: [tint, tint.withValues(alpha: 0.55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PGSeverityBadge(
                      severity: severity,
                      label: severityLabel,
                      evidence: evidence,
                    ),
                  ),
                  if (score != null) ...[
                    const SizedBox(width: V2Spacing.space16),
                    PGScoreChip(score: score!, showCaption: false),
                  ],
                ],
              ),
              const SizedBox(height: V2Spacing.space16),
              Text(
                verdictLine,
                style: V2Typography.displayXs(color: V2Colors.fg),
                textAlign: TextAlign.left,
              ),
              if (productName != null) ...[
                const SizedBox(height: V2Spacing.space12),
                if (brand != null) ...[
                  PGEyebrow(brand!, color: V2Colors.fgMuted),
                  const SizedBox(height: V2Spacing.space4),
                ],
                Text(
                  productName!,
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Opening details…',
                style: V2Typography.caption(color: V2Colors.fgMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
