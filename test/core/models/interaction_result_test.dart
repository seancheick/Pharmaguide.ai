import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

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

    test('missing row evidence hydrates as ungraded, not theoretical', () {
      final result = InteractionResult.fromRow(_row(evidenceLevel: null));

      expect(result.evidenceLevel, EvidenceLevel.ungraded);
    });

    test('explicit theoretical row evidence remains theoretical', () {
      final result = InteractionResult.fromRow(
        _row(evidenceLevel: 'theoretical'),
      );

      expect(result.evidenceLevel, EvidenceLevel.theoretical);
    });
  });
}

InteractionRow _row({String? evidenceLevel}) {
  return InteractionRow(
    id: 'TEST_ROW',
    agent1Type: 'drug',
    agent1Name: 'Warfarin',
    agent1Id: '11289',
    agent2Type: 'supplement',
    agent2Name: 'Vitamin K',
    agent2Id: 'vitamin_k',
    severity: 'caution',
    mechanism: 'May affect anticoagulation management.',
    management: 'Review with prescriber.',
    evidenceLevel: evidenceLevel,
    sourceUrlsJson: '[]',
    sourcePmidsJson: '[]',
    bidirectional: 1,
    doseDependent: 0,
    typeAuthored: 'drug_supplement',
    source: 'curated',
    provenance: 'test',
    versionAdded: 'test',
    versionLastModified: 'test',
    lastUpdated: 'test',
  );
}
