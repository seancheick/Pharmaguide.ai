// E1 Dosage Appropriateness Calculator.
// Compares product nutrient amounts against age/sex-specific RDA and UL values.
//
// Scoring:
//   - UL exceeded: -5 pts (ALWAYS runs, even without profile)
//   - 50-200% of RDA: +7/n pts per nutrient
//   - 25-50% of RDA: +4/n pts per nutrient
//   - < 25% of RDA: +2/n pts per nutrient
//   - No age/sex? Use highest_ul fallback, baseline 4 pts
// Clamp to [-5, 7]
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

class E1DosageCalculator {
  final Map<String, dynamic> rdaData;

  E1DosageCalculator(this.rdaData);

  double calculate({
    required List<Map<String, dynamic>> nutrients,
    String? ageBracket,
    String? sex,
  }) {
    if (nutrients.isEmpty) return 0.0;

    final aggregated = const StackNutrientAggregator().aggregate([
      StackItemNutrients(
        stackEntryId: 'fit_score_product',
        productName: 'Product',
        ingredients: nutrients,
      ),
    ]);
    final statuses = StackUlChecker(
      rdaData: rdaData,
    ).check(aggregated, ageBracket: ageBracket, sex: sex);

    double totalScore = 0.0;
    var scoredCount = 0;
    final ulExceeded = statuses.any((s) => s.tier == NutrientTier.exceedsUl);

    for (final status in statuses) {
      final pctOfRda = status.pctOfRda;
      if (pctOfRda == null) continue;
      if (pctOfRda >= 50 && pctOfRda <= 200) {
        totalScore += 7.0;
      } else if (pctOfRda >= 25) {
        totalScore += 4.0;
      } else {
        totalScore += 2.0;
      }
      scoredCount++;
    }

    double score;
    if (scoredCount > 0) {
      score = totalScore / scoredCount;
    } else if (ageBracket == null) {
      score = 4.0; // Baseline without profile
    } else {
      score = 0.0;
    }

    if (ulExceeded) score = -5.0;

    return score.clamp(-5.0, 7.0);
  }
}
