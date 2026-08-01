import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Item type — drives badge color, icon, and label.
enum PGItemType {
  /// Bottle / capsule supplement.
  supplement,

  /// Prescription or OTC medication. Distinct visually so users can scan
  /// their stack and immediately see what's a Rx vs what isn't.
  medication,

  /// Bookmarked / wishlist item — saved but not yet in the active stack.
  bookmark,
}

extension PGItemTypeX on PGItemType {
  IconData get icon => switch (this) {
    PGItemType.supplement => Icons.medication_outlined,
    PGItemType.medication => Icons.local_pharmacy_outlined,
    PGItemType.bookmark => Icons.bookmark_outline_rounded,
  };

  String get label => switch (this) {
    PGItemType.supplement => 'Supplement',
    PGItemType.medication => 'Medication',
    PGItemType.bookmark => 'Saved',
  };

  /// Foreground tone. Supplements get the brand accent; medications get
  /// a calm desaturated brown-grey so the visual hierarchy stays muted
  /// (medications shouldn't shout — they're contextual, not alerts).
  // Takes the palette: an enum has no element tree, but its colour
  // still has to follow brightness.
  Color color(V2Palette p) => switch (this) {
    PGItemType.supplement => p.accent,
    PGItemType.medication => p.monitor,
    PGItemType.bookmark => p.fgMuted,
  };

  /// Background tint at low opacity.
  // Takes the palette: an enum has no element tree, but its colour
  // still has to follow brightness.
  Color tint(V2Palette p) => switch (this) {
    PGItemType.supplement => p.accentTint,
    PGItemType.medication => p.monitorTint,
    PGItemType.bookmark => p.outline,
  };

  /// Foreground paired with [color] when the badge uses a solid fill.
  Color onColor(V2Palette p) => switch (this) {
    PGItemType.supplement => p.onAccent,
    PGItemType.medication => p.onMonitor,
    // Bookmark uses a neutral foreground as its fill. The resolved surface is
    // its high-contrast inverse in both modes.
    PGItemType.bookmark => p.surface,
  };
}

/// Tiny pill badge identifying a stack item as supplement / medication /
/// bookmark.
///
/// Designed to sit on top of (or beside) a product thumbnail. Compact —
/// icon + caps label — never the dominant element.
class PGTypeBadge extends StatelessWidget {
  final PGItemType type;

  /// Override the default label (e.g. "Rx", "OTC").
  final String? labelOverride;

  /// When true, renders with a heavier solid fill instead of the tinted
  /// background. Use for cases where the badge overlays a photo and
  /// needs more contrast.
  final bool solid;

  const PGTypeBadge({
    super.key,
    required this.type,
    this.labelOverride,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = type.color(context.v2);
    final tinted = context.v2.tintedLabel(color, borderAlpha: 0.25);
    final bg = solid ? color : tinted.fill;
    final fg = solid ? type.onColor(context.v2) : tinted.foreground;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: solid ? null : Border.all(color: tinted.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 10, color: fg),
          const SizedBox(width: V2Spacing.space4),
          Text(
            (labelOverride ?? type.label).toUpperCase(),
            style: V2Typography.overline(color: fg),
          ),
        ],
      ),
    );
  }
}
