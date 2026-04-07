import 'package:pharmaguide/core/constants/severity.dart';

enum InteractionType {
  drugSupplement,
  supplementSupplement,
  drugDrug,
  conditionSupplement,
}

enum InteractionSource {
  pipeline,
  stackEngine,
  aiChat,
}

class InteractionResult {
  final String id;
  final InteractionType type;
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String agent1Name;
  final String agent2Name;
  final String mechanism;
  final String management;
  final bool doseDependant;
  final String? doseThreshold;
  final List<String> sourceUrls;
  final InteractionSource source;

  const InteractionResult({
    required this.id,
    required this.type,
    required this.severity,
    required this.evidenceLevel,
    required this.agent1Name,
    required this.agent2Name,
    required this.mechanism,
    required this.management,
    required this.doseDependant,
    required this.doseThreshold,
    required this.sourceUrls,
    required this.source,
  });

  /// Returns the midpoint stack penalty for a given severity.
  static int stackPenaltyFor(Severity severity) {
    return switch (severity) {
      Severity.contraindicated => -18,
      Severity.avoid => -12,
      Severity.caution => -7,
      Severity.monitor => -3,
      Severity.safe => 0,
    };
  }
}
