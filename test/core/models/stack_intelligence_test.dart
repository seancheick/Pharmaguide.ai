import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';

void main() {
  group('StackTier.healthLabel', () {
    test('five user-facing tiers map 1:1 to StackHealthLabel', () {
      expect(StackTier.optimized.healthLabel, StackHealthLabel.optimized);
      expect(StackTier.solid.healthLabel, StackHealthLabel.solid);
      expect(StackTier.decent.healthLabel, StackHealthLabel.decent);
      expect(StackTier.concerning.healthLabel, StackHealthLabel.concerning);
      expect(StackTier.unsafe.healthLabel, StackHealthLabel.unsafe);
    });

    test('incomplete tier has no healthLabel (internal fallback only)', () {
      expect(StackTier.incomplete.healthLabel, isNull);
    });
  });

  group('StackIntelligence.deriveTier — hard gates', () {
    test('empty stack → incomplete', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 0,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
      );
      expect(tier, StackTier.incomplete);
    });

    test('banned ingredient → unsafe even with otherwise-clean stack', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 10,
        hasBannedIngredient: true,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
        qualityScore: 95,
      );
      expect(tier, StackTier.unsafe);
    });

    test('recalled ingredient → unsafe', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 5,
        hasBannedIngredient: false,
        hasRecalledIngredient: true,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
        qualityScore: 80,
      );
      expect(tier, StackTier.unsafe);
    });

    test('contraindicated interaction → unsafe', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 4,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: true,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
      );
      expect(tier, StackTier.unsafe);
    });
  });

  group('StackIntelligence.deriveTier — concerning rules', () {
    test('avoid-level interaction → concerning', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 6,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 1,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
      );
      expect(tier, StackTier.concerning);
    });

    test('two or more nutrient warnings → concerning', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 8,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 2,
      );
      expect(tier, StackTier.concerning);
    });
  });

  group('StackIntelligence.deriveTier — decent rules', () {
    test('caution-level interaction → decent', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 5,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 1,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
      );
      expect(tier, StackTier.decent);
    });

    test('exactly one nutrient warning → decent', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 5,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 1,
      );
      expect(tier, StackTier.decent);
    });

    test('monitor-level interaction → decent', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 3,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 1,
        nutrientWarningCount: 0,
      );
      expect(tier, StackTier.decent);
    });

    test('missingData on otherwise-clean stack with high score → decent', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 4,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
        qualityScore: 95,
        missingData: true,
      );
      expect(tier, StackTier.decent);
    });

    test('clean stack with no quality score → decent (cannot promote)', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 2,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
      );
      expect(tier, StackTier.decent);
    });
  });

  group('StackIntelligence.deriveTier — clean-stack quality bands', () {
    test('clean stack, qualityScore 90 → optimized', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 6,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
        qualityScore: 90,
      );
      expect(tier, StackTier.optimized);
    });

    test('clean stack, qualityScore 75 → solid', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 4,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
        qualityScore: 75,
      );
      expect(tier, StackTier.solid);
    });

    test('clean stack, qualityScore 60 → decent', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 4,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 0,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
        qualityScore: 60,
      );
      expect(tier, StackTier.decent);
    });

    test('avoid + high quality still → concerning (gates beat quality)', () {
      final tier = StackIntelligence.deriveTier(
        stackSize: 6,
        hasBannedIngredient: false,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        avoidInteractionCount: 1,
        cautionInteractionCount: 0,
        monitorInteractionCount: 0,
        nutrientWarningCount: 0,
        qualityScore: 95,
      );
      expect(tier, StackTier.concerning);
    });
  });

  group('StackIntelligence constructor', () {
    test('exposes the inputs verbatim', () {
      const issue = StackIssue(
        severity: Severity.avoid,
        headline: 'Iron + thyroid med — separate by 4h',
      );
      const intelligence = StackIntelligence(
        tier: StackTier.concerning,
        stackSize: 7,
        issues: [issue],
        interactionCount: 1,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
        qualityScore: 78,
      );

      expect(intelligence.tier, StackTier.concerning);
      expect(intelligence.stackSize, 7);
      expect(intelligence.issues, hasLength(1));
      expect(intelligence.issues.first.headline,
          'Iron + thyroid med — separate by 4h');
      expect(intelligence.issues.first.severity, Severity.avoid);
      expect(intelligence.interactionCount, 1);
      expect(intelligence.qualityScore, 78);
    });
  });
}
