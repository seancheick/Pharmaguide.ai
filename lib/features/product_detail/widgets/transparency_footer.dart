// Transparency footer (Section 13).
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.14 +
// INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T21.
//
// Always-visible footer that surfaces the catalog freshness, the
// source institutions backing the data, and the educational-only
// disclaimer.
//
// Format (post-T21):
//   Updated 2 days ago
//   Sources: NIH · FDA · PubMed
//   Educational use only — not medical advice.
//
// **T21 (2026-04-30) — cleanup:**
//   - Removed `Coverage: n/total` segment (was redundant with
//     §6 "What we don't know" coverage callout above the fold).
//   - Disclaimer rephrased to "Educational use only — not medical
//     advice." (was "PharmaGuide does not sell supplements.
//     Educational only." — the new copy is shorter and direct).
//   - Removed italic styling everywhere — the footer reads as plain
//     trust language, not a legal aside.

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
    'Educational use only — not medical advice.';

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

/// Always-visible footer for the product detail screen. Watches
/// [catalogInfoProvider] for the catalog freshness.
///
/// **T21 (2026-04-30):** dropped `mappedCoverage` /
/// `totalIngredientCount` ctor params (were used for the deleted
/// "Coverage: n/total" segment).
class TransparencyFooter extends ConsumerWidget {
  /// Override "now" for deterministic widget tests.
  final DateTime? nowOverride;

  const TransparencyFooter({super.key, this.nowOverride});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final catalogInfo = ref.watch(catalogInfoProvider).asData?.value;
    final now = nowOverride ?? DateTime.now();
    final updatedLine = formatRelativeUpdate(catalogInfo?.buildDate, now);
    final sourcesLine = 'Sources: ${kTransparencySources.join(' · ')}';

    // T21 — single style across all three lines. No italic, no
    // coverage segment, three discrete rows for scan-readability.
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
          Text(updatedLine, style: smallStyle),
          const SizedBox(height: 2),
          Text(sourcesLine, style: smallStyle),
          const SizedBox(height: AppTheme.space4),
          Text(kTransparencyDisclaimer, style: smallStyle),
        ],
      ),
    );
  }
}
