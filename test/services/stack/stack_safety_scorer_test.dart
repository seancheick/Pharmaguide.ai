import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';

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
      sourceUrls: [],
      source: InteractionSource.stackEngine,
    );

void main() {
  late StackSafetyScorer scorer;
  setUp(() => scorer = StackSafetyScorer());

  group('StackSafetyScorer', () {
    test('empty stack scores 100', () {
      final result = scorer.compute(issues: []);
      expect(result.score, 100);
      expect(result.riskTier, RiskTier.excellent);
    });

    test('caution issue reduces score', () {
      final result = scorer.compute(issues: [_issue(Severity.caution)]);
      expect(result.score, lessThan(100));
      expect(result.score, greaterThanOrEqualTo(25));
    });

    test('contraindicated caps at 25', () {
      final result =
          scorer.compute(issues: [_issue(Severity.contraindicated)]);
      expect(result.score, 25);
      expect(result.riskTier, RiskTier.highRisk);
    });

    test('avoid caps at 50', () {
      final result = scorer.compute(issues: [_issue(Severity.avoid)]);
      expect(result.score, lessThanOrEqualTo(50));
    });

    test('synergies add bonus points', () {
      final result = scorer.compute(
        issues: [_issue(Severity.monitor)],
        synergies: [
          const SynergyResult(
            ingredient1: 'D3',
            ingredient2: 'K2',
            description: 'Enhanced absorption',
            evidenceLevel: EvidenceLevel.established,
            bonus: 5,
          ),
        ],
      );
      // 100 - 3 (monitor) + 5 (synergy) = 102, capped at 100
      expect(result.score, 100);
    });

    test('floor is 25 even with massive penalties', () {
      final result = scorer.compute(issues: [
        _issue(Severity.caution),
        _issue(Severity.caution),
        _issue(Severity.caution),
        _issue(Severity.caution),
        _issue(Severity.caution),
        _issue(Severity.caution),
        _issue(Severity.caution),
        _issue(Severity.caution),
      ]);
      expect(result.score, greaterThanOrEqualTo(25));
    });
  });
}
