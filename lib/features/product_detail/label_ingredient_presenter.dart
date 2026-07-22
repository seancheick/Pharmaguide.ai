import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/features/product_detail/label_ingredient_types.dart';

PGActiveIngredient presentActiveIngredient(
  Map<String, dynamic> ingredient, {
  Map<String, dynamic>? ulEntry,
}) {
  final identityState = _firstNonEmpty([
    ingredient['identity_integrity_state'],
    ingredient['identity_disposition'],
  ]);
  final rawFormDisplayState = _trimOrNull(ingredient['form_display_state']);
  final labelDisplayForm = _trimOrNull(ingredient['label_display_form']);
  final displayFormLabel = _trimOrNull(ingredient['display_form_label']);
  final legacyKnownForm =
      rawFormDisplayState == null &&
      ingredient['form_status']?.toString() == 'known' &&
      displayFormLabel != null;
  final disclosedForm =
      labelDisplayForm ??
      ((rawFormDisplayState != null || legacyKnownForm)
          ? displayFormLabel
          : null);
  final formDisplayState = _parseFormDisplayState(
    rawFormDisplayState,
    identityState: identityState,
    displayDisposition: ingredient['display_disposition']?.toString(),
    hasDisclosedForm: disclosedForm != null,
    legacyKnownForm: legacyKnownForm,
  );
  final identityNeedsReview =
      identityState == 'identity_conflict' ||
      identityState == 'missing_display_label';
  final claimsNeedSuppression =
      identityNeedsReview ||
      formDisplayState == PGIngredientFormDisplayState.needsReview;

  final rawDisplayDisposition = _trimOrNull(ingredient['display_disposition']);
  final hasExplicitScoreFlag = ingredient.containsKey('score_included');
  final explicitlyIncluded = ingredient['score_included'] == true;
  final displayDisposition =
      rawDisplayDisposition ??
      ((hasExplicitScoreFlag && explicitlyIncluded) ? 'scored' : null);
  final scoreIncluded = hasExplicitScoreFlag
      ? explicitlyIncluded
      : rawDisplayDisposition == null
      ? true
      : rawDisplayDisposition == 'scored';

  if (claimsNeedSuppression) {
    return PGActiveIngredient(
      name: _firstNonEmpty([
        ingredient['source_label_name'],
        ingredient['raw_source_text'],
        ingredient['label_display_name'],
        ingredient['name'],
      ]),
      dose: _doseLabelFor(ingredient),
      parentheticalDoseText: _trimOrNull(ingredient['parenthetical_dose_text']),
      identityNeedsReview: identityNeedsReview,
      formDisplayState: PGIngredientFormDisplayState.needsReview,
      labelOrder: _readInt(ingredient['label_order']),
      rawSourcePath: _trimOrNull(ingredient['raw_source_path']),
      nestedDepth: _readInt(ingredient['nested_depth']),
      parentLabel: _trimOrNull(ingredient['parent_label']),
      scoreIncluded: scoreIncluded,
      displayDisposition: displayDisposition,
    );
  }

  final formLabel = switch (formDisplayState) {
    PGIngredientFormDisplayState.assessed ||
    PGIngredientFormDisplayState.listedNotAssessed => disclosedForm,
    _ => null,
  };

  final formQuality = formDisplayState == PGIngredientFormDisplayState.assessed
      ? resolveFormQuality(_analysisValue(ingredient, 'bio_score'))
      : FormQuality.unknown;
  final doseIngredient = _withAnalysisSignals(ingredient, const [
    'standard_name',
    'quantity',
    'unit',
    'below_clinical_dose',
  ]);

  return PGActiveIngredient(
    name: _firstNonEmpty([
      ingredient['label_display_name'],
      ingredient['display_label'],
      ingredient['standard_name'],
      ingredient['name'],
      ingredient['raw_source_text'],
    ]),
    dose: _doseLabelFor(ingredient),
    parentheticalDoseText: _trimOrNull(ingredient['parenthetical_dose_text']),
    formLabel: formLabel,
    formQuality: formQuality,
    doseCallOut: scoreIncluded
        ? resolveDoseCallOut(ingredient: doseIngredient, ulEntry: ulEntry)
        : DoseCallOut.withinLimits,
    isSafetyConcern:
        scoreIncluded &&
        _analysisValue(ingredient, 'is_safety_concern') == true,
    isInferredFromLabel:
        ingredient['display_type']?.toString() == 'inferred_from_label',
    identityNeedsReview: false,
    formDisplayState: formDisplayState,
    labelOrder: _readInt(ingredient['label_order']),
    rawSourcePath: _trimOrNull(ingredient['raw_source_path']),
    nestedDepth: _readInt(ingredient['nested_depth']),
    parentLabel: _trimOrNull(ingredient['parent_label']),
    scoreIncluded: scoreIncluded,
    displayDisposition: displayDisposition,
  );
}

