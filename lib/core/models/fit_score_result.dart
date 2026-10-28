import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

enum FitAssessmentState {
  notRecommended,
  limitedFit,
  goodFit,
  strongMatch,
  incompleteProfile,
}

class FitScoreResult {
  final List<String> missingFields;
  final FitAssessmentState state;
  final List<String> reasons;
  final String? maxRelevantSeverity;
  final double mappedCoverage;

  /// The same transient, exposure-qualified assessment used by E1/E2b.
  /// Never persisted; personal review rows render these findings directly.
  final List<NutrientStatus> nutrientStatuses;

  const FitScoreResult({
    required this.missingFields,
    this.state = FitAssessmentState.limitedFit,
    this.reasons = const [],
    this.maxRelevantSeverity,
    this.nutrientStatuses = const [],
    // Required on purpose: coverage is a separate, visible assessment input.
    required this.mappedCoverage,
  });

  String get fitLabel {
    switch (state) {
      case FitAssessmentState.notRecommended:
        return 'Not recommended';
      case FitAssessmentState.limitedFit:
        return 'Limited fit';
      case FitAssessmentState.goodFit:
        return 'Good fit';
      case FitAssessmentState.strongMatch:
        return 'Strong match';
      case FitAssessmentState.incompleteProfile:
        return 'Incomplete profile';
    }
  }

  String get displayText {
    final missing = missingFields.isEmpty ? '' : ' — Complete profile';
    return '$fitLabel$missing';
  }
}
