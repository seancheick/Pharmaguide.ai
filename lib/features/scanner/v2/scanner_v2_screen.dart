import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// v2 Scanner — faithful visual mirror of `scanner_screen.dart`.
///
/// Production composition preserved:
///   1. Camera feed background (here: cameraOverlay solid black —
///      MobileScanner can't preview in the gallery)
///   2. Top bar: "Scan Product" title (white) + flash toggle
///   3. Center: 250pt scan-frame with v2 corner brackets
///   4. Below frame: "Center the barcode in the frame" + tagline
///   5. Bottom: two outlined buttons — "Enter code manually" + "Add
///      medication"
///   6. PGVerdictReveal overlay on barcode detection (v2 enhancement
///      of production's _showFlash overlay — celebration motion for
///      safe verdicts, decelerate for caution+, layered haptics)
///
/// Production wiring (Phase 8.x): swap the dark placeholder for
/// MobileScanner + onDetect callback; verdict resolution maps the
/// existing scanner_logic verdict types to PGVerdictKind.
class ScannerV2Screen extends StatefulWidget {
  /// When non-null, the verdict reveal renders immediately — used by
  /// the gallery preview to demo each tier without hitting the real
  /// scan flow.
  final PGVerdictKind? demoVerdict;

  /// Callback when the verdict reveal auto-dismisses or is tapped.
  final VoidCallback? onVerdictDismiss;

  /// Hides the nav bar (preview wrapper passes false; production
  /// ShellRoute keeps it visible).
  final bool showNavBar;

  /// Tab index for the nav bar — defaults to Scan (index 2 in v2
  /// order: Home / Stack / Scan / Chat / Profile).
  final int selectedIndex;

  /// Optional handler for nav-destination taps.
  final ValueChanged<int>? onDestinationSelected;

  const ScannerV2Screen({
    super.key,
    this.demoVerdict,
    this.onVerdictDismiss,
    this.showNavBar = true,
    this.selectedIndex = 2,
    this.onDestinationSelected,
  });

  @override
  State<ScannerV2Screen> createState() => _ScannerV2ScreenState();
}

class _ScannerV2ScreenState extends State<ScannerV2Screen> {
  bool _flashOn = false;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: V2Colors.cameraOverlayTop,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Camera feed surrogate. Production wires MobileScanner here;
            // the gallery preview shows a calm dark-gradient placeholder
            // so reviewers can see the chrome composition.
            const _CameraSurrogate(),
            // Scanner overlay (top bar + frame + bottom buttons).
            SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    flashOn: _flashOn,
                    onToggleFlash: () =>
                        setState(() => _flashOn = !_flashOn),
                  ),
                  const Spacer(),
                  const _ScanFrame(),
                  const SizedBox(height: V2Spacing.space24),
                  Text(
                    'Center the barcode in the frame',
                    style: V2Typography.bodyMedium(color: Colors.white),
                  ),
                  const SizedBox(height: V2Spacing.space8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space32,
                    ),
                    child: Text(
                      "We'll match it against your on-device catalog.",
                      textAlign: TextAlign.center,
                      style: V2Typography.bodySm(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Bottom buttons + extra room for the nav bar overlap.
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      V2Spacing.space24,
                      V2Spacing.space16,
                      V2Spacing.space24,
                      V2Spacing.space16 +
                          (widget.showNavBar ? kPGNavBarHeight : 0),
                    ),
                    child: const _BottomActions(),
                  ),
                ],
              ),
            ),
            // Verdict reveal — Phase 10.1 enhancement of the legacy
            // _showFlash overlay.
            if (widget.demoVerdict != null)
              PGVerdictReveal(
                key: ValueKey(widget.demoVerdict),
                kind: widget.demoVerdict!,
                label: _labelFor(widget.demoVerdict!),
                subline: _sublineFor(widget.demoVerdict!),
                onDismiss: widget.onVerdictDismiss,
              ),
          ],
        ),
        bottomNavigationBar: widget.showNavBar
            ? PGFrostedNavBar(
                useV2Tones: true,
                selectedIndex: widget.selectedIndex,
                onDestinationSelected:
                    widget.onDestinationSelected ?? (_) {},
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.layers_outlined),
                    selectedIcon: Icon(Icons.layers_rounded),
                    label: 'Stack',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.qr_code_scanner_outlined),
                    selectedIcon: Icon(Icons.qr_code_scanner_rounded),
                    label: 'Scan',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome_rounded),
                    label: 'Chat',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  static String _labelFor(PGVerdictKind kind) => switch (kind) {
        PGVerdictKind.safe => 'Looks safe for you',
        PGVerdictKind.monitor => 'Worth knowing',
        PGVerdictKind.caution => 'Use with caution',
        PGVerdictKind.avoid => 'Better to avoid',
        PGVerdictKind.contraindicated => 'Do not take with your meds',
      };

  static String? _sublineFor(PGVerdictKind kind) => switch (kind) {
        PGVerdictKind.safe =>
          'No conflicts with your stack — score 84.',
        PGVerdictKind.monitor =>
          'Within limits, but worth a check-in if you take it daily.',
        PGVerdictKind.caution =>
          'Talk to your doctor before adding this to your stack.',
        PGVerdictKind.avoid =>
          'Conflicts with a higher-priority item in your stack.',
        PGVerdictKind.contraindicated =>
          'Major interaction with your blood thinner.',
      };
}

// =============================================================================
// Camera surrogate — vertical gradient that suggests a viewfinder.
// =============================================================================

