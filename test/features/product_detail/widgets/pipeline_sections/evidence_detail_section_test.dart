import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/pubmed_launcher.dart';
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
  test('one PMID and its link-only aliases dedupe in either order', () {
    for (final shared in [
      {'doi': '10.1234/shared'},
      {'url': 'https://example.org/shared'},
    ]) {
      final bare = {'title': 'Source', ...shared};
      final study = {'title': 'Study', 'pmid': '12345', ...shared};
      for (final refs in [
        [bare, study],
        [study, bare],
      ]) {
        expect(evidenceCitations([], sourceReferences: refs), hasLength(1));
      }
      // A link-only bridge must not hide a second, distinct PubMed record.
      expect(
        evidenceCitations(
          [],
          sourceReferences: [
            bare,
            study,
            {'title': 'Other study', 'pmid': '67890', ...shared},
            bare,
          ],
        ),
        hasLength(2),
      );
    }
  });

  test('link-only bridges retain distinct PMID identities', () {
    expect(
      evidenceCitations(
        [],
        sourceReferences: [
          {'title': 'First', 'pmid': '12345', 'doi': '10.1234/shared'},
          {
            'title': 'Bridge',
            'doi': '10.1234/shared',
            'url': 'https://example.org/shared',
          },
          {
            'title': 'Second',
            'pmid': '67890',
            'url': 'https://example.org/shared',
          },
        ],
      ),
      hasLength(2),
    );
  });

  test('conflicting PubMed URL cannot replace an explicit PMID', () {
    final first = {
      'title': 'First',
      'pmid': '123',
      'url': 'https://pubmed.ncbi.nlm.nih.gov/456/',
    };
    final second = {'title': 'Second', 'pmid': '456'};
    for (final refs in [
      [first, second],
      [second, first],
    ]) {
      expect(
        evidenceCitations([], sourceReferences: refs).map((c) => c.pmid),
        refs.map((ref) => ref['pmid']),
      );
    }
  });

  test('URL-derived PMID remains distinct from conflicting explicit PMID', () {
    final urlOnly = {
      'title': 'URL study',
      'url': 'https://pubmed.ncbi.nlm.nih.gov/456/',
    };
    final explicit = {
      'title': 'Explicit study',
      'pmid': '123',
      'url': 'https://pubmed.ncbi.nlm.nih.gov/456/',
    };
    for (final refs in [
      [urlOnly, explicit],
      [explicit, urlOnly],
    ]) {
      expect(evidenceCitations([], sourceReferences: refs), hasLength(2));
    }
  });

  test('malformed PMIDs never count as human studies', () {
    expect(
      evidenceTotalStudies([
        _match(
          refs: [
            _ref('123'),
            _ref(' 123 '),
            _ref('PMID:456'),
            _ref('12x'),
            _ref('-1'),
            _ref('0'),
            _ref('000'),
            _ref(''),
            _ref('456'),
          ],
        ),
      ]),
      2,
    );
  });

  test('legacy DOI resolver dedupes against the DOI identity', () {
    final citations = evidenceCitations(
      [],
      sourceReferences: [
        {'title': 'Legacy URL', 'url': 'https://dx.doi.org/10.1234/example'},
        {'title': 'Same DOI', 'doi': '10.1234/example'},
      ],
    );
    expect(citations, hasLength(1));
  });

  test('distinct PMIDs survive shared DOI and URL identities', () {
    for (final shared in [
      {'doi': '10.1234/shared'},
      {'url': 'https://example.org/shared'},
    ]) {
      final citations = evidenceCitations(
        [],
        sourceReferences: [
          {'pmid': '12345', 'title': 'First study', ...shared},
          {'pmid': '67890', 'title': 'Second study', ...shared},
          {'pmid': '12345', 'title': 'Duplicate first study', ...shared},
        ],
      );
      expect(citations.map((citation) => citation.pmid), ['12345', '67890']);
    }
  });

  test('source links reject unsafe schemes, credentials and malformed DOI', () {
    for (final url in [
      'javascript:alert(1)',
      'data:text/html,x',
      'file:///private/x',
      '//example.org/x',
      'https://user@example.org/x',
      'https://example.org/a b',
      'http://example.org',
    ]) {
      expect(evidenceSourceUri(url: url), isNull, reason: url);
    }
    expect(evidenceSourceUri(doi: 'not-a-doi'), isNull);
    expect(
      evidenceSourceUri(doi: '10.17226/10490').toString(),
      'https://doi.org/10.17226/10490',
    );
  });

  test('mixed sources dedupe identities without creating clinical studies', () {
    final matches = [
      _match(refs: [_ref('123', title: 'Human study')]),
    ];
    final citations = evidenceCitations(
      matches,
      sourceReferences: [
        {'title': 'Duplicate', 'url': 'https://pubmed.ncbi.nlm.nih.gov/123/'},
        {'title': 'DRI', 'doi': '10.17226/10490'},
        {'title': 'Duplicate DRI', 'url': 'https://doi.org/10.17226/10490'},
        {'title': 'Unsafe', 'url': 'javascript:alert(1)'},
        {'url': 'https://example.org'},
        {'title': 'Invalid PMID', 'pmid': '123/evil'},
      ],
    );
    expect(citations, hasLength(2));
    expect(evidenceTotalStudies(matches), 1);
    expect(evidenceTier(matches), EvidenceTier.moderate);
  });

  testWidgets('authority-only metadata uses sources without clinical claims', (
    tester,
  ) async {
    await _pump(
      tester,
      evidenceData: {
        'source_references': [
          {
            'title': 'Dietary Reference Intakes',
            'authority': 'National Academies',
            'doi': '10.17226/10490',
          },
        ],
      },
    );
    final section = tester.widget<PGEvidenceSection>(
      find.byType(PGEvidenceSection),
    );
    expect(section.totalStudies, 0);
    expect(section.hasMetaAnalysis, isFalse);
    expect(find.text('Clinical evidence'), findsNothing);
    expect(find.text('No direct evidence'), findsNothing);
    await tester.tap(find.text('View sources (1)'));
    await tester.pumpAndSettle();
    expect(find.text('National Academies'), findsOneWidget);
    expect(find.textContaining('PMID'), findsNothing);
  });

  test('missing sources do not borrow unrelated Dose citations', () {
    expect(
      hasRenderableClinicalEvidence({
        'dose': {
          'source_references': [
            {'title': 'Dose', 'url': 'https://example.org'},
          ],
        },
        'source_references': ['malformed', null],
      }),
      isFalse,
    );
    expect(evidenceCitations([]), isEmpty);
  });

  test(
    'HTTPS DOI-host sources with absent or malformed identity do not crash',
    () {
      final citations = evidenceCitations(
        [],
        sourceReferences: [
          {'title': 'Authority landing page', 'url': 'https://doi.org'},
          {'title': 'Malformed DOI identity', 'url': 'https://doi.org/%FF'},
        ],
      );
      expect(citations.map((citation) => citation.title), [
        'Authority landing page',
        'Malformed DOI identity',
      ]);
      expect(citations.every((citation) => citation.pmid.isEmpty), isTrue);
    },
  );

  test(
    'malformed UTF8 DOI path remains a source without decoded DOI identity',
    () {
      final citations = evidenceCitations(
        [],
        sourceReferences: [
          {'title': 'Malformed identity', 'url': 'https://doi.org/%FF'},
        ],
      );
      expect(citations.single.title, 'Malformed identity');
    },
  );

  test(
    'DOI case variants share identity while source destinations retain case',
    () {
      const original = 'https://doi.org/10.1234/MixedCase';
      expect(evidenceSourceUri(url: original).toString(), original);
      expect(evidenceSourceUri(doi: '10.1234/MixedCase').toString(), original);
      expect(evidenceDoiIdentity('10.1234/MixedCase'), '10.1234/mixedcase');
      final citations = evidenceCitations(
        [],
        sourceReferences: [
          {'title': 'Original', 'url': original},
          {'title': 'Duplicate raw DOI', 'doi': '10.1234/mixedcase'},
          {
            'title': 'Duplicate URL',
            'url': 'https://doi.org/10.1234/MIXEDCASE',
          },
        ],
      );
      expect(citations.single.title, 'Original');
    },
  );

  test('authority and DOI references use the shared citation collector', () {
    final citations = evidenceCitations([
      _match(
        refs: [
          {
            'title': 'Vitamin A and Carotenoids',
            'authority': 'NIH ODS',
            'url':
                'https://ods.od.nih.gov/factsheets/VitaminA-HealthProfessional/',
          },
          {
            'title': 'Dietary Reference Intakes',
            'authority': 'National Academies',
            'doi': '10.17226/10490',
          },
        ],
      ),
    ]);
    expect(citations, hasLength(2));
    expect(citations.first.title, 'Vitamin A and Carotenoids');
    expect(citations.every((citation) => citation.pmid.isEmpty), isTrue);
  });

  group('hasRenderableClinicalEvidence', () {
    test('requires parsed clinical match rows, not match_count alone', () {
      expect(
        hasRenderableClinicalEvidence({
          'match_count': 2,
          'clinical_matches': const <Map<String, dynamic>>[],
        }),
        isFalse,
      );
      expect(
        hasRenderableClinicalEvidence({
          'match_count': 1,
          'clinical_matches': [
            {'study_id': 'PMID-1', 'evidence_level': 'ingredient-human'},
          ],
        }),
        isTrue,
      );
    });
  });
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
      expect(find.text('Product evidence: Strong · 1 study'), findsOneWidget);
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
        find.text('Branded ingredient evidence: Strong · 1 study'),
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

      // Citations now live behind the studies sheet, not inline on the card.
      await tester.tap(find.text('View studies (2)'));
      await tester.pumpAndSettle();

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

      expect(
        find.text('Ingredient evidence: Moderate · 1 study'),
        findsOneWidget,
      );

      await tester.tap(find.text('View studies (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Shared study'), findsOneWidget);
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
      expect(find.text('Early evidence: Limited'), findsOneWidget);
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

      expect(find.text('Ingredient evidence: Moderate'), findsOneWidget);
      expect(find.textContaining('PMID'), findsNothing);
    });

    // Critique 2026-09-29: "~14573 participants" had no thousands separator.
    testWidgets('large enrollment reads with a thousands separator', (
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
              effectDirection: 'positive_strong',
              refs: [_ref('39519498'), _ref('39074168')],
              totalEnrollment: 14573,
            ),
          ],
        },
      );

      expect(find.textContaining('~14,573 participants'), findsOneWidget);
      expect(find.textContaining('14573'), findsNothing);
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
          find.text('Ingredient evidence: Strong · 2 studies · meta-analysis'),
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
        find.text('Ingredient evidence: Moderate · 1 study · meta-analysis'),
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
          find.text('Ingredient evidence: Strong · 2 studies · meta-analysis'),
          findsOneWidget,
        );
        expect(find.textContaining('Product evidence: Strong'), findsNothing);
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
          find.text('Ingredient evidence: Limited · 1 study · meta-analysis'),
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

    testWidgets('studies sheet shows every study the button promises', (
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
                for (var i = 1; i <= 8; i++) _ref('$i', title: 'Study $i'),
              ],
            ),
          ],
        },
      );

      // Card summary reflects all deduped studies.
      expect(
        find.text('Ingredient evidence: Moderate · 8 studies'),
        findsOneWidget,
      );

      // The scrollable sheet shows ALL 8 — the "View studies (8)" button must
      // never promise more rows than the sheet holds (was capped at 5).
      await tester.tap(find.text('View studies (8)'));
      await tester.pumpAndSettle();

      expect(find.text('Study 5'), findsOneWidget);
      expect(find.text('Study 8'), findsOneWidget);
    });
  });
}
