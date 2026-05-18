import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_evidence_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/evidence_section.dart';

Map<String, dynamic> _match({
  String ingredient = 'Ashwagandha',
  String evidence = 'moderate',
  List<String> pmids = const [],
}) {
  return {'ingredient': ingredient, 'evidence_level': evidence, 'pmids': pmids};
}

Future<void> _pump(WidgetTester tester, {Map<String, dynamic>? evidenceData}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: buildEvidenceSection(evidenceData: evidenceData),
        ),
      ),
    ),
  );
}

void main() {
  group('evidenceTotalStudies', () {
    test('dedupes PMIDs across matches and ignores blanks', () {
      final total = evidenceTotalStudies([
        _match(pmids: const ['1', '2', '']),
        _match(pmids: const ['2', '3', '   ']),
      ]);

      expect(total, 3);
    });
  });

  group('evidenceHasMetaQuality', () {
    test('recognizes strong, established, and high levels', () {
      expect(evidenceHasMetaQuality([_match(evidence: 'strong')]), isTrue);
      expect(evidenceHasMetaQuality([_match(evidence: 'established')]), isTrue);
      expect(evidenceHasMetaQuality([_match(evidence: 'High')]), isTrue);
      expect(evidenceHasMetaQuality([_match(evidence: 'moderate')]), isFalse);
    });
  });

  group('evidenceTier', () {
    test('0-2 studies resolves to limited regardless of meta label', () {
      expect(evidenceTier(const []), EvidenceTier.limited);
      expect(
        evidenceTier([
          _match(evidence: 'strong', pmids: const ['1', '2']),
        ]),
        EvidenceTier.limited,
      );
    });

    test('3-4 studies resolves to moderate', () {
      expect(
        evidenceTier([
          _match(pmids: const ['1', '2', '3']),
        ]),
        EvidenceTier.moderate,
      );
    });

    test('5 studies without meta stays moderate', () {
      expect(
        evidenceTier([
          _match(pmids: const ['1', '2', '3', '4', '5']),
        ]),
        EvidenceTier.moderate,
      );
    });

    test('5 studies with meta resolves to strong', () {
      expect(
        evidenceTier([
          _match(evidence: 'strong', pmids: const ['1', '2', '3']),
          _match(pmids: const ['4', '5']),
        ]),
        EvidenceTier.strong,
      );
    });
  });

  group('Evidence section v2 render', () {
    testWidgets('null evidenceData hides section', (tester) async {
      await _pump(tester);

      expect(find.byType(PGEvidenceSection), findsNothing);
    });

    testWidgets('matchCount=0 and no matches hides section', (tester) async {
      await _pump(
        tester,
        evidenceData: const {
          'match_count': 0,
          'clinical_matches': <Map<String, dynamic>>[],
        },
      );

      expect(find.byType(PGEvidenceSection), findsNothing);
    });

    testWidgets('strong tier renders summary and citations', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'strong',
              pmids: const ['111', '222', '333', '444', '555'],
            ),
          ],
        },
      );

      expect(find.text('Clinical evidence'), findsOneWidget);
      expect(find.text('STRONG · 5 studies · meta-analysis'), findsOneWidget);
      expect(find.text('PMID 111 · Ashwagandha'), findsOneWidget);
    });

    testWidgets('limited tier renders without meta-analysis text', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'limited', pmids: const ['111']),
          ],
        },
      );

      expect(find.text('LIMITED · 1 study'), findsOneWidget);
      expect(find.textContaining('meta-analysis'), findsNothing);
    });

    testWidgets('PMID-less rows do not render citation contradictions', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [_match(evidence: 'strong', pmids: const [])],
        },
      );

      expect(find.text('LIMITED'), findsOneWidget);
      expect(find.textContaining('PMID'), findsNothing);
      expect(find.textContaining('0 studies'), findsNothing);
    });
  });
}
