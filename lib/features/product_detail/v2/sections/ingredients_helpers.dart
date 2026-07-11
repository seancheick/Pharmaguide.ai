// Ingredients helpers (pure mapping).
//
//   raw active map → PGActiveIngredient
//     name           = label_display_name || display_label || standard_name
//                      || name || raw_source_text  (label-first; never infer
//                      identity from a canonical field)
//     dose           = display_dose_label OR (quantity + unit fallback)
//     formLabel      = label_display_form || display_form_label (when
//                      form_status == 'known'); casing preserved verbatim
//     formQuality    = resolveFormQuality(bio_score)
//     doseCallOut    = resolveDoseCallOut(ingredient, ulEntry)
//     isSafetyConcern = ingredient['is_safety_concern'] == true
//     isInferredFromLabel = ingredient['display_type'] == 'inferred_from_label'
//
//   raw inactive map → PGInactiveIngredient
//     name        = label_display || name || raw_source_text || display_label
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
  // Unresolved identity (defense-in-depth): if a cached/stale blob whose
  // identity the pipeline could not resolve reaches the app, show the literal
  // label text with an integrity flag and suppress every quality/dose/safety
  // claim — never the canonical standard_name. The release audit blocks these
  // before ship; this is the last-line fallback.
  final disposition = ingredient['identity_disposition']?.toString();
  if (disposition == 'identity_conflict' ||
      disposition == 'missing_display_label') {
    return PGActiveIngredient(
      name: _firstNonEmpty([
        ingredient['source_label_name'],
        ingredient['raw_source_text'],
        ingredient['name'],
        ingredient['label_display_name'],
      ]),
      identityNeedsReview: true,
    );
  }

  // Label-first identity: the pipeline's approved label-native name wins over
  // the computed display_label and, crucially, over the canonical standard_name
  // — the displayed identity is never inferred from a canonical field. Legacy
  // blobs (no label_display_name) keep the existing display_label behavior.
  final labelDisplayName = ingredient['label_display_name']?.toString().trim();
  final displayLabel = ingredient['display_label']?.toString().trim();
  final String name;
  if (labelDisplayName != null && labelDisplayName.isNotEmpty) {
    name = labelDisplayName;
  } else if (displayLabel != null && displayLabel.isNotEmpty) {
    name = displayLabel;
  } else {
    name =
        ingredient['standard_name']?.toString() ??
        ingredient['name']?.toString() ??
        ingredient['raw_source_text']?.toString() ??
        '';
  }

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

  // Label-first form: the pipeline's label-native form (e.g. "as Ethyl Esters")
  // wins and its casing is preserved verbatim — never lowercased. Legacy blobs
  // fall back to display_form_label (gated on form_status == 'known'), also
  // case-preserved.
  final labelDisplayForm = ingredient['label_display_form']?.toString().trim();
  final formStatus = ingredient['form_status']?.toString();
  final displayFormLabel = ingredient['display_form_label']?.toString().trim();
  final String? formLabel;
  if (labelDisplayForm != null && labelDisplayForm.isNotEmpty) {
    formLabel = labelDisplayForm;
  } else if (formStatus == 'known' &&
      displayFormLabel != null &&
      displayFormLabel.isNotEmpty) {
    formLabel = displayFormLabel;
  } else {
    formLabel = null;
  }

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
/// Defensive against missing fields — falls back through label_display →
/// name → raw_source_text → display_label, returns empty roleHelper when no
/// roles ship.
PGInactiveIngredient inactiveFromMap(Map<String, dynamic> ingredient) {
  final name = _firstNonEmpty([
    ingredient['label_display'],
    ingredient['name'],
    ingredient['raw_source_text'],
    ingredient['display_label'],
  ]);

  final tone = inactiveColorRank(ingredient);
  final roleHelper = _resolveRoleHelper(ingredient);

  return PGInactiveIngredient(name: name, tone: tone, roleHelper: roleHelper);
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return '';
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
