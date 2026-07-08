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
  final hasStructuredAllergens = _hasStructuredAllergens(blob['allergens']);
  for (final key in const ['warnings', 'warnings_profile_gated']) {
    final raw = blob[key];
    if (raw is! List) continue;
    final candidates = raw.whereType<Map<String, dynamic>>().where(
      (warning) =>
          !_isLegacyProductStatusWarning(
            warning,
            hasStructuredProductStatus: hasStructuredProductStatus,
          ) &&
          !_isStructuredAllergenDuplicate(
            warning,
            hasStructuredAllergens: hasStructuredAllergens,
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

bool _hasStructuredAllergens(Object? raw) {
  if (raw is! List) return false;
  // "Structured present" MUST mean the matcher can actually use it:
  // matchAllergens keys strictly on a non-empty `allergen_id`. Treating a
  // display_name-only entry as structured would drop the legacy allergen
  // warning (see _isStructuredAllergenDuplicate) with nothing to replace it
  // — a silent allergen miss for a sensitized user. Require a usable id.
  return raw.whereType<Map<Object?, Object?>>().any((entry) {
    final id = entry['allergen_id']?.toString().trim();
    return id != null && id.isNotEmpty;
  });
}

/// Drop legacy allergen warning rows once the structured `allergens[]`
/// contract is present. Structured allergens are profile-matched via
/// `matchAllergens(profile.allergens, blob.allergens)`. Keeping the
/// duplicate warning row here makes "Allergen: X" show for users who
/// explicitly declared no allergies.
bool _isStructuredAllergenDuplicate(
  Map<String, dynamic> warning, {
  required bool hasStructuredAllergens,
}) {
  if (!hasStructuredAllergens) return false;
  final tokens = [
    warning['type'],
    warning['source'],
    warning['category'],
    warning['warning_type'],
  ].map((value) => value?.toString().trim().toLowerCase() ?? '');
  return tokens.contains('allergen') || tokens.contains('allergen_db');
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

/// Split guarded warnings into the ones that belong in the
/// "Review for your profile" card vs. global/educational notes.
///
/// A warning stays in the profile bucket when it is a hard safety warning
/// (contraindicated / avoid) OR it actually fires for the current profile
/// ([InteractionWarning.matchesProfile]) AND is actionable (caution / monitor —
/// severities that carry a real penalty).
///
/// Everything else moves to [general]: unmatched "if you have X…" notes, and —
/// even when the profile matches — informational / safe rows, which are neutral
/// context or positive notes (e.g. "B12 recommended preconception"). This keeps
/// the profile card and its "N things to review" count focused on what actually
/// needs attention, not benefits or FYIs.
({List<InteractionWarning> profile, List<InteractionWarning> general})
partitionProfileWarnings({
  required List<InteractionWarning> warnings,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  required Set<String> userProfileFlags,
}) {
  final profile = <InteractionWarning>[];
  final general = <InteractionWarning>[];
  for (final w in warnings) {
    final matched = w.matchesProfile(
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
      userProfileFlags: userProfileFlags,
    );
    final isHard =
        w.severity == Severity.contraindicated || w.severity == Severity.avoid;
    // Only actionable severities (caution / monitor — a real, if mild,
    // negative signal) count as "review before use". Informational / safe
    // rows carry no penalty: they are neutral context or positive notes
    // (e.g. "B12 recommended preconception", "may support PCOS-related
    // fertility") and move to the calm general surface even when the profile
    // matches, so the "N things to review" count reflects only what needs
    // attention. Hard warnings always surface regardless of profile.
    // Critical-mode caution rows with no profile gate (for example product
    // quality additives such as P80) remain visible, but in the general surface
    // instead of inflating "Review for your profile".
    final isActionable =
        w.severity == Severity.caution || w.severity == Severity.monitor;
    if (isHard || (matched && isActionable)) {
      profile.add(w);
    } else {
      general.add(w);
    }
  }
  return (profile: profile, general: general);
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
