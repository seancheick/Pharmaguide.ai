// Tests for DepletionChecker — three-state coverage (none / partial /
// adequate) and authored-copy passthrough.
//
// Uses injected fixtures (not the bundled asset) so tests are
// deterministic regardless of authoring progress. See
// scripts/SAFETY_DATA_PATH_C_PLAN.md in the pipeline repo for the
// schema v5.2 contract these assertions codify.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

Map<String, dynamic> _metforminB12Fixture({
  num? adequacyMcg,
  Map<String, String?>? authoredCopy,
}) {
  return {
    'depletions': [
      {
        'id': 'DEP_METFORMIN_VITAMINB12',
        'drug_ref': {
          'id': '860974',
          'display_name': 'Metformin (type 2 diabetes medication)',
        },
        'depleted_nutrient': {
          'standard_name': 'Vitamin B12',
          'canonical_id': 'vitamin_b12',
        },
        'depletion_type': 'depletion',
        'severity': 'significant',
        'mechanism': 'Metformin impairs B12 absorption.',
        'clinical_impact': 'Up to 30% of long-term users develop low B12.',
        'recommendation': 'Consider B12 supplementation.',
        'onset_timeline': 'years',
        'evidence_level': 'established',
        'sources': [
          {'source_type': 'reference', 'url': 'https://example.test/nih-b12'},
        ],
        if (adequacyMcg != null) 'adequacy_threshold_mcg': adequacyMcg,
        if (authoredCopy != null) ...authoredCopy,
      },
    ],
  };
}

