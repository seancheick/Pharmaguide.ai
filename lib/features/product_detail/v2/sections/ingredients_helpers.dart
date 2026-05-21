// Ingredients helpers (pure mapping).
//
//   raw active map → PGActiveIngredient
//     name           = display_label || standard_name || name || raw_source_text
//     dose           = display_dose_label OR (quantity + unit fallback)
//     formLabel      = display_form_label (only when form_status == 'known')
//     formQuality    = resolveFormQuality(bio_score)
//     doseCallOut    = resolveDoseCallOut(ingredient, ulEntry)
//     isSafetyConcern = ingredient['is_safety_concern'] == true
//     isInferredFromLabel = ingredient['display_type'] == 'inferred_from_label'
//
//   raw inactive map → PGInactiveIngredient
//     name        = display_label || name || raw_source_text
//     tone        = inactiveColorRank(map) — verbatim port
//     roleHelper  = display_role_label OR comma-joined functional_roles[]
//                   (capped at 2 roles)
//
// Sean's rules (2026-05-15):
//   • Preserve provider logic verbatim. No new clinical language.
//   • Production helpers (resolveFormQuality / resolveDoseCallOut /
//     matchUlEntry / sortActivesForDisplay / inactiveColorRank /
//     groupActivesByBlend) are imported, NOT reimplemented.
//   • Active/inactive patterns preserved (Sean's specific call):
//     * Active list collapsible header with auto-expand ≤5
//     * Inactive list collapsible header with auto-expand ≤5
//     * Active sort: disclosed-dose → blend buckets → undisclosed (FLTR-9)
//     * Inactive color dots via `inactiveColorRank`

import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

/// Convert a raw active-ingredient map into a typed [PGActiveIngredient].
///
/// [ulEntry] is the matched UL analysis entry produced by
/// `matchUlEntry(ingredient, ulAnalysis)` from `dose_safety.dart`. Pass
/// null when the blob lacks `rda_ul_data.analyzed_ingredients`.
PGActiveIngredient activeFromMap(
  Map<String, dynamic> ingredient, {
  Map<String, dynamic>? ulEntry,
}) {
  // Name resolution — matches production lines 142–148 of
  // ingredient_explain_model.dart's `buildIngredientExplain`.
  final displayLabel = ingredient['display_label']?.toString().trim();
  final name = (displayLabel != null && displayLabel.isNotEmpty)
      ? displayLabel
      : (ingredient['standard_name']?.toString() ??
            ingredient['name']?.toString() ??
            ingredient['raw_source_text']?.toString() ??
            '');

  // Dose label — production canonical contract (display_dose_label)
  // with quantity+unit fallback for stale blobs.
  final displayDoseLabel = ingredient['display_dose_label']?.toString().trim();
  final doseStatus = ingredient['dose_status']?.toString();
  String? dose;
  if (displayDoseLabel != null && displayDoseLabel.isNotEmpty) {
    dose = displayDoseLabel;
  } else if (doseStatus == 'missing' || doseStatus == 'not_disclosed_blend') {
    dose = null;
  } else {
    final quantity = ingredient['quantity'];
    final unit = ingredient['unit']?.toString() ?? '';
    final fallbackDose = quantity != null ? '$quantity $unit'.trim() : '';
    dose = fallbackDose.isNotEmpty ? fallbackDose : null;
  }

  // Form label — only when pipeline says form_status == 'known'.
  final formStatus = ingredient['form_status']?.toString();
  final displayFormLabel = ingredient['display_form_label']
      ?.toString()
      .trim()
      .toLowerCase();
  final formLabel =
      (formStatus == 'known' &&
          displayFormLabel != null &&
          displayFormLabel.isNotEmpty)
      ? displayFormLabel
      : null;

  // Tier resolution — verbatim production helpers.
  final formQuality = resolveFormQuality(ingredient['bio_score']);
  final doseCallOut = resolveDoseCallOut(
    ingredient: ingredient,
    ulEntry: ulEntry,
  );

  // Safety / inferred flags.
  final isSafetyConcern = ingredient['is_safety_concern'] == true;
  final displayType = ingredient['display_type']?.toString();
  final isInferredFromLabel = displayType == 'inferred_from_label';

  return PGActiveIngredient(
    name: name,
    dose: dose,
    formLabel: formLabel,
    formQuality: formQuality,
    doseCallOut: doseCallOut,
    isSafetyConcern: isSafetyConcern,
    isInferredFromLabel: isInferredFromLabel,
  );
}

/// Convert a raw inactive-ingredient map into a typed [PGInactiveIngredient].
///
/// Defensive against missing fields — falls back through display_label →
/// name → raw_source_text, returns empty roleHelper when no roles ship.
PGInactiveIngredient inactiveFromMap(Map<String, dynamic> ingredient) {
  final name =
      (ingredient['display_label']?.toString().trim().isNotEmpty == true)
      ? ingredient['display_label'].toString().trim()
      : ((ingredient['name']?.toString().trim().isNotEmpty == true)
            ? ingredient['name'].toString().trim()
            : (ingredient['raw_source_text']?.toString().trim() ?? ''));

  final tone = inactiveColorRank(ingredient);
  final roleHelper = _resolveRoleHelper(ingredient);

  return PGInactiveIngredient(name: name, tone: tone, roleHelper: roleHelper);
}

/// Pipeline v1.5.0 ships `display_role_label` (one-line, canonical).
/// Legacy blobs may ship `functional_roles[]` as a list of strings.
/// We cap at 2 roles to keep the row compact.
String? _resolveRoleHelper(Map<String, dynamic> ingredient) {
  final displayRole = ingredient['display_role_label']?.toString().trim();
  if (displayRole != null && displayRole.isNotEmpty) return displayRole;

  final rolesRaw = ingredient['functional_roles'];
  if (rolesRaw is List) {
    final roles = rolesRaw
        .map((r) => r.toString().trim())
        .where((s) => s.isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (roles.isEmpty) return null;
    return roles.join(', ');
  }
  return null;
}
