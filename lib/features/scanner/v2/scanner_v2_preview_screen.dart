import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 Scanner preview — gallery-only screen that demos the new verdict
/// reveal across all 5 severity tiers without spinning up the camera.
///
/// The real `ScannerScreen` keeps its mobile_scanner pipeline; this
/// prototype renders a mock camera surface (deep dark with the v2
/// chrome) and a row of "Trigger" buttons so the user can preview each
/// reveal pattern side-by-side.
///
/// Production swap (Phase 8): the verdict overlay in `scanner_screen.dart`
/// will replace its full-screen color flash with `PGVerdictReveal`, keep
/// using `PGHaptics.forVerdict()`, and call onComplete to navigate.
class ScannerV2PreviewScreen extends StatefulWidget {
  const ScannerV2PreviewScreen({super.key});

  @override
  State<ScannerV2PreviewScreen> createState() => _ScannerV2PreviewScreenState();
}

class _ScannerV2PreviewScreenState extends State<ScannerV2PreviewScreen> {
  PGSeverity? _activeReveal;
  int _revealKey = 0;

  /// Fixtures keyed by severity tier. Mirrors the kind of payload
  /// a real scan-complete handler will pass.
  static const _fixtures = <PGSeverity, _RevealFixture>{
    PGSeverity.safe: _RevealFixture(
      verdictLine: 'No high-risk conflicts.',
      brand: 'Thorne',
      productName: 'Magnesium Glycinate',
      score: 88,
      evidence: 'ESTABLISHED',
    ),
    PGSeverity.monitor: _RevealFixture(
      verdictLine: 'Keep an eye on the dose.',
      brand: 'Nordic Naturals',
      productName: 'Omega-3 + D3 + K2',
      score: 74,
      evidence: 'MODERATE',
    ),
    PGSeverity.caution: _RevealFixture(
      verdictLine: 'Worth a closer look.',
      brand: 'Pure Encapsulations',
      productName: 'B-Complex Plus',
      score: 62,
      evidence: 'MODERATE',
    ),
    PGSeverity.avoid: _RevealFixture(
      verdictLine: 'Reconsider for your stack.',
      brand: 'Generic Brand',
      productName: 'Triple-Strength Pre-Workout',
      score: 41,
      evidence: 'MODERATE',
    ),
    PGSeverity.contraindicated: _RevealFixture(
      verdictLine: "Worth a conversation\nwith your doctor.",
      brand: 'Generic Brand',
      productName: "St. John's Wort Extract",
      score: 32,
      evidence: 'ESTABLISHED',
    ),
  };

  void _trigger(PGSeverity severity) {
    setState(() {
      _activeReveal = severity;
      _revealKey += 1;
    });
  }

  void _onRevealComplete() {
    if (!mounted) return;
    setState(() => _activeReveal = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Mocked camera feed — deep gradient stands in for the live
          // preview so the chrome reads correctly without spinning up
          // mobile_scanner.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0E1011), Color(0xFF1B1F22)],
              ),
            ),
          ),
          // Chrome overlay.
          SafeArea(
            child: Column(
              children: [
                _TopBar(onClose: () => Navigator.of(context).maybePop()),
                const Spacer(),
                const _ScanGuide(),
                const SizedBox(height: V2Spacing.space24),
                const PGEyebrow('Position barcode', color: Colors.white),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'We’ll match it against your on-device catalog.',
                  style: V2Typography.body(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                _SeverityTriggerRow(onTrigger: _trigger),
                const SizedBox(height: V2Spacing.space16),
                _BottomActions(
                  onManual: () {},
                  onAddMedication: () {},
                ),
                const SizedBox(height: V2Spacing.space24),
              ],
            ),
          ),
          // Verdict reveal — keyed so re-triggering the same tier
          // rebuilds the animation from scratch.
          if (_activeReveal != null)
            PGVerdictReveal(
              key: ValueKey(_revealKey),
              severity: _activeReveal!,
              verdictLine: _fixtures[_activeReveal!]!.verdictLine,
              brand: _fixtures[_activeReveal!]!.brand,
              productName: _fixtures[_activeReveal!]!.productName,
              score: _fixtures[_activeReveal!]!.score,
              evidence: _fixtures[_activeReveal!]!.evidence,
              onComplete: _onRevealComplete,
            ),
        ],
      ),
    );
  }
}

