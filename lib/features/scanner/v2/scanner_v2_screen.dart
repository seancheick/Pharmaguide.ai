import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_scan_not_found.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// v2 Scanner — visual mirror of `scanner_screen.dart` with simplified
/// 2-tone verdict flash + amber not-found overlay.
///
/// Layout:
///   - Camera feed background (gallery preview: dark gradient surrogate)
///   - SafeArea(bottom: false) → status bar inset only; we own bottom
///     spacing explicitly so the nav-bar overlap is exact
///   - Top bar (anchored top)
///   - Scan frame + tagline (centered, slightly above viewport center)
///   - "Enter code manually" + "Add medication" buttons (anchored
///     bottom, sitting just above the frosted nav bar)
///
/// Overlays (mutually exclusive):
///   - PGVerdictReveal: 2 states only — success (green) for safe/
///     monitor, attention (amber) for everything else. Decision
///     tier lives on the product page.
///   - PGScanNotFound: light amber screen with search, retry, and
///     manual-entry CTAs when the scan doesn't match the catalog.
class ScannerV2Screen extends StatefulWidget {
  /// When non-null, the verdict flash renders immediately.
  final PGVerdictKind? demoVerdict;

  /// When true, renders the "not found" overlay instead.
  final bool showNotFound;

  final VoidCallback? onVerdictDismiss;
  final VoidCallback? onNotFoundDismiss;
  final VoidCallback? onRetryScan;
  final VoidCallback? onSearchByName;
  final VoidCallback? onManualEntry;
  final VoidCallback? onAddMedication;

  /// Optional tap target on the scan frame — gallery preview wires
  /// this to a demo cycle; production leaves it null.
  final VoidCallback? onFrameTap;

  final bool showNavBar;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  const ScannerV2Screen({
    super.key,
    this.demoVerdict,
    this.showNotFound = false,
    this.onVerdictDismiss,
    this.onNotFoundDismiss,
    this.onRetryScan,
    this.onSearchByName,
    this.onManualEntry,
    this.onAddMedication,
    this.onFrameTap,
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
    // Bottom buttons sit just above the frosted nav bar. kPGNavBarHeight
    // already accounts for the home-indicator inset (~88pt total).
    // SafeArea(bottom: false) means we don't double-count that inset.
    final bottomActionsPad =
        (widget.showNavBar ? kPGNavBarHeight : 0) + V2Spacing.space12;

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
            const _CameraSurrogate(),
            SafeArea(
              // SafeArea handles status-bar inset at the top only. Bottom
              // spacing is owned by the bottomActionsPad above so it
              // matches the actual nav-bar overlap exactly.
              bottom: false,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: _TopBar(
                      flashOn: _flashOn,
                      onToggleFlash: () => setState(() => _flashOn = !_flashOn),
                    ),
                  ),
                  // Frame + tagline centered, slightly above viewport
                  // center for visual balance with the bottom anchor.
                  Align(
                    alignment: const Alignment(0, -0.20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ScanFrame(onTap: widget.onFrameTap),
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
                      ],
                    ),
                  ),
                  // Bottom buttons anchored above the nav bar with a
                  // single small visual gap.
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        V2Spacing.space24,
                        V2Spacing.space16,
                        V2Spacing.space24,
                        bottomActionsPad,
                      ),
                      child: _BottomActions(
                        onManualEntry: widget.onManualEntry,
                        onAddMedication: widget.onAddMedication,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Verdict flash — 2-tone (success/attention), brief, no
            // copy. Auto-dismisses after 900ms.
            if (widget.demoVerdict != null && !widget.showNotFound)
              PGVerdictReveal(
                key: ValueKey(widget.demoVerdict),
                kind: widget.demoVerdict!,
                onDismiss: widget.onVerdictDismiss,
              ),
            // Not-found overlay — light amber screen with search,
            // retry, and manual entry CTAs.
            if (widget.showNotFound)
              PGScanNotFound(
                scannedCode: '0123456789',
                onRetry: widget.onRetryScan ?? () {},
                onSearchByName:
                    widget.onSearchByName ?? () => context.push(Routes.search),
                onManualEntry: widget.onManualEntry ?? () {},
                onClose: widget.onNotFoundDismiss ?? () {},
              ),
          ],
        ),
        bottomNavigationBar: widget.showNavBar
            ? PGFrostedNavBar(
                selectedIndex: widget.selectedIndex,
                onDestinationSelected: widget.onDestinationSelected ?? (_) {},
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
}

