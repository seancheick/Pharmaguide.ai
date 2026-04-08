/// E2b Age Appropriateness Calculator.
/// Penalizes nutrients that are way outside age-appropriate range.
class E2bAgeCalculator {
  final Map<String, dynamic> rdaData;

  E2bAgeCalculator(this.rdaData);

  double calculate({
    required List<Map<String, dynamic>> nutrients,
    String? ageBracket,
  }) {
    if (ageBracket == null || nutrients.isEmpty) return 0.0;

    final recommendations = rdaData['nutrient_recommendations'] as List? ?? [];
    int checked = 0;
    int appropriate = 0;

    for (final nutrient in nutrients) {
      final name = (nutrient['standard_name'] ?? nutrient['name'] ?? '')
          .toString()
          .toLowerCase();
      final amount = _parseAmount(nutrient);
      if (amount == null || amount <= 0) continue;

      final entry = _findEntry(recommendations, name);
      if (entry == null) continue;

      final rda = _getAgeGroupRda(entry, ageBracket);
      if (rda == null || rda <= 0) continue;

      checked++;
      final ratio = amount / rda;
      // Appropriate if between 10% and 500% of age-group RDA
      if (ratio >= 0.1 && ratio <= 5.0) {
        appropriate++;
      }
    }

    if (checked == 0) return 0.0;
    return (appropriate / checked * 3.0).clamp(0.0, 3.0);
  }

  double? _parseAmount(Map<String, dynamic> nutrient) {
    final v = nutrient['normalizedAmount'] ?? nutrient['quantity'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Map<String, dynamic>? _findEntry(List<dynamic> recs, String name) {
    for (final entry in recs) {
      if (entry is! Map<String, dynamic>) continue;
      final n = (entry['nutrient'] ?? '').toString().toLowerCase();
      if (n == name || n.contains(name) || name.contains(n)) return entry;
    }
    return null;
  }

  double? _getAgeGroupRda(Map<String, dynamic> entry, String ageBracket) {
    final data = entry['data'] as List? ?? [];
    // Average RDA across sexes for this age group
    double total = 0;
    int count = 0;
    for (final group in data) {
      if (group is! Map<String, dynamic>) continue;
      if (group['age_bracket'] == ageBracket) {
        final rda = group['rda'] ?? group['ai'];
        if (rda is num) {
          total += rda.toDouble();
          count++;
        }
      }
    }
    return count > 0 ? total / count : null;
  }
}
