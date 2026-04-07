class FitScoreResult {
  final double scoreFit20;
  final double scoreCombined100;
  final double e1;
  final double e2a;
  final double e2b;
  final double e2c;
  final List<String> missingFields;
  final double maxPossible;

  const FitScoreResult({
    required this.scoreFit20,
    required this.scoreCombined100,
    required this.e1,
    required this.e2a,
    required this.e2b,
    required this.e2c,
    required this.missingFields,
    required this.maxPossible,
  });

  String get displayText {
    final pct = maxPossible > 0
        ? (scoreCombined100 / maxPossible * 100).toStringAsFixed(1)
        : '0.0';
    final missing = missingFields.isEmpty
        ? ''
        : ' — Complete profile for full scoring';
    return '${scoreCombined100.toStringAsFixed(0)}/${maxPossible.toStringAsFixed(0)} ($pct%)$missing';
  }
}
