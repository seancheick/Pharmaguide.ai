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
class TradeoffsSection extends StatelessWidget {
  final List<TradeoffItem> items;
  const TradeoffsSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    // Filter out blank-label entries (defensive — `_extractWhyItems`
    // shouldn't emit them, but pipeline drift could).
    final bonuses = <TradeoffItem>[];
    final penalties = <TradeoffItem>[];
    for (final item in items) {
      if (item.label.trim().isEmpty) continue;
      if (item.isPositive) {
        bonuses.add(item);
      } else {
        penalties.add(item);
      }
    }

    if (bonuses.isEmpty && penalties.isEmpty) {
      return const SizedBox.shrink();
    }

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
          final stack = constraints.maxWidth < 380 ||
              bonuses.isEmpty ||
              penalties.isEmpty;

          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bonuses.isNotEmpty) ...[
                  _TradeoffColumn(
                    title: '👍 What\'s good',
                    tone: AppTheme.severitySafe,
                    items: bonuses,
                  ),
                  if (penalties.isNotEmpty)
                    const SizedBox(height: AppTheme.space12),
                ],
                if (penalties.isNotEmpty)
                  _TradeoffColumn(
                    title: '⚖️ What to consider',
                    tone: AppTheme.severityAvoid,
                    items: penalties,
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
                ),
              ),
              const SizedBox(width: AppTheme.space16),
              Expanded(
                child: _TradeoffColumn(
                  title: '⚖️ What to consider',
                  tone: AppTheme.severityAvoid,
                  items: penalties,
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
class _TradeoffColumn extends StatelessWidget {
  final String title;
  final Color tone;
  final List<TradeoffItem> items;

  const _TradeoffColumn({
    required this.title,
    required this.tone,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: tone,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        for (final item in items)
          TradeoffRow(
            label: item.label,
            detail: item.detail,
            tone: tone,
          ),
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
              decoration: BoxDecoration(
                color: tone,
                shape: BoxShape.circle,
              ),
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
