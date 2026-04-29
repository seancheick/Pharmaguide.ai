import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';

InteractionResult _issue(Severity severity) => InteractionResult(
  id: 'test',
  type: InteractionType.supplementSupplement,
  severity: severity,
  evidenceLevel: EvidenceLevel.established,
  agent1Name: 'A',
  agent2Name: 'B',
  mechanism: '',
  management: '',
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: const [],
  source: InteractionSource.stackEngine,
);

void main() {
  group('RiskTier', () {
    test('fromScore returns correct tier', () {
      expect(RiskTier.fromScore(95), RiskTier.excellent);
      expect(RiskTier.fromScore(80), RiskTier.good);
      expect(RiskTier.fromScore(65), RiskTier.caution);
      expect(RiskTier.fromScore(45), RiskTier.moderateRisk);
      expect(RiskTier.fromScore(20), RiskTier.highRisk);
    });

    test('boundary values', () {
      expect(RiskTier.fromScore(90), RiskTier.excellent);
      expect(RiskTier.fromScore(89), RiskTier.good);
      expect(RiskTier.fromScore(75), RiskTier.good);
      expect(RiskTier.fromScore(74), RiskTier.caution);
      expect(RiskTier.fromScore(60), RiskTier.caution);
      expect(RiskTier.fromScore(59), RiskTier.moderateRisk);
      expect(RiskTier.fromScore(40), RiskTier.moderateRisk);
      expect(RiskTier.fromScore(39), RiskTier.highRisk);
      expect(RiskTier.fromScore(0), RiskTier.highRisk);
    });
  });

  group('StackHealthLabel', () {
    StackSafetyScore buildScore(
      int score, {
      List<InteractionResult> issues = const [],
    }) {
      return StackSafetyScore(
        score: score,
        riskTier: RiskTier.fromScore(score),
        issues: issues,
        synergies: const [],
        optimizations: const [],
      );
    }

    test('uses score bands when no safety caps apply', () {
      expect(buildScore(92).healthLabel, StackHealthLabel.optimized);
      expect(buildScore(78).healthLabel, StackHealthLabel.solid);
      expect(buildScore(60).healthLabel, StackHealthLabel.decent);
      expect(buildScore(42).healthLabel, StackHealthLabel.concerning);
    });

    test('unsafe severities override score', () {
      expect(
        buildScore(96, issues: [_issue(Severity.avoid)]).healthLabel,
        StackHealthLabel.unsafe,
      );
      expect(
        buildScore(96, issues: [_issue(Severity.contraindicated)]).healthLabel,
        StackHealthLabel.unsafe,
      );
    });

    test('caution caps optimistic labels at decent', () {
      expect(
        buildScore(88, issues: [_issue(Severity.caution)]).healthLabel,
        StackHealthLabel.decent,
      );
      expect(
        buildScore(72, issues: [_issue(Severity.caution)]).healthLabel,
        StackHealthLabel.decent,
      );
    });

    test('monitor caps optimized at solid only', () {
      expect(
        buildScore(90, issues: [_issue(Severity.monitor)]).healthLabel,
        StackHealthLabel.solid,
      );
      expect(
        buildScore(72, issues: [_issue(Severity.monitor)]).healthLabel,
        StackHealthLabel.solid,
      );
    });

    // Boundary lock — monitor cap fires exactly at the optimized cutoff
    // (score >= 85). Score 85 is in the optimized band, so the cap should
    // demote it to solid. Score 84 is already in the solid band, so the
    // cap is a no-op there. Score 86 with no monitor issues stays
    // optimized (regression guard against the cap leaking into clean
    // stacks).
    test('monitor cap fires exactly at the optimized boundary (score 85)', () {
      expect(
        buildScore(85, issues: [_issue(Severity.monitor)]).healthLabel,
        StackHealthLabel.solid,
        reason: 'score 85 is optimized → monitor caps it to solid',
      );
    });

    test('monitor cap is a no-op below the optimized boundary (score 84)', () {
      expect(
        buildScore(84, issues: [_issue(Severity.monitor)]).healthLabel,
        StackHealthLabel.solid,
        reason: 'score 84 is already solid; monitor cap leaves it unchanged',
      );
    });

    test('clean stack at score 86 stays optimized (cap does not leak)', () {
      expect(
        buildScore(86).healthLabel,
        StackHealthLabel.optimized,
        reason: 'no caps apply → score 86 remains optimized',
      );
    });
  });
}
