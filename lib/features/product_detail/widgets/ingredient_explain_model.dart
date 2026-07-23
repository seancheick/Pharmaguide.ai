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

import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/features/product_detail/label_ingredient_presenter.dart';
import 'package:pharmaguide/features/product_detail/label_ingredient_types.dart';

export 'package:pharmaguide/features/product_detail/label_ingredient_types.dart';

/// What the explain sheet renders. Pure data; no widgets.
class IngredientExplain {
  /// Heading at the top of the sheet — the ingredient's display name.
  final String title;

  /// Optional form name verbatim from the pipeline (e.g. "bisglycinate").
  final String? formName;

  /// Optional dose label verbatim ("200 mg" / "Amount not disclosed").
  final String? doseLabel;

  /// Exact component amount printed parenthetically on the same label row.
  final String? parentheticalDoseText;

  /// Optional evidence level label (e.g. "Strong" / "Moderate").
  final String? evidenceLabel;

  /// Form-quality tier — drives chip label and primary block heading.
  final FormQuality formQuality;

  /// Consumer-facing state for forms that cannot carry a quality tier.
  final String? formStatusLabel;

  /// Heading that preserves assessed/not-disclosed/not-assessed/review state.
  final String? formHeading;

  /// Dose call-out — drives the dose block heading.
  final DoseCallOut doseCallOut;

  /// 1–2 sentence pharmacist-style copy explaining a verified form signal.
  /// Null keeps unassessed/internal states out of the consumer sheet.
  final String? formExplanation;

  /// Sentence explaining the dose call-out. Empty for `withinLimits`.
  final String doseExplanation;

  /// Defense-in-depth flag copied from the shared label presenter.
  final bool identityNeedsReview;

  /// Whether this label row participates in the product analysis.
  final bool scoreIncluded;

  const IngredientExplain({
    required this.title,
    required this.formQuality,
    required this.formHeading,
    required this.doseCallOut,
    required this.formExplanation,
    required this.doseExplanation,
    this.formName,
    this.doseLabel,
    this.parentheticalDoseText,
    this.evidenceLabel,
    this.formStatusLabel,
    this.identityNeedsReview = false,
    this.scoreIncluded = false,
  });
}

/// Builds an [IngredientExplain] for the modal. Pure function over the
/// raw ingredient map + matched UL entry, mirroring the inputs the row
/// already has — keeps row and modal in lockstep.
IngredientExplain buildIngredientExplain({
  required Map<String, dynamic> ingredient,
  Map<String, dynamic>? ulEntry,
}) {
  final presented = presentActiveIngredient(ingredient, ulEntry: ulEntry);

  final evidenceLabel = ingredient['evidence_level']?.toString().trim();
  final materialUndisclosedForm =
      ingredient['form_disclosure_material'] == true &&
      presented.formDisplayState == PGIngredientFormDisplayState.notDisclosed;
  final formStatusLabel = materialUndisclosedForm
      ? presented.formStatusLabel
      : null;
  final formHeading =
      formStatusLabel ??
      (presented.formQuality == FormQuality.unknown
          ? null
          : formBlockHeading(presented.formQuality));
  final formExplanation = formHeading == null
      ? null
      : _formExplanationForPresentation(
          formStatusLabel: formStatusLabel,
          quality: presented.formQuality,
          form: presented.formLabel,
        );

  return IngredientExplain(
    title: presented.name,
    formName: presented.formLabel,
    doseLabel: presented.dose,
    parentheticalDoseText: presented.parentheticalDoseText,
    evidenceLabel: (evidenceLabel == null || evidenceLabel.isEmpty)
        ? null
        : evidenceLabel,
    formQuality: presented.formQuality,
    formStatusLabel: formStatusLabel,
    formHeading: formHeading,
    doseCallOut: presented.doseCallOut,
    formExplanation: formExplanation,
    doseExplanation: _doseExplanationFor(presented.doseCallOut),
    identityNeedsReview: presented.identityNeedsReview,
    scoreIncluded: presented.scoreIncluded,
  );
}

String _formExplanationForPresentation({
  required String? formStatusLabel,
  required FormQuality quality,
  required String? form,
}) {
  switch (formStatusLabel) {
    case 'Form not disclosed':
      return 'The label does not disclose a molecular or delivery form, so '
          'we do not assign a form-quality rating.';
    case 'Form listed · not yet assessed':
      return 'The label lists this form, but our form reference has not '
          'assessed it yet. No form-quality rating is shown.';
    default:
      if (quality == FormQuality.unknown) {
        return 'A form-quality rating does not apply to this label row.';
      }
      return _formExplanationFor(quality, form);
  }
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
      // Material disclosure limitations are shown by the label structure
      // itself (blend header, probiotic CFU, omega composition), not as a
      // generic analysis block on every ingredient sheet.
      return '';
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
      // Unknown/unassessed is intentionally silent in consumer UI.
      return '';
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
      return '';
    case DoseCallOut.withinLimits:
      return '';
  }
}

/// Label used by the row chip — the explicit "{tier} form" vocabulary, shared
/// with [formBlockHeading] so the chip and the sheet heading always agree.
String formChipLabel(FormQuality q) {
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
      return '';
    case DoseCallOut.withinLimits:
      return '';
  }
}
