import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/constants/severity.dart';

void main() {
  group('InteractionResult', () {
    test('creates from valid data', () {
      const result = InteractionResult(
        id: 'TEST_001',
        type: InteractionType.conditionSupplement,
        severity: Severity.caution,
        evidenceLevel: EvidenceLevel.established,
        agent1Name: 'Pregnancy',
        agent2Name: 'Ginkgo Biloba',
        mechanism: 'May stimulate uterine contractions',
        management: 'Avoid during pregnancy',
        doseDependant: false,
        doseThreshold: null,
        sourceUrls: ['https://pubmed.ncbi.nlm.nih.gov/12345678/'],
        source: InteractionSource.pipeline,
      );
      expect(result.id, 'TEST_001');
      expect(result.severity, Severity.caution);
      expect(result.sourceUrls, hasLength(1));
    });

    test('stackPenaltyFor returns correct values', () {
      expect(InteractionResult.stackPenaltyFor(Severity.contraindicated), -18);
      expect(InteractionResult.stackPenaltyFor(Severity.avoid), -12);
      expect(InteractionResult.stackPenaltyFor(Severity.caution), -7);
      expect(InteractionResult.stackPenaltyFor(Severity.monitor), -3);
      expect(InteractionResult.stackPenaltyFor(Severity.safe), 0);
    });
  });
}
