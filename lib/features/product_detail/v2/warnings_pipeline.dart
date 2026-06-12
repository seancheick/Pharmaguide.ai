// Phase 11.7b.1 — Product Detail v2 warning compose pipeline.
//
// Pure functions that combine the 2 warning sources (personalized DB
// + blob-static) into the single `guardedWarnings` list every Product
// Detail surface consumes. No Riverpod, no BuildContext — designed to
// be unit-tested by passing canned inputs.
//
// Mirrors production's inline pipeline in
// `_ProductDetailScreenState.build` lines 194–225 verbatim:
//   1. Parse blob warnings (drop legacy product-status entries, dedupe)
//   2. Merge personalized + blob, dedup by composite key (personalized
//      wins on collision)
//   3. Apply `filterProductDetailWarningsForProfile` — the shared
//      profile / UL / threshold gate
//
// Phase 11.11 will also extract `filterProductDetailWarningsForProfile`
// from into this same module so the heavy
// transitive import disappears. For now we import the production
// top-level fn as-is.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart'
    show filterProductDetailWarningsForProfile;
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Compose the warning list every Product Detail surface renders.
///
/// Returns the same `guardedWarnings` list production passes to
/// ReviewBeforeUseCard, the For-You section, and BetterAlternatives.
List<InteractionWarning> composeGuardedWarnings({
  required Map<String, dynamic>? detailBlob,
  required List<InteractionWarning> personalizedWarnings,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  required Set<String> userProfileFlags,
}) {
  final blobWarnings = parseBlobWarnings(detailBlob);
  // Dedup composite: (severity, mechanism). Personalized wins because
  // it carries live DB context (active stack matches, dose-aware
  // thresholds) the static blob can't know about.
  final seenKeys = <String>{
    for (final w in personalizedWarnings) '${w.severity.name}:${w.mechanism}',
  };
  final merged = <InteractionWarning>[
    ...personalizedWarnings,
    ...blobWarnings.where(
      (w) => !seenKeys.contains('${w.severity.name}:${w.mechanism}'),
    ),
  ];
  return filterProductDetailWarningsForProfile(
    detailBlob: detailBlob,
    warnings: merged,
    userConditions: userConditions,
    userDrugClasses: userDrugClasses,
    userProfileFlags: userProfileFlags,
  );
}

/// Drain the blob's `warnings` + `warnings_profile_gated` lists, drop
/// legacy product-status entries when structured product status is
/// present, dedupe via the InteractionWarning composite-key rule.
///
/// Copied verbatim from production's `_parseWarnings` private method.
/// Phase 11.11 dedupes both copies into this single source.
List<InteractionWarning> parseBlobWarnings(Map<String, dynamic>? blob) {
  if (blob == null) return const [];
  final result = <InteractionWarning>[];
  final hasStructuredProductStatus = blob['product_status'] is Map;
  for (final key in const ['warnings', 'warnings_profile_gated']) {
    final raw = blob[key];
    if (raw is! List) continue;
    final candidates = raw.whereType<Map<String, dynamic>>().where(
      (warning) => !_isLegacyProductStatusWarning(
        warning,
        hasStructuredProductStatus: hasStructuredProductStatus,
      ),
    );
    // Parse per-element so one malformed blob entry can't throw away
    // every other (valid) warning in the list. A skipped entry is
    // recorded to Sentry; the rest of the warnings still render.
    for (final warning in candidates) {
      try {
        result.add(InteractionWarning.fromJson(warning));
      } on Object catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'warnings_pipeline:skip_malformed',
        );
      }
    }
  }
  return InteractionWarning.dedupe(result);
}

/// Drop "status" entries that predate structured `product_status`.
/// When the blob carries structured product_status, the legacy
/// free-text status warnings duplicate what the structured surface
/// renders elsewhere. Mirrors production's
/// `_isLegacyProductStatusWarning` private method.
bool _isLegacyProductStatusWarning(
  Map<String, dynamic> warning, {
  required bool hasStructuredProductStatus,
}) {
  if (!hasStructuredProductStatus) return false;
  final tokens = [
    warning['type'],
    warning['source'],
    warning['category'],
    warning['warning_type'],
  ].map((value) => value?.toString().trim().toLowerCase() ?? '');
  return tokens.contains('status') || tokens.contains('product_status');
}

/// Worst-case severity across a warning list. Empty list returns
/// `Severity.safe` (the no-issues baseline). Used by For-You section
/// to gate the risk surface + by BetterAlternatives to compute fit
/// display verdict.
Severity worstSeverityOf(List<InteractionWarning> warnings) {
  Severity worst = Severity.safe;
  for (final w in warnings) {
    if (w.severity.weight > worst.weight) worst = w.severity;
  }
  return worst;
}
