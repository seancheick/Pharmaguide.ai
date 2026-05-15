import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';

/// Tier driving the verdict reveal's color, icon, copy, motion, and
/// haptic. Maps 1:1 to the severity vocabulary used elsewhere — caller
/// adapts production's verdict result to this.
enum PGVerdictKind { safe, monitor, caution, avoid, contraindicated }

/// v2 enhancement of `scanner_screen.dart`'s `_showFlash` overlay.
///
/// Renders a brief severity-tinted "we got it" flash:
/// - Solid tinted overlay (no text content) — just the icon
/// - White radial halo behind the icon (static gradient, no blur)
/// - Entrance motion that celebrates safe verdicts (scale spring 1.0
///   → 1.08 → 1.0) and decelerates caution+ ones (no scale, calm
///   fade-up)
/// - Layered haptic: light tap for safe, medium for caution, heavy
///   triple-pulse for contraindicated
///
/// Sean 2026-05-15: no verbose label or subline — the rest of the
/// info (product name, score, interactions) lives on the product
/// detail page that opens immediately after. This is the "found it"
/// moment, nothing more.
///
/// Stays on screen until tapped or [autoDismissAfter] elapses (default
/// 900ms). Host screen layers above the camera via Stack.
class PGVerdictReveal extends StatefulWidget {
  final PGVerdictKind kind;

  /// Auto-dismiss delay. Null keeps it on-screen until manually
  /// dismissed.
  final Duration? autoDismissAfter;
  final VoidCallback? onDismiss;

  const PGVerdictReveal({
    super.key,
    required this.kind,
    this.autoDismissAfter = const Duration(milliseconds: 900),
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
              // Icon-only "found it" flash. No label, no subline —
              // product info lives on the detail page that opens
              // right after dismiss.
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
                          Icon(_icon, color: Colors.white, size: 120),
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
