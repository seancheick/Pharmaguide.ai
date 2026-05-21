import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Pill-shaped iOS-style segmented control with a sliding highlighter
/// behind the active segment.
///
/// Composition:
///   - Track: subtle cream/outline material at full pill radius
///   - Highlighter: white surface tile with sm shadow that slides into
///     position when [selectedIndex] changes. Motion: 280ms emphasized
///     curve.
///   - Labels: accent + 500-weight when active, muted + 400-weight when
///     inactive — both fade smoothly via AnimatedDefaultTextStyle.
///
/// 3-segment usage is the design target (Stack / Nutrients / Wishlist)
/// but the widget works for any 2+.
class PGSegmentedControl extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// Overall height of the track. 44pt is the iOS standard and what
  /// the design system uses elsewhere for tap targets.
  final double height;

  const PGSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    assert(segments.length >= 2);
    assert(selectedIndex >= 0 && selectedIndex < segments.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final segmentWidth = w / segments.length;
        // 4pt inset gives the highlighter a clean "tile inside a track"
        // look — the iOS segmented-control hallmark.
        const inset = 4.0;
        final highlightWidth = segmentWidth - (inset * 2);
        final highlightHeight = height - (inset * 2);

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              // Track.
              Container(
                decoration: BoxDecoration(
                  color: V2Colors.surfaceContainerHighest,
                  borderRadius:
                      BorderRadius.circular(V2Spacing.radiusPill),
                  border: Border.all(color: V2Colors.outline),
                ),
              ),
              // Sliding highlighter — AnimatedPositioned glides between
              // segment slots when selectedIndex changes.
              AnimatedPositioned(
                duration: V2Motion.base,
                curve: V2Motion.emphasized,
                left: (segmentWidth * selectedIndex) + inset,
                top: inset,
                width: highlightWidth,
                height: highlightHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: V2Colors.surface,
                    borderRadius: BorderRadius.circular(
                      (highlightHeight / 2) - 0.5,
                    ),
                    boxShadow: V2Shadows.sm,
                  ),
                ),
              ),
              // Tap targets + labels.
              Row(
                children: List.generate(segments.length, (i) {
                  final isActive = i == selectedIndex;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i != selectedIndex) onChanged(i);
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: V2Motion.base,
                          curve: V2Motion.emphasized,
                          style: isActive
                              ? V2Typography.label(color: V2Colors.accent)
                              : V2Typography.bodyMedium(
                                  color: V2Colors.fgMuted,
                                ),
                          child: Text(segments[i]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
