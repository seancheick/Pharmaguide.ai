// Isolated prototype: iOS 26-style interactive Liquid Glass on the bottom
// navigation. Debug-only (`/dev/v2/glass-nav`); nothing in the production
// shell uses it. Sean 2026-09-28: prototype one bottom-nav interaction,
// compare it with Apple's native tab bar, then decide where it belongs.
//
// What it reproduces (Apple's Phone / Files tab bar on iOS 26):
//   resting   → a floating glass capsule; the selected tab sits on a quiet pill
//   touch-down → a larger glass "lens" grows out of the touched tab, lifting
//                past the capsule's edges and magnifying what is beneath it
//   drag      → the lens follows the finger across tabs, stretching slightly
//                with speed; crossing into a new tab ticks a selection haptic
//   release   → the lens springs onto the tab under the finger and settles
//                back into the resting pill; the tab is selected
//
// Honest limits: Flutter cannot sample the real iOS glass material, so the
// "refraction" is a magnified backdrop (RawMagnifier) plus a blurred capsule,
// a rim and a specular highlight. See docs/PRODUCT_UX_AUDIT_2026-09-28.md for
// the native (platform-view) option and where this interaction belongs.
//
// Accessibility: each tab is a button with its label and selected state and
// a hit area of at least 44pt. Reduce Motion drops the lens and its springs:
// the pill moves at once. Increase Contrast, Reduce Transparency (and
// Android, which has no glass language) draw an opaque bar with a solid
// outline and no lens.

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/reduce_transparency.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';

/// One tab in [PGGlassTabBar].
@immutable
class PGGlassTab {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const PGGlassTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Floating glass tab bar with an interactive press lens (prototype).
class PGGlassTabBar extends StatefulWidget {
  final List<PGGlassTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Test hook: force the glass path on non-iOS test hosts.
  final bool? glassOverride;

  const PGGlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.glassOverride,
  });

  /// Capsule height. Tab hit areas are the full height (≥44pt).
  static const double barHeight = 64;

  @override
  State<PGGlassTabBar> createState() => _PGGlassTabBarState();
}