void main() {
  final checker = DepletionChecker();

  group('DepletionChecker — identity integrity (B1.1)', () {
    // A medication-nutrient signal's stable identity derives from the entry
    // `id`. A missing id (previously silently emitted as '') or a duplicate id
    // makes that identity unstable/colliding, so the entry must NOT produce a
    // signal — the app defensively drops it (the pipeline is the primary gate).
    Map<String, dynamic> metforminEntry({
      required Object? id,
      String nutrient = 'Vitamin B12',
      String canonicalId = 'vitamin_b12',
    }) => {
      if (id != null) 'id': id,
      'drug_ref': {
        'id': '860974',
        'display_name': 'Metformin (type 2 diabetes medication)',
      },
      'depleted_nutrient': {
        'standard_name': nutrient,
        'canonical_id': canonicalId,
      },
      'depletion_type': 'depletion',
      'severity': 'significant',
      'mechanism': 'x',
      'recommendation': 'y',
    };

    const metformin = (name: 'Metformin', drugClassId: null);

    test('entry with missing id is dropped, never emitted with an empty id', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [metforminEntry(id: null)],
        },
      );
      expect(out, isEmpty);
    });

    test('entry with empty-string id is dropped', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [metforminEntry(id: '')],
        },
      );
      expect(out, isEmpty);
    });

    test('duplicate ids across entries are all dropped (no colliding signals)', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [
            metforminEntry(id: 'DUP'),
            metforminEntry(id: 'DUP', nutrient: 'Folate', canonicalId: 'folate'),
          ],
        },
      );
      expect(out, isEmpty);
    });

    test('valid unique id still emits normally', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [metforminEntry(id: 'DEP_METFORMIN_VITAMINB12')],
        },
      );
      expect(out, hasLength(1));
      expect(out.single.depletionId, 'DEP_METFORMIN_VITAMINB12');
    });

    test('onDataIssue reports missing and duplicate ids', () {
      final issues = <String>[];
      checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [
            metforminEntry(id: null),
            metforminEntry(id: 'DUP'),
            metforminEntry(id: 'DUP', nutrient: 'Folate', canonicalId: 'folate'),
          ],
        },
        onDataIssue: issues.add,
      );
      expect(issues.any((m) => m.contains('missing id')), isTrue);
      expect(issues.any((m) => m.contains('duplicate')), isTrue);
    });
  });

  group('DepletionChecker — detected amount plumbing (B1.1)', () {
    // Factual supply copy ("your stack contains X mcg per day") needs the
    // detected stack amount + unit surfaced on the match, not just the
    // computed coverage band.
    const metformin = (name: 'Metformin', drugClassId: null);

    test('emits detected amount + unit from the matched stack dose', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: _metforminB12Fixture(adequacyMcg: 100),
        stackDoses: const [
          StackSupplementDose(
            canonicalId: 'vitamin_b12',
            doseAmount: 50,
            doseUnit: 'mcg',
          ),
        ],
      );
      expect(out, hasLength(1));
      expect(out.single.detectedAmount, 50);
      expect(out.single.detectedUnit, 'mcg');
    });

    test('detected amount + unit are null when no dose is supplied', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: _metforminB12Fixture(),
      );
      expect(out, hasLength(1));
      expect(out.single.detectedAmount, isNull);
      expect(out.single.detectedUnit, isNull);
    });
  });

  group('DepletionChecker — canonical subject validation (B1.1)', () {
    // A signal's subjects are the drug/condition + the nutrient canonical id.
    // A matched entry missing the nutrient canonical id would emit a signal
    // with no stable nutrient subject, so it is dropped (app-defensive; the
    // pipeline is the primary gate that resolves ids against the catalog).
    const metformin = (name: 'Metformin', drugClassId: null);

    Map<String, dynamic> entry({Object? canonicalId = 'vitamin_b12'}) => {
      'id': 'DEP_METFORMIN_VITAMINB12',
      'drug_ref': {
        'id': '860974',
        'display_name': 'Metformin (type 2 diabetes medication)',
      },
      'depleted_nutrient': {
        'standard_name': 'Vitamin B12',
        if (canonicalId != null) 'canonical_id': canonicalId,
      },
      'depletion_type': 'depletion',
      'severity': 'significant',
    };

    test('entry missing the nutrient canonical_id is dropped', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [entry(canonicalId: null)],
        },
      );
      expect(out, isEmpty);
    });

    test('entry with a blank nutrient canonical_id is dropped', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [entry(canonicalId: '   ')],
        },
      );
      expect(out, isEmpty);
    });

    test('onDataIssue reports the dropped canonical subject', () {
      final issues = <String>[];
      checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [entry(canonicalId: null)],
        },
        onDataIssue: issues.add,
      );
      expect(issues.any((m) => m.contains('canonical subject')), isTrue);
    });

    test('valid nutrient canonical_id still emits', () {
      final out = checker.check(
        medications: const [metformin],
        depletionsData: {
          'depletions': [entry()],
        },
      );
      expect(out, hasLength(1));
      expect(out.single.nutrientCanonicalId, 'vitamin_b12');
    });
  });

  group('medNutrientRelationshipLabel (B1.1)', () {
    test('maps each relationship type to consumer language', () {
      expect(
        medNutrientRelationshipLabel('depletion'),
        'Associated nutrient to monitor',
      );
      expect(
        medNutrientRelationshipLabel('condition_related'),
        'Condition-related nutrient consideration',
      );
      expect(
        medNutrientRelationshipLabel('functional_antagonism'),
        'May affect nutrient function',
      );
      expect(
        medNutrientRelationshipLabel('monitoring_stability'),
        'Monitoring consideration',
      );
      expect(
        medNutrientRelationshipLabel('supplement_interaction'),
        'Supplement consideration',
      );
    });

    test('non-depletion types never read as "depletion"', () {
      for (final t in const [
        'functional_antagonism',
        'monitoring_stability',
        'supplement_interaction',
        'condition_related',
        'unknown_future_type',
      ]) {
        expect(
          medNutrientRelationshipLabel(t).toLowerCase(),
          isNot(contains('deplet')),
        );
      }
    });

    test('unknown type falls back to a neutral label', () {
      expect(medNutrientRelationshipLabel('something_new'), 'Nutrient consideration');
    });

    test('is case/whitespace tolerant', () {
      expect(
        medNutrientRelationshipLabel('  Depletion '),
        'Associated nutrient to monitor',
      );
    });
  });

  group('DepletionChecker — medication matching', () {
    test('no medications returns empty results', () {
      final out = checker.check(
        medications: const [],
        depletionsData: _metforminB12Fixture(),
      );
      expect(out, isEmpty);
    });

    test('matches by drug display name substring', () {
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(),
      );
      expect(out, hasLength(1));
      expect(out.first.depletionId, 'DEP_METFORMIN_VITAMINB12');
    });

    test('matches generic RxCUI when user selected a brand medication', () {
      final out = checker.check(
        medications: const [],
        medicationIdentities: const [
          DepletionMedicationIdentity(
            name: 'Xenical',
            rxcui: '312962',
            genericRxcui: '37925',
          ),
        ],
        depletionsData: {
          'depletions': [
            {
              'id': 'DEP_ORLISTAT_VITAMIND',
              'drug_ref': {
                'type': 'drug',
                'id': '37925',
                'display_name': 'Orlistat',
              },
              'depleted_nutrient': {
                'standard_name': 'Vitamin D',
                'canonical_id': 'vitamin_d',
              },
              'severity': 'moderate',
            },
          ],
        },
      );
      expect(out, hasLength(1));
      expect(out.first.depletionId, 'DEP_ORLISTAT_VITAMIND');
    });

    test('matches ingredient RxCUI for combination medications', () {
      final out = checker.check(
        medications: const [],
        medicationIdentities: const [
          DepletionMedicationIdentity(
            name: 'Combination medicine',
            rxcui: '999999',
            ingredientRxcuis: ['9524'],
          ),
        ],
        depletionsData: {
          'depletions': [
            {
              'id': 'DEP_SULFASALAZINE_FOLATE',
              'drug_ref': {
                'type': 'drug',
                'id': '9524',
                'display_name': 'Sulfasalazine',
              },
              'depleted_nutrient': {
                'standard_name': 'Folate',
                'canonical_id': 'folate',
              },
              'severity': 'moderate',
            },
          ],
        },
      );
      expect(out, hasLength(1));
      expect(out.first.depletionId, 'DEP_SULFASALAZINE_FOLATE');
    });

    test(
      'matches high-value brand-name prescriptions through generic RxCUI',
      () {
        final cases = [
          (
            brandName: 'Questran',
            genericRxcui: '2447',
            depletionId: 'DEP_CHOLESTYRAMINE_VITAMINK',
            genericName: 'Cholestyramine',
            nutrient: 'Vitamin K',
            canonicalId: 'vitamin_k',
          ),
          (
            brandName: 'Azulfidine',
            genericRxcui: '9524',
            depletionId: 'DEP_SULFASALAZINE_FOLATE',
            genericName: 'Sulfasalazine',
            nutrient: 'Folate',
            canonicalId: 'folate',
          ),
        ];

        for (final c in cases) {
          final out = checker.check(
            medications: const [],
            medicationIdentities: [
              DepletionMedicationIdentity(
                name: c.brandName,
                rxcui: 'brand-${c.genericRxcui}',
                genericRxcui: c.genericRxcui,
              ),
            ],
            depletionsData: {
              'depletions': [
                {
                  'id': c.depletionId,
                  'drug_ref': {
                    'type': 'drug',
                    'id': c.genericRxcui,
                    'display_name': c.genericName,
                  },
                  'depleted_nutrient': {
                    'standard_name': c.nutrient,
                    'canonical_id': c.canonicalId,
                  },
                  'severity': 'moderate',
                },
              ],
            },
          );
          expect(out, hasLength(1), reason: c.brandName);
          expect(out.first.depletionId, c.depletionId);
        }
      },
    );

    test('no match returns empty', () {
      final out = checker.check(
        medications: [(name: 'Atorvastatin', drugClassId: 'statins')],
        depletionsData: _metforminB12Fixture(),
      );
      expect(out, isEmpty);
    });
  });

  group('DepletionChecker — three-state coverage', () {
    test('nutrient not in stack → CoverageLevel.none', () {
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(adequacyMcg: 500),
        stackCanonicalIds: {'vitamin_d'},
      );
      expect(out, hasLength(1));
      expect(out.first.coverageLevel, CoverageLevel.none);
      expect(out.first.isCovered, isFalse);
    });

    test(
      'nutrient present, no threshold authored → CoverageLevel.adequate',
      () {
        final out = checker.check(
          medications: [(name: 'Metformin', drugClassId: null)],
          depletionsData: _metforminB12Fixture(),
          stackCanonicalIds: {'vitamin_b12'},
        );
        expect(out.first.coverageLevel, CoverageLevel.adequate);
        expect(out.first.isCovered, isTrue);
      },
    );

    test(
      'nutrient present, threshold authored, no dose data → CoverageLevel.partial',
      () {
        // This is the default state of the app today: pipeline adds a
        // threshold, Flutter doesn't yet load product detail blobs into
        // the stack flow. Partial coverage is the honest answer: "you're
        // taking some but we can't tell how much."
        final out = checker.check(
          medications: [(name: 'Metformin', drugClassId: null)],
          depletionsData: _metforminB12Fixture(adequacyMcg: 500),
          stackCanonicalIds: {'vitamin_b12'},
        );
        expect(out.first.coverageLevel, CoverageLevel.partial);
        expect(out.first.isCovered, isFalse);
      },
    );

    test('dose above threshold → CoverageLevel.adequate', () {
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(adequacyMcg: 500),
        stackCanonicalIds: {'vitamin_b12'},
        stackDoses: [
          const StackSupplementDose(
            canonicalId: 'vitamin_b12',
            doseAmount: 1000,
            doseUnit: 'mcg',
          ),
        ],
      );
      expect(out.first.coverageLevel, CoverageLevel.adequate);
    });

    test('dose below threshold → CoverageLevel.partial', () {
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(adequacyMcg: 500),
        stackCanonicalIds: {'vitamin_b12'},
        stackDoses: [
          const StackSupplementDose(
            canonicalId: 'vitamin_b12',
            doseAmount: 100,
            doseUnit: 'mcg',
          ),
        ],
      );
      expect(out.first.coverageLevel, CoverageLevel.partial);
    });

    test('mg-unit dose correctly compared to mcg threshold', () {
      // 0.5 mg == 500 mcg — exactly at threshold, adequate.
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(adequacyMcg: 500),
        stackCanonicalIds: {'vitamin_b12'},
        stackDoses: [
          const StackSupplementDose(
            canonicalId: 'vitamin_b12',
            doseAmount: 0.5,
            doseUnit: 'mg',
          ),
        ],
      );
      expect(out.first.coverageLevel, CoverageLevel.adequate);
    });

    test('canonical_id matching is case-insensitive', () {
      // Safety invariant: lowercase the join key on both sides.
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(),
        stackCanonicalIds: {'VITAMIN_B12'},
      );
      expect(out.first.coverageLevel, CoverageLevel.adequate);
    });

    test('unknown unit (IU) degrades to partial, not adequate', () {
      // IU→mcg is vitamin-specific; we don't silently assume a factor.
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(adequacyMcg: 500),
        stackCanonicalIds: {'vitamin_b12'},
        stackDoses: [
          const StackSupplementDose(
            canonicalId: 'vitamin_b12',
            doseAmount: 1000,
            doseUnit: 'IU',
          ),
        ],
      );
      expect(out.first.coverageLevel, CoverageLevel.partial);
    });

    test(
      'functional antagonism rows are not treated as supplement coverage',
      () {
        final out = checker.check(
          medications: [(name: 'Warfarin', drugClassId: null)],
          depletionsData: {
            'depletions': [
              {
                'id': 'DEP_ANTICOAGULANTS_VITAMINK',
                'drug_ref': {'display_name': 'Warfarin'},
                'depleted_nutrient': {
                  'standard_name': 'Vitamin K',
                  'canonical_id': 'vitamin_k',
                },
                'depletion_type': 'functional_antagonism',
                'severity': 'significant',
              },
            ],
          },
          stackCanonicalIds: {'vitamin_k'},
          stackDoses: [
            const StackSupplementDose(
              canonicalId: 'vitamin_k',
              doseAmount: 100,
              doseUnit: 'mcg',
            ),
          ],
        );
        expect(out.first.coverageLevel, CoverageLevel.none);
        expect(out.first.isCovered, isFalse);
      },
    );

    test('non-coverage taxonomy buckets ignore supplement presence', () {
      for (final depletionType in const [
        'functional_antagonism',
        'monitoring_stability',
        'supplement_interaction',
      ]) {
        final out = checker.check(
          medications: [(name: 'Test medication', drugClassId: null)],
          depletionsData: {
            'depletions': [
              {
                'id': 'DEP_$depletionType',
                'drug_ref': {'display_name': 'Test medication'},
                'depleted_nutrient': {
                  'standard_name': 'Calcium',
                  'canonical_id': 'calcium',
                },
                'depletion_type': depletionType,
                'severity': 'moderate',
                'adequacy_threshold_mg': 500,
              },
            ],
          },
          stackCanonicalIds: {'calcium'},
          stackDoses: [
            const StackSupplementDose(
              canonicalId: 'calcium',
              doseAmount: 1000,
              doseUnit: 'mg',
            ),
          ],
        );
        expect(
          out.first.coverageLevel,
          CoverageLevel.none,
          reason: '$depletionType should not render as depletion coverage',
        );
      }
    });
  });

  group('DepletionChecker — authored copy passthrough', () {
    test('depletion_type flows through and defaults to depletion', () {
      final typed = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(
          authoredCopy: {'depletion_type': 'functional_antagonism'},
        ),
      );
      expect(typed.first.depletionType, 'functional_antagonism');

      final legacy = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: {
          'depletions': [
            {
              'id': 'DEP_LEGACY',
              'drug_ref': {'display_name': 'Metformin'},
              'depleted_nutrient': {
                'standard_name': 'Vitamin B12',
                'canonical_id': 'vitamin_b12',
              },
              'severity': 'significant',
            },
          ],
        },
      );
      expect(legacy.first.depletionType, 'depletion');
    });

    test('authored fields flow through to DepletionMatch', () {
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(
          authoredCopy: {
            'alert_headline': 'May lower vitamin B12 over time',
            'alert_body': 'Long-term metformin use can reduce B12 absorption.',
            'acknowledgement_note':
                'Nice — you are taking B12, which doctors recommend.',
            'monitoring_tip_short':
                'Consider checking B12 levels every 2-3 years.',
          },
        ),
      );
      final m = out.first;
      expect(m.alertHeadline, 'May lower vitamin B12 over time');
      expect(m.alertBody, contains('Long-term metformin'));
      expect(m.acknowledgementNote, contains('Nice'));
      expect(m.monitoringTipShort, contains('Consider'));
    });

    test('food_sources_short field flows through when authored', () {
      // Simulates the absorption-blocked hint Dr. Pham authors for
      // metformin/B12 — supplement is more reliable than food.
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(
          authoredCopy: {
            'food_sources_short':
                'Because metformin reduces B12 absorption, food sources may '
                'not be enough on their own — a supplement is often more '
                'reliable.',
          },
        ),
      );
      expect(out.first.foodSourcesShort, isNotNull);
      expect(out.first.foodSourcesShort, contains('food sources may not'));
    });

    test('food_sources_short is null when pipeline omits it', () {
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(),
      );
      expect(out.first.foodSourcesShort, isNull);
    });

    test('authored fields are null on legacy-shape entries', () {
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(),
      );
      final m = out.first;
      expect(m.alertHeadline, isNull);
      expect(m.alertBody, isNull);
      expect(m.acknowledgementNote, isNull);
      expect(m.monitoringTipShort, isNull);
      // But the legacy fields still flow through for the fallback path.
      expect(m.mechanism, contains('Metformin'));
      expect(m.clinicalImpact, contains('30%'));
      expect(m.onsetTimeline, 'years');
    });
  });

  group('DepletionChecker — sort order', () {
    test('uncovered sort before partial before adequate', () {
      final data = {
        'depletions': [
          {
            'id': 'A_ADEQUATE',
            'drug_ref': {'display_name': 'Metformin'},
            'depleted_nutrient': {'standard_name': 'N1', 'canonical_id': 'n1'},
            'severity': 'significant',
          },
          {
            'id': 'B_PARTIAL',
            'drug_ref': {'display_name': 'Metformin'},
            'depleted_nutrient': {'standard_name': 'N2', 'canonical_id': 'n2'},
            'severity': 'significant',
            'adequacy_threshold_mcg': 500,
          },
          {
            'id': 'C_NONE',
            'drug_ref': {'display_name': 'Metformin'},
            'depleted_nutrient': {'standard_name': 'N3', 'canonical_id': 'n3'},
            'severity': 'mild',
          },
        ],
      };
      final out = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: data,
        stackCanonicalIds: {'n1', 'n2'},
      );
      // none (C) first, partial (B) next, adequate (A) last.
      expect(out.map((m) => m.depletionId).toList(), [
        'C_NONE',
        'B_PARTIAL',
        'A_ADEQUATE',
      ]);
    });
  });

  group('CoverageLevel convenience', () {
    test('isCovered only true for adequate', () {
      expect(CoverageLevel.none.isCovered, isFalse);
      expect(CoverageLevel.partial.isCovered, isFalse);
      expect(CoverageLevel.adequate.isCovered, isTrue);
    });

    test('isAnyCoverage true for partial and adequate', () {
      expect(CoverageLevel.none.isAnyCoverage, isFalse);
      expect(CoverageLevel.partial.isAnyCoverage, isTrue);
      expect(CoverageLevel.adequate.isAnyCoverage, isTrue);
    });
  });

  group('DepletionChecker — legacy name fallback tightening', () {
    /// Row whose drug_ref carries no structured RxCUI or class id —
    /// the only shape that should still rely on display-name matching.
    Map<String, dynamic> ironNoteFixture() => {
      'depletions': [
        {
          'id': 'DEP_LEGACY_IRON_NOTE',
          'drug_ref': {'id': 'legacy:iron-note', 'display_name': 'Iron'},
          'depleted_nutrient': {
            'standard_name': 'Vitamin C',
            'canonical_id': 'vitamin_c',
          },
          'severity': 'moderate',
        },
      ],
    };

    test('"iron" no longer false-positives inside unrelated names', () {
      // "environ" contains the substring "iron" — the old bidirectional
      // substring check matched this. Min-length 5 now rejects it.
      final out = checker.check(
        medications: [(name: 'Environ Pills', drugClassId: null)],
        depletionsData: ironNoteFixture(),
      );
      expect(out, isEmpty);
    });

    test('short row display names cannot match longer med names', () {
      // Reverse direction of the same false positive: row says "Iron",
      // user med name contains those letters incidentally.
      final out = checker.check(
        medications: [(name: 'Environmental Health Rx', drugClassId: null)],
        depletionsData: ironNoteFixture(),
      );
      expect(out, isEmpty);
    });

    test('true positives are kept in both directions', () {
      // med name shorter than row display name.
      final forward = checker.check(
        medications: [(name: 'Metformin', drugClassId: null)],
        depletionsData: _metforminB12Fixture(),
      );
      expect(forward, hasLength(1));

      // row display name shorter than med name.
      final reverse = checker.check(
        medications: [(name: 'Metformin Extended Release', drugClassId: null)],
        depletionsData: {
          'depletions': [
            {
              'id': 'DEP_LEGACY_METFORMIN',
              'drug_ref': {
                'id': 'legacy:metformin-note',
                'display_name': 'Metformin',
              },
              'depleted_nutrient': {
                'standard_name': 'Vitamin B12',
                'canonical_id': 'vitamin_b12',
              },
              'severity': 'significant',
            },
          ],
        },
      );
      expect(reverse, hasLength(1));
      expect(reverse.first.depletionId, 'DEP_LEGACY_METFORMIN');
    });

    test('identity-backed meds (with RxCUI) do not name-match', () {
      // The med carries a structured RxCUI that does NOT match the row.
      // Name matching must not rescue it — names of RxCUI-backed meds
      // are excluded from the legacy fallback set.
      final out = checker.check(
        medications: const [],
        medicationIdentities: const [
          DepletionMedicationIdentity(name: 'Metformin', rxcui: '111111'),
        ],
        depletionsData: _metforminB12Fixture(),
      );
      expect(out, isEmpty);
    });

    group('legacyDrugNameMatches', () {
      test('requires minimum 5-char shorter name', () {
        expect(legacyDrugNameMatches('iron', 'iron'), isFalse);
        expect(legacyDrugNameMatches('ironwood extract', 'iron'), isFalse);
      });

      test('requires word boundaries', () {
        expect(legacyDrugNameMatches('environ pills', 'iron'), isFalse);
        expect(legacyDrugNameMatches('prednisone', 'predni'), isFalse);
      });

      test('matches whole words bidirectionally', () {
        expect(
          legacyDrugNameMatches(
            'metformin (type 2 diabetes medication)',
            'metformin',
          ),
          isTrue,
        );
        expect(
          legacyDrugNameMatches('metformin', 'metformin extended release'),
          isTrue,
        );
        expect(legacyDrugNameMatches('lisinopril', 'lisinopril'), isTrue);
      });

      test('empty inputs never match', () {
        expect(legacyDrugNameMatches('', 'metformin'), isFalse);
        expect(legacyDrugNameMatches('metformin', ''), isFalse);
      });
    });
  });
}
