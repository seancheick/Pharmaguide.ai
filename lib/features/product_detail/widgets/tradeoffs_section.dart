// Tradeoffs section (Section 5) — two-column "What's good / What to
// consider" replacement for the pre-T1.6 single-column "Highlights".
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.6.
//
// Pulls `score_bonuses[]` + `score_penalties[]` (already sanitized via
// T0.2's `sanitizeWhyDetail` upstream in `_extractWhyItems`) and splits
// them into a two-column pros/cons layout. Bullets-with-icons reads
// better than the pre-T1.6 single-column prose paragraph and the
// split itself reduces cognitive load — users scan the column they
// care about (good vs concerning) without having to read every entry.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Single pro/con record. Same shape as `_extractWhyItems` returns —
/// keep this in sync if the helper's record changes.
typedef TradeoffItem = ({String label, String detail, bool isPositive});

/// Maximum number of bullets rendered per column. Beyond this the
/// section adds an "… and N more concerns" muted footer (no chevron —
/// the section stays quiet by design). Per the T15 spec.
const int _maxTradeoffBulletsPerSide = 4;

/// Regex matching the "Harmful additive" prefix the pipeline emits on
/// score_penalties labels. Matches both `"Harmful additive Sugar syrup"`
/// (no colon — original T15 shape) and `"Harmful additive: Sugar syrup"`
/// (with colon — what the live pipeline now actually emits, caught by
/// Sean's 2026-04-30 walkthrough). Case-insensitive for drift tolerance.
final RegExp _harmfulAdditivePrefix = RegExp(
  r'^harmful additive[: ]\s*',
  caseSensitive: false,
);

/// Collapse all `"Harmful additive X"` items in [penalties] into a
/// single combined row at the front of the returned list. Non-matching
/// penalties pass through unchanged.
///
/// **Sean 2026-04-29:** "we don't need to keep repeating 'harmful
/// additive sugar syrup', 'harmful additive palm oil' — just put
/// 'additive sugar syrup, palm oil' with a comma."
///
/// **Sean 2026-04-30 (this revision):** drop the word "Harmful" — too
/// harsh, and the per-additive evidence carries the actual concern in
/// the inactives color-dot list. Use singular "Additive:" prefix for
/// the consolidated row even when multiple names follow (e.g.
/// "Additive: Modified Food Starch, Silicon Dioxide"). Also dedupe
/// names case-insensitively — pipeline sometimes emits a name twice
/// (e.g. duplicate "Modified Food Starch" entries from two source
/// fields), and the consolidated bullet shouldn't repeat.
///
/// Public so unit tests can pin the collapse contract directly.
List<TradeoffItem> collapseHarmfulAdditives(List<TradeoffItem> penalties) {
  final additiveNames = <String>[];
  final seen = <String>{};
  final remaining = <TradeoffItem>[];
  for (final item in penalties) {
    final label = item.label.trim();
    final match = _harmfulAdditivePrefix.firstMatch(label);
    if (match != null) {
      final name = label.substring(match.end).trim();
      final key = name.toLowerCase();
      if (name.isNotEmpty && seen.add(key)) {
        additiveNames.add(name);
      }
      continue;
    }
    remaining.add(item);
  }
  if (additiveNames.isEmpty) return penalties;
  final combined = (
    label: 'Additive: ${additiveNames.join(", ")}',
    detail: '',
    isPositive: false,
  );
  return [combined, ...remaining];
}

/// Tradeoffs section (Section 5).
///
/// Splits [items] into bonuses (`isPositive == true`) and penalties
/// (`isPositive == false`) and renders them in two columns:
///
///   👍 What's good          ⚖️ What to consider
///   • Third-party tested    • Contains proprietary blend
///   • Bioavailable forms    • Non-disclosed dose
///
/// Hide-when-empty rules per spec:
///
///   * Both lists empty  → section returns `SizedBox.shrink()`
///   * Only bonuses      → single-column "What's good" renders
///   * Only penalties    → single-column "What to consider" renders
///   * Both populated    → side-by-side two-column layout, with a
///                         responsive single-column fallback below
///                         a 380pt width breakpoint (SE-class
///                         devices) so each column has room to read.
/// Count of high- and moderate-severity inactives derived from the
/// pipeline's `inactive_ingredients[].severity_level`. Drives the
/// "What to consider" summary bullet.
class _InactiveSeverityCount {
  final int high;
  final int moderate;
  const _InactiveSeverityCount({required this.high, required this.moderate});

  int get total => high + moderate;

  /// 2026-04-30 — Sean's locked threshold:
  ///   trigger if (≥ 1 high) OR (≥ 3 moderate) OR (≥ 2 combined)
  ///
  /// Catches a single serious offender, a cluster of moderate concerns,
  /// AND mixed cases (1 high + 1 moderate, 2 moderate, etc.). Does NOT
  /// fire on `low`-only or empty.
  bool get shouldShowSummary => high >= 1 || moderate >= 3 || total >= 2;
}

