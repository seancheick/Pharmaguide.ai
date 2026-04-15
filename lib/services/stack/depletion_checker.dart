// Depletion Checker — matches user's medications against known
// drug-induced nutrient depletions from medication_depletions.json.

/// A matched depletion between a user's medication and a nutrient.
class DepletionMatch {
  final String depletionId;
  final String drugDisplayName;
  final String drugClassId;
  final String nutrientName;
  final String nutrientCanonicalId;
  final String severity;
  final String mechanism;
  final String recommendation;
  final List<String> sourceUrls;

  /// True if the user already has a supplement in their stack that
  /// covers this depleted nutrient.
  final bool isCovered;

  const DepletionMatch({
    required this.depletionId,
    required this.drugDisplayName,
    required this.drugClassId,
    required this.nutrientName,
    required this.nutrientCanonicalId,
    required this.severity,
    required this.mechanism,
    required this.recommendation,
    this.sourceUrls = const [],
    this.isCovered = false,
  });
}

class DepletionChecker {
  /// Check user's medications against known depletions.
  ///
  /// [medications] — user's stack entries of type 'medication'.
  /// [depletionsData] — parsed `medication_depletions.json`.
  /// [stackCanonicalIds] — set of canonical IDs from supplement stack,
  ///   used to flag covered depletions.
  List<DepletionMatch> check({
    required List<({String name, String? drugClassId})> medications,
    required Map<String, dynamic> depletionsData,
    Set<String> stackCanonicalIds = const {},
  }) {
    final depletions = depletionsData['depletions'] as List? ?? [];
    final results = <DepletionMatch>[];

    // Build a set of user's drug class IDs for matching.
    final userDrugClassIds = <String>{};
    final userDrugNames = <String>{};
    for (final med in medications) {
      if (med.drugClassId != null && med.drugClassId!.isNotEmpty) {
        userDrugClassIds.add(med.drugClassId!.toLowerCase());
      }
      userDrugNames.add(med.name.toLowerCase());
    }

    for (final dep in depletions) {
      if (dep is! Map<String, dynamic>) continue;

      final drugRef = dep['drug_ref'] as Map<String, dynamic>? ?? {};
      final drugId = (drugRef['id']?.toString() ?? '').toLowerCase();
      final drugDisplayName = drugRef['display_name']?.toString() ?? '';

      // Match by drug class ID or drug name substring
      final matches = userDrugClassIds.any((id) => drugId.contains(id)) ||
          userDrugNames.any((name) =>
              drugDisplayName.toLowerCase().contains(name) ||
              name.contains(drugDisplayName.toLowerCase()));

      if (!matches) continue;

      final nutrient = dep['depleted_nutrient'] as Map<String, dynamic>? ?? {};
      final canonicalId = nutrient['canonical_id']?.toString() ?? '';
      final isCovered = stackCanonicalIds.contains(canonicalId);

      final sourceUrls = (dep['sources'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((s) => s['url']?.toString() ?? '')
              .where((u) => u.isNotEmpty)
              .toList() ??
          const [];

      results.add(DepletionMatch(
        depletionId: dep['id']?.toString() ?? '',
        drugDisplayName: drugDisplayName,
        drugClassId: drugId,
        nutrientName: nutrient['standard_name']?.toString() ?? '',
        nutrientCanonicalId: canonicalId,
        severity: dep['severity']?.toString() ?? 'moderate',
        mechanism: dep['mechanism']?.toString() ?? '',
        recommendation: dep['recommendation']?.toString() ?? '',
        sourceUrls: sourceUrls,
        isCovered: isCovered,
      ));
    }

    // Sort: uncovered first, then by severity
    results.sort((a, b) {
      if (a.isCovered != b.isCovered) {
        return a.isCovered ? 1 : -1;
      }
      return _severityWeight(b.severity)
          .compareTo(_severityWeight(a.severity));
    });

    return results;
  }

  static int _severityWeight(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 4;
      case 'significant':
        return 3;
      case 'moderate':
        return 2;
      case 'mild':
        return 1;
      default:
        return 0;
    }
  }
}
