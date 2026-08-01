import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Brief, earned celebration surface. Use ONCE per emotional moment:
/// onboarding completion, scan-complete safe verdict, first stack save.
///
/// Visual: a centered serif headline with a soft accent halo, fading
/// in from below and lifting into place. Subtle — never confetti, never
/// bouncy. Per the v2 plan, celebrations live in the "delight allowed"
/// bucket but must remain calm.
///
/// The celebration calls [onComplete] after [hold] elapses. Default flow:
///   - 100ms initial settle
///   - 640ms hero entrance (fade + slight lift)
///   - [hold] visible
///   - 280ms exit fade
///   - [onComplete] fires
class PGCelebration extends StatefulWidget {
  /// Serif headline — short, intentional. e.g. "You're set."
  final String headline;

  /// Optional subline beneath the headline (Geist Sans body).
  final String? subline;

  /// Optional eyebrow above the headline (mono caps).
  final String? eyebrow;

  /// How long the celebration stays fully visible before fading.
  final Duration hold;

  /// Called once the celebration finishes its exit.
  final VoidCallback? onComplete;

  const PGCelebration({
    super.key,
    required this.headline,
    this.subline,
    this.eyebrow,
    this.hold = const Duration(milliseconds: 900),
    this.onComplete,
  });

  @override
  State<PGCelebration> createState() => _PGCelebrationState();
}

class _PGCelebrationState extends State<PGCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _lift;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: V2Motion.slower);
    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: V2Motion.emphasized));
    _lift = Tween<double>(
      begin: 16,
      end: 0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: V2Motion.emphasized));

    Future<void>.delayed(V2Motion.instant, () async {
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _lift.value),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Soft halo — radial accent at very low opacity.
                IgnorePointer(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          context.v2.accent.withValues(alpha: 0.10),
                          context.v2.accent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.eyebrow != null) ...[
                      PGEyebrow(widget.eyebrow!, color: context.v2.accent),
                      const SizedBox(height: V2Spacing.space12),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: V2Spacing.space24,
                      ),
                      child: Text(
                        widget.headline,
                        style: V2Typography.displayXs(color: context.v2.fg),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (widget.subline != null) ...[
                      const SizedBox(height: V2Spacing.space12),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: V2Spacing.space32,
                        ),
                        child: Text(
                          widget.subline!,
                          style: V2Typography.body(color: context.v2.fgMuted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
