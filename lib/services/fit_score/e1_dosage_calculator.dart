/// E1 Dosage Appropriateness Calculator.
/// Compares product nutrient amounts against age/sex-specific RDA and UL values.
///
/// Scoring:
///   - UL exceeded: -5 pts (ALWAYS runs, even without profile)
///   - 50-200% of RDA: +7/n pts per nutrient
///   - 25-50% of RDA: +4/n pts per nutrient
///   - < 25% of RDA: +2/n pts per nutrient
///   - No age/sex? Use highest_ul fallback, baseline 4 pts
/// Clamp to [-5, 7]
class E1DosageCalculator {
  final Map<String, dynamic> rdaData;

  E1DosageCalculator(this.rdaData);

  double calculate({
    required List<Map<String, dynamic>> nutrients,
    String? ageBracket,
    String? sex,
  }) {
    if (nutrients.isEmpty) return 0.0;

    final recommendations = rdaData['nutrient_recommendations'] as List? ?? [];
    double totalScore = 0.0;
    int scoredCount = 0;
    bool ulExceeded = false;

    for (final nutrient in nutrients) {
      final name = (nutrient['standard_name'] ?? nutrient['name'] ?? '')
          .toString()
          .toLowerCase();
      final amount = _parseAmount(nutrient);
      if (amount == null || amount <= 0) continue;

      // Find matching nutrient in RDA data
      final rdaEntry = _findNutrientEntry(recommendations, name);
      if (rdaEntry == null) continue;

      // Get age/sex-specific values
      final ul = _getUl(rdaEntry, ageBracket, sex);
      final rda = _getRda(rdaEntry, ageBracket, sex);

      // UL check (always runs)
      if (ul != null && ul > 0 && amount > ul) {
        ulExceeded = true;
      }

      // RDA scoring (only with profile data)
      if (rda != null && rda > 0) {
        final pctOfRda = (amount / rda) * 100;
        if (pctOfRda >= 50 && pctOfRda <= 200) {
          totalScore += 7.0;
        } else if (pctOfRda >= 25) {
          totalScore += 4.0;
        } else {
          totalScore += 2.0;
        }
        scoredCount++;
      }
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

  double? _parseAmount(Map<String, dynamic> nutrient) {
    final v = nutrient['normalizedAmount'] ?? nutrient['quantity'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Map<String, dynamic>? _findNutrientEntry(List<dynamic> recommendations, String name) {
    for (final entry in recommendations) {
      if (entry is! Map<String, dynamic>) continue;
      final entryName = (entry['nutrient'] ?? '').toString().toLowerCase();
      if (entryName == name ||
          entryName.contains(name) ||
          name.contains(entryName)) {
        return entry;
      }
    }
    return null;
  }

  double? _getUl(Map<String, dynamic> entry, String? ageBracket, String? sex) {
    // Try age/sex-specific first, fall back to highest_ul
    final data = entry['data'] as List? ?? [];
    for (final group in data) {
      if (group is! Map<String, dynamic>) continue;
      if (ageBracket != null && group['age_bracket'] == ageBracket) {
        if (sex != null && group['group'] == sex) {
          final ul = group['ul'];
          if (ul is num) return ul.toDouble();
        }
      }
    }
    // Fallback: highest_ul
    final highest = entry['highest_ul'];
    if (highest is num) return highest.toDouble();
    return null;
  }

  double? _getRda(Map<String, dynamic> entry, String? ageBracket, String? sex) {
    final data = entry['data'] as List? ?? [];
    for (final group in data) {
      if (group is! Map<String, dynamic>) continue;
      if (ageBracket != null && group['age_bracket'] == ageBracket) {
        if (sex != null && group['group'] == sex) {
          final rda = group['rda'] ?? group['ai'];
          if (rda is num) return rda.toDouble();
        }
      }
    }
    return null;
  }
}