class _CameraSurrogate extends StatelessWidget {
  const _CameraSurrogate();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            V2Colors.cameraOverlayTop,
            V2Colors.cameraOverlayBottom,
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Top bar — "Scan Product" title + flash toggle.
// =============================================================================

class _TopBar extends StatelessWidget {
  final bool flashOn;
  final VoidCallback onToggleFlash;

  const _TopBar({required this.flashOn, required this.onToggleFlash});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space16,
        V2Spacing.space24,
        V2Spacing.space16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Scan Product',
            style: V2Typography.titleSm(color: Colors.white),
          ),
          _FlashChip(on: flashOn, onTap: onToggleFlash),
        ],
      ),
    );
  }
}

class _FlashChip extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _FlashChip({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = on
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.08);
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Scan frame — 250pt square with white corner brackets, no full border.
// More iOS-Wallet-QR-feel than the production white-border rectangle.
// =============================================================================

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        children: [
          for (final corner in _Corner.values) _CornerBracket(corner: corner),
        ],
      ),
    );
  }
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerBracket extends StatelessWidget {
  final _Corner corner;
  const _CornerBracket({required this.corner});

  @override
  Widget build(BuildContext context) {
    const len = 28.0;
    const stroke = 3.0;
    final color = Colors.white.withValues(alpha: 0.92);
    final isTop = corner == _Corner.topLeft || corner == _Corner.topRight;
    final isLeft = corner == _Corner.topLeft || corner == _Corner.bottomLeft;

    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      child: SizedBox(
        width: len,
        height: len,
        child: CustomPaint(
          painter: _CornerPainter(
            corner: corner,
            color: color,
            stroke: stroke,
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final _Corner corner;
  final Color color;
  final double stroke;

  _CornerPainter({
    required this.corner,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    const r = 6.0;

    final path = Path();
    switch (corner) {
      case _Corner.topLeft:
        path
          ..moveTo(0, h)
          ..lineTo(0, r)
          ..quadraticBezierTo(0, 0, r, 0)
          ..lineTo(w, 0);
      case _Corner.topRight:
        path
          ..moveTo(0, 0)
          ..lineTo(w - r, 0)
          ..quadraticBezierTo(w, 0, w, r)
          ..lineTo(w, h);
      case _Corner.bottomLeft:
        path
          ..moveTo(0, 0)
          ..lineTo(0, h - r)
          ..quadraticBezierTo(0, h, r, h)
          ..lineTo(w, h);
      case _Corner.bottomRight:
        path
          ..moveTo(w, 0)
          ..lineTo(w, h - r)
          ..quadraticBezierTo(w, h, w - r, h)
          ..lineTo(0, h);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.corner != corner || old.color != color || old.stroke != stroke;
}

// =============================================================================
// Bottom actions — Enter code manually + Add medication. Mirror of
// production's stacked OutlinedButton.icon pair.
// =============================================================================

class _BottomActions extends StatelessWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OutlineAction(
          icon: Icons.keyboard_rounded,
          label: 'Enter code manually',
          onTap: () {},
        ),
        const SizedBox(height: V2Spacing.space8),
        _OutlineAction(
          icon: Icons.medication_outlined,
          label: 'Add medication',
          onTap: () {},
        ),
      ],
    );
  }
}

class _OutlineAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlineAction({
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
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space16,
            vertical: V2Spacing.space12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: V2Spacing.space8),
              Text(label, style: V2Typography.label(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Preview wrapper — adds a row of "Demo verdict" chips at the top so
// reviewers can see each tier without wiring real camera detection.
// =============================================================================

class ScannerV2Preview extends StatefulWidget {
  const ScannerV2Preview({super.key});

  @override
  State<ScannerV2Preview> createState() => _ScannerV2PreviewState();
}

class _ScannerV2PreviewState extends State<ScannerV2Preview> {
  PGVerdictKind? _demo;
  int _navIndex = 2; // Scan tab

  void _fire(PGVerdictKind kind) {
    setState(() => _demo = kind);
  }

  void _clear() {
    setState(() => _demo = null);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ScannerV2Screen(
          demoVerdict: _demo,
          onVerdictDismiss: _clear,
          selectedIndex: _navIndex,
          onDestinationSelected: (i) => setState(() => _navIndex = i),
        ),
        // Floating close chip — gallery preview only.
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 8,
          child: Material(
            color: Colors.white.withValues(alpha: 0.18),
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.go('/dev/v2'),
              child: const Padding(
                padding: EdgeInsets.all(V2Spacing.space8),
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        // Demo verdict chips — sit just under the top bar.
        Positioned(
          top: MediaQuery.of(context).padding.top + 64,
          left: V2Spacing.space24,
          right: V2Spacing.space24,
          child: IgnorePointer(
            ignoring: _demo != null,
            child: AnimatedOpacity(
              opacity: _demo == null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _DemoChip(
                      label: 'Safe',
                      onTap: () => _fire(PGVerdictKind.safe),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    _DemoChip(
                      label: 'Monitor',
                      onTap: () => _fire(PGVerdictKind.monitor),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    _DemoChip(
                      label: 'Caution',
                      onTap: () => _fire(PGVerdictKind.caution),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    _DemoChip(
                      label: 'Avoid',
                      onTap: () => _fire(PGVerdictKind.avoid),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    _DemoChip(
                      label: 'Contraindicated',
                      onTap: () => _fire(PGVerdictKind.contraindicated),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DemoChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DemoChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space12,
            vertical: V2Spacing.space8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.30),
              width: 0.8,
            ),
          ),
          child: Text(label, style: V2Typography.label(color: Colors.white)),
        ),
      ),
    );
  }
}
