import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';

void main() {
  group('extractIngredientDoses', () {
    test('null blob -> empty map', () {
      expect(extractIngredientDoses(null), isEmpty);
    });

    test('blob without ingredients key -> empty map', () {
      expect(extractIngredientDoses({'foo': 'bar'}), isEmpty);
    });

    test('extracts canonical -> (value, unit) for valid entries', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Vitamin D3', 'dose_amount': 1000, 'dose_unit': 'IU'},
          {
            'name': 'Magnesium glycinate',
            'dose_amount': 200,
            'dose_unit': 'mg',
          },
        ],
      });

      expect(result, hasLength(2));
      // Units are now canonically normalized on read (shared readDoseUnit),
      // so 'IU' → 'iu' — matching what stack_dose_summer already emitted and
      // what the downstream dose math (amountInMass) expects. Consumers feed
      // this unit back through the normalizing readers, so casing never
      // reaches a case-sensitive comparison or the UI.
      expect(result['vitamin_d3'], (value: 1000.0, unit: 'iu'));
      expect(result['magnesium_glycinate'], (value: 200.0, unit: 'mg'));
    });

    test('extracts live pipeline quantity / unit field names', () {
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
    });

    test('drops proprietary-blend + parent-total rows (B#2 double-count)', () {
      // The gate previously skipped the usability filter the stack summers
      // enforce, so a nested-tree parent total (500 mg) was summed ON TOP of
      // its real child dose (200 mg) → 700 mg, over-counting the nutrient. The
      // shared isUsableDoseRow now drops the parent-total and blend-container
      // rows, so only the genuine 200 mg contribution remains.
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'standard_name': 'Magnesium',
            'quantity': 500,
            'unit': 'mg',
            'is_parent_total': true,
          },
          {'standard_name': 'Magnesium', 'quantity': 200, 'unit': 'mg'},
          {
            'standard_name': 'Proprietary Blend',
            'quantity': 900,
            'unit': 'mg',
            'is_proprietary_blend': true,
          },
        ],
      });

      expect(result['magnesium'], (value: 200.0, unit: 'mg'));
      expect(result.containsKey('proprietary_blend'), isFalse);
    });

    test('extracts dose rows from rda_ul_data when ingredients are absent', () {
      final result = extractIngredientDoses({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Alpha Lipoic Acid',
              'quantity': 350,
              'daily_amount_unit': 'mg',
            },
            {
              'standard_name': 'Vanadium',
              'quantity': '50',
              'daily_amount_unit': 'mcg',
            },
          ],
        },
      });

      expect(result['alpha_lipoic_acid'], (value: 350.0, unit: 'mg'));
      expect(result['vanadium'], (value: 50.0, unit: 'mcg'));
    });

    test('skips rda_ul_data rows marked unsafe for UL evaluation', () {
      final result = extractIngredientDoses({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Vitamin A',
              'quantity': 2000,
              'daily_amount_unit': 'IU',
              'skip_ul_check': true,
            },
          ],
        },
      });

      expect(result, isEmpty);
    });

    test('live quantity field wins over stale dose_amount mirror', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'name': 'Iodine',
            'quantity': 100,
            'unit': 'mcg',
            'dose_amount': 999,
            'dose_unit': 'IU',
          },
        ],
      });

      expect(result['iodine'], (value: 100.0, unit: 'mcg'));
    });

    test('sums duplicate canonical dose rows when units match', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          {'name': 'Caffeine', 'quantity': 60, 'unit': 'mg'},
        ],
      });

      expect(result['caffeine'], (value: 140.0, unit: 'mg'));
    });

    test('sums duplicate canonical dose rows across simple mass units', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Alpha Lipoic Acid', 'quantity': 0.3, 'unit': 'g'},
          {'name': 'Alpha Lipoic Acid', 'quantity': 300, 'unit': 'mg'},
        ],
      });

      expect(result['alpha_lipoic_acid'], (value: 0.6, unit: 'g'));
    });

    test('drops duplicate canonical dose rows with incompatible units', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Vitamin A', 'quantity': 3000, 'unit': 'IU'},
          {'name': 'Vitamin A', 'quantity': 900, 'unit': 'mcg RAE'},
        ],
      });

      expect(result.containsKey('vitamin_a'), isFalse);
    });

    test('parses string-typed dose amount defensively', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Iron', 'dose_amount': '18', 'dose_unit': 'mg'},
        ],
      });

      expect(result['iron']?.value, 18.0);
    });
  });

  group('extractIngredientDoses - elemental vs compound dedup', () {
    test('mirrored elemental + compound rows use only elemental value', () {
      final magnesiumRows = [
        {
          'name': 'Magnesium',
          'canonical_id': 'magnesium',
          'quantity': 60,
          'unit': 'mg',
        },
        {
          'name': 'Magnesium Glycinate',
          'canonical_id': 'magnesium',
          'quantity': 400,
          'unit': 'mg',
        },
      ];

      final result = extractIngredientDoses({
        'ingredients': magnesiumRows,
        'rda_ul_data': {'analyzed_ingredients': magnesiumRows},
      });

      expect(result['magnesium'], (value: 60.0, unit: 'mg'));
      expect(result['magnesium_glycinate'], (value: 400.0, unit: 'mg'));
    });

    test('elemental parenthetical counts as elemental row', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'name': 'Magnesium (elemental)',
            'canonical_id': 'magnesium',
            'quantity': 60,
            'unit': 'mg',
          },
          {
            'name': 'Magnesium Glycinate',
            'canonical_id': 'magnesium',
            'quantity': 400,
            'unit': 'mg',
          },
        ],
      });

      expect(result['magnesium']?.value, 60.0);
    });

    test('multi-form rows with no bare elemental row legitimately sum', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'name': 'Magnesium (as oxide)',
            'mapped_name': 'magnesium',
            'quantity': 200,
            'unit': 'mg',
          },
          {
            'name': 'Magnesium (as citrate)',
            'mapped_name': 'magnesium',
            'quantity': 100,
            'unit': 'mg',
          },
        ],
      });

      expect(result['magnesium'], (value: 300.0, unit: 'mg'));
    });
  });

  group('extractIngredientDoses - one label row, one exposure', () {
    // Rows below are trimmed from the real detail blobs named in each test.
    // `ingredients` rows are per serving and never carry `dose_role`;
    // `rda_ul_data.analyzed_ingredients` rows carry the per-day figure.
    Map<String, dynamic> labelRow(
      String path,
      String name,
      String canonicalId,
      num quantity,
      String unit, {
      String? standardName,
    }) => {
      'raw_source_path': path,
      'name': name,
      'standard_name': standardName ?? name,
      'canonical_id': canonicalId,
      'quantity': quantity,
      'unit': unit,
      'normalized_amount': quantity,
      'normalized_unit': unit,
    };

    Map<String, dynamic> analyzedRow(
      String path,
      String name,
      String canonicalId,
      num quantity,
      num perDayMax,
      String unit, {
      String? standardName,
      String doseRole = 'declared_total',
    }) => {
      'raw_source_path': path,
      'ingredient': name,
      'standard_name': standardName ?? name,
      'canonical_id': canonicalId,
      'quantity': quantity,
      'unit': unit,
      'converted_quantity': quantity,
      'converted_unit': unit,
      'per_day_min': quantity,
      'per_day_max': perDayMax,
      'dose_role': doseRole,
      'skip_ul_check': false,
    };

    Map<String, dynamic> blob(
      List<Map<String, dynamic>> ingredients,
      List<Map<String, dynamic>> analyzed,
    ) => {
      'ingredients': ingredients,
      'rda_ul_data': {'analyzed_ingredients': analyzed},
    };

    test('207221: a per-serving row and its per-day mirror count once', () {
      final result = extractIngredientDoses(
        blob(
          [labelRow('ingredientRows[0]', 'Vitamin C', 'vitamin_c', 500, 'mg')],
          [
            analyzedRow(
              'ingredientRows[0]',
              'Vitamin C',
              'vitamin_c',
              500,
              1000,
              'mg',
            ),
          ],
        ),
      );

      expect(result['vitamin_c'], (value: 1000.0, unit: 'mg'));
    });

    test('207221: the stack dose total reads the per-day figure', () {
      final facts = ProductHealthFacts.fromDetailBlob(
        blob(
          [labelRow('ingredientRows[0]', 'Vitamin C', 'vitamin_c', 500, 'mg')],
          [
            analyzedRow(
              'ingredientRows[0]',
              'Vitamin C',
              'vitamin_c',
              500,
              1000,
              'mg',
            ),
          ],
        ),
      );

      final totals = const StackDoseSummer().sum([
        StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Chewable Vitamin C',
          ingredients: facts.doseRowsForThresholds,
        ),
      ]);

      expect(totals['vitamin_c']?.totalValue, 1000.0);
    });

    test('257002: the per-serving mirror cannot win the elemental pass', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow(
              'ingredientRows[3]',
              'Vitamin K',
              'vitamin_k',
              12.5,
              'mcg',
            ),
          ],
          [
            analyzedRow(
              'ingredientRows[3]',
              'Vitamin K',
              'vitamin_k',
              12.5,
              25,
              'mcg',
              standardName: 'Vitamin K1',
            ),
          ],
        ),
      );

      expect(result['vitamin_k'], (value: 25.0, unit: 'mcg'));
    });

    test('294081: K1 and K2 each read their own per-day figure', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow(
              'ingredientRows[1]',
              'Vitamin K',
              'vitamin_k1',
              184,
              'mcg',
              standardName: 'Vitamin K1',
            ),
            labelRow(
              'ingredientRows[8]',
              'Vitamin K2',
              'vitamin_k2',
              30,
              'mcg',
            ),
          ],
          [
            analyzedRow(
              'ingredientRows[1]',
              'Vitamin K',
              'vitamin_k1',
              184,
              368,
              'mcg',
              standardName: 'Vitamin K',
            ),
            analyzedRow(
              'ingredientRows[8]',
              'Vitamin K2',
              'vitamin_k2',
              30,
              60,
              'mcg',
            ),
          ],
        ),
      );

      expect(result['vitamin_k1'], (value: 368.0, unit: 'mcg'));
      expect(result['vitamin_k2'], (value: 60.0, unit: 'mcg'));
    });

    test(
      '328600: a nested source mass does not add to its analyzed parent',
      () {
        final result = extractIngredientDoses(
          blob(
            [
              labelRow(
                'ingredientRows[0]',
                'Magnesium',
                'magnesium',
                144,
                'mg',
              ),
              labelRow(
                'ingredientRows[0].nestedRows[0]',
                'Magtein',
                'magnesium',
                2000,
                'mg',
                standardName: 'Magnesium',
              ),
            ],
            [
              analyzedRow(
                'ingredientRows[0]',
                'Magnesium',
                'magnesium',
                144,
                144,
                'mg',
              ),
            ],
          ),
        );

        expect(result['magnesium'], (value: 144.0, unit: 'mg'));
        // It still answers to its own name, like any compound row.
        expect(result['magtein'], (value: 2000.0, unit: 'mg'));
      },
    );

    test('299037: a source-mass parent does not add to its analyzed child', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow(
              'ingredientRows[0]',
              'Magtein Magnesium L-Threonate',
              'magnesium',
              1000,
              'mg',
              standardName: 'Magnesium',
            ),
            labelRow(
              'ingredientRows[0].nestedRows[0]',
              'Magnesium',
              'magnesium',
              72,
              'mg',
            ),
          ],
          [
            analyzedRow(
              'ingredientRows[0].nestedRows[0]',
              'Magnesium',
              'magnesium',
              72,
              144,
              'mg',
            ),
          ],
        ),
      );

      expect(result['magnesium'], (value: 144.0, unit: 'mg'));
    });

    test('74499: a separate label row for the nutrient stays additive', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow('ingredientRows[3]', 'Vitamin E', 'vitamin_e', 67, 'mg'),
            labelRow(
              'ingredientRows[27]',
              'natural Mixed Tocopherols',
              'vitamin_e',
              20,
              'mg',
              standardName: 'Vitamin E',
            ),
          ],
          [
            analyzedRow(
              'ingredientRows[3]',
              'Vitamin E',
              'vitamin_e',
              67,
              67,
              'mg',
            ),
          ],
        ),
      );

      expect(result['vitamin_e'], (value: 87.0, unit: 'mg'));
    });

    test('1627: distinct label rows with equal amounts both count', () {
      final result = extractIngredientDoses(
        blob([
          labelRow(
            'ingredientRows[0]',
            'American Ginseng root extract',
            'ginseng',
            200,
            'mg',
            standardName: 'Ginseng',
          ),
          labelRow(
            'ingredientRows[1]',
            'Panax Ginseng Root Extract',
            'ginseng',
            200,
            'mg',
            standardName: 'Ginseng',
          ),
        ], const []),
      );

      expect(result['ginseng'], (value: 400.0, unit: 'mg'));
    });

    test('321391: a mirrored row stays elemental under its mirror name', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow('ingredientRows[2]', 'Vitamin K', 'vitamin_k', 120, 'mcg'),
            labelRow('ingredientRows[5]', 'Vitamin K', 'vitamin_k', 50, 'mcg'),
          ],
          [
            analyzedRow(
              'ingredientRows[2]',
              'Vitamin K',
              'vitamin_k',
              120,
              120,
              'mcg',
              standardName: 'Vitamin K1',
            ),
          ],
        ),
      );

      expect(result['vitamin_k'], (value: 170.0, unit: 'mcg'));
    });

    // The reader joins on row paths and never guesses from a name and amount.
    // These read as written until the pipeline marks the duplicate or the
    // alternate label column.
    test('two rows at distinct paths both count, however equal they look', () {
      final result = extractIngredientDoses(
        blob(const [], [
          analyzedRow(
            'ingredientRows[0]',
            'Vitamin C',
            'vitamin_c',
            100,
            100,
            'mg',
          ),
          analyzedRow(
            'ingredientRows[1]',
            'Vitamin C',
            'vitamin_c',
            100,
            100,
            'mg',
          ),
        ]),
      );

      expect(result['vitamin_c'], (value: 200.0, unit: 'mg'));
    });

    test('206322: a name and amount repeated three times adds up', () {
      List<Map<String, dynamic>> rows(
        Map<String, dynamic> Function(String path) row,
      ) => [
        row('ingredientRows[8]'),
        row('ingredientRows[18]'),
        row('ingredientRows[26]'),
      ];

      final result = extractIngredientDoses(
        blob(
          rows((p) => labelRow(p, 'Colostrum', 'colostrum', 1500, 'mg')),
          rows(
            (p) => analyzedRow(p, 'Colostrum', 'colostrum', 1500, 1500, 'mg'),
          ),
        ),
      );

      expect(result['colostrum'], (value: 4500.0, unit: 'mg'));
    });

    test('329778: a repeated row with its mirrors counts once per path', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow('ingredientRows[3]', 'Selenium', 'selenium', 55, 'mcg'),
            labelRow('ingredientRows[16]', 'Selenium', 'selenium', 55, 'mcg'),
          ],
          [
            analyzedRow(
              'ingredientRows[3]',
              'Selenium',
              'selenium',
              55,
              55,
              'mcg',
            ),
            analyzedRow(
              'ingredientRows[16]',
              'Selenium',
              'selenium',
              55,
              55,
              'mcg',
            ),
          ],
        ),
      );

      expect(result['selenium'], (value: 110.0, unit: 'mcg'));
    });

    test(
      '217227: rows that look like label columns add until they are marked',
      () {
        final result = extractIngredientDoses(
          blob(const [], [
            analyzedRow(
              'ingredientRows[4]',
              'Vitamin D',
              'vitamin_d',
              20,
              20,
              'mcg',
            ),
            analyzedRow(
              'ingredientRows[5]',
              'Vitamin D',
              'vitamin_d',
              10,
              10,
              'mcg',
            ),
          ]),
        );

        expect(result['vitamin_d'], (value: 30.0, unit: 'mcg'));
      },
    );

    group('legacy threshold alerts', () {
      const rule = StackDoseThresholdRule(
        conditionId: 'kidney_disease',
        canonicalId: 'vitamin_c',
        displayName: 'Vitamin C',
        thresholdValue: 150,
        thresholdUnit: 'mg',
      );

      List<StackDoseThresholdAlert> alertsFor(Map<String, dynamic> detailBlob) {
        final facts = ProductHealthFacts.fromDetailBlob(detailBlob);
        const summer = StackDoseSummer();
        return summer.thresholdAlerts(
          totals: summer.sum([
            StackItemNutrients(
              stackEntryId: 'a',
              productName: 'Vitamin C',
              ingredients: facts.doseRowsForThresholds,
            ),
          ]),
          userConditions: const ['kidney_disease'],
          thresholdRules: const [rule],
        );
      }

      test('rows at distinct paths reach the threshold together', () {
        final alerts = alertsFor(
          blob(const [], [
            analyzedRow(
              'ingredientRows[0]',
              'Vitamin C',
              'vitamin_c',
              100,
              100,
              'mg',
            ),
            analyzedRow(
              'ingredientRows[1]',
              'Vitamin C',
              'vitamin_c',
              100,
              100,
              'mg',
            ),
          ]),
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.totalValue, 200);
      });

      test('a row and its mirror do not reach it', () {
        final alerts = alertsFor(
          blob(
            [
              labelRow(
                'ingredientRows[0]',
                'Vitamin C',
                'vitamin_c',
                100,
                'mg',
              ),
            ],
            [
              analyzedRow(
                'ingredientRows[0]',
                'Vitamin C',
                'vitamin_c',
                100,
                100,
                'mg',
              ),
            ],
          ),
        );

        expect(alerts, isEmpty);
      });
    });

    test('row 10 is not nested under row 1', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow('ingredientRows[1]', 'Vitamin E', 'vitamin_e', 67, 'mg'),
            labelRow('ingredientRows[10]', 'Vitamin E', 'vitamin_e', 20, 'mg'),
          ],
          [
            analyzedRow(
              'ingredientRows[1]',
              'Vitamin E',
              'vitamin_e',
              67,
              67,
              'mg',
            ),
          ],
        ),
      );

      expect(result['vitamin_e'], (value: 87.0, unit: 'mg'));
    });

    for (final role in const ['ul_scoped_component', 'form_component']) {
      test('a $role row does not leak back through its mirror', () {
        final result = extractIngredientDoses(
          blob(
            [
              labelRow('ingredientRows[2]', 'Selenium', 'selenium', 55, 'mcg'),
              labelRow('ingredientRows[16]', 'Selenium', 'selenium', 55, 'mcg'),
            ],
            [
              analyzedRow(
                'ingredientRows[2]',
                'Selenium',
                'selenium',
                55,
                110,
                'mcg',
              ),
              analyzedRow(
                'ingredientRows[16]',
                'Selenium',
                'selenium',
                55,
                110,
                'mcg',
                doseRole: role,
              ),
            ],
          ),
        );

        expect(result['selenium'], (value: 110.0, unit: 'mcg'));
      });
    }

    test('a row hidden by dose_role never takes the total from its branch', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow('ingredientRows[0]', 'Folate', 'folate', 400, 'mcg'),
            labelRow(
              'ingredientRows[0].nestedRows[0]',
              'Folic Acid',
              'folate',
              400,
              'mcg',
              standardName: 'Folate',
            ),
          ],
          [
            analyzedRow(
              'ingredientRows[0].nestedRows[0]',
              'Folic Acid',
              'folate',
              400,
              400,
              'mcg',
              standardName: 'Folate',
              doseRole: 'ul_scoped_component',
            ),
          ],
        ),
      );

      expect(result['folate'], (value: 400.0, unit: 'mcg'));
    });

    test('18309: the total answers to every name its mirror spelled', () {
      final result = extractIngredientDoses(
        blob(
          [
            {
              ...labelRow(
                'ingredientRows[0]',
                "Cat's Claw",
                'cat_s_claw',
                500,
                'mg',
              ),
              'normalized_key': 'cats_claw',
            },
          ],
          [
            analyzedRow(
              'ingredientRows[0]',
              "Cat's Claw",
              'cat_s_claw',
              500,
              1000,
              'mg',
            ),
          ],
        ),
      );

      expect(result['cats_claw'], (value: 1000.0, unit: 'mg'));
    });

    test(
      '178910: a hidden folic acid row is not counted under any name',
      () {
        final result = extractIngredientDoses(
          blob(
            [
              {
                ...labelRow(
                  'ingredientRows[8]',
                  'Folate',
                  'vitamin_b9_folate',
                  680,
                  'mcg DFE',
                  standardName: 'Vitamin B9 (Folate)',
                ),
                'normalized_key': 'folate',
              },
              {
                ...labelRow(
                  'ingredientRows[8].nestedRows[0]',
                  'Folic Acid',
                  'vitamin_b9_folate',
                  680,
                  'mcg DFE',
                  standardName: 'Vitamin B9 (Folate)',
                ),
                'normalized_key': 'folic_acid',
              },
            ],
            [
              analyzedRow(
                'ingredientRows[8]',
                'Folate',
                'vitamin_b9_folate',
                680,
                680,
                'mcg DFE',
                standardName: 'Vitamin B9 (Folate)',
              ),
              analyzedRow(
                'ingredientRows[8].nestedRows[0]',
                'Folic Acid',
                'vitamin_b9_folate',
                680,
                680,
                'mcg DFE',
                standardName: 'Vitamin B9 (Folate)',
                doseRole: 'ul_scoped_component',
              ),
            ],
          ),
        );

        expect(result['vitamin_b9_folate'], (value: 680.0, unit: 'mcg dfe'));
        expect(result, isNot(contains('folic_acid')));
      },
    );

    test('an ingredients row stamped with dose_role is not counted', () {
      final result = extractIngredientDoses(
        blob([
          labelRow('ingredientRows[3]', 'Selenium', 'selenium', 55, 'mcg'),
          {
            ...labelRow(
              'ingredientRows[16]',
              'Selenium',
              'selenium',
              60,
              'mcg',
            ),
            'dose_role': 'form_component',
          },
        ], const []),
      );

      expect(result['selenium'], (value: 55.0, unit: 'mcg'));
    });

    test('an analyzed row with no amount leaves its children counted', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow('ingredientRows[0]', 'Iron', 'iron', 0, 'mg'),
            labelRow(
              'ingredientRows[0].nestedRows[0]',
              'Iron Bisglycinate',
              'iron',
              18,
              'mg',
              standardName: 'Iron',
            ),
          ],
          [analyzedRow('ingredientRows[0]', 'Iron', 'iron', 0, 0, 'mg')],
        ),
      );

      expect(result['iron'], (value: 18.0, unit: 'mg'));
    });

    // No current blob has these shapes; the export could change that, and a
    // lost dose or skip would read as no concern.
    Map<String, dynamic> without(
      Map<String, dynamic> row,
      List<String> fields,
    ) => {...row}..removeWhere((field, _) => fields.contains(field));
    const amountFields = [
      'quantity',
      'converted_quantity',
      'per_day_min',
      'per_day_max',
    ];
    const unitFields = ['unit', 'converted_unit'];
    final iron = analyzedRow('ingredientRows[0]', 'Iron', 'iron', 18, 18, 'mg');
    final ironMirror = labelRow('ingredientRows[0]', 'Iron', 'iron', 18, 'mg');
    final nestedIron = labelRow(
      'ingredientRows[0].nestedRows[0]',
      'Iron Bisglycinate',
      'iron',
      18,
      'mg',
      standardName: 'Iron',
    );

    test('an analyzed row with no unit leaves its children counted', () {
      final result = extractIngredientDoses(
        blob([nestedIron], [without(iron, unitFields)]),
      );

      expect(result['iron'], (value: 18.0, unit: 'mg'));
    });

    for (final (missing, fields) in [
      ('amount', amountFields),
      ('unit', unitFields),
    ]) {
      test('an analyzed row with no $missing keeps its mirror', () {
        final result = extractIngredientDoses(
          blob([ironMirror], [without(iron, fields)]),
        );

        expect(result['iron'], (value: 18.0, unit: 'mg'));
      });
    }

    test('a hidden row stays hidden when its name reads no dose', () {
      final result = extractIngredientDoses(
        blob(
          [
            labelRow(
              'ingredientRows[1]',
              'Iron Bisglycinate',
              'iron',
              18,
              'mg',
              standardName: 'Iron',
            ),
          ],
          [
            without(iron, amountFields),
            analyzedRow(
              'ingredientRows[1]',
              'Iron Bisglycinate',
              'iron',
              18,
              18,
              'mg',
              standardName: 'Iron',
              doseRole: 'ul_scoped_component',
            ),
          ],
        ),
      );

      expect(result, isNot(contains('iron')));
    });

    test('an unresolved analyzed unit does not fall back to its mirror', () {
      final result = extractIngredientDoses(
        blob(
          [ironMirror],
          [
            {
              ...iron,
              'dose_data_quality': {'status': 'unresolved_unit'},
            },
          ],
        ),
      );

      expect(result, isNot(contains('iron')));
    });

    test('a skipped analyzed row with no amount still blocks its mirror', () {
      final result = extractIngredientDoses(
        blob(
          [ironMirror],
          [
            {...without(iron, amountFields), 'skip_ul_check': true},
          ],
        ),
      );

      expect(result, isNot(contains('iron')));
    });

    test('a skip on the ingredients row outlives its analyzed twin', () {
      final result = extractIngredientDoses(
        blob(
          [
            {...ironMirror, 'skip_ul_check': true},
          ],
          [iron],
        ),
      );

      expect(result, isNot(contains('iron')));
    });

    test('a skip on a nested row still blocks what its parent reports', () {
      final result = extractIngredientDoses(
        blob(
          [
            {...nestedIron, 'skip_ul_check': true},
          ],
          [iron],
        ),
      );

      expect(result, isNot(contains('iron')));
    });

    test('older catalogs without row paths keep the signature dedupe', () {
      final rows = [
        {
          'name': 'Vitamin C',
          'canonical_id': 'vitamin_c',
          'quantity': 500,
          'unit': 'mg',
        },
      ];

      final result = extractIngredientDoses({
        'ingredients': rows,
        'rda_ul_data': {'analyzed_ingredients': rows},
      });

      expect(result['vitamin_c'], (value: 500.0, unit: 'mg'));
    });

    test('an analyzed row without a path still dedupes by signature', () {
      final result = extractIngredientDoses({
        'ingredients': [
          labelRow('ingredientRows[0]', 'Vitamin C', 'vitamin_c', 500, 'mg'),
        ],
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Vitamin C',
              'canonical_id': 'vitamin_c',
              'quantity': 500,
              'unit': 'mg',
            },
          ],
        },
      });

      expect(result['vitamin_c'], (value: 500.0, unit: 'mg'));
    });

    test('a malformed row path is treated as no path', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'raw_source_path': 7,
            'name': 'Vitamin C',
            'canonical_id': 'vitamin_c',
            'quantity': 500,
            'unit': 'mg',
          },
        ],
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'raw_source_path': 7,
              'standard_name': 'Vitamin C',
              'canonical_id': 'vitamin_c',
              'quantity': 500,
              'unit': 'mg',
            },
          ],
        },
      });

      expect(result['vitamin_c'], (value: 500.0, unit: 'mg'));
    });
  });

  group('parseBlobWarnings - structured allergen contract', () {
    test(
      'drops duplicate allergen warnings when structured allergens exist',
      () {
        final result = parseBlobWarnings({
          'allergens': [
            {
              'allergen_id': 'ALLERGEN_BARLEY',
              'display_name': 'Barley',
              'presence_type': 'ingredient_list',
            },
          ],
          'warnings': [
            {
              'type': 'allergen',
              'source': 'allergen_db',
              'severity': 'caution',
              'title': 'Allergen: Barley',
              'detail': 'Presence: ingredient_list',
            },
          ],
          'warnings_profile_gated': [
            {
              'type': 'allergen',
              'source': 'allergen_db',
              'severity': 'caution',
              'title': 'Allergen: Wheat',
              'detail': 'Presence: ingredient_list',
            },
          ],
        });

        expect(result, isEmpty);
      },
    );

    test('keeps legacy allergen warning when structured id is absent', () {
      final result = parseBlobWarnings({
        'allergens': [
          {'display_name': 'Milk', 'presence_type': 'contains'},
        ],
        'warnings': [
          {
            'type': 'allergen',
            'source': 'allergen_db',
            'severity': 'caution',
            'title': 'Allergen: Milk',
            'detail': 'Presence: contains',
          },
        ],
      });

      expect(result, hasLength(1));
      expect(result.single.title, 'Allergen: Milk');
    });

    test(
      'keeps legacy allergen warnings when structured allergens are absent',
      () {
        final result = parseBlobWarnings({
          'warnings': [
            {
              'type': 'allergen',
              'source': 'allergen_db',
              'severity': 'caution',
              'title': 'Allergen: Barley',
              'detail': 'Presence: ingredient_list',
            },
          ],
        });

        expect(result, hasLength(1));
        expect(result.single.title, 'Allergen: Barley');
      },
    );
  });

  test('core product status suppresses legacy status warning aliases', () {
    final result = parseBlobWarnings({
      'warnings': [
        {
          'type': 'status',
          'severity': 'info',
          'title': 'Discontinued',
          'detail': 'Legacy duplicate status copy.',
        },
      ],
    }, productStatus: 'active');

    expect(result, isEmpty);
  });
}
