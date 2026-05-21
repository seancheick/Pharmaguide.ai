import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

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

  const PGActiveIngredient({
    required this.name,
    this.dose,
    this.formLabel,
    this.formQuality = FormQuality.unknown,
    this.doseCallOut = DoseCallOut.withinLimits,
    this.isSafetyConcern = false,
    this.isInferredFromLabel = false,
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
