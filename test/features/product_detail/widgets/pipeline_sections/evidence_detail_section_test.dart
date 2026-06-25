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
  String? studyType,
  List<String>? publishedStudies,
  String? effectDirection,
  String? uiEvidenceScope,
}) {
  return {
    'ingredient': ingredient,
    'evidence_level': evidence,
    if (refs.isNotEmpty) 'references_structured': refs,
    if (totalEnrollment != null) 'total_enrollment': totalEnrollment,
    if (metaReviewCount != null) 'published_meta_review_count': metaReviewCount,
    if (studyType != null) 'study_type': studyType,
    if (publishedStudies != null) 'published_studies': publishedStudies,
    if (effectDirection != null) 'effect_direction': effectDirection,
    if (uiEvidenceScope != null) 'ui_evidence_scope': uiEvidenceScope,
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

    test('preclinical and reference matches never count as human studies', () {
      expect(
        evidenceTotalStudies([
          _match(evidence: 'preclinical', refs: [_ref('1'), _ref('2')]),
          _match(evidence: 'reference', refs: [_ref('3')]),
        ]),
        0,
      );
      // Human-grade matches still count alongside excluded ones.
      expect(
        evidenceTotalStudies([
          _match(evidence: 'preclinical', refs: [_ref('1')]),
          _match(evidence: 'ingredient-human', refs: [_ref('2')]),
        ]),
        1,
      );
    });
  });

  group('evidenceTotalEnrollment', () {
    test('sums enrollment for human-grade matches only', () {
      expect(
        evidenceTotalEnrollment([
          _match(evidence: 'ingredient-human', totalEnrollment: 200),
          _match(evidence: 'branded-rct', totalEnrollment: 100),
          _match(evidence: 'preclinical', totalEnrollment: 9999),
          _match(evidence: 'reference', totalEnrollment: 5000),
        ]),
        300,
      );
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

    test(
      'supportive human meta-analysis ingredient evidence resolves to strong',
      () {
        expect(
          evidenceTier([
            _match(
              evidence: 'ingredient-human',
              studyType: 'systematic_review_meta',
              effectDirection: 'positive_strong',
            ),
          ]),
          EvidenceTier.strong,
        );
        expect(
          evidenceTier([
            _match(
              evidence: 'ingredient-human',
              publishedStudies: ['RCT', 'systematic_review', 'meta-analysis'],
              effectDirection: 'positive_weak',
            ),
          ]),
          EvidenceTier.strong,
        );
      },
    );

    test('mixed or null meta-analysis evidence does not resolve to strong', () {
      expect(
        evidenceTier([
          _match(
            evidence: 'ingredient-human',
            studyType: 'systematic_review_meta',
            effectDirection: 'mixed',
          ),
        ]),
        EvidenceTier.moderate,
      );
      expect(
        evidenceTier([
          _match(
            evidence: 'ingredient-human',
            studyType: 'systematic_review_meta',
            effectDirection: 'null',
          ),
        ]),
        EvidenceTier.moderate,
      );
    });

    test('negative human evidence resolves to limited', () {
      expect(
        evidenceTier([
          _match(
            evidence: 'ingredient-human',
            studyType: 'systematic_review_meta',
            effectDirection: 'negative',
          ),
        ]),
        EvidenceTier.limited,
      );
    });
  });

  group('evidenceScope', () {
    test(
      'uses pipeline ui_evidence_scope only when it does not overstate level',
      () {
        expect(
          evidenceScope([
            _match(evidence: 'product-human', uiEvidenceScope: 'ingredient'),
          ]),
          EvidenceScope.ingredient,
        );
        expect(
          evidenceScope([
            _match(evidence: 'reference', uiEvidenceScope: 'product'),
          ]),
          EvidenceScope.indirect,
        );
      },
    );
  });

  group('evidenceHeadline', () {
    test('product-human leads with direct product copy', () {
      expect(
        evidenceHeadline([_match(evidence: 'product-human')]),
        'Direct human research exists for this product or formulation.',
      );
    });

    test('branded-rct leads with branded ingredient copy', () {
      expect(
        evidenceHeadline([_match(evidence: 'branded-rct')]),
        'A branded ingredient in this product has human clinical research.',
      );
    });

    test('aggregates study count and enrollment', () {
      final headline = evidenceHeadline([
        _match(refs: [_ref('1'), _ref('2')], totalEnrollment: 400),
        _match(refs: [_ref('3')], totalEnrollment: 220),
      ]);

      expect(headline, 'Includes 3 human studies · ~620 participants');
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

    test('preclinical refs/enrollment never inflate the human headline', () {
      final headline = evidenceHeadline([
        _match(refs: [_ref('1')], totalEnrollment: 100),
        _match(
          evidence: 'preclinical',
          refs: [_ref('2'), _ref('3')],
          totalEnrollment: 9000,
        ),
      ]);
      expect(headline, 'Includes 1 human study · ~100 participants');
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

    testWidgets('product-human renders product-scoped strong evidence', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'product-human',
              refs: [_ref('111', title: 'A randomized trial of ashwagandha')],
            ),
          ],
        },
      );

      expect(find.text('Clinical evidence'), findsOneWidget);
      expect(find.text('Product evidence: STRONG · 1 study'), findsOneWidget);
      expect(
        find.text(
          'Direct human research exists for this product or formulation.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('branded-rct renders branded-ingredient scoped evidence', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'branded-rct',
              refs: [_ref('111', title: 'A randomized trial of KSM-66')],
            ),
          ],
        },
      );

      expect(
        find.text('Branded ingredient evidence: STRONG · 1 study'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Human research exists for a branded ingredient used in this product, not necessarily the finished product.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining("product's formulation"), findsNothing);
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
      expect(
        find.text('Ingredient evidence: MODERATE · 1 study'),
        findsOneWidget,
      );
    });

    testWidgets('preclinical only renders limited tier with no study count', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'preclinical', refs: [_ref('111')]),
          ],
        },
      );

      // Preclinical refs inform the tier only — never a "study" count
      // that downstream copy could read as human studies.
      expect(find.text('Early evidence: LIMITED'), findsOneWidget);
      expect(find.textContaining('study'), findsNothing);
      expect(find.textContaining('meta-analysis'), findsNothing);
    });

    testWidgets('match_count > 0 with zero parsed matches hides section', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: const {
          'match_count': 3,
          'clinical_matches': <Map<String, dynamic>>[],
        },
      );

      expect(find.byType(PGEvidenceSection), findsNothing);
    });

    testWidgets(
      'product evidence helper line never claims generic claims support',
      (tester) async {
        await _pump(
          tester,
          evidenceData: {
            'match_count': 1,
            'clinical_matches': [
              _match(evidence: 'product-human', refs: [_ref('111')]),
            ],
          },
        );

        expect(
          find.text(
            'Direct human research exists for this product or formulation.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('support these claims'), findsNothing);
      },
    );

    testWidgets('strong product evidence keeps product scope with 2+ studies', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'product-human', refs: [_ref('111'), _ref('222')]),
          ],
        },
      );

      expect(
        find.text(
          'Direct human research exists for this product or formulation.',
        ),
        findsOneWidget,
      );
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

      expect(find.text('Ingredient evidence: MODERATE'), findsOneWidget);
      expect(find.textContaining('PMID'), findsNothing);
    });

    testWidgets(
      'creatine-style ingredient meta-analysis renders scoped strong evidence',
      (tester) async {
        await _pump(
          tester,
          evidenceData: {
            'match_count': 1,
            'clinical_matches': [
              _match(
                evidence: 'ingredient-human',
                studyType: 'systematic_review_meta',
                effectDirection: 'positive_strong',
                refs: [_ref('39519498'), _ref('39074168')],
                totalEnrollment: 220,
              ),
            ],
          },
        );

        expect(
          find.text('Ingredient evidence: STRONG · 2 studies · meta-analysis'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Ashwagandha: strong ingredient evidence · 2 human studies · ~220 participants',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Human research supports one or more ingredients, not necessarily this exact product.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('support these claims'), findsNothing);
      },
    );

    testWidgets('mixed ingredient meta-analysis renders review-style copy', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'ingredient-human',
              studyType: 'systematic_review_meta',
              effectDirection: 'mixed',
              refs: [_ref('15537682')],
            ),
          ],
        },
      );

      expect(
        find.text('Ingredient evidence: MODERATE · 1 study · meta-analysis'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Human studies exist for one or more ingredients; results may be mixed and do not prove this exact product.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('support these claims'), findsNothing);
    });

    testWidgets(
      'product mixed evidence plus supportive ingredient meta renders ingredient scope',
      (tester) async {
        await _pump(
          tester,
          evidenceData: {
            'match_count': 2,
            'clinical_matches': [
              _match(
                ingredient: 'Exact Product',
                evidence: 'product-human',
                effectDirection: 'mixed',
                refs: [_ref('111')],
              ),
              _match(
                ingredient: 'Creatine Monohydrate',
                evidence: 'ingredient-human',
                studyType: 'systematic_review_meta',
                effectDirection: 'positive_strong',
                refs: [_ref('222'), _ref('333')],
              ),
            ],
          },
        );

        expect(
          find.text('Ingredient evidence: STRONG · 2 studies · meta-analysis'),
          findsOneWidget,
        );
        expect(find.textContaining('Product evidence: STRONG'), findsNothing);
        expect(
          find.text(
            'Human research supports one or more ingredients, not necessarily this exact product.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'negative ingredient evidence renders non-supportive limited copy',
      (tester) async {
        await _pump(
          tester,
          evidenceData: {
            'match_count': 1,
            'clinical_matches': [
              _match(
                evidence: 'ingredient-human',
                studyType: 'systematic_review_meta',
                effectDirection: 'negative',
                refs: [_ref('999')],
              ),
            ],
          },
        );

        expect(
          find.text('Ingredient evidence: LIMITED · 1 study · meta-analysis'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Human studies for one or more ingredients show no benefit or possible unfavorable results; this does not support the product.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('MODERATE'), findsNothing);
        expect(find.textContaining('support these claims'), findsNothing);
      },
    );

    testWidgets('surfaces the strongest ingredient attribution', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 2,
          'clinical_matches': [
            _match(
              ingredient: 'Vitamin D3',
              evidence: 'ingredient-human',
              studyType: 'systematic_review_meta',
              effectDirection: 'positive_strong',
              refs: [_ref('111'), _ref('222'), _ref('333')],
            ),
            _match(
              ingredient: 'Vitamin K2',
              evidence: 'ingredient-human',
              refs: [_ref('444')],
            ),
          ],
        },
      );

      expect(
        find.text('Vitamin D3: strong ingredient evidence · 3 human studies'),
        findsOneWidget,
      );
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
          'This research feeds the Evidence pillar; only Product evidence means the exact product or formulation was studied.',
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
      expect(
        find.text('Ingredient evidence: MODERATE · 8 studies'),
        findsOneWidget,
      );
    });
  });
}
