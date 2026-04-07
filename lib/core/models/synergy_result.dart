import 'package:pharmaguide/core/constants/severity.dart';

class SynergyResult {
  final String ingredient1;
  final String ingredient2;
  final String description;
  final EvidenceLevel evidenceLevel;
  final int bonus;

  const SynergyResult({
    required this.ingredient1,
    required this.ingredient2,
    required this.description,
    required this.evidenceLevel,
    required this.bonus,
  });
}
