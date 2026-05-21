import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Pill-shape segmented tab bar.
///
/// Replaces Material's underline-style `TabBar` with a more modern,
/// iOS-style pill segmented control. The selected pill slides smoothly
/// between positions (280ms smooth curve) — feels like one continuous
/// surface, not a row of independent buttons.
///
/// Visual:
/// - Container is a pill-radius surface with hairline outline
/// - Selected pill is the inverse: accent fill, white label, soft shadow
/// - Smooth 280ms slide on selection change
/// - Labels render in Geist Sans label style (500 weight, 14pt) so they
///   stay readable at small sizes
///
/// Layout: tap a label and the underlying pill slides to that position.
/// Children are spread evenly via [Expanded]; pass 2-4 tabs for best
/// legibility (5 or more gets cramped on narrow screens).
class PGPillTabBar extends StatelessWidget {
  /// Labels for each tab in order.
  final List<String> tabs;

  /// Currently selected tab index.
  final int currentIndex;

  /// Called when a tab is tapped.
  final ValueChanged<int> onChanged;

  /// Override the container background.
  /// Default: a 6% accent tint over surface, so the unselected pill row
  /// reads as muted while the selected pill pops accent.
  final Color? backgroundColor;

  /// Vertical padding inside each pill.
  final double verticalPadding;

  const PGPillTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
    this.backgroundColor,
    this.verticalPadding = V2Spacing.space8,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? V2Colors.accentTint.withValues(alpha: 0.5);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Account for the outer container's horizontal padding when
        // computing the indicator's width / left-offset.
        const horizontalPad = 4.0;
        final innerWidth = constraints.maxWidth - horizontalPad * 2;
        final tabWidth = innerWidth / tabs.length;

        return Container(
          padding: const EdgeInsets.all(horizontalPad),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          ),
          child: Stack(
            children: [
              // Animated selection pill — slides between tabs.
              AnimatedPositioned(
                duration: V2Motion.base,
                curve: V2Motion.smooth,
                left: tabWidth * currentIndex,
                top: 0,
                bottom: 0,
                width: tabWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: V2Colors.accent,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    boxShadow: V2Shadows.sm,
                  ),
                ),
              ),
              // Tap labels overlaid on top.
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _PillTab(
                        label: tabs[i],
                        selected: i == currentIndex,
                        onTap: () => onChanged(i),
                        verticalPadding: verticalPadding,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PillTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double verticalPadding;

  const _PillTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.verticalPadding,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedDefaultTextStyle(
        duration: V2Motion.fast,
        curve: V2Motion.smooth,
        style: V2Typography.label(
          color: selected ? Colors.white : V2Colors.fgMuted,
        ),
        textAlign: TextAlign.center,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
