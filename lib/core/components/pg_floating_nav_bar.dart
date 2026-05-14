import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One slot in the [PGFloatingNavBar].
///
/// [raised] tabs render as a 56pt accent circle that overlaps the top
/// edge of the bar — the Instagram / Twitter / native iOS-search pattern
/// for the most-important action.
class PGNavDestination {
  /// Default icon (outlined / quieter variant).
  final IconData icon;

  /// Selected icon — typically the filled / rounded variant of [icon].
  /// Defaults to [icon] when null.
  final IconData? selectedIcon;

  final String label;

  /// When true, this slot renders as an elevated accent circle instead
  /// of the standard icon row. Reserve for the single most-used action
  /// (scan).
  final bool raised;

  const PGNavDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.raised = false,
  });
}

/// Floating-pill bottom nav bar.
///
/// **Visual:**
/// - Pill-radius container floating above the bottom safe area by 12pt
///   with 16pt side margins
/// - Glass blur (single BackdropFilter, never animated — perf contract)
///   over surface @ 92% opacity
/// - V2Shadows.lg layered shadow for soft lift
/// - 5 destinations with the middle slot raised into a 56pt accent
///   circle overlapping the pill's top edge by ~14pt
/// - Active label slides in beside the active icon (AnimatedSize)
/// - Active dot indicator under non-raised active icons, animated 180ms
///
/// **Use with** `Scaffold(extendBody: true, ...)` so content flows under
/// the bar and the glass has pixels to blur.
class PGFloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<PGNavDestination> destinations;

  const PGFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.destinations,
  })  : assert(destinations.length >= 3 && destinations.length <= 5,
            'PGFloatingNavBar supports 3-5 destinations.');

  static const double _barHeight = 64;
  static const double _bottomGap = 12;
  static const double _sideGap = 16;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideGap,
        0,
        _sideGap,
        bottomInset + _bottomGap,
      ),
      child: RepaintBoundary(
        child: SizedBox(
          height: _barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: _barHeight,
                    decoration: BoxDecoration(
                      color: V2Colors.surface.withValues(alpha: 0.92),
                      borderRadius:
                          BorderRadius.circular(V2Spacing.radiusPill),
                      border: Border.all(color: V2Colors.outline),
                      boxShadow: V2Shadows.lg,
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          Expanded(
                            child: _NavSlot(
                              destination: destinations[i],
                              selected: i == currentIndex,
                              onTap: () => onChanged(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Raised slot — find the raised destination and render it
              // as an overlay so it overlaps the pill's top edge.
              for (var i = 0; i < destinations.length; i++)
                if (destinations[i].raised)
                  _RaisedSlot(
                    index: i,
                    total: destinations.length,
                    icon: destinations[i].icon,
                    label: destinations[i].label,
                    selected: i == currentIndex,
                    onTap: () => onChanged(i),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final PGNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavSlot({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Raised slots are rendered by the parent stack; this slot just
    // holds empty space at the same width so the others stay evenly
    // distributed.
    if (destination.raised) {
      return const SizedBox.shrink();
    }

    final icon = selected
        ? (destination.selectedIcon ?? destination.icon)
        : destination.icon;
    final fg = selected ? V2Colors.accent : V2Colors.fgMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: AnimatedContainer(
          duration: V2Motion.fast,
          curve: V2Motion.smooth,
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: V2Spacing.space4),
              AnimatedSize(
                duration: V2Motion.fast,
                curve: V2Motion.smooth,
                child: selected
                    ? Text(
                        destination.label,
                        style: V2Typography.overline(color: fg),
                      )
                    : Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised accent circle that overlaps the top of the pill by ~14pt.
/// Positioned absolutely via LayoutBuilder math so it lands centered in
/// its slot regardless of how many siblings exist.
class _RaisedSlot extends StatelessWidget {
  final int index;
  final int total;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RaisedSlot({
    required this.index,
    required this.total,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const double _size = 56;
  static const double _topOverlap = 14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / total;
        final leftEdge = slotWidth * index + (slotWidth - _size) / 2;

        return Positioned(
          left: leftEdge,
          top: -_topOverlap,
          width: _size,
          height: _size,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: V2Motion.fast,
              curve: V2Motion.smooth,
              decoration: BoxDecoration(
                color: V2Colors.accent,
                shape: BoxShape.circle,
                boxShadow:
                    selected ? V2Shadows.accentGlow : V2Shadows.md,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(icon, size: 26, color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }
}
