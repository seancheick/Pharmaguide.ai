// Pure model + sentence selector for IngredientExplainSheet.
//
// Sprint: docs/sprints/product_detail_page_sprint.md — T4C.
//
// The sheet renders one short pharmacist-style explanation chosen from
// the ingredient's `bio_score`, `form`, dose safety verdict, and
// optional `below_clinical_dose` flag. Selection is data-driven — no
// per-ingredient hardcoding — so the same engine works for the whole
// 180k-product catalog.
//
// Vocabulary contract (matches `_SafetyTag._resolve` and
// `FormAbsorptionSection.bioLabel`): Excellent / Good / Fair / Poor.
// In the explain sheet the chip label gets a "form" suffix because we
// have room for clarity ("Excellent form" vs the chip's "Excellent").

import 'package:pharmaguide/features/product_detail/dose_safety.dart';

/// Form-quality tier driven by `bio_score` on the 0–15 scale (pure
/// form quality; natural-source bonus lives in pipeline A5 starting
/// Phase 7C).
enum FormQuality {
  excellent, // bio_score >= 12
  good, //      bio_score 8..11
  fair, //      bio_score 4..7
  poor, //      bio_score 0..3
  unknown, //   bio_score == null
}

/// Dose-related call-out for the chip / sheet block. Mirrors `DoseSafety`
/// outcomes plus a Low-dose tier for the future `below_clinical_dose`
/// pipeline signal (Phase 7A).
enum DoseCallOut {
  high, //         DoseSafety.exceedsUl
  low, //          pipeline `below_clinical_dose == true`
  notDisclosed, // DoseSafety.skip
  withinLimits, // (no chip)
}

/// Resolves [DoseCallOut] from the same inputs `_SafetyTag._resolve`
/// uses today, plus the future `below_clinical_dose` flag.
DoseCallOut resolveDoseCallOut({
  required Map<String, dynamic> ingredient,
  Map<String, dynamic>? ulEntry,
}) {
  // Pipeline below_clinical_dose flag — preferred when present (Phase 7A).
  final belowClinical = ingredient['below_clinical_dose'];
  if (belowClinical == true) return DoseCallOut.low;
  // Also check the matched UL entry — pipeline may emit the flag there
  // when it's tied to the UL row rather than the raw ingredient.
  if (ulEntry != null && ulEntry['below_clinical_dose'] == true) {
    return DoseCallOut.low;
  }

  final doseSafety = resolveDoseSafety(
    ingredient: ingredient,
    ulAnalysis: ulEntry == null ? null : <Map<String, dynamic>>[ulEntry],
  );
  switch (doseSafety) {
    case DoseSafety.exceedsUl:
      return DoseCallOut.high;
    case DoseSafety.skip:
      // Sean 2026-05-05 — pipeline emits skip_ul_check for retinyl
      // Vitamin A and similar "unknown form" cases even when the dose
      // is plainly disclosed (e.g. 1.05 mg). Surfacing "Dose not
      // disclosed" on a row that shows a real dose is contradictory.
      // Only chip when the dose is genuinely missing — otherwise the
      // skip is a backend evaluation choice the user doesn't need to
      // see flagged at row level.
      final qty = _readQuantity(ingredient);
      if (qty != null && qty > 0) return DoseCallOut.withinLimits;
      return DoseCallOut.notDisclosed;
    case DoseSafety.withinLimits:
      return DoseCallOut.withinLimits;
  }
}

