// Transparency footer (Section 13).
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.14.
//
// Always-visible footer that surfaces the catalog freshness, this
// product's mapping coverage, the source institutions backing the
// data, and the educational-only disclaimer.
//
// Format (one block, multiple lines for readability):
//   Updated 2 days ago · Coverage: 15/20 · Sources: NIH · FDA · PubMed
//   PharmaGuide does not sell supplements. Educational only.
//
// The footer renders on every product page regardless of personal
// state — it's site-wide trust language, not personalized signal.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

/// Source institutions backing the catalog. Static — site-wide trust
/// language, not per-product. Order matches the spec.
const List<String> kTransparencySources = ['NIH', 'FDA', 'PubMed'];

/// Educational-only disclaimer. Static — must always render so the
/// user is never left guessing about scope.
const String kTransparencyDisclaimer =
    'PharmaGuide does not sell supplements. Educational only.';

/// Format the catalog `generated_at` timestamp as a human-readable
/// "last updated" line.
///
/// Within 7 days → relative ("Updated today", "Updated 2 days ago").
/// Older         → absolute ("Updated Apr 28").
/// Null input    → "Updated recently" (defensive — manifest read failed).
///
/// `now` is injectable for deterministic tests.
String formatRelativeUpdate(DateTime? buildDate, DateTime now) {
  if (buildDate == null) return 'Updated recently';

  final today = DateTime(now.year, now.month, now.day);
  final buildDay = DateTime(buildDate.year, buildDate.month, buildDate.day);
  final daysAgo = today.difference(buildDay).inDays;

  if (daysAgo <= 0) return 'Updated today';
  if (daysAgo == 1) return 'Updated yesterday';
  if (daysAgo < 7) return 'Updated $daysAgo days ago';

  // ≥ 7 days — flip to absolute "Apr 28" form for readability.
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Updated ${months[buildDate.month - 1]} ${buildDate.day}';
}

/// Format the coverage fraction as "n/total".
///
/// `mappedCoverage` is 0..1 (matches the field on `products_core`).
/// `totalIngredientCount` is the count of active ingredients on this
/// product — caller passes `activeIngredients.length`.
///
/// Returns `null` when either input is missing OR when total is 0
/// (no ingredients to cover, footer hides the coverage segment
/// rather than showing a divide-by-zero placeholder).
String? formatCoverage(double? mappedCoverage, int? totalIngredientCount) {
  if (mappedCoverage == null) return null;
  if (totalIngredientCount == null || totalIngredientCount <= 0) return null;
  // Clamp to [0..1] defensively — pipeline shouldn't ship outside this
  // band but a stale catalog might.
  final clamped = mappedCoverage.clamp(0.0, 1.0);
  final mapped = (clamped * totalIngredientCount).round();
  return 'Coverage: $mapped/$totalIngredientCount';
}

/// Always-visible footer for the product detail screen. Watches
/// [catalogInfoProvider] for the catalog freshness; consumes
/// `mappedCoverage` + `totalIngredientCount` for the per-product
/// coverage segment.
class TransparencyFooter extends ConsumerWidget {
  /// 0..1 fraction. Same value driving T1.4's coverage line.
  final double? mappedCoverage;

  /// Active-ingredient count for this product. Used together with
  /// [mappedCoverage] to render "Coverage: n/total".
  final int? totalIngredientCount;

  /// Override "now" for deterministic widget tests.
  final DateTime? nowOverride;

  const TransparencyFooter({
    super.key,
    required this.mappedCoverage,
    required this.totalIngredientCount,
    this.nowOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final catalogInfo = ref.watch(catalogInfoProvider).asData?.value;
    final now = nowOverride ?? DateTime.now();
    final updatedLine = formatRelativeUpdate(catalogInfo?.buildDate, now);
    final coverageLine = formatCoverage(mappedCoverage, totalIngredientCount);
    final sourcesLine = 'Sources: ${kTransparencySources.join(' · ')}';

    final segments = <String>[
      updatedLine,
      if (coverageLine != null) coverageLine,
      sourcesLine,
    ];
    final summary = segments.join(' · ');

    final smallStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space12,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary, style: smallStyle),
          const SizedBox(height: AppTheme.space4),
          Text(
            kTransparencyDisclaimer,
            style: smallStyle?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}
