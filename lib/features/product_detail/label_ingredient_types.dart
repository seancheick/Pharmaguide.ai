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

/// Dose-related call-out for the chip / sheet block. Mirrors [DoseSafety]
/// outcomes plus a Low-dose tier for the future `below_clinical_dose`
/// pipeline signal (Phase 7A).
enum DoseCallOut {
  high, //         DoseSafety.exceedsUl
  low, //          pipeline `below_clinical_dose == true`
  notDisclosed, // DoseSafety.skip
  withinLimits, // (no chip)
}

/// Resolves [DoseCallOut] from the same inputs as the ingredient safety tag,
/// plus the future `below_clinical_dose` flag.
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
      // The pipeline emits skip_ul_check for retinyl Vitamin A and similar
      // cases even when the dose is disclosed. Do not contradict a real dose
      // with a "Dose not disclosed" call-out.
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

/// Resolves [FormQuality] from `bio_score`.
FormQuality resolveFormQuality(dynamic bioScore) {
  if (bioScore is! num) return FormQuality.unknown;
  final s = bioScore.toDouble();
  if (s < 0) return FormQuality.unknown;
  if (s >= 12) return FormQuality.excellent;
  if (s >= 8) return FormQuality.good;
  if (s >= 4) return FormQuality.fair;
  return FormQuality.poor;
}
