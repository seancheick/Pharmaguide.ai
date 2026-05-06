// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T4.
//
// Verifies the threshold-gate filter:
//   - the headline false-positive cases Sean caught (Vit D + TTC, Mg
//     + diabetes) are now suppressed
//   - retinol teratogenic threshold fires correctly (below 3000 IU
//     suppressed, at/above kept)
//   - kidney-mineral overload threshold fires correctly (Mg < 400 mg
//     suppressed, ≥ 400 kept)
//   - multi-condition warnings: any-fires-keeps semantics
//   - all the fail-safe paths (no entry, missing dose, missing
//     ingredient, unit mismatch, missing condition tag) keep the
//     warning rather than silently swallow it
//
// All tests construct InteractionWarning fixtures directly — no
// pipeline integration here. T4's screen-level wiring is verified
// at the screen-test level (T20 pin-the-order test scope).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';

InteractionWarning _w({
  required List<String> conditionIds,
  String? ingredientName,
  Severity severity = Severity.caution,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.theoretical,
    title: 'Test warning',
    mechanism: 'Test mechanism',
    management: 'Test management',
    conditionIds: conditionIds,
    ingredientName: ingredientName,
  );
}

void main() {
  group('applyConditionThresholdGate — headline false positives', () {
    test('Vit D 1000 IU + TTC profile → suppressed (positive)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['ttc'], ingredientName: 'Vitamin D'),
        ],
        ingredientDoses: {
          'vitamin_d': (value: 1000, unit: 'IU'),
        },
      );
      expect(result, isEmpty);
    });

    test('Vit D 5000 IU + TTC profile → STILL suppressed (positive ignores dose)', () {
      // Positive directionality means "always beneficial, never warn"
      // — dose is irrelevant.
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['ttc'], ingredientName: 'Vitamin D'),
        ],
        ingredientDoses: {
          'vitamin_d': (value: 5000, unit: 'IU'),
        },
      );
      expect(result, isEmpty);
    });

    test('Magnesium 200 mg + diabetes profile → suppressed (positive)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['diabetes'], ingredientName: 'Magnesium'),
        ],
        ingredientDoses: {
          'magnesium': (value: 200, unit: 'mg'),
        },
      );
      expect(result, isEmpty);
    });

    test('Magnesium 600 mg + diabetes profile → STILL suppressed (positive)', () {
      // Magnesium is positive for diabetes regardless of dose. UL
      // exceedance warnings (high-dose harm) come from a different
      // pipeline path and aren't gated here.
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['diabetes'], ingredientName: 'Magnesium'),
        ],
        ingredientDoses: {
          'magnesium': (value: 600, unit: 'mg'),
        },
      );
      expect(result, isEmpty);
    });
  });

  group('applyConditionThresholdGate — retinol teratogenic gate', () {
    test('Vitamin A 2000 IU + pregnancy → suppressed (below 3000 IU)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['pregnancy'], ingredientName: 'Vitamin A'),
        ],
        ingredientDoses: {
          'vitamin_a': (value: 2000, unit: 'IU'),
        },
      );
      expect(result, isEmpty);
    });

    test('Vitamin A 4000 IU + pregnancy → KEPT (above 3000 IU)', () {
      final warning = _w(
        conditionIds: ['pregnancy'],
        ingredientName: 'Vitamin A',
      );
      final result = applyConditionThresholdGate(
        warnings: [warning],
        ingredientDoses: {
          'vitamin_a': (value: 4000, unit: 'IU'),
        },
      );
      expect(result, hasLength(1));
      expect(result.single, same(warning));
    });

    test('Vitamin A exactly at 3000 IU + pregnancy → KEPT (boundary fires)', () {
      // Threshold semantics: dose >= minDose fires. Boundary lives on
      // the "fire" side so a clinical threshold isn't off-by-one.
      final warning = _w(
        conditionIds: ['pregnancy'],
        ingredientName: 'Vitamin A',
      );
      final result = applyConditionThresholdGate(
        warnings: [warning],
        ingredientDoses: {
          'vitamin_a': (value: 3000, unit: 'IU'),
        },
      );
      expect(result, hasLength(1));
    });
  });

  group('applyConditionThresholdGate — kidney mineral overload', () {
    test('Magnesium 200 mg + kidney_disease → suppressed (below 400 mg)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['kidney_disease'], ingredientName: 'Magnesium'),
        ],
        ingredientDoses: {
          'magnesium': (value: 200, unit: 'mg'),
        },
      );
      expect(result, isEmpty);
    });

    test('Magnesium 600 mg + kidney_disease → KEPT (above 400 mg)', () {
      final warning = _w(
        conditionIds: ['kidney_disease'],
        ingredientName: 'Magnesium',
      );
      final result = applyConditionThresholdGate(
        warnings: [warning],
        ingredientDoses: {
          'magnesium': (value: 600, unit: 'mg'),
        },
      );
      expect(result, hasLength(1));
    });

    test(
      'Vit D 1000 IU + kidney_disease → suppressed (below 4000 IU CKD threshold)',
      () {
        // Important: Vit D is generally positive but kidney_disease
        // is the one condition where it has a neutral threshold (CKD
        // calcium/phosphate concerns). Below 4000 IU still suppressed.
        final result = applyConditionThresholdGate(
          warnings: [
            _w(
              conditionIds: ['kidney_disease'],
              ingredientName: 'Vitamin D',
            ),
          ],
          ingredientDoses: {
            'vitamin_d': (value: 1000, unit: 'IU'),
          },
        );
        expect(result, isEmpty);
      },
    );

    test('Vit D 5000 IU + kidney_disease → KEPT (above CKD threshold)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['kidney_disease'], ingredientName: 'Vitamin D'),
        ],
        ingredientDoses: {
          'vitamin_d': (value: 5000, unit: 'IU'),
        },
      );
      expect(result, hasLength(1));
    });
  });

  group('applyConditionThresholdGate — multi-condition warnings', () {
    test('positive for both tagged conditions → suppressed', () {
      // Vit D is positive for TTC AND pregnancy. Multi-condition
      // warning tagged with both → suppress.
      final result = applyConditionThresholdGate(
        warnings: [
          _w(
            conditionIds: ['ttc', 'pregnancy'],
            ingredientName: 'Vitamin D',
          ),
        ],
        ingredientDoses: {
          'vitamin_d': (value: 1000, unit: 'IU'),
        },
      );
      expect(result, isEmpty);
    });

    test(
      'any-fires-keeps: Vit D positive for TTC but above threshold for kidney → KEPT',
      () {
        // Multi-condition warning with mixed gating: TTC says
        // suppress, kidney_disease at 5000 IU says fire. Medical-
        // grade conservative: any-fires keeps the warning.
        final result = applyConditionThresholdGate(
          warnings: [
            _w(
              conditionIds: ['ttc', 'kidney_disease'],
              ingredientName: 'Vitamin D',
            ),
          ],
          ingredientDoses: {
            'vitamin_d': (value: 5000, unit: 'IU'),
          },
        );
        expect(result, hasLength(1));
      },
    );

    test(
      'any-fires-keeps: condition without table entry → KEPT regardless',
      () {
        // Vit D positive for TTC but NO entry for autoimmune.
        // Unknown rule → fire (table is opt-in suppression).
        final result = applyConditionThresholdGate(
          warnings: [
            _w(
              conditionIds: ['ttc', 'autoimmune'],
              ingredientName: 'Vitamin D',
            ),
          ],
          ingredientDoses: {
            'vitamin_d': (value: 1000, unit: 'IU'),
          },
        );
        expect(result, hasLength(1));
      },
    );
  });

  group('applyConditionThresholdGate — fail-safe passthroughs', () {
    test('warning with empty conditionIds → KEPT (not subject to gate)', () {
      // E.g., banned-recall warnings — global, no condition gating.
      const warning = InteractionWarning(
        severity: Severity.avoid,
        evidenceLevel: EvidenceLevel.established,
        title: 'Banned substance',
        mechanism: 'Banned',
        management: 'Avoid',
      );
      final result = applyConditionThresholdGate(
        warnings: [warning],
        ingredientDoses: const {},
      );
      expect(result, hasLength(1));
    });

    test('warning with no ingredientName → KEPT (can\'t reason about dose)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['ttc']), // ingredientName: null
        ],
        ingredientDoses: const {},
      );
      expect(result, hasLength(1));
    });

    test(
      'no table entry for (condition, ingredient) → KEPT (table is opt-in)',
      () {
        // Reishi mushroom isn't in the table → fall through to
        // existing pipeline behavior.
        final result = applyConditionThresholdGate(
          warnings: [
            _w(conditionIds: ['ttc'], ingredientName: 'Reishi Mushroom'),
          ],
          ingredientDoses: {
            'reishi_mushroom': (value: 500, unit: 'mg'),
          },
        );
        expect(result, hasLength(1));
      },
    );

    test(
      'neutral entry but ingredient missing from doses → KEPT (fail-safe)',
      () {
        // Vitamin A + pregnancy is neutral with 3000 IU threshold.
        // No dose data → can't compare → fail-safe fire.
        final result = applyConditionThresholdGate(
          warnings: [
            _w(
              conditionIds: ['pregnancy'],
              ingredientName: 'Vitamin A',
            ),
          ],
          ingredientDoses: const {},
        );
        expect(result, hasLength(1));
      },
    );

    test('unit mismatch (IU threshold vs mg dose) → KEPT (fail-safe)', () {
      // Vitamin A pregnancy threshold is in IU. If pipeline labels a
      // Vit A dose in mcg, we don't try to convert — fail-safe fire.
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['pregnancy'], ingredientName: 'Vitamin A'),
        ],
        ingredientDoses: {
          'vitamin_a': (value: 600, unit: 'mcg'),
        },
      );
      expect(result, hasLength(1));
    });

    test('canonicalization works across pipeline name variants', () {
      // Pipeline emits 'Vitamin D'; threshold table keyed
      // 'vitamin_d'. Helper canonicalizes both sides.
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['ttc'], ingredientName: 'Vitamin D'),
        ],
        ingredientDoses: {
          'vitamin_d': (value: 1000, unit: 'IU'),
        },
      );
      expect(result, isEmpty);
    });

    test('preserves order of kept warnings', () {
      // Filter mustn't reorder — downstream UI relies on stable
      // warning ordering for severity-sort consistency.
      final w1 = _w(conditionIds: ['ttc'], ingredientName: 'Vitamin A');
      final w2 = _w(conditionIds: ['ttc'], ingredientName: 'Vitamin D');
      final w3 = _w(conditionIds: ['ttc'], ingredientName: 'Iron');
      // w2 (Vit D for TTC) is positive → suppressed.
      // w1 (Vit A for TTC) at 4000 IU → above threshold, kept.
      // w3 (Iron for TTC) is positive → suppressed.
      final result = applyConditionThresholdGate(
        warnings: [w1, w2, w3],
        ingredientDoses: {
          'vitamin_a': (value: 4000, unit: 'IU'),
          'vitamin_d': (value: 1000, unit: 'IU'),
          'iron': (value: 18, unit: 'mg'),
        },
      );
      expect(result, hasLength(1));
      expect(result.single, same(w1));
    });
  });

  group('gateInteractionSummary — T4 follow-up (post live walkthrough)', () {
    test('null input → null output', () {
      expect(gateInteractionSummary(null), isNull);
    });

    test('summary without condition_summary → unchanged', () {
      final input = {'foo': 'bar'};
      expect(gateInteractionSummary(input), equals(input));
    });

    test('drops condition where every ingredient is positive', () {
      // Vit D × diabetes: vitamin_d is `positive` for diabetes per
      // the threshold table. The whole condition entry should drop.
      final result = gateInteractionSummary({
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'highest_severity': 'monitor',
            'ingredients': ['Vitamin D'],
            'actions': ['Monitor glucose...'],
          },
        },
      });
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isFalse);
    });

    test('keeps condition with only positive ingredients dropped, neutral kept', () {
      // High-dose niacin is neutral for diabetes (threshold-gated, not
      // positive). Vit D is positive → dropped. Result: 'Niacin' is
      // the only surviving entry, condition kept.
      final result = gateInteractionSummary({
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'highest_severity': 'monitor',
            'ingredients': ['Vitamin D', 'Niacin'],
            'actions': ['Monitor glucose...'],
          },
        },
      });
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
      final diabetes = cs['diabetes'] as Map<String, dynamic>;
      expect(diabetes['ingredients'], ['Niacin']);
    });

    test('multi-condition Vit D + magnesium product on diabetes profile drops both', () {
      // The exact scenario Sean caught: Vit D + Mg both positive for
      // diabetes, condition entry should be dropped wholesale.
      final result = gateInteractionSummary({
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'highest_severity': 'monitor',
            'ingredients': ['Vitamin D', 'Magnesium'],
            'actions': ['Monitor glucose...'],
          },
        },
      });
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs, isEmpty);
    });

    test('preserves drug_class_summary untouched', () {
      // Drug-class summary doesn't have positive-directional nutrients;
      // gate doesn't touch it.
      final result = gateInteractionSummary({
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'highest_severity': 'monitor',
            'ingredients': ['Vitamin D'],
          },
        },
        'drug_class_summary': {
          'anticoagulants': {
            'label': 'Blood thinners',
            'highest_severity': 'caution',
            'ingredients': ['Vitamin K'],
          },
        },
      });
      final dcs = result?['drug_class_summary'] as Map<String, dynamic>;
      expect(dcs.containsKey('anticoagulants'), isTrue);
    });

    test('unknown ingredient passes through (table is opt-in suppression)', () {
      // Reishi mushroom isn't in the table → no entry → fall through.
      final result = gateInteractionSummary({
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'ingredients': ['Reishi Mushroom'],
          },
        },
      });
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
      expect(
        (cs['diabetes'] as Map<String, dynamic>)['ingredients'],
        ['Reishi Mushroom'],
      );
    });

    test('condition with malformed data (no ingredients list) passes through', () {
      // Defensive — pipeline shape variation shouldn't drop conditions
      // we can't reason about.
      final result = gateInteractionSummary({
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'ingredients': 'not a list',
          },
        },
      });
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
    });

    test('does NOT mutate input', () {
      final input = {
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'ingredients': ['Vitamin D'],
          },
        },
      };
      gateInteractionSummary(input);
      // Input untouched — diabetes entry still present.
      final cs = input['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
    });
  });

  group('gateInteractionSummary — T16.2e (dose-gating extension)', () {
    // PureLean reproduction: ALA 350mg < 600mg, Vanadium 50mcg < 50000mcg,
    // Niacin 37.5mg < 500mg — all sub-clinical. Pre-T16.2e leaked through
    // the §7 condition_summary surface as "Diabetes — caution — Affected
    // by: Alpha-Lipoic Acid, Vanadium, Niacin" while T4's main warnings-
    // list gate had already suppressed the inline warnings. Cross-surface
    // contradiction.

    test('drops sub-threshold aboveDose ingredient when doses provided', () {
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'highest_severity': 'caution',
              'ingredients': ['Alpha-Lipoic Acid'],
            },
          },
        },
        ingredientDoses: {
          'alpha_lipoic_acid': (value: 350, unit: 'mg'),
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isFalse,
          reason: 'all ingredients sub-threshold → drop entire entry');
    });

    test('keeps at-threshold aboveDose ingredient (boundary fires)', () {
      // 600mg = ALA threshold for diabetes. dose < minDose, NOT dose <=,
      // so 600 fires. Same boundary semantics as `_isFullyGated`.
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'ingredients': ['Alpha-Lipoic Acid'],
            },
          },
        },
        ingredientDoses: {
          'alpha_lipoic_acid': (value: 600, unit: 'mg'),
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
      expect(
        (cs['diabetes'] as Map<String, dynamic>)['ingredients'],
        ['Alpha-Lipoic Acid'],
      );
    });

    test('keeps above-threshold aboveDose ingredient', () {
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'ingredients': ['Alpha-Lipoic Acid'],
            },
          },
        },
        ingredientDoses: {
          'alpha_lipoic_acid': (value: 1200, unit: 'mg'),
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
    });

    test('PureLean reproduction — ALA 350mg + Vanadium 50mcg + Niacin 37.5mg → drop diabetes', () {
      // The exact false positive Sean caught in the §7 surface. All three
      // are aboveDose / sub-clinical → entry drops wholesale.
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'highest_severity': 'caution',
              'ingredients': ['Alpha-Lipoic Acid', 'Vanadium', 'Niacin'],
            },
          },
        },
        ingredientDoses: {
          'alpha_lipoic_acid': (value: 350, unit: 'mg'),
          'vanadium': (value: 50, unit: 'mcg'),
          'niacin': (value: 37.5, unit: 'mg'),
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isFalse);
    });

    test('mixed sub-threshold + above-threshold — only sub-threshold drops', () {
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'ingredients': ['Alpha-Lipoic Acid', 'Niacin'],
            },
          },
        },
        ingredientDoses: {
          'alpha_lipoic_acid': (value: 350, unit: 'mg'), // sub
          'niacin': (value: 600, unit: 'mg'), // above
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
      expect(
        (cs['diabetes'] as Map<String, dynamic>)['ingredients'],
        ['Niacin'],
      );
    });

    test('missing dose for aboveDose entry → KEEP (fail-safe)', () {
      // Can't reason about dose → over-warn rather than miss.
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'ingredients': ['Alpha-Lipoic Acid'],
            },
          },
        },
        ingredientDoses: const {}, // ingredient not in dose map
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
    });

    test('unit mismatch → KEEP (fail-safe)', () {
      // Vanadium threshold is mcg, label dose in mg → fail-safe fire.
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'ingredients': ['Vanadium'],
            },
          },
        },
        ingredientDoses: {
          'vanadium': (value: 1, unit: 'mg'),
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
    });

    test('null ingredientDoses → behavior matches pre-T16.2e (positive-only)', () {
      // No dose-gate input → only positive entries get filtered. Sub-
      // threshold aboveDose entries pass through (back-compat).
      final result = gateInteractionSummary({
        'condition_summary': {
          'diabetes': {
            'label': 'Diabetes',
            'ingredients': ['Alpha-Lipoic Acid'],
          },
        },
      });
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isTrue);
    });

    test('positive ingredients still drop alongside dose-gating', () {
      // Vit D positive (drops). ALA sub-threshold (drops). Both gone →
      // entry drops.
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'ingredients': ['Vitamin D', 'Alpha-Lipoic Acid'],
            },
          },
        },
        ingredientDoses: {
          'vitamin_d': (value: 1000, unit: 'IU'),
          'alpha_lipoic_acid': (value: 350, unit: 'mg'),
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isFalse);
    });

    test('canonicalization handles raw display names (Alpha-Lipoic Acid)', () {
      // The §7 surface ships raw display strings; gate must canonicalize
      // before lookup.
      final result = gateInteractionSummary(
        {
          'condition_summary': {
            'diabetes': {
              'label': 'Diabetes',
              'ingredients': ['Alpha-Lipoic Acid'], // hyphenated, mixed case
            },
          },
        },
        ingredientDoses: {
          'alpha_lipoic_acid': (value: 350, unit: 'mg'),
        },
      );
      final cs = result?['condition_summary'] as Map<String, dynamic>;
      expect(cs.containsKey('diabetes'), isFalse);
    });
  });

  group('computeMatchedHighestSeverity — T16.2a (PureLean dedup)', () {
    test('null gatedSummary → fallback', () {
      expect(
        computeMatchedHighestSeverity(
          gatedSummary: null,
          matchedConditionIds: const ['diabetes'],
          matchedDrugClassIds: const [],
          fallback: 'avoid',
        ),
        equals('avoid'),
      );
    });

    test('empty matched lists → fallback (no entries to walk)', () {
      expect(
        computeMatchedHighestSeverity(
          gatedSummary: {
            'condition_summary': {
              'diabetes': {'highest_severity': 'caution'},
            },
          },
          matchedConditionIds: const [],
          matchedDrugClassIds: const [],
          fallback: 'monitor',
        ),
        equals('monitor'),
      );
    });

    test(
      'matched condition with caution → "caution" (NOT pipeline overall avoid)',
      () {
        // The PureLean bug: pipeline ships highest_severity:'avoid' but
        // user-matched conditions are only caution-tier.
        final result = computeMatchedHighestSeverity(
          gatedSummary: {
            'highest_severity': 'avoid', // pipeline overall
            'condition_summary': {
              'diabetes': {
                'highest_severity': 'caution',
                'ingredients': ['Alpha-lipoic acid'],
              },
              'pregnancy': {
                'highest_severity': 'avoid',
                'ingredients': ['Some teratogen'],
              },
            },
          },
          matchedConditionIds: const ['diabetes'], // user is diabetic only
          matchedDrugClassIds: const [],
          fallback: 'avoid',
        );
        expect(result, equals('caution'));
      },
    );

    test('multiple matched conditions → max across them', () {
      final result = computeMatchedHighestSeverity(
        gatedSummary: {
          'condition_summary': {
            'diabetes': {'highest_severity': 'caution'},
            'hypertension': {'highest_severity': 'avoid'},
            'thyroid_disorder': {'highest_severity': 'monitor'},
          },
        },
        matchedConditionIds: const [
          'diabetes',
          'hypertension',
          'thyroid_disorder',
        ],
        matchedDrugClassIds: const [],
        fallback: 'safe',
      );
      expect(result, equals('avoid'));
    });

    test('matched drug class severity contributes to max', () {
      final result = computeMatchedHighestSeverity(
        gatedSummary: {
          'condition_summary': {
            'diabetes': {'highest_severity': 'caution'},
          },
          'drug_class_summary': {
            'anticoagulants': {'highest_severity': 'contraindicated'},
          },
        },
        matchedConditionIds: const ['diabetes'],
        matchedDrugClassIds: const ['anticoagulants'],
        fallback: 'safe',
      );
      // Drug class is the worst → wins.
      expect(result, equals('contraindicated'));
    });

    test('matched condition not in summary → ignored, not fallback', () {
      // If user has a profile condition that's not in the product's
      // summary, that entry simply contributes nothing — but other
      // matched entries still drive the result.
      final result = computeMatchedHighestSeverity(
        gatedSummary: {
          'condition_summary': {
            'diabetes': {'highest_severity': 'monitor'},
          },
        },
        matchedConditionIds: const ['diabetes', 'pregnancy'], // pregnancy absent
        matchedDrugClassIds: const [],
        fallback: 'avoid',
      );
      expect(result, equals('monitor'));
    });

    test(
      'matched ID present but no usable severity field → fallback to '
      'parsed.highestSeverity (fail-safe over-warn)',
      () {
        final result = computeMatchedHighestSeverity(
          gatedSummary: {
            'condition_summary': {
              'diabetes': {'ingredients': <String>[]}, // missing highest_severity
            },
          },
          matchedConditionIds: const ['diabetes'],
          matchedDrugClassIds: const [],
          fallback: 'avoid',
        );
        // Defensive: when we can't read a per-entry severity, fall
        // back to the pipeline's overall — better to over-warn than
        // miss a real avoid.
        expect(result, equals('avoid'));
      },
    );

    test('unknown severity string → coerced to safe (zero contribution)', () {
      final result = computeMatchedHighestSeverity(
        gatedSummary: {
          'condition_summary': {
            'diabetes': {'highest_severity': 'pineapple'}, // unknown
            'hypertension': {'highest_severity': 'monitor'},
          },
        },
        matchedConditionIds: const ['diabetes', 'hypertension'],
        matchedDrugClassIds: const [],
        fallback: 'avoid',
      );
      // 'pineapple' coerces to safe (weight 0); monitor wins.
      expect(result, equals('monitor'));
    });

    test(
      'severity strings normalized — uppercase / whitespace / mixed case',
      () {
        final result = computeMatchedHighestSeverity(
          gatedSummary: {
            'condition_summary': {
              'diabetes': {'highest_severity': '  AVOID '},
            },
          },
          matchedConditionIds: const ['diabetes'],
          matchedDrugClassIds: const [],
          fallback: 'safe',
        );
        expect(result, equals('avoid'));
      },
    );

    test(
      'PureLean reproduction — overall avoid, matched only caution+monitor',
      () {
        // Direct repro of Sean's screenshot: pipeline says "avoid"
        // overall but for the user's diabetes profile only ALA
        // (caution) and Vanadium (monitor) match. Banner should now
        // read "caution" not "avoid".
        final result = computeMatchedHighestSeverity(
          gatedSummary: {
            'highest_severity': 'avoid',
            'condition_summary': {
              'diabetes': {
                'highest_severity': 'caution',
                'ingredients': ['Alpha-lipoic acid', 'Vanadium'],
              },
              'pregnancy': {
                'highest_severity': 'avoid',
                'ingredients': ['Vitamin A retinol'],
              },
            },
          },
          matchedConditionIds: const ['diabetes'],
          matchedDrugClassIds: const [],
          fallback: 'avoid',
        );
        expect(result, equals('caution'));
      },
    );
  });

  group('extractIngredientDoses', () {
    test('null blob → empty map', () {
      expect(extractIngredientDoses(null), isEmpty);
    });

    test('blob without ingredients key → empty map', () {
      expect(extractIngredientDoses({'foo': 'bar'}), isEmpty);
    });

    test('extracts canonical → (value, unit) for valid entries', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Vitamin D3', 'dose_amount': 1000, 'dose_unit': 'IU'},
          {'name': 'Magnesium glycinate', 'dose_amount': 200, 'dose_unit': 'mg'},
        ],
      });
      expect(result, hasLength(2));
      expect(result['vitamin_d3'], (value: 1000.0, unit: 'IU'));
      expect(result['magnesium_glycinate'], (value: 200.0, unit: 'mg'));
    });

    test(
      'T16.2b — extracts live pipeline shape (quantity / unit field names)',
      () {
        // Live pipeline ships dose data under `quantity` + `unit` (the
        // names used by the rendering side). Pre-T16.2b this test
        // didn't exist and the extractor only looked at `dose_amount`
        // / `dose_unit` — so live products silently produced an empty
        // dose map and every aboveDose threshold gate failed open.
        final result = extractIngredientDoses({
          'ingredients': [
            {'name': 'Alpha Lipoic Acid', 'quantity': 350, 'unit': 'mg'},
            {'name': 'Vanadium', 'quantity': 50, 'unit': 'mcg'},
            {'name': 'Niacin', 'quantity': 37.5, 'unit': 'mg'},
          ],
        });
        expect(result, hasLength(3));
        expect(result['alpha_lipoic_acid'], (value: 350.0, unit: 'mg'));
        expect(result['vanadium'], (value: 50.0, unit: 'mcg'));
        expect(result['niacin'], (value: 37.5, unit: 'mg'));
      },
    );

    test(
      'T16.2b — live `quantity` field wins over legacy `dose_amount` '
      'when both present',
      () {
        // Belt-and-braces: pipeline sometimes mirrors fields during
        // schema migrations. We prefer the live shape.
        final result = extractIngredientDoses({
          'ingredients': [
            {
              'name': 'Iodine',
              'quantity': 100,
              'unit': 'mcg',
              'dose_amount': 999, // stale mirror — should be ignored
              'dose_unit': 'IU',
            },
          ],
        });
        expect(result['iodine'], (value: 100.0, unit: 'mcg'));
      },
    );

    test('skips entries missing dose_amount', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Magnesium', 'dose_unit': 'mg'},
        ],
      });
      expect(result, isEmpty);
    });

    test('skips entries missing dose_unit', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Magnesium', 'dose_amount': 200},
        ],
      });
      expect(result, isEmpty);
    });

    test('skips entries missing name', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'dose_amount': 200, 'dose_unit': 'mg'},
        ],
      });
      expect(result, isEmpty);
    });

    test('parses string-typed dose_amount (defensive)', () {
      // Some pipeline blobs ship dose_amount as a string due to JSON
      // round-trips. Helper should handle it.
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Iron', 'dose_amount': '18', 'dose_unit': 'mg'},
        ],
      });
      expect(result['iron']?.value, 18.0);
    });

    test('skips entries with non-numeric dose_amount', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Iron', 'dose_amount': 'a lot', 'dose_unit': 'mg'},
        ],
      });
      expect(result, isEmpty);
    });
  });
}