class _RevealFixture {
  final String verdictLine;
  final String brand;
  final String productName;
  final double score;
  final String evidence;

  const _RevealFixture({
    required this.verdictLine,
    required this.brand,
    required this.productName,
    required this.score,
    required this.evidence,
  });
}

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;
  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        0,
      ),
      child: Row(
        children: [
          const PGEyebrow('Scan', color: Colors.white),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.flash_off_rounded, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Premium scan-guide frame — 4 corner brackets instead of a full
/// rectangle border. Reads as more refined / less HUD-game.
class _ScanGuide extends StatelessWidget {
  const _ScanGuide();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        children: [
          for (final corner in const [
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ])
            Align(alignment: corner, child: _Corner(corner: corner)),
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final Alignment corner;
  const _Corner({required this.corner});

  @override
  Widget build(BuildContext context) {
    const length = 28.0;
    const thickness = 2.5;
    return SizedBox(
      width: length,
      height: length,
      child: CustomPaint(
        painter: _CornerPainter(
          color: Colors.white.withValues(alpha: 0.9),
          length: length,
          thickness: thickness,
          corner: corner,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double length;
  final double thickness;
  final Alignment corner;

  _CornerPainter({
    required this.color,
    required this.length,
    required this.thickness,
    required this.corner,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    // Each corner draws two perpendicular strokes meeting at the corner's
    // anchor point.
    final isTop = corner.y < 0;
    final isLeft = corner.x < 0;
    final x = isLeft ? 0.0 : size.width;
    final y = isTop ? 0.0 : size.height;
    canvas.drawLine(
      Offset(x, y),
      Offset(x + (isLeft ? length : -length), y),
      paint,
    );
    canvas.drawLine(
      Offset(x, y),
      Offset(x, y + (isTop ? length : -length)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.color != color ||
      old.length != length ||
      old.thickness != thickness ||
      old.corner != corner;
}

class _SeverityTriggerRow extends StatelessWidget {
  final ValueChanged<PGSeverity> onTrigger;
  const _SeverityTriggerRow({required this.onTrigger});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space16),
      child: Column(
        children: [
          PGEyebrow('Preview verdict tier',
              color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(height: V2Spacing.space12),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            alignment: WrapAlignment.center,
            children: [
              for (final s in PGSeverity.values)
                _SeverityTriggerChip(
                  severity: s,
                  onTap: () => onTrigger(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeverityTriggerChip extends StatelessWidget {
  final PGSeverity severity;
  final VoidCallback onTap;
  const _SeverityTriggerChip({required this.severity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = severity.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: V2Motion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space12,
          vertical: V2Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: V2Spacing.space8),
            Text(
              severity.label,
              style: V2Typography.caption(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final VoidCallback onManual;
  final VoidCallback onAddMedication;
  const _BottomActions({
    required this.onManual,
    required this.onAddMedication,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
      child: Row(
        children: [
          Expanded(
            child: _DarkPill(
              icon: Icons.keyboard_rounded,
              label: 'Enter code',
              onTap: onManual,
            ),
          ),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: _DarkPill(
              icon: Icons.medication_outlined,
              label: 'Add medication',
              onTap: onAddMedication,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill on a dark camera-overlay — translucent surface, white text.
/// Local to this screen because the regular [PGPillButton] is tuned for
/// light surfaces; tweaking it for the dark overlay would compromise
/// its primary use.
class _DarkPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DarkPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: V2Spacing.space12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: V2Spacing.space8),
              Text(label, style: V2Typography.label(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
