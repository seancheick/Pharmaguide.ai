import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/gating.dart';

void main() {
  group('shouldShowAllergenDataUnavailableHedge', () {
    test('shows when a user with allergens opens a product with no allergen '
        'data at all', () {
      expect(
        shouldShowAllergenDataUnavailableHedge(
          isBlocked: false,
          userHasAllergens: true,
          noStructuredAllergens: true,
          allergenSummary: null,
        ),
        isTrue,
      );
      // Whitespace-only summary counts as "no data".
      expect(
        shouldShowAllergenDataUnavailableHedge(
          isBlocked: false,
          userHasAllergens: true,
          noStructuredAllergens: true,
          allergenSummary: '   ',
        ),
        isTrue,
      );
    });

    test('hidden when the user declared no allergens', () {
      expect(
        shouldShowAllergenDataUnavailableHedge(
          isBlocked: false,
          userHasAllergens: false,
          noStructuredAllergens: true,
          allergenSummary: null,
        ),
        isFalse,
      );
    });

    test(
      'hidden when structured allergens exist (the matcher handles them)',
      () {
        expect(
          shouldShowAllergenDataUnavailableHedge(
            isBlocked: false,
            userHasAllergens: true,
            noStructuredAllergens: false,
            allergenSummary: null,
          ),
          isFalse,
        );
      },
    );

    test(
      'hidden when a free-text summary exists (summary banner covers it)',
      () {
        expect(
          shouldShowAllergenDataUnavailableHedge(
            isBlocked: false,
            userHasAllergens: true,
            noStructuredAllergens: true,
            allergenSummary: 'Contains milk.',
          ),
          isFalse,
        );
      },
    );

    test('hidden on blocked products (consistent with the summary banner)', () {
      expect(
        shouldShowAllergenDataUnavailableHedge(
          isBlocked: true,
          userHasAllergens: true,
          noStructuredAllergens: true,
          allergenSummary: null,
        ),
        isFalse,
      );
    });
  });
}
