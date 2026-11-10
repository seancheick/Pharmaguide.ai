// Match-level dedupe tests for the evidence section adapter — mirrors
// the verified dsld_id 315678 shape where the SAME study matched via
// both the elemental row ('Magnesium') and the compound row
// ('Magnesium Glycinate'), appearing twice in clinical_matches with
// the same study_id.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_evidence_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/evidence_section.dart';

Map<String, dynamic> _mgMatch({
  required String ingredient,
  String studyId = 'INGR_MAGNESIUM_GENERIC',
  String evidenceLevel = 'ingredient-human',
  int enrollment = 2500,
  List<Map<String, dynamic>>? refs,
}) {
  return {
    'ingredient': ingredient,
    'standard_name': ingredient,
    'study_id': studyId,
    'id': studyId,
    'study_name': 'Magnesium (Generic)',
    'evidence_level': evidenceLevel,
    'study_type': 'meta-analysis',
    'total_enrollment': enrollment,
    'references_structured':
        refs ??
        [
          {'pmid': '11111111', 'title': 'Magnesium RCT'},
        ],
  };
}

void main() {
  group('pipeline ingredient research', () {
    final research = <String, dynamic>{
      'ingredient': 'Reviewed botanical',
      'summary': 'Some short-term human research.',
      'applicability_note':
          'This preparation is unknown; results may not apply.',
      'studied_uses': [
        {'outcome': 'Studied use', 'summary': 'Limited human support.'},
      ],
      'references_structured': [
        {'pmid': '23439798', 'title': 'Reviewed research source'},
      ],
    };

    testWidgets('research renders without clinical matches or inferred tier', (
      tester,
    ) async {
      final data = <String, dynamic>{
        'ingredient_research': [research],
      };
      expect(hasRenderableClinicalEvidence(data), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildEvidenceSection(evidenceData: data),
            ),
          ),
        ),
      );
      expect(find.text('Reviewed botanical'), findsOneWidget);
      expect(find.text('Some short-term human research.'), findsOneWidget);
      expect(find.text('Studied use'), findsOneWidget);
      expect(find.text('Limited human support.'), findsOneWidget);
      expect(
        find.text('This preparation is unknown; results may not apply.'),
        findsOneWidget,
      );
      final section = tester.widget<PGEvidenceSection>(
        find.byType(PGEvidenceSection),
      );
      expect(section.tier, PGEvidenceTier.none);
      expect(section.totalStudies, 0);
      expect(section.citations.single.pmid, '23439798');
      await tester.tap(find.text('View sources (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Reviewed research source'), findsOneWidget);
      expect(
        find.text('This preparation is unknown; results may not apply.'),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'authored research suppresses legacy ingredient strength subtitle',
      (tester) async {
        final match = _mgMatch(ingredient: 'Reviewed botanical');
        Future<void> render(bool withResearch) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: buildEvidenceSection(
                  evidenceData: {
                    'clinical_matches': [match],
                    if (withResearch) 'ingredient_research': [research],
                  },
                  presentationTier: PGEvidenceTier.limited,
                  summaryLine: 'Limited · 10.4/20',
                  helperLine: 'Qualified pipeline explanation',
                ),
              ),
            ),
          ),
        );
        await render(false);
        expect(
          tester
              .widget<PGEvidenceSection>(find.byType(PGEvidenceSection))
              .subtitle,
          contains('strong ingredient evidence'),
        );
        await render(true);
        final section = tester.widget<PGEvidenceSection>(
          find.byType(PGEvidenceSection),
        );
        expect(section.subtitle, isNull);
        expect(section.tier, PGEvidenceTier.limited);
        expect(find.text('Limited · 10.4/20'), findsOneWidget);
        expect(find.text('Qualified pipeline explanation'), findsOneWidget);
        expect(find.textContaining('strong ingredient evidence'), findsNothing);
        expect(find.text('Some short-term human research.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('canonical presentation and existing extra content survive', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildEvidenceSection(
                evidenceData: {
                  'ingredient_research': [research],
                },
                presentationTier: PGEvidenceTier.limited,
                summaryLine: 'Canonical evidence assessment',
                cardExtra: const Text('Existing card content'),
                relatedResearch: const Text('Existing sheet content'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Canonical evidence assessment'), findsOneWidget);
      expect(find.text('Existing card content'), findsOneWidget);
      expect(
        tester.widget<PGEvidenceSection>(find.byType(PGEvidenceSection)).tier,
        PGEvidenceTier.limited,
      );
      await tester.tap(find.text('View sources (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Existing sheet content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'clinical and research citations dedupe without extra study credit',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: buildEvidenceSection(
                  evidenceData: {
                    'clinical_matches': [
                      _mgMatch(
                        ingredient: 'Reviewed botanical',
                        refs: [
                          {
                            'pmid': '23439798',
                            'title': 'Reviewed research source',
                          },
                        ],
                      ),
                    ],
                    'ingredient_research': [
                      {
                        ...research,
                        'references_structured': [
                          {
                            'pmid': '23439798',
                            'title': 'Reviewed research source',
                          },
                          {
                            'pmid': '32021735',
                            'title': 'Additional research source',
                          },
                        ],
                      },
                    ],
                  },
                ),
              ),
            ),
          ),
        );
        final section = tester.widget<PGEvidenceSection>(
          find.byType(PGEvidenceSection),
        );
        expect(section.totalStudies, 1);
        expect(section.citations, hasLength(2));
        expect(section.tier, PGEvidenceTier.strong);
        expect(find.text('What the research suggests'), findsOneWidget);
        expect(find.text('What remains uncertain'), findsOneWidget);
        await tester.tap(find.text('View studies (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Reviewed research source'), findsOneWidget);
        expect(find.text('Additional research source'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'null and malformed research neither crash nor invent content',
      (tester) async {
        for (final data in <Map<String, dynamic>?>[
          null,
          {'ingredient_research': null},
          {'ingredient_research': 'bad'},
          {
            'ingredient_research': [
              null,
              7,
              {'ingredient': <String, dynamic>{}, 'summary': <dynamic>[]},
            ],
          },
        ]) {
          expect(hasRenderableClinicalEvidence(data), isFalse);
          await tester.pumpWidget(
            MaterialApp(home: buildEvidenceSection(evidenceData: data)),
          );
          expect(find.byType(PGEvidenceSection), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: buildEvidenceSection(
                  evidenceData: {
                    'ingredient_research': [
                      {
                        ...research,
                        'studied_uses': [
                          null,
                          'bad',
                          {'outcome': <dynamic>[]},
                        ],
                        'references_structured': 'bad',
                      },
                    ],
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.text('Some short-term human research.'), findsOneWidget);
        expect(find.text('[]'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('dedupeClinicalMatches', () {
    test('same study via elemental + compound rows counts once', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium'),
        _mgMatch(ingredient: 'Magnesium Glycinate'),
      ]);
      expect(deduped, hasLength(1));
      expect(deduped.single['ingredient'], 'Magnesium');
    });

    test('falls back to id when study_id is missing or empty', () {
      final a = _mgMatch(ingredient: 'Magnesium')
        ..remove('study_id')
        ..['study_id'] = '';
      final b = _mgMatch(ingredient: 'Magnesium Glycinate')..remove('study_id');
      expect(dedupeClinicalMatches([a, b]), hasLength(1));
    });

    test('matches with no identity are kept (never drop evidence)', () {
      final a = _mgMatch(ingredient: 'Magnesium')
        ..remove('study_id')
        ..remove('id');
      final b = _mgMatch(ingredient: 'Magnesium Glycinate')
        ..remove('study_id')
        ..remove('id');
      expect(dedupeClinicalMatches([a, b]), hasLength(2));
    });

    test('distinct studies still count separately', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium'),
        _mgMatch(
          ingredient: 'Zinc',
          studyId: 'INGR_ZINC_GENERIC',
          enrollment: 800,
        ),
      ]);
      expect(deduped, hasLength(2));
    });
  });

  group('downstream computation on deduped matches', () {
    test('enrollment sums once for a duplicated study', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium', enrollment: 2500),
        _mgMatch(ingredient: 'Magnesium Glycinate', enrollment: 2500),
      ]);
      expect(evidenceTotalEnrollment(deduped), 2500);
      expect(evidenceTotalStudies(deduped), 1);
      expect(evidenceCitations(deduped), hasLength(1));
    });

    test('distinct studies sum enrollment and counts separately', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium', enrollment: 2500),
        _mgMatch(
          ingredient: 'Zinc',
          studyId: 'INGR_ZINC_GENERIC',
          enrollment: 800,
          refs: [
            {'pmid': '22222222', 'title': 'Zinc RCT'},
          ],
        ),
      ]);
      expect(evidenceTotalEnrollment(deduped), 3300);
      expect(evidenceTotalStudies(deduped), 2);
      expect(evidenceCitations(deduped), hasLength(2));
    });

    test('tier unaffected by dedupe — duplicate strong match', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium', evidenceLevel: 'product-human'),
        _mgMatch(
          ingredient: 'Magnesium Glycinate',
          evidenceLevel: 'product-human',
        ),
      ]);
      expect(evidenceTier(deduped), EvidenceTier.strong);
    });
  });
}
