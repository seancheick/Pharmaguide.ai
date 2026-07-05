import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';

void main() {
  group('buildBlockedAllergenAlertSummary', () {
    test('returns null when there are no matched allergens', () {
      expect(buildBlockedAllergenAlertSummary(const []), isNull);
    });

    test('a "contains" match surfaces a danger summary with allergen rows', () {
      final summary = buildBlockedAllergenAlertSummary(const [
        MatchedAllergen(
          id: 'ALLERGEN_PEANUTS',
          displayName: 'Peanuts',
          presenceType: 'contains',
          severityLevel: 'high',
        ),
      ]);
      expect(summary, isNotNull);
      expect(summary!.headline, 'Contains an allergen in your profile');
      expect(summary.rows, isNotEmpty);
    });

    test('a "may_contain"-only match surfaces a review summary', () {
      final summary = buildBlockedAllergenAlertSummary(const [
        MatchedAllergen(
          id: 'ALLERGEN_TREE_NUTS',
          displayName: 'Tree nuts',
          presenceType: 'may_contain',
          severityLevel: 'moderate',
        ),
      ]);
      expect(summary, isNotNull);
      expect(summary!.headline, 'May contain an allergen in your profile');
      expect(summary.rows, isNotEmpty);
    });
  });
}
