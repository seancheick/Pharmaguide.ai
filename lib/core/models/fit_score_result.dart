enum FitAssessmentState {
  notRecommended,
  limitedFit,
  goodFit,
  strongMatch,
  incompleteProfile,
}

class FitScoreResult {
  final double scoreFit20;
  final double e1;
  final double e2a;
  final double e2b;
  final double e2c;
  final List<String> missingFields;
  final double maxPossible;
  final FitAssessmentState state;
  final List<String> reasons;
  final String? maxRelevantSeverity;
  final double mappedCoverage;

  const FitScoreResult({
    required this.scoreFit20,
    required this.e1,
    required this.e2a,
    required this.e2b,
    required this.e2c,
    required this.missingFields,
    required this.maxPossible,
    this.state = FitAssessmentState.limitedFit,
    this.reasons = const [],
    this.maxRelevantSeverity,
    // Required on purpose — a silent `= 1.0` default let call sites
    // imply full label coverage when none was measured (safety rule:
    // never display "safe" when mapped_coverage < 0.3).
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
