import 'package:pharmaguide/features/product_detail/label_ingredient_types.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

enum PGIngredientFormDisplayState {
  assessed,
  notDisclosed,
  listedNotAssessed,
  notApplicable,
  needsReview,
}

extension PGIngredientFormDisplayStatePresentation
    on PGIngredientFormDisplayState {
  /// Exact consumer copy for non-quality form states.
  ///
  /// Assessed rows use their quality tier instead. `notApplicable` is
  /// intentionally silent because no form badge applies to that label row.
  String? get statusLabel => switch (this) {
    PGIngredientFormDisplayState.assessed => null,
    PGIngredientFormDisplayState.notDisclosed => 'Form not disclosed',
    PGIngredientFormDisplayState.listedNotAssessed =>
      'Form listed · not yet assessed',
    PGIngredientFormDisplayState.notApplicable => null,
    PGIngredientFormDisplayState.needsReview => null,
  };
}

/// Typed input for [PGActiveIngredientTile].
///
/// In production, callers build this from the raw pipeline map at the
/// screen level (the same fields `_IngredientTile` reads inline today —
/// `display_label`, `display_dose_label`, `display_form_label`,
/// `form_status`, `bio_score`, `is_safety_concern`, `display_type`).
/// Keeping the v2 widget on a typed input means the presentation layer
/// doesn't touch the map shape — only the screen-level adapter does.
class PGActiveIngredient {
  /// Display name. Production: `standard_name` ?? `display_label`,
  /// or `display_label` when no known form (see _IngredientTile:2469).
  final String name;

  /// Pre-formatted dose label, e.g. "200 mg" or "Amount not disclosed".
  /// Empty string / null hides the dose column.
  final String? dose;

  /// Exact parenthetical component amount printed with the logical label row.
  /// For example, Folate may carry "400 mcg folic acid" beneath its DFE dose.
  final String? parentheticalDoseText;

  /// Lowercased form helper line shown under the name when known.
  /// e.g. "bisglycinate". Production: only rendered when
  /// `form_status == 'known'`.
  final String? formLabel;

  /// Bioavailability tier resolved from `bio_score`. Drives the form chip.
  final FormQuality formQuality;

  /// Dose-related call-out (UL exceedance / below-clinical / not disclosed).
  /// Drives the dose chip.
  final DoseCallOut doseCallOut;

  /// Production canonical hazard flag (moderate/high/critical hazards).
  /// Distinct from form quality — a high-quality form can still hit a
  /// kidney-disease safety concern.
  final bool isSafetyConcern;

  /// True when the row was inferred from the product name rather than a
  /// structured pipeline source. Surfaces an "Inferred from label" chip.
  final bool isInferredFromLabel;

  /// True when the pipeline could not resolve this ingredient's identity
  /// (`identity_conflict` / `missing_display_label`). The tile then shows the
  /// literal label facts while hiding form-quality, dose-quality, and safety
  /// claims — defense-in-depth for a cached/stale blob that slipped past the
  /// release audit.
  final bool identityNeedsReview;

  /// Closed presentation state for label/native form truth.
  final PGIngredientFormDisplayState formDisplayState;

  /// Label hierarchy depth. `0` is a top-level row.
  final int nestedDepth;

  /// Source-label order from the canonical display ledger.
  final int labelOrder;

  /// Stable source occurrence path used for label reconciliation.
  final String? rawSourcePath;

  /// Optional label parent title for nested rows.
  final String? parentLabel;

  /// Whether this row participates in scoring.
  final bool scoreIncluded;

  /// Source-aware display disposition from the pipeline label ledger.
  final String? displayDisposition;

  /// Consumer-facing non-quality form status. Assessed and not-applicable
  /// rows intentionally return null.
  String? get formStatusLabel => formDisplayState.statusLabel;

  /// Accessible context explaining whether this label row affected analysis.
  String get scoreParticipationLabel =>
      scoreIncluded ? 'Included in analysis' : 'Not included in analysis';

  const PGActiveIngredient({
    required this.name,
    this.dose,
    this.parentheticalDoseText,
    this.formLabel,
    this.formQuality = FormQuality.unknown,
    this.doseCallOut = DoseCallOut.withinLimits,
    this.isSafetyConcern = false,
    this.isInferredFromLabel = false,
    this.identityNeedsReview = false,
    this.formDisplayState = PGIngredientFormDisplayState.notApplicable,
    this.nestedDepth = 0,
    this.labelOrder = 0,
    this.rawSourcePath,
    this.parentLabel,
    this.scoreIncluded = false,
    this.displayDisposition,
  });
}

/// Typed input for [PGInactiveRow] — display name, severity-driven
/// tone, optional role helper line.
class PGInactiveIngredient {
  /// Display name (pipeline `display_label` ?? `name` ?? `raw_source_text`).
  final String name;

  /// Visual tone driven by pipeline `severity_status`. Resolved upstream
  /// via `inactiveColorRank()` from `lib/features/product_detail/widgets/
  /// inactive_color.dart`.
  final InactiveTone tone;

  /// Optional 1-line role helper. Production prefers `display_role_label`
  /// (v1.5.0 canonical), falls back to a comma-joined list of matched
  /// `functional_roles[]` from the bundled vocab (capped at 2).
  final String? roleHelper;

  const PGInactiveIngredient({
    required this.name,
    required this.tone,
    this.roleHelper,
  });
}
