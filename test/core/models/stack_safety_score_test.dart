import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';

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
}