class _PGGlassTabBarState extends State<PGGlassTabBar>
    with TickerProviderStateMixin {
  // Spring feel, from Apple's response / damping-fraction model:
  // stiffness = (2π / response)² · mass, damping = 2 · ζ · √(stiffness · mass).
  static const _track = SpringDescription(mass: 1, stiffness: 420, damping: 32);
  static const _grow = SpringDescription(mass: 1, stiffness: 560, damping: 30);
  static const _settle = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 27,
  );

  /// Lens centre x within the capsule, in logical pixels.
  late final AnimationController _lensX = AnimationController.unbounded(
    vsync: this,
  );

  /// 0 = resting (no lens), 1 = lens fully grown.
  late final AnimationController _presence = AnimationController.unbounded(
    vsync: this,
  );

  double _barWidth = 0;
  bool _pressing = false;
  int _hoverIndex = 0;
  double _velocityX = 0;
  Duration? _lastMoveTime;
  double? _lastMoveX;

  @override
  void dispose() {
    _lensX.dispose();
    _presence.dispose();
    super.dispose();
  }

  double get _slot => _barWidth / widget.tabs.length;
  double _centerOf(int index) => _slot * (index + 0.5);
  int _indexAt(double x) =>
      (x / _slot).floor().clamp(0, widget.tabs.length - 1);

  bool _glassEnabled(BuildContext context) {
    final override = widget.glassOverride;
    if (override != null) return override;
    if (MediaQuery.highContrastOf(context)) return false;
    if (ReduceTransparency.of(context)) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  void _springTo(
    AnimationController c,
    double target,
    SpringDescription spring,
  ) {
    c.animateWith(SpringSimulation(spring, c.value, target, _velocityOf(c)));
  }

  double _velocityOf(AnimationController c) => c.isAnimating ? c.velocity : 0.0;

  void _onDown(PointerDownEvent e, {required bool lens}) {
    if (_barWidth <= 0) return;
    _pressing = true;
    _hoverIndex = _indexAt(e.localPosition.dx);
    _velocityX = 0;
    _lastMoveTime = e.timeStamp;
    _lastMoveX = e.localPosition.dx;
    if (!lens) return;
    // The lens grows out of the touched tab, not out of the old selection.
    _lensX.value = _centerOf(_hoverIndex);
    _springTo(_presence, 1, _grow);
    setState(() {});
  }

  void _onMove(PointerMoveEvent e, {required bool lens}) {
    if (!_pressing) return;
    final x = e.localPosition.dx.clamp(0.0, _barWidth);
    final t = e.timeStamp;
    if (_lastMoveTime != null && _lastMoveX != null) {
      final dt = (t - _lastMoveTime!).inMicroseconds / 1e6;
      if (dt > 0) _velocityX = (x - _lastMoveX!) / dt;
    }
    _lastMoveTime = t;
    _lastMoveX = x;
    final index = _indexAt(x);
    if (index != _hoverIndex) {
      _hoverIndex = index;
      HapticFeedback.selectionClick();
    }
    if (lens) {
      // Follow the finger, but keep the lens inside the capsule's ends.
      final half = _slot / 2;
      _springTo(_lensX, x.clamp(half, _barWidth - half), _track);
    }
    setState(() {});
  }

  void _onUp(PointerUpEvent e, {required bool lens}) {
    if (!_pressing) return;
    _pressing = false;
    final target = _indexAt(e.localPosition.dx.clamp(0.0, _barWidth));
    _velocityX = 0;
    if (lens) {
      _springTo(_lensX, _centerOf(target), _settle);
      _springTo(_presence, 0, _settle);
    }
    if (target != widget.selectedIndex) {
      HapticFeedback.selectionClick();
      widget.onSelected(target);
    }
    setState(() {});
  }

  void _onCancel({required bool lens}) {
    _pressing = false;
    _velocityX = 0;
    if (lens) {
      _springTo(_lensX, _centerOf(widget.selectedIndex), _settle);
      _springTo(_presence, 0, _settle);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glass = _glassEnabled(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lens = glass && !reduceMotion;

    return LayoutBuilder(
      builder: (context, constraints) {
        _barWidth = constraints.maxWidth;
        final restingIndex = _pressing && !lens
            ? _hoverIndex
            : widget.selectedIndex;
        return SizedBox(
          height: PGGlassTabBar.barHeight,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _onDown(e, lens: lens),
            onPointerMove: (e) => _onMove(e, lens: lens),
            onPointerUp: (e) => _onUp(e, lens: lens),
            onPointerCancel: (_) => _onCancel(lens: lens),
            child: AnimatedBuilder(
              animation: Listenable.merge([_lensX, _presence]),
              builder: (context, _) {
                final presence = _presence.value.clamp(0.0, 1.2);
                // Native: the whole capsule swells ~3.5% while pressed.
                final swell = 1 + 0.035 * presence.clamp(0.0, 1.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Transform.scale(
                        scale: swell,
                        child: _Capsule(glass: glass, isDark: isDark),
                      ),
                    ),
                    // Resting pill: fades while the lens is out and settles
                    // back in as it shrinks.
                    _Pill(
                      center: _centerOf(restingIndex),
                      width: _slot - V2Spacing.space8,
                      opacity: (1 - presence).clamp(0.0, 1.0),
                      animate: !reduceMotion && !lens,
                      glass: glass,
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < widget.tabs.length; i++)
                          Expanded(
                            child: _TabItem(
                              tab: widget.tabs[i],
                              selected: i == widget.selectedIndex,
                              highlighted: _pressing && i == _hoverIndex,
                              onActivate: () {
                                if (i != widget.selectedIndex) {
                                  widget.onSelected(i);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                    if (lens && presence > 0.01)
                      _Lens(
                        centerX: _lensX.value,
                        slot: _slot,
                        presence: presence,
                        velocityX: _velocityX,
                        isDark: isDark,
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Capsule extends StatelessWidget {
  final bool glass;
  final bool isDark;
  const _Capsule({required this.glass, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    final radius = BorderRadius.circular(PGGlassTabBar.barHeight / 2);
    if (!glass) {
      // Increase Contrast / Android: opaque, outlined, no blur.
      return DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: radius,
          border: Border.all(color: palette.fgSubtle),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // Regular glass: ~24px blur with a mild saturation lift so colour
          // under the bar stays alive (liquid-glass.md › Flutter).
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            inner: const ColorFilter.matrix(_saturate130),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: palette.surface.withValues(alpha: isDark ? 0.52 : 0.62),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.70),
                width: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.3× saturation (luminance-preserving), row-major 4×5.
const List<double> _saturate130 = <double>[
  1.2362, -0.2145, -0.0217, 0, 0, //
  -0.0638, 1.0855, -0.0217, 0, 0, //
  -0.0638, -0.2145, 1.2783, 0, 0, //
  0, 0, 0, 1, 0, //
];

class _Pill extends StatelessWidget {
  final double center;
  final double width;
  final double opacity;
  final bool animate;
  final bool glass;

  const _Pill({
    required this.center,
    required this.width,
    required this.opacity,
    required this.animate,
    required this.glass,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    const height = PGGlassTabBar.barHeight - V2Spacing.space12;
    return AnimatedPositioned(
      duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
      curve: Curves.easeOutCubic,
      left: center - width / 2,
      top: (PGGlassTabBar.barHeight - height) / 2,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.fg.withValues(alpha: glass ? 0.07 : 0.10),
              borderRadius: BorderRadius.circular(height / 2),
              border: glass ? null : Border.all(color: palette.fgMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _Lens extends StatelessWidget {
  final double centerX;
  final double slot;
  final double presence;
  final double velocityX;
  final bool isDark;

  const _Lens({
    required this.centerX,
    required this.slot,
    required this.presence,
    required this.velocityX,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Grows from the resting pill to a lens that lifts past the capsule.
    final restW = slot - V2Spacing.space8;
    const restH = PGGlassTabBar.barHeight - V2Spacing.space12;
    // Native capture: the lens is ~1.34x the tab and ~1.36x the bar.
    final fullW = slot * 1.34;
    const fullH = PGGlassTabBar.barHeight * 1.36;
    // A little stretch along the drag, like the native material.
    final stretch = 1 + (velocityX.abs() / 3000).clamp(0.0, 0.12);
    final w = (restW + (fullW - restW) * presence) * stretch;
    final h = restH + (fullH - restH) * presence;
    final rim = Colors.white.withValues(alpha: isDark ? 0.35 : 0.85);

    return Positioned(
      left: centerX - w / 2,
      top: (PGGlassTabBar.barHeight - h) / 2,
      width: w,
      height: h,
      child: IgnorePointer(
        child: RawMagnifier(
          size: Size(w, h),
          magnificationScale: 1 + 0.16 * presence.clamp(0.0, 1.0),
          clipBehavior: Clip.hardEdge,
          decoration: MagnifierDecoration(
            opacity: presence.clamp(0.0, 1.0),
            shape: StadiumBorder(
              side: BorderSide(color: rim.withValues(alpha: 0.5), width: 0.5),
            ),
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          // Specular highlight (light catching the upper edge) plus the
          // faint chromatic edge the native lens shows.
          child: CustomPaint(
            foregroundPainter: _ChromaticRim(isDark: isDark),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 1],
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.10 : 0.28),
                    const Color(0x00FFFFFF), // clear white: no grey mid-band
                    Colors.white.withValues(alpha: isDark ? 0.03 : 0.08),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin sweep of cool and warm tints around the lens edge — the faint
/// iridescence of the native material. Kept at low alpha: a hint, not a
/// rainbow.
class _ChromaticRim extends CustomPainter {
  final bool isDark;
  const _ChromaticRim({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final a = isDark ? 0.45 : 0.75;
    final white = Colors.white.withValues(alpha: isDark ? 0.45 : 0.75);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        colors: [
          white,
          const Color(0xFF8FE3FF).withValues(alpha: a * 0.8),
          white,
          const Color(0xFFFFB8E6).withValues(alpha: a * 0.7),
          white,
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(0.7),
        Radius.circular(size.height / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChromaticRim oldDelegate) => oldDelegate.isDark != isDark;
}

class _TabItem extends StatelessWidget {
  final PGGlassTab tab;
  final bool selected;
  final bool highlighted;
  final VoidCallback onActivate;

  const _TabItem({
    required this.tab,
    required this.selected,
    required this.highlighted,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    // Brand colour only on the selected tab (liquid-glass.md › Color).
    final color = selected || highlighted ? palette.accent : palette.fgMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      // Screen readers activate through semantics; pointer input goes
      // through the bar's Listener so the lens can track the finger.
      onTap: onActivate,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected || highlighted ? tab.selectedIcon : tab.icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: V2Typography.caption(color: color).copyWith(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `/dev/v2/glass-nav` — the prototype over the real Home screen, so the
/// glass has PharmaGuide content to blur and magnify.
class GlassTabBarPrototypeScreen extends StatefulWidget {
  const GlassTabBarPrototypeScreen({super.key});

  @override
  State<GlassTabBarPrototypeScreen> createState() =>
      _GlassTabBarPrototypeScreenState();
}

class _GlassTabBarPrototypeScreenState
    extends State<GlassTabBarPrototypeScreen> {
  int _index = 0;

  static const _tabs = [
    PGGlassTab(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
    ),
    PGGlassTab(
      icon: Icons.qr_code_scanner_outlined,
      selectedIcon: Icons.qr_code_scanner_rounded,
      label: 'Scan',
    ),
    PGGlassTab(
      icon: Icons.layers_outlined,
      selectedIcon: Icons.layers_rounded,
      label: 'Stack',
    ),
    PGGlassTab(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: HomeV2Screen(showNavBar: false)),
          Positioned(
            left: V2Spacing.space16,
            right: V2Spacing.space16,
            bottom: bottom + V2Spacing.space8,
            child: PGGlassTabBar(
              tabs: _tabs,
              selectedIndex: _index,
              onSelected: (i) => setState(() => _index = i),
            ),
          ),
        ],
      ),
    );
  }
}
