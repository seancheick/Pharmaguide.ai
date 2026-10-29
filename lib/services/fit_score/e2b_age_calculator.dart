// E2b Age Appropriateness Calculator.
// Penalizes nutrients that are way outside age-appropriate range.
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';

class E2bAgeCalculator {
  final Map<String, dynamic> rdaData;

  E2bAgeCalculator(this.rdaData);

  double calculate({
    required List<Map<String, dynamic>> nutrients,
    String? ageBracket,
    String? sex,
    List<NutrientStatus>? assessment,
  }) {
    if (ageBracket == null || nutrients.isEmpty) return 0.0;

    final statuses =
        assessment ??
        E1DosageCalculator(
          rdaData,
        ).assess(nutrients: nutrients, ageBracket: ageBracket, sex: sex);

    var checked = 0;
    var appropriate = 0;
    for (final status in statuses) {
      final pctOfRda = status.pctOfRda;
      if (pctOfRda == null) continue;
      checked++;
      final ratio = pctOfRda / 100.0;
      // Appropriate if between 10% and 500% of age-group RDA
      if (ratio >= 0.1 && ratio <= 5.0) {
        appropriate++;
      }
    }

    if (checked == 0) return 0.0;
    return (appropriate / checked * 3.0).clamp(0.0, 3.0);
  }
}