// =============================================================================
// Camera surrogate.
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
          colors: [V2Colors.cameraOverlayTop, V2Colors.cameraOverlayBottom],
        ),
      ),
    );
  }
}

// =============================================================================
// Top bar.
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
// Scan frame with corner brackets. Tap-target wired through onTap so
// the preview can trigger demo states.
// =============================================================================

class _ScanFrame extends StatelessWidget {
  final VoidCallback? onTap;
  const _ScanFrame({this.onTap});

  @override
  Widget build(BuildContext context) {
    final frame = SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        children: [
          for (final corner in _Corner.values) _CornerBracket(corner: corner),
        ],
      ),
    );
    if (onTap == null) return frame;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: frame,
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
          painter: _CornerPainter(corner: corner, color: color, stroke: stroke),
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
// Bottom actions.
// =============================================================================

class _BottomActions extends StatelessWidget {
  final VoidCallback? onManualEntry;
  final VoidCallback? onAddMedication;

  const _BottomActions({this.onManualEntry, this.onAddMedication});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OutlineAction(
          icon: Icons.keyboard_rounded,
          label: 'Enter code manually',
          onTap: onManualEntry ?? () {},
        ),
        const SizedBox(height: V2Spacing.space8),
        _OutlineAction(
          icon: Icons.medication_outlined,
          label: 'Add medication',
          onTap: onAddMedication ?? () {},
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
// Preview wrapper. Tapping the scan frame cycles through demo states:
//   tap 1 → success flash
//   tap 2 → attention flash
//   tap 3 → not-found overlay
//   tap 4 → clear (back to live frame)
// =============================================================================

class ScannerV2Preview extends StatefulWidget {
  const ScannerV2Preview({super.key});

  @override
  State<ScannerV2Preview> createState() => _ScannerV2PreviewState();
}

enum _DemoState { idle, success, attention, notFound }

class _ScannerV2PreviewState extends State<ScannerV2Preview> {
  _DemoState _demo = _DemoState.idle;
  int _navIndex = 2;

  void _cycle() {
    setState(() {
      _demo = switch (_demo) {
        _DemoState.idle => _DemoState.success,
        _DemoState.success => _DemoState.attention,
        _DemoState.attention => _DemoState.notFound,
        _DemoState.notFound => _DemoState.idle,
      };
    });
  }

  void _clear() => setState(() => _demo = _DemoState.idle);

  @override
  Widget build(BuildContext context) {
    final demoVerdict = switch (_demo) {
      _DemoState.success => PGVerdictKind.success,
      _DemoState.attention => PGVerdictKind.attention,
      _DemoState.idle || _DemoState.notFound => null,
    };

    return Stack(
      children: [
        ScannerV2Screen(
          demoVerdict: demoVerdict,
          showNotFound: _demo == _DemoState.notFound,
          onVerdictDismiss: _clear,
          onNotFoundDismiss: _clear,
          onRetryScan: _clear,
          onFrameTap: _cycle,
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
                child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        // Single hint line — only visible in the idle preview state.
        if (_demo == _DemoState.idle)
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: V2Spacing.space24,
            right: V2Spacing.space24,
            child: IgnorePointer(
              child: Text(
                'Preview · tap the frame to cycle scan states',
                textAlign: TextAlign.center,
                style: V2Typography.caption(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
