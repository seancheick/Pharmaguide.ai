import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_evidence_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/evidence_section.dart';

Map<String, dynamic> _match({
  String ingredient = 'Ashwagandha',
  String evidence = 'ingredient-human',
  List<Map<String, dynamic>> refs = const [],
  int? totalEnrollment,
  int? metaReviewCount,
}) {
  return {
    'ingredient': ingredient,
    'evidence_level': evidence,
    if (refs.isNotEmpty) 'references_structured': refs,
    if (totalEnrollment != null) 'total_enrollment': totalEnrollment,
    if (metaReviewCount != null) 'published_meta_review_count': metaReviewCount,
  };
}

Map<String, dynamic> _ref(String pmid, {String? title}) {
  return {'type': 'pubmed', 'pmid': pmid, if (title != null) 'title': title};
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
        _match(refs: [_ref('1'), _ref('2'), _ref('')]),
        _match(refs: [_ref('2'), _ref('3'), _ref('   ')]),
      ]);

      expect(total, 3);
    });

    test('match without references_structured contributes zero studies', () {
      expect(evidenceTotalStudies([_match()]), 0);
    });
  });

  group('evidenceHasMetaQuality', () {
    test('recognizes published_meta_review_count > 0', () {
      expect(evidenceHasMetaQuality([_match(metaReviewCount: 2)]), isTrue);
      expect(evidenceHasMetaQuality([_match(metaReviewCount: 0)]), isFalse);
      expect(evidenceHasMetaQuality([_match()]), isFalse);
    });
  });

  group('evidenceTier', () {
    test('branded-rct resolves to strong even with zero references', () {
      expect(
        evidenceTier([_match(evidence: 'branded-rct')]),
        EvidenceTier.strong,
      );
    });

    test('product-human resolves to strong', () {
      expect(
        evidenceTier([_match(evidence: 'product-human')]),
        EvidenceTier.strong,
      );
    });

    test('ingredient-human only resolves to moderate', () {
      expect(
        evidenceTier([_match(evidence: 'ingredient-human')]),
        EvidenceTier.moderate,
      );
    });

    test('strain-clinical resolves to moderate', () {
      expect(
        evidenceTier([_match(evidence: 'strain-clinical')]),
        EvidenceTier.moderate,
      );
    });

    test('preclinical / reference only resolves to limited', () {
      expect(
        evidenceTier([_match(evidence: 'preclinical')]),
        EvidenceTier.limited,
      );
      expect(
        evidenceTier([_match(evidence: 'reference')]),
        EvidenceTier.limited,
      );
      expect(evidenceTier(const []), EvidenceTier.limited);
    });

    test('match without refs still counts toward tier', () {
      // No references_structured at all — tier comes from evidence_level.
      expect(
        evidenceTier([
          _match(evidence: 'preclinical', refs: [_ref('1')]),
          _match(evidence: 'ingredient-human'),
        ]),
        EvidenceTier.moderate,
      );
    });
  });

  group('evidenceHeadline', () {
    test('branded-rct leads with formulation copy', () {
      expect(
        evidenceHeadline([_match(evidence: 'branded-rct')]),
        "This product's formulation was clinically studied.",
      );
    });

    test('aggregates study count and enrollment', () {
      final headline = evidenceHeadline([
        _match(refs: [_ref('1'), _ref('2')], totalEnrollment: 400),
        _match(refs: [_ref('3')], totalEnrollment: 220),
      ]);

      expect(headline, 'Backed by 3 human studies · ~620 participants');
    });

    test('null when no studies and not branded-rct', () {
      expect(evidenceHeadline([_match()]), isNull);
    });

    test('null for preclinical-only — never claims human studies', () {
      expect(
        evidenceHeadline([
          _match(evidence: 'preclinical', refs: [_ref('1')]),
        ]),
        isNull,
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

    testWidgets('branded-rct renders strong tier with formulation subtitle', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'branded-rct',
              refs: [_ref('111', title: 'A randomized trial of ashwagandha')],
            ),
          ],
        },
      );

      expect(find.text('Clinical evidence'), findsOneWidget);
      expect(find.text('STRONG · 1 study'), findsOneWidget);
      expect(
        find.text("This product's formulation was clinically studied."),
        findsOneWidget,
      );
    });

    testWidgets('citations use real paper titles from references_structured', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'ingredient-human',
              refs: [
                _ref('111', title: 'Effects of ashwagandha on stress'),
                _ref('222'), // no title — falls back to PMID label
              ],
            ),
          ],
        },
      );

      expect(find.text('Effects of ashwagandha on stress'), findsOneWidget);
      expect(find.text('PMID 222 · Ashwagandha'), findsOneWidget);
    });

    testWidgets('dedupes citations by PMID across matches', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 2,
          'clinical_matches': [
            _match(
              ingredient: 'Ashwagandha',
              evidence: 'ingredient-human',
              refs: [_ref('111', title: 'Shared study')],
            ),
            _match(
              ingredient: 'Rhodiola',
              evidence: 'ingredient-human',
              refs: [_ref('111', title: 'Shared study')],
            ),
          ],
        },
      );

      expect(find.text('Shared study'), findsOneWidget);
      expect(find.text('MODERATE · 1 study'), findsOneWidget);
    });

    testWidgets('preclinical only renders limited tier', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'preclinical', refs: [_ref('111')]),
          ],
        },
      );

      expect(find.text('LIMITED · 1 study'), findsOneWidget);
      expect(find.textContaining('meta-analysis'), findsNothing);
    });

    testWidgets('match without refs still renders and informs tier', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [_match(evidence: 'ingredient-human')],
        },
      );

      expect(find.text('MODERATE'), findsOneWidget);
      expect(find.textContaining('PMID'), findsNothing);
    });

    testWidgets('renders score-pillar caption', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'ingredient-human', refs: [_ref('111')]),
          ],
        },
      );

      expect(
        find.text(
          'This research feeds the Evidence pillar in the score above.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('caps displayed citations at five', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'ingredient-human',
              refs: [
                for (var i = 1; i <= 8; i++) _ref('$i', title: 'Study $i'),
              ],
            ),
          ],
        },
      );

      expect(find.text('Study 5'), findsOneWidget);
      expect(find.text('Study 6'), findsNothing);
      // Count still reflects all deduped studies.
      expect(find.text('MODERATE · 8 studies'), findsOneWidget);
    });
  });
}
