import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Tier driving the verdict reveal's color, icon, copy, motion, and
/// haptic. Maps 1:1 to the severity vocabulary used elsewhere — caller
/// adapts production's verdict result to this.
enum PGVerdictKind { safe, monitor, caution, avoid, contraindicated }

/// v2 enhancement of `scanner_screen.dart`'s `_showFlash` overlay.
///
/// Renders a severity-tinted full-screen overlay with:
/// - Blurless solid tinted bg + radial accent halo behind the icon
///   (one blur surface per viewport rule preserved — the halo is a
///   static gradient, not a backdrop filter)
/// - Large icon at the visual center
/// - Verdict label + optional subline
/// - Entrance motion that celebrates safe verdicts (scale spring 1.0
///   → 1.08 → 1.0) and decelerates caution+ ones (no scale, calm
///   fade-up). Sean's plan: "Caution+ verdicts deceleration, not
///   celebration."
/// - Layered haptic: light tap for safe, medium for caution, heavy
///   triple-pulse for avoid/contraindicated
///
/// Stays on screen until tapped or [onDismiss] elapses (default
/// 1400ms). The host screen layers this above the camera feed via a
/// Stack + IgnorePointer/AnimatedOpacity pattern.
class PGVerdictReveal extends StatefulWidget {
  final PGVerdictKind kind;
  final String label;
  final String? subline;

  /// Auto-dismiss delay. Null keeps it on-screen until manually
  /// dismissed (tap or external setState).
  final Duration? autoDismissAfter;
  final VoidCallback? onDismiss;

  const PGVerdictReveal({
    super.key,
    required this.kind,
    required this.label,
    this.subline,
    this.autoDismissAfter = const Duration(milliseconds: 1400),
    this.onDismiss,
  });

  @override
  State<PGVerdictReveal> createState() => _PGVerdictRevealState();
}

class _PGVerdictRevealState extends State<PGVerdictReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: V2Motion.slow, // 420ms entrance
    )..forward();
    _fireHaptic();
    if (widget.autoDismissAfter != null) {
      Future.delayed(widget.autoDismissAfter!, () {
        if (mounted) widget.onDismiss?.call();
      });
    }
  }

  void _fireHaptic() {
    switch (widget.kind) {
      case PGVerdictKind.safe:
        HapticFeedback.lightImpact();
      case PGVerdictKind.monitor:
        HapticFeedback.lightImpact();
      case PGVerdictKind.caution:
        HapticFeedback.mediumImpact();
      case PGVerdictKind.avoid:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 120),
            HapticFeedback.heavyImpact);
      case PGVerdictKind.contraindicated:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 100),
            HapticFeedback.heavyImpact);
        Future.delayed(const Duration(milliseconds: 220),
            HapticFeedback.heavyImpact);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _tone => switch (widget.kind) {
        PGVerdictKind.safe => V2Colors.safe,
        PGVerdictKind.monitor => V2Colors.monitor,
        PGVerdictKind.caution => V2Colors.caution,
        PGVerdictKind.avoid => V2Colors.avoid,
        PGVerdictKind.contraindicated => V2Colors.contraindicated,
      };

  IconData get _icon => switch (widget.kind) {
        PGVerdictKind.safe => Icons.check_circle_rounded,
        PGVerdictKind.monitor => Icons.info_rounded,
        PGVerdictKind.caution => Icons.warning_amber_rounded,
        PGVerdictKind.avoid => Icons.error_rounded,
        PGVerdictKind.contraindicated => Icons.block_rounded,
      };

  bool get _isCelebration => widget.kind == PGVerdictKind.safe;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          // Backdrop fades in linearly. Icon block scale/translate is
          // tier-aware: celebration for safe, decelerate for caution+.
          final t = _ctrl.value;
          final curve = _isCelebration ? V2Motion.spring : V2Motion.decelerate;
          final eased = curve.transform(t);
          final scale = _isCelebration
              ? 0.92 + (eased * 0.16) // overshoots to 1.08, settles 1.0
              : 0.96 + (eased * 0.04);
          final lift = (1 - eased) * 14;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Severity-tinted base. 92% opacity so the camera shows
              // faintly through — gives the verdict a "captured" feel
              // rather than a hard cut.
              Opacity(
                opacity: t,
                child: ColoredBox(color: _tone.withValues(alpha: 0.92)),
              ),
              // Radial halo behind the icon for that "moment of truth"
              // glow. Static gradient — no BackdropFilter.
              Opacity(
                opacity: t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.05),
                      radius: 0.7,
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Icon + label block.
              Center(
                child: Opacity(
                  opacity: eased,
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform.scale(
                      scale: scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icon, color: Colors.white, size: 96),
                          const SizedBox(height: V2Spacing.space16),
                          Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: V2Typography.displayXs(color: Colors.white),
                          ),
                          if (widget.subline != null) ...[
                            const SizedBox(height: V2Spacing.space8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: V2Spacing.space32,
                              ),
                              child: Text(
                                widget.subline!,
                                textAlign: TextAlign.center,
                                style: V2Typography.body(
                                  color:
                                      Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