Object? _analysisValue(Map<String, dynamic> ingredient, String key) {
  if (ingredient.containsKey(key)) return ingredient[key];
  final analysis = ingredient['analysis'];
  return analysis is Map ? analysis[key] : null;
}

Map<String, dynamic> _withAnalysisSignals(
  Map<String, dynamic> ingredient,
  List<String> keys,
) {
  final analysis = ingredient['analysis'];
  if (analysis is! Map) return ingredient;

  Map<String, dynamic>? merged;
  for (final key in keys) {
    if (ingredient.containsKey(key) || !analysis.containsKey(key)) continue;
    merged ??= Map<String, dynamic>.from(ingredient);
    merged[key] = analysis[key];
  }
  return merged ?? ingredient;
}

PGIngredientFormDisplayState _parseFormDisplayState(
  String? raw, {
  required String identityState,
  required String? displayDisposition,
  required bool hasDisclosedForm,
  required bool legacyKnownForm,
}) {
  if (identityState == 'identity_conflict' ||
      identityState == 'missing_display_label') {
    return PGIngredientFormDisplayState.needsReview;
  }

  switch ((raw ?? '').trim()) {
    case 'assessed':
      return hasDisclosedForm
          ? PGIngredientFormDisplayState.assessed
          : PGIngredientFormDisplayState.needsReview;
    case 'not_disclosed':
      return hasDisclosedForm
          ? PGIngredientFormDisplayState.needsReview
          : PGIngredientFormDisplayState.notDisclosed;
    case 'listed_not_assessed':
      return hasDisclosedForm
          ? PGIngredientFormDisplayState.listedNotAssessed
          : PGIngredientFormDisplayState.needsReview;
    case 'not_applicable':
      return hasDisclosedForm
          ? PGIngredientFormDisplayState.needsReview
          : PGIngredientFormDisplayState.notApplicable;
    case 'needs_review':
      return PGIngredientFormDisplayState.needsReview;
    case '':
      if (displayDisposition == 'other_ingredient' ||
          displayDisposition == 'label_context') {
        return PGIngredientFormDisplayState.notApplicable;
      }
      if (legacyKnownForm) {
        return PGIngredientFormDisplayState.assessed;
      }
      return hasDisclosedForm
          ? PGIngredientFormDisplayState.listedNotAssessed
          : PGIngredientFormDisplayState.notDisclosed;
    default:
      return PGIngredientFormDisplayState.needsReview;
  }
}

String? _doseLabelFor(Map<String, dynamic> ingredient) {
  final exactDose = _trimOrNull(ingredient['exact_dose_text']);
  if (exactDose != null) return exactDose;

  final displayDose = _trimOrNull(ingredient['display_dose_label']);
  if (displayDose != null) return displayDose;

  final doseStatus = ingredient['dose_status']?.toString();
  if (doseStatus == 'missing' || doseStatus == 'not_disclosed_blend') {
    return null;
  }

  final quantity = ingredient['quantity'];
  final unit = _firstNonEmpty([ingredient['unit']]);
  if (quantity == null) return null;
  final fallback = '$quantity $unit'.trim();
  return fallback.isEmpty ? null : fallback;
}

String? _trimOrNull(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = _trimOrNull(value);
    if (text != null) return text;
  }
  return '';
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