_InactiveSeverityCount _countInactiveSeverity(
  List<Map<String, dynamic>> inactives,
) {
  var high = 0;
  var moderate = 0;
  for (final ing in inactives) {
    final raw = ing['severity_level'];
    final sev = raw is String ? raw.trim().toLowerCase() : '';
    if (sev == 'high') {
      high++;
    } else if (sev == 'moderate') {
      moderate++;
    }
  }
  return _InactiveSeverityCount(high: high, moderate: moderate);
}

class TradeoffsSection extends StatelessWidget {
  final List<TradeoffItem> items;

  /// 2026-04-30 — full inactive-ingredient rows from the pipeline blob.
  /// Used to derive the "N ingredients flagged for safety — review the
  /// list" summary bullet at the top of "What to consider" when the
  /// per-ingredient `severity_level` cluster crosses Sean's locked
  /// threshold. Empty / null → no summary bullet rendered. The bullet
  /// is informational only (no tap) — the dot-coded inactives list
  /// renders directly above this section, so "review the list" is a
  /// passive directive not an interactive affordance.
  final List<Map<String, dynamic>> inactiveIngredients;

  const TradeoffsSection({
    super.key,
    required this.items,
    this.inactiveIngredients = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Filter out blank-label entries (defensive — `_extractWhyItems`
    // shouldn't emit them, but pipeline drift could).
    final bonusesRaw = <TradeoffItem>[];
    final penaltiesRaw = <TradeoffItem>[];
    for (final item in items) {
      if (item.label.trim().isEmpty) continue;
      if (item.isPositive) {
        bonusesRaw.add(item);
      } else {
        penaltiesRaw.add(item);
      }
    }

    // T15 (2026-04-29 PM) — collapse "Harmful additive X" rows into a
    // single combined "Additives: X, Y, Z" row before capping. Bonuses
    // don't have an equivalent prefix pattern, so they pass through.
    final bonuses = bonusesRaw;
    final penalties = collapseHarmfulAdditives(penaltiesRaw);

    // 2026-04-30 — derive the "N ingredients flagged for safety —
    // review the list" summary bullet. Only built when the locked
    // threshold fires; otherwise null and the column renders normally.
    final severity = _countInactiveSeverity(inactiveIngredients);
    final summaryWidget = severity.shouldShowSummary
        ? _SafetySummaryBullet(
            count: severity.total,
            // Red dot when ANY high; orange when moderate-only.
            isHighSeverity: severity.high >= 1,
          )
        : null;

    if (bonuses.isEmpty && penalties.isEmpty && summaryWidget == null) {
      return const SizedBox.shrink();
    }

    // T15.1 — per-side cap is now enforced INSIDE `_TradeoffColumn`
    // so it can also drive the expand-in-place toggle. The section
    // just hands off the full lists; the column collapses to its
    // visible cap by default and reveals the rest on tap.

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Single-column fallback when:
          //   * Only one half has content (no point in two columns
          //     where one is permanently empty), OR
          //   * The card is narrower than 380pt (each column would
          //     have ~165pt of usable text width — too cramped for
          //     supplement labels with long branded names).
          // 2026-04-30 — `hasPenaltyContent` includes both regular
          // penalty bullets AND the new safety-summary leading bullet
          // (which can fire even on an otherwise-empty penalty side
          // for products with severe additives but no other quality
          // concerns).
          final hasPenaltyContent =
              penalties.isNotEmpty || summaryWidget != null;
          final stack =
              constraints.maxWidth < 380 ||
              bonuses.isEmpty ||
              !hasPenaltyContent;

          // T15.1 (2026-04-29 PM follow-up) — pass the FULL items
          // list plus the visible-cap so `_TradeoffColumn` can render
          // an expand-in-place toggle. Pre-T15.1 the section showed
          // "… and N concerns" as a static line, forcing the user to
          // scroll elsewhere to find what those concerns were.
          // Sean's call: "we should have a drop down to show more,
          // and list all there".
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bonuses.isNotEmpty) ...[
                  _TradeoffColumn(
                    title: '👍 What\'s good',
                    tone: AppTheme.severitySafe,
                    items: bonuses,
                    visibleCap: _maxTradeoffBulletsPerSide,
                    overflowSingularNoun: 'bonus',
                  ),
                  if (hasPenaltyContent)
                    const SizedBox(height: AppTheme.space12),
                ],
                if (hasPenaltyContent)
                  _TradeoffColumn(
                    title: '⚖️ What to consider',
                    tone: AppTheme.severityAvoid,
                    items: penalties,
                    visibleCap: _maxTradeoffBulletsPerSide,
                    overflowSingularNoun: 'concern',
                    leading: summaryWidget,
                  ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TradeoffColumn(
                  title: '👍 What\'s good',
                  tone: AppTheme.severitySafe,
                  items: bonuses,
                  visibleCap: _maxTradeoffBulletsPerSide,
                  overflowSingularNoun: 'bonus',
                ),
              ),
              const SizedBox(width: AppTheme.space16),
              Expanded(
                child: _TradeoffColumn(
                  title: '⚖️ What to consider',
                  tone: AppTheme.severityAvoid,
                  items: penalties,
                  visibleCap: _maxTradeoffBulletsPerSide,
                  overflowSingularNoun: 'concern',
                  leading: summaryWidget,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One side of the tradeoffs split — the column header + the list of
/// pro/con rows. Public-private (lives in the same file as
/// [TradeoffsSection]) so the widget tree stays self-contained.
/// Naive English pluralizer used by the "Show N more X" toggle copy.
/// Handles the two nouns this widget passes:
///   - `'concern'` → `'concerns'`
///   - `'bonus'`   → `'bonuses'`
/// Anything ending in 's', 'x', 'z' or 'sh'/'ch' takes 'es'; else 's'.
/// Adequate for the small fixed vocabulary; not a general pluralizer.
String _pluralize(String singular) {
  final lower = singular.toLowerCase();
  if (lower.endsWith('s') ||
      lower.endsWith('x') ||
      lower.endsWith('z') ||
      lower.endsWith('sh') ||
      lower.endsWith('ch')) {
    return '${singular}es';
  }
  return '${singular}s';
}

/// Single tradeoff column — stateful so the "Show N more / Show
/// less" toggle can flip the rendered slice without rebuilding the
/// section. T15.1 (2026-04-29 PM follow-up) — pre-fix the column was
/// stateless with a static "… and N more" footer; Sean's walkthrough:
/// *"if it goes over few line, we should have a drop down to show
/// more, and list all there, easier than scrolling somewhere else
/// to read."*
class _TradeoffColumn extends StatefulWidget {
  final String title;
  final Color tone;
  final List<TradeoffItem> items;

  /// Maximum items to show in the collapsed state. The toggle reveals
  /// the rest in place when the user taps. Defaults match the section
  /// constant so callers don't need to import it.
  final int visibleCap;

  /// Singular noun for the toggle copy (e.g., `'more'` for bonuses,
  /// `'concern'` for penalties). Pluralized as needed.
  final String overflowSingularNoun;

  /// Optional widget rendered above the bullet list (after the title).
  /// Used by 2026-04-30's safety-summary bullet on the penalties side.
  final Widget? leading;

  const _TradeoffColumn({
    required this.title,
    required this.tone,
    required this.items,
    this.visibleCap = _maxTradeoffBulletsPerSide,
    this.overflowSingularNoun = 'more',
    this.leading,
  });

  @override
  State<_TradeoffColumn> createState() => _TradeoffColumnState();
}

class _TradeoffColumnState extends State<_TradeoffColumn> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overflow = widget.items.length - widget.visibleCap;
    // When expanded → render every item. When collapsed → render up
    // to the cap. `take` is safe when cap >= length.
    final visible = _expanded
        ? widget.items
        : widget.items.take(widget.visibleCap).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: widget.tone,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        if (widget.leading != null) ...[
          widget.leading!,
          if (visible.isNotEmpty) const SizedBox(height: 6),
        ],
        for (final item in visible)
          TradeoffRow(
            label: item.label,
            detail: item.detail,
            tone: widget.tone,
          ),
        // T15.1 — tappable expand-in-place toggle. Collapsed copy:
        // "Show N more concerns ⌄". Expanded: "Show less ⌃". Reveals
        // the rest of the items inline so the user doesn't have to
        // scroll elsewhere to read them.
        if (overflow > 0) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              // Padding makes the tap target reach the row edges so
              // the user doesn't have to land precisely on the text.
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded
                        ? 'Show less'
                        : (overflow == 1
                              ? 'Show 1 more ${widget.overflowSingularNoun}'
                              : 'Show $overflow more '
                                    '${_pluralize(widget.overflowSingularNoun)}'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Single tradeoff row — colored bullet + label + optional detail
/// subline. Public so it can be reused in other surfaces if T1.x
/// adds more pro/con rendering (T1.7 interactions, T1.10 evidence).
class TradeoffRow extends StatelessWidget {
  final String label;
  final String detail;
  final Color tone;

  const TradeoffRow({
    super.key,
    required this.label,
    required this.detail,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 2026-04-30 — top-of-"What to consider" summary bullet driven by the
/// pipeline's per-inactive `severity_level`. Rendered as a leading row
/// in the penalties column when [_InactiveSeverityCount.shouldShowSummary]
/// returns true.
///
/// Visual cue:
///   - 🔴 red dot when ANY high-severity additive is present
///   - 🟠 orange dot when only moderate-severity additives are present
///
/// Copy is locked: "N ingredients flagged for safety — review the
/// list" (Sean 2026-04-30). Informational only — no tap. The dot-coded
/// inactives list renders directly above this section, so "review the
/// list" is a passive directive.
class _SafetySummaryBullet extends StatelessWidget {
  final int count;

  /// `true` when `≥ 1 high` additives present → render with red dot.
  /// `false` when moderate-only → orange dot.
  final bool isHighSeverity;

  const _SafetySummaryBullet({
    required this.count,
    required this.isHighSeverity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotColor = isHighSeverity
        ? AppTheme.severityContraindicated
        : AppTheme.severityAvoid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count ingredients flagged for safety — review the list',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
