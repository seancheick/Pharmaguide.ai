import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Two-state scan-confirmation flash. Sean 2026-05-15: no per-tier
/// judgement at scan time — the product page is where verdict
/// nuance happens. The flash is purely "we recognized this."
///
/// Green: recognized with a positive product verdict — no major concern at a
/// glance. Spring scale celebration.
///
/// Amber: caution / avoid / contraindicated — product matched, worth
/// reviewing. Calm fade-up, decelerate curve.
enum PGVerdictKind { success, attention }

/// Brief severity-tinted icon flash that signals "scan succeeded."
///
/// Renders a tinted overlay with a single white check/warning icon.
/// No label, no subline — product info lives on the detail page that
/// opens immediately after this dismisses (~900ms).
///
/// Motion: spring scale 1.0 → 1.08 → 1.0 for [success] (celebration),
/// decelerate fade-up for [attention] (calm).
///
/// Haptics: light tap for success, medium tap for attention.
class PGVerdictReveal extends StatefulWidget {
  final PGVerdictKind kind;

  /// Auto-dismiss delay. Null keeps it on-screen until manually
  /// dismissed.
  final Duration? autoDismissAfter;
  final VoidCallback? onDismiss;

  /// When false, skip the built-in haptic so the caller can fire a
  /// richer severity-gated pattern (e.g. [PGHaptics.forVerdict]).
  final bool playHaptic;

  /// Optional one-line caption under the icon (e.g. product name on
  /// scan confirm). Null hides the line.
  final String? caption;

  const PGVerdictReveal({
    super.key,
    required this.kind,
    this.autoDismissAfter = const Duration(milliseconds: 900),
    this.onDismiss,
    this.playHaptic = true,
    this.caption,
  });

  @override
  State<PGVerdictReveal> createState() => _PGVerdictRevealState();
}

class _PGVerdictRevealState extends State<PGVerdictReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // One-shot dismissal guard. The auto-dismiss timer AND the tap
  // gesture(s) both invoke onDismiss; without this, a tap that overlaps
  // the ~900ms timer fires the caller's completion twice. On the scanner
  // that re-armed detection mid-navigation (`_hasScanned` reset while the
  // first `context.push` was still pending). Guarantee onDismiss runs at
  // most once per reveal instance — fixing every caller at the source.
  bool _dismissed = false;

  void _handleDismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDismiss?.call();
  }

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
        if (mounted) _handleDismiss();
      });
    }
  }

  void _fireHaptic() {
    if (!widget.playHaptic) return;
    switch (widget.kind) {
      case PGVerdictKind.success:
        HapticFeedback.lightImpact();
      case PGVerdictKind.attention:
        HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _tone => switch (widget.kind) {
    PGVerdictKind.success => context.v2.safe,
    PGVerdictKind.attention => context.v2.caution,
  };

  IconData get _icon => switch (widget.kind) {
    PGVerdictKind.success => Icons.check_circle_rounded,
    PGVerdictKind.attention => Icons.warning_amber_rounded,
  };

  bool get _isCelebration => widget.kind == PGVerdictKind.success;

  String get _semanticsLabel {
    final caption = widget.caption?.trim();
    final status = widget.kind == PGVerdictKind.attention
        ? 'Product found. Review product details.'
        : 'Product found.';
    return caption == null || caption.isEmpty ? status : '$status $caption';
  }

  @override
  Widget build(BuildContext context) {
    final canDismiss = widget.onDismiss != null;
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: _semanticsLabel,
      button: canDismiss,
      onTap: canDismiss ? _handleDismiss : null,
      child: GestureDetector(
        onTap: canDismiss ? _handleDismiss : null,
        excludeFromSemantics: true,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final curve = _isCelebration
                ? V2Motion.spring
                : V2Motion.decelerate;
            // **Sentry fix — 58× AssertionError 'opacity >= 0.0 && opacity
            // <= 1.0'.** V2Motion.spring is `Cubic(0.34, 1.56, 0.64, 1)` —
            // the 1.56 control point produces a brief overshoot above 1.0
            // for celebration verdicts, which Opacity rejects. Clamp the
            // eased value before any Opacity consumer reads it. Scale +
            // lift consumers don't have a bounds constraint, so they use
            // the unclamped easedRaw (the spring overshoot adds the
            // pleasant pop on the icon).
            final easedRaw = curve.transform(t);
            final eased = easedRaw.clamp(0.0, 1.0);
            final tClamped = t.clamp(0.0, 1.0);
            final scale = _isCelebration
                ? 0.92 + (easedRaw * 0.16)
                : 0.96 + (easedRaw * 0.04);
            final lift = (1 - easedRaw) * 14;

            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: tClamped,
                  child: ColoredBox(color: _tone.withValues(alpha: 0.92)),
                ),
                // Radial white halo behind the icon for the "moment of
                // truth" glow. Static gradient — no BackdropFilter.
                Opacity(
                  opacity: tClamped,
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
                            if (widget.caption != null &&
                                widget.caption!.trim().isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                ),
                                child: Text(
                                  widget.caption!.trim(),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      V2Typography.bodyXl(
                                        color: Colors.white,
                                      ).copyWith(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                        height: 1.25,
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
      ),
    );
  }
}
