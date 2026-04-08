import 'package:pharmaguide/core/constants/severity.dart';

/// E2c Medical Compatibility Calculator.
/// Checks interaction_summary from detail blob against user conditions + drug classes.
class E2cMedicalCalculator {
  double calculate({
    required Map<String, dynamic> interactionSummary,
    required List<String> userConditions,
    required List<String> userDrugClasses,
  }) {
    double score = 8.0;

    final rawConditions = interactionSummary['condition_summary'];
    final conditionSummary = rawConditions is Map
        ? Map<String, dynamic>.from(rawConditions)
        : <String, dynamic>{};
    final rawDrugs = interactionSummary['drug_class_summary'];
    final drugClassSummary = rawDrugs is Map
        ? Map<String, dynamic>.from(rawDrugs)
        : <String, dynamic>{};

    // Check conditions
    for (final conditionId in userConditions) {
      final rawMatch = conditionSummary[conditionId];
      if (rawMatch is! Map) continue;
      final match = Map<String, dynamic>.from(rawMatch);

      final severityStr = match['highest_severity']?.toString() ?? '';
      final severity = Severity.fromString(severityStr);
      score += severity.e2cPenalty; // e2cPenalty is negative
    }

    // Check drug classes
    for (final drugClassId in userDrugClasses) {
      final rawMatch = drugClassSummary[drugClassId];
      if (rawMatch is! Map) continue;
      final match = Map<String, dynamic>.from(rawMatch);

      final severityStr = match['highest_severity']?.toString() ?? '';
      final severity = Severity.fromString(severityStr);
      score += severity.e2cPenalty;
    }

    return score.clamp(0.0, 8.0);
  }
}
