import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Banner tone for the review-before-use card. Mirrors production
/// `PGBannerTone` (lib/core/widgets/pg_severity_banner.dart) — same
/// severity-driven palette, just consumed by v2 layout.
enum PGReviewTone {
  /// "Looks safe for you" — green tint, no urgency.
  safe,

  /// "Review before use" — amber, low-severity warnings or unmatched
  /// signals worth flagging.
  caution,

  /// "Review before use" — red, contraindicated or allergen match.
  danger,

  /// Neutral, used when only informational free-from claims surface
  /// (e.g., "Gluten free claim present" with no conflicts).
  info,
}

extension PGReviewToneMeta on PGReviewTone {
  Color get tint => switch (this) {
        PGReviewTone.safe => AppTheme.severitySafe,
        PGReviewTone.caution => AppTheme.severityCaution,
        PGReviewTone.danger => AppTheme.severityContraindicated,
        PGReviewTone.info => AppTheme.severityInformational,
      };

  IconData get icon => switch (this) {
        PGReviewTone.safe => Icons.check_circle_outline,
        PGReviewTone.caution => Icons.error_outline_rounded,
        PGReviewTone.danger => Icons.warning_amber_rounded,
        PGReviewTone.info => Icons.info_outline_rounded,
      };
}

/// One row in the review card — a matched allergen, free-from conflict,
/// or generic precaution. Caller composes these from the same providers
/// production uses (`allergen_match.dart`, `free_from_match.dart`,
/// interaction warnings).
class PGReviewRow {
  /// Bullet headline, e.g. "Contains gluten" or "Citrate may interact
  /// with quinolone antibiotics".
  final String headline;

  /// Optional second-line caption ("Allergen · matched from your profile").
  final String? caption;

  /// Tone for the leading icon. Defaults to the parent banner's tone.
  final PGReviewTone? rowTone;

  /// Optional tap handler — production opens an explain sheet or
  /// citations modal.
  final VoidCallback? onTap;

  const PGReviewRow({
    required this.headline,
    this.caption,
    this.rowTone,
    this.onTap,
  });
}

/// v2 mirror of `ReviewBeforeUseCard`
/// (lib/features/product_detail/widgets/review_before_use_card.dart).
///
/// **Same intent preserved:**
/// - One severity-toned banner block at the top of the card
/// - Title is count-aware ("Review before use" with N count badge, or
///   "Looks safe for you" when zero matches)
/// - Body line below the title (caller-supplied — production uses
///   `interactionHint` for the warning count summary)
/// - Optional rows of matched allergens / free-from conflicts /
///   generic warnings — each tappable
/// - Expand/collapse chevron when more than [collapseThreshold] rows
///
/// **Production parity rules:**
/// - Allergen match always bumps tone to `danger` even with a free-from
///   claim present (matches production line 170).
/// - Card flips to the calm `safe` tone when there are 0 rows.
/// - Count badge in the title uses the banner tone's tint background.
class PGReviewBeforeUseCard extends StatefulWidget {
  /// Banner tone — caller composes via the same severity rules
  /// production uses (allergen match wins > danger; free-from conflict
  /// alone → caution; clean → safe).
  final PGReviewTone tone;

  /// Header title — production uses "Review before use" / "Looks safe".
  final String title;

  /// 1-line body under the title — caller can pass interactionHint
  /// ("3 interactions need review") or a tone-specific summary.
  final String? body;

  /// All review rows (allergens + free-from + warnings). Empty list
  /// hides the row section entirely (only the banner shows).
  final List<PGReviewRow> rows;

  /// Threshold above which the row list collapses behind a "View N more"
  /// expander. Default 3 — matches production's "show top 3" pattern.
  final int collapseThreshold;

  /// True to start expanded regardless of collapse threshold. Production
  /// auto-expands when ≥1 row is danger-tier.
  final bool startExpanded;

  const PGReviewBeforeUseCard({
    super.key,
    required this.tone,
    required this.title,
    this.body,
    this.rows = const [],
    this.collapseThreshold = 3,
    this.startExpanded = false,
  });

  @override
  State<PGReviewBeforeUseCard> createState() => _PGReviewBeforeUseCardState();
}

class _PGReviewBeforeUseCardState extends State<PGReviewBeforeUseCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.startExpanded ||
        widget.rows.length <= widget.collapseThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone.tint;
    final rows = widget.rows;
    final overflow = rows.length - widget.collapseThreshold;
    final canCollapse = !_expanded && rows.length > widget.collapseThreshold;
    final visible = canCollapse
        ? rows.take(widget.collapseThreshold).toList(growable: false)
        : rows;

    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tone-tinted banner header (3pt left accent strip — matches
          // PGSeverityBanner pattern from lib/core/widgets/
          // pg_severity_banner.dart).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(V2Spacing.radiusCard),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(V2Spacing.space16),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.06),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(V2Spacing.radiusCard),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(widget.tone.icon, size: 20, color: tone),
                        const SizedBox(width: V2Spacing.space8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      style: V2Typography.titleSm(
                                        color: V2Colors.fg,
                                      ),
                                    ),
                                  ),
                                  if (rows.isNotEmpty)
                                    _CountBadge(
                                      count: rows.length,
                                      tone: tone,
                                    ),
                                ],
                              ),
                              if (widget.body != null) ...[
                                const SizedBox(height: V2Spacing.space4),
                                Text(
                                  widget.body!,
                                  style: V2Typography.bodySm(
                                    color: V2Colors.fgMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (rows.isNotEmpty) ...[
            const Divider(
              color: V2Colors.outline,
              height: 1,
              thickness: 0.5,
            ),
            ...[
              for (var i = 0; i < visible.length; i++)
                _ReviewRowTile(
                  row: visible[i],
                  fallbackTone: widget.tone,
                  isLast: i == visible.length - 1 && !canCollapse,
                ),
            ],
            if (canCollapse)
              InkWell(
                onTap: () => setState(() => _expanded = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.space16,
                    vertical: V2Spacing.space12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'View $overflow more',
                        style: V2Typography.label(color: V2Colors.accent),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: V2Colors.accent,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReviewRowTile extends StatelessWidget {
  final PGReviewRow row;
  final PGReviewTone fallbackTone;
  final bool isLast;

  const _ReviewRowTile({
    required this.row,
    required this.fallbackTone,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final tone = (row.rowTone ?? fallbackTone).tint;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: row.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space16,
            vertical: V2Spacing.space12,
          ),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(
                    bottom: BorderSide(color: V2Colors.outline, width: 0.4),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                (row.rowTone ?? fallbackTone).icon,
                size: 18,
                color: tone,
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.headline,
                      style: V2Typography.bodyMedium(color: V2Colors.fg),
                    ),
                    if (row.caption != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        row.caption!,
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (row.onTap != null) ...[
                const SizedBox(width: V2Spacing.space8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: V2Colors.fgMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Color tone;
  const _CountBadge({required this.count, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        '$count',
        style: V2Typography.overline(color: tone).copyWith(
          fontSize: 11,
          letterSpacing: 0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
