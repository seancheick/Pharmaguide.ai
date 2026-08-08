// Copy contract for the shared Stack Health summary lines (ADR-006).
//
// Optimized must never read as a medical endorsement: its claim is scoped to
// the checks that actually completed. Solid stays a distinct, softer line,
// and the incomplete tier never borrows graded-verdict language.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/utils/stack_intelligence_helpers.dart';

StackIntelligence _intel(StackTier tier) => StackIntelligence(
  tier: tier,
  stackSize: 3,
  issues: const [],
  interactionCount: 0,
  nutrientWarningCount: 0,
  hasRecalledIngredient: false,
  hasContraindicatedInteraction: false,
  hasBannedIngredient: false,
);

void main() {
  group('describeStackSummary — top-tier copy stays qualified', () {
    test('optimized scopes the claim to completed checks', () {
      expect(
        describeStackSummary(_intel(StackTier.optimized)),
        'No significant issues found in the checks PharmaGuide completed.',
      );
    });

    test('solid stays distinct from optimized', () {
      expect(
        describeStackSummary(_intel(StackTier.solid)),
        'No major safety issues found. Minor items may be worth monitoring.',
      );
    });

    test('incomplete never reads as a graded verdict', () {
      expect(
        describeStackSummary(_intel(StackTier.incomplete)),
        'Some checks need more information before this stack can be rated.',
      );
    });
  });
}
