import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One caveat row in the label-confidence card. Caller composes from the
/// pipeline blob (production parses `productStatus`, `unmappedActives`,
/// `hasProprietaryBlends`, `mappedCoverage`, `isNotScored` separately
/// and emits a `_Row` per signal — v2 takes the rows directly).
class PGLabelConfidenceItem {
  final IconData icon;
  final String title;
  final String body;

  /// Optional second-line detail string (e.g. for recall date / FDA
  /// reference). Production renders this in a smaller text below the body.
  final String? detail;

  /// Tap → opens production's product-status explanation bottom sheet.
  final VoidCallback? onTap;

  const PGLabelConfidenceItem({
    required this.icon,
    required this.title,
    required this.body,
    this.detail,
    this.onTap,
  });
}

/// v2 label-confidence card.
///
/// **Same intent preserved:**
/// - Calm caveat block — never red, even when signals are concerning
/// - Header tier label drives the icon tone (caution amber when there's
///   incomplete data; muted grey when it's just a note-tier signal)
/// - List of items beneath the header, separated by hairlines
/// - Each item: icon + title + body, optionally + detail line + tap
///
/// **What changes in v2:**
/// - Surface: cream + outline + sm (no shadow — this card sits between
///   denser cards and shouldn't compete visually)
/// - Typography: Geist Sans 500 for the header + item titles, body
///   for the explanation copy
/// - Item rows use 0.4pt hairlines (matches PGInactiveRow indented
///   hairline pattern)
class PGLabelConfidenceCard extends StatelessWidget {
  /// Header copy. Production composes from tier:
  ///   - note tier         → "Product note"
  ///   - low-confidence    → "Limited data — partial coverage"
  ///   - missing-data      → "Missing data — score may be incomplete"
  /// Caller builds the string; widget renders it.
  final String header;

  /// When true, the header icon + title render in caution-amber tone.
  /// When false (note tier), render in muted grey.
  final bool isCaution;

  /// Caveat items. Empty → card hides entirely (production behavior:
  /// `hasAnySignal` returns false → SizedBox.shrink).
  final List<PGLabelConfidenceItem> items;

  const PGLabelConfidenceCard({
    super.key,
    required this.header,
    required this.items,
    this.isCaution = true,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final tone = isCaution ? context.v2.caution : context.v2.fgMuted;

    return Container(
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space16,
              vertical: V2Spacing.space12,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: tone),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Text(
                    header,
                    style: V2Typography.bodyMedium(color: context.v2.fg),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: context.v2.outline, height: 1, thickness: 0.5),
          for (var i = 0; i < items.length; i++)
            _LabelConfidenceRow(item: items[i], isLast: i == items.length - 1),
        ],
      ),
    );
  }
}

class _LabelConfidenceRow extends StatelessWidget {
  final PGLabelConfidenceItem item;
  final bool isLast;

  const _LabelConfidenceRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space16,
        vertical: V2Spacing.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 18, color: context.v2.fgMuted),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: V2Typography.bodyMedium(color: context.v2.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  item.body,
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                ),
                if (item.detail != null) ...[
                  const SizedBox(height: V2Spacing.space4),
                  Text(
                    item.detail!,
                    style: V2Typography.caption(color: context.v2.fgSubtle),
                  ),
                ],
              ],
            ),
          ),
          if (item.onTap != null) ...[
            const SizedBox(width: V2Spacing.space8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.v2.fgMuted,
            ),
          ],
        ],
      ),
    );

    final wrapped = item.onTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(onTap: item.onTap, child: row),
          )
        : row;

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: context.v2.outline, width: 0.4),
              ),
      ),
      child: wrapped,
    );
  }
}
