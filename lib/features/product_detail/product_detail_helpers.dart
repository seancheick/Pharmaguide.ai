// Pure helpers extracted from the (now-deleted) legacy
// `product_detail_screen.dart` during the Phase 11.11 hygiene pass.
// Both the v2 product detail screen and the test suite depend on
// these functions; keeping them top-level here keeps them
// widget-independent and unit-testable without pumping a screen.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/features/product_detail/dose_safety.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

// ---------------------------------------------------------------------------
// `topGoalLabelFromFit`
//
// Extracts the user-facing goal label from a FitScoreResult's `reasons`
// list for the "For You" section's verdict headline copy.
//
// Pattern note: `(.+?)` is non-greedy and matches ANY character
// (including `/`, `&`, `,`) so labels like "Reduce Stress/Anxiety",
// "Focus & Mental Clarity", and "Skin, Hair, & Nails" all extract
// cleanly. Anchoring on `\s+goal\b` ensures the boundary is the
// literal word "goal", not a substring like "goalkeeper".
//
// Returns null when no reason matches the pattern.
// ---------------------------------------------------------------------------

String? topGoalLabelFromFit(FitScoreResult? result) {
  if (result == null) return null;
  final pattern = RegExp(r'your\s+(.+?)\s+goal\b', caseSensitive: false);
  for (final reason in result.reasons) {
    final m = pattern.firstMatch(reason);
    if (m != null) {
      final label = m.group(1)?.trim();
      if (label != null && label.isNotEmpty) return label;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// `filterProductDetailWarningsForProfile`
//
// Product-detail warning gate shared by the top "For You" card and the
// deeper warning stack. Profile-tagged rules only render when the
// active profile matches; global critical/informational warnings still
// render without a profile match. Product-level UL exceedance warnings
// are synthesized here because they live under `rda_ul_data`, not the
// top-level warning lists.
// ---------------------------------------------------------------------------

List<InteractionWarning> filterProductDetailWarningsForProfile({
  required Map<String, dynamic>? detailBlob,
  required List<InteractionWarning> warnings,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  Set<String> userProfileFlags = const <String>{},
}) {
  final combinedWarnings = [..._synthesizeUlWarnings(detailBlob), ...warnings];

  // Apply (condition, ingredient, dose) threshold gating BEFORE the
  // profile-visibility filter. Drops false-positive condition monitor
  // warnings the pipeline emits without dose awareness (Vit D + TTC,
  // Mg + diabetes, etc.). UL warnings carry no conditionIds so they
  // pass through untouched.
  final ingredientDoses = extractIngredientDoses(detailBlob);
  final gatedWarnings = applyConditionThresholdGate(
    warnings: combinedWarnings,
    ingredientDoses: ingredientDoses,
  );

  // Emitted-floor gate: drop rows the pipeline marked immaterial at this
  // product's dose (harmful + dose_dependent + below its form-scoped floor),
  // before the profile filter can promote them back (G2).
  final flooredWarnings = applyEmittedFloorGate(gatedWarnings);

  return flooredWarnings
      .where((w) {
        if (w.matchesProfile(
          userConditions: userConditions,
          userDrugClasses: userDrugClasses,
          userProfileFlags: userProfileFlags,
        )) {
          return true;
        }

        // Profile-tagged rules are never promoted to global alerts
        // when the current user does not match them. This prevents
        // pregnancy, kidney, and medication warnings from reading as
        // personal guidance for the wrong profile even if an older
        // blob marked them critical.
        if (w.conditionIds.isNotEmpty || w.drugClassIds.isNotEmpty) {
          return false;
        }

        final mode = w.displayModeDefault;
        if (mode == 'critical' || mode == 'informational') return true;
        if (mode == 'suppress') return false;

        // Legacy blobs predating display_mode_default had no explicit
        // gate. Untagged legacy warnings remain visible for backward
        // compatibility.
        return true;
      })
      .toList(growable: false);
}

List<InteractionWarning> _synthesizeUlWarnings(Map<String, dynamic>? blob) {
  final rdaUlData = blob?['rda_ul_data'];
  if (rdaUlData is! Map) return const [];
  final ulAnalysis = rdaUlData['analyzed_ingredients'];
  if (ulAnalysis is! List) return const [];
  final ulExceedances = extractUlExceedances(ulAnalysis);
  return ulExceedances
      .map(
        (e) => InteractionWarning(
          severity: Severity.avoid,
          evidenceLevel: EvidenceLevel.established,
          title: 'Exceeds upper limit: ${e.standardName}',
          mechanism: e.warning,
          management: 'Reduce dose or consult a healthcare provider.',
          displayModeDefault: 'critical',
        ),
      )
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// `sanitizeWhyDetail`
//
// Strip noisy numeric or "Tier N" detail strings emitted by the
// pipeline (e.g. `score_bonuses[i].detail == "3"` for the delivery
// tier). The user can't interpret a bare number under a label like
// "Advanced delivery system" — it reads as a bug.
//
// Returns an empty string when the input is null, blank, a bare
// integer, or "Tier N" (case-insensitive). Otherwise returns the
// trimmed input unchanged.
// ---------------------------------------------------------------------------

final RegExp _whyDetailNoise = RegExp(
  r'^(?:\d+|tier\s+\d+)$',
  caseSensitive: false,
);

String sanitizeWhyDetail(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (_whyDetailNoise.hasMatch(trimmed)) return '';
  return trimmed;
}