double? _readQuantity(Map<String, dynamic> ingredient) {
  final raw = ingredient['quantity'];
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

/// Resolves [FormQuality] from `bio_score`. Same thresholds as
/// `_bioColor` and `_SafetyTag._resolve`.
FormQuality resolveFormQuality(dynamic bioScore) {
  if (bioScore is! num) return FormQuality.unknown;
  final s = bioScore.toDouble();
  if (s < 0) return FormQuality.unknown;
  if (s >= 12) return FormQuality.excellent;
  if (s >= 8) return FormQuality.good;
  if (s >= 4) return FormQuality.fair;
  return FormQuality.poor;
}

/// What the explain sheet renders. Pure data; no widgets.
class IngredientExplain {
  /// Heading at the top of the sheet — the ingredient's display name.
  final String title;

  /// Optional form name verbatim from the pipeline (e.g. "bisglycinate").
  final String? formName;

  /// Optional dose label verbatim ("200 mg" / "Amount not disclosed").
  final String? doseLabel;

  /// Optional evidence level label (e.g. "Strong" / "Moderate").
  final String? evidenceLabel;

  /// Form-quality tier — drives chip label and primary block heading.
  final FormQuality formQuality;

  /// Dose call-out — drives the dose block heading.
  final DoseCallOut doseCallOut;

  /// 1–2 sentence pharmacist-style copy explaining the form. Always
  /// present — generic when no form is known.
  final String formExplanation;

  /// Sentence explaining the dose call-out. Empty for `withinLimits`.
  final String doseExplanation;

  const IngredientExplain({
    required this.title,
    required this.formQuality,
    required this.doseCallOut,
    required this.formExplanation,
    required this.doseExplanation,
    this.formName,
    this.doseLabel,
    this.evidenceLabel,
  });
}

/// Builds an [IngredientExplain] for the modal. Pure function over the
/// raw ingredient map + matched UL entry, mirroring the inputs the row
/// already has — keeps row and modal in lockstep.
IngredientExplain buildIngredientExplain({
  required Map<String, dynamic> ingredient,
  Map<String, dynamic>? ulEntry,
}) {
  final displayLabel = ingredient['display_label']?.toString().trim();
  final name = (displayLabel != null && displayLabel.isNotEmpty)
      ? displayLabel
      : (ingredient['standard_name']?.toString() ??
          ingredient['name']?.toString() ??
          ingredient['raw_source_text']?.toString() ??
          '');

  // v1.5.0 contract — prefer display_form_label + form_status; fall back
  // to legacy `form` for stale blobs. See FINAL_EXPORT_SCHEMA_V1.md.
  final formStatus = ingredient['form_status']?.toString();
  final displayFormLabel = ingredient['display_form_label']?.toString().trim();
  final legacyForm = ingredient['form']?.toString().trim();
  final formCandidate = (displayFormLabel != null && displayFormLabel.isNotEmpty)
      ? displayFormLabel
      : legacyForm;
  final hasKnownForm = formStatus != null
      ? formStatus == 'known'
      : (formCandidate != null && formCandidate.isNotEmpty);
  final formName = (hasKnownForm && formCandidate != null && formCandidate.isNotEmpty)
      ? formCandidate
      : null;

  // v1.5.0 contract — display_dose_label is the canonical pre-formatted
  // string; dose_status disambiguates empty states. Legacy quantity+unit
  // fallback retained for stale blobs only.
  final displayDoseLabel = ingredient['display_dose_label']?.toString().trim();
  final doseStatus = ingredient['dose_status']?.toString();
  String? doseLabel;
  if (displayDoseLabel != null && displayDoseLabel.isNotEmpty) {
    doseLabel = displayDoseLabel;
  } else if (doseStatus == 'missing' || doseStatus == 'not_disclosed_blend') {
    doseLabel = null;
  } else {
    final quantity = ingredient['quantity'];
    final unit = ingredient['unit']?.toString() ?? '';
    final fallbackDose = quantity != null ? '$quantity $unit'.trim() : '';
    doseLabel = fallbackDose.isNotEmpty ? fallbackDose : null;
  }

  final evidenceLabel = ingredient['evidence_level']?.toString().trim();

  final formQuality = resolveFormQuality(ingredient['bio_score']);
  final doseCallOut =
      resolveDoseCallOut(ingredient: ingredient, ulEntry: ulEntry);

  return IngredientExplain(
    title: name,
    formName: formName,
    doseLabel: doseLabel,
    evidenceLabel: (evidenceLabel == null || evidenceLabel.isEmpty)
        ? null
        : evidenceLabel,
    formQuality: formQuality,
    doseCallOut: doseCallOut,
    formExplanation: _formExplanationFor(formQuality, formName),
    doseExplanation: _doseExplanationFor(doseCallOut),
  );
}

String _formExplanationFor(FormQuality q, String? form) {
  // Prefer form-specific copy when we have a known chelated/methylated form.
  final f = form?.toLowerCase() ?? '';
  switch (q) {
    case FormQuality.excellent:
      if (f.contains('glycinate') || f.contains('bisglycinate')) {
        return 'Glycinate is a chelated form, often gentler on the stomach '
            'and well absorbed.';
      }
      if (f.contains('methylcobalamin') ||
          f.contains('methyl') && f.contains('folate')) {
        return 'A methylated active form, typically efficient at reaching '
            'the bloodstream.';
      }
      if (f.contains('mk-7') || f.contains('mk7')) {
        return 'MK-7 is a long-acting form of vitamin K2 with strong '
            'absorption and tissue retention.';
      }
      return 'Bioavailable form — typically well absorbed.';
    case FormQuality.good:
      return 'Reasonable absorption profile for most users.';
    case FormQuality.fair:
      return 'Fair absorption — varies by individual.';
    case FormQuality.poor:
      if (f.contains('oxide')) {
        return 'Oxide form is widely used but typically less efficiently '
            'absorbed than chelated alternatives.';
      }
      return 'Lower-absorption form — widely used but less efficient than '
          'chelated alternatives.';
    case FormQuality.unknown:
      return 'We do not have absorption data for this form.';
  }
}

String _doseExplanationFor(DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return 'Dose is above the established Upper Limit. Consider reducing '
          'daily intake.';
    case DoseCallOut.low:
      return 'This dose is below amounts shown to produce a meaningful '
          'effect in studies.';
    case DoseCallOut.notDisclosed:
      return 'Label dose is incomplete or hidden in a proprietary blend, so '
          'this ingredient was not evaluated against safety thresholds.';
    case DoseCallOut.withinLimits:
      return '';
  }
}

/// Heading copy for the form block in the sheet — uses the
/// "{tier} form" pattern per the plan's vocabulary contract.
String formBlockHeading(FormQuality q) {
  switch (q) {
    case FormQuality.excellent:
      return 'Excellent form';
    case FormQuality.good:
      return 'Good form';
    case FormQuality.fair:
      return 'Fair form';
    case FormQuality.poor:
      return 'Poor form';
    case FormQuality.unknown:
      return 'Form unknown';
  }
}

/// Heading copy for the dose block in the sheet.
String doseBlockHeading(DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return 'High dose';
    case DoseCallOut.low:
      return 'Low dose';
    case DoseCallOut.notDisclosed:
      return 'Dose not disclosed';
    case DoseCallOut.withinLimits:
      return '';
  }
}

/// Short label used by the row chip (no "form" suffix).
String formChipLabel(FormQuality q) {
  switch (q) {
    case FormQuality.excellent:
      return 'Excellent';
    case FormQuality.good:
      return 'Good';
    case FormQuality.fair:
      return 'Fair';
    case FormQuality.poor:
      return 'Poor';
    case FormQuality.unknown:
      return '';
  }
}

/// Short label used by the dose chip.
String doseChipLabel(DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return 'High dose';
    case DoseCallOut.low:
      return 'Low dose';
    case DoseCallOut.notDisclosed:
      return 'Dose not disclosed';
    case DoseCallOut.withinLimits:
      return '';
  }
}
