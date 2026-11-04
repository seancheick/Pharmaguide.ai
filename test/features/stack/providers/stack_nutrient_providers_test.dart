import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/consumer_disposition.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart'
    show ClinicalSignal;
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

void main() {
  group('stackDoseRulesUnreadProvider', () {
    Future<ProviderContainer> stack({
      required List<String> conditions,
      required String carrierStatus,
    }) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(() async {
        await coreDb.close();
        await userDb.close();
      });
      await userDb.saveProfile(
        ProfileState(
          ageBracket: '19-30',
          sex: 'Female',
          conditions: conditions,
        ).toCompanion(),
      );
      await _seedProduct(coreDb, dsldId: 'READ', name: 'Read');
      await _seedStack(userDb, dsldId: 'READ', name: 'Read');
      await userDb.cacheDetail(
        'READ',
        jsonEncode({
          'ingredients': [
            {
              'name': 'Caffeine',
              'standard_name': 'Caffeine',
              'quantity': 400,
              'unit': 'mg',
            },
          ],
          'warnings': [_thresholdWarning('hypertension', 'Caffeine', 400)],
        }),
        _blobSha,
      );
      await _seedProduct(coreDb, dsldId: 'CARRIER', name: 'Carrier');
      await _seedStack(userDb, dsldId: 'CARRIER', name: 'Carrier');
      await userDb.cacheDetail(
        'CARRIER',
        jsonEncode({
          'ingredients': [
            {'name': 'Caffeine', 'standard_name': 'Caffeine'},
          ],
          'warnings': [
            {
              'type': 'interaction',
              'severity': 'caution',
              'title': 'Caffeine / hypertension',
              'ingredient_name': 'Caffeine',
              'condition_ids': ['hypertension'],
              'profile_gate': {
                'gate_type': 'condition',
                'requires': {
                  'conditions_any': ['hypertension'],
                  'drug_classes_any': <String>[],
                  'profile_flags_any': <String>[],
                },
                'excludes': <String, Object?>{},
                'dose': {
                  'basis': 'per_day',
                  'comparator': '>',
                  'value': 400,
                  'unit': 'mg',
                  'severity_if_met': 'caution',
                  'severity_if_not_met': 'informational',
                },
              },
              'dose_decision': {
                'clinical_severity': 'caution',
                'evaluation_status': carrierStatus,
                'consumer_disposition': 'suppress',
              },
            },
          ],
        }),
        _blobSha,
      );
      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          evaluatorProfileFlagsProvider.overrideWith(
            (ref) async => const <String>{},
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('exactly 400 beside an unread carrier reads as incomplete', () async {
      final container = await stack(
        conditions: const ['hypertension'],
        carrierStatus: 'amount_unknown',
      );

      expect(await container.read(stackDoseRulesUnreadProvider.future), isTrue);
    });

    test('someone the rule does not apply to is unaffected', () async {
      final container = await stack(
        conditions: const ['pregnancy'],
        carrierStatus: 'amount_unknown',
      );

      expect(
        await container.read(stackDoseRulesUnreadProvider.future),
        isFalse,
      );
    });

    test('a carrier whose amount was read is unaffected', () async {
      final container = await stack(
        conditions: const ['hypertension'],
        carrierStatus: 'below_threshold',
      );

      expect(
        await container.read(stackDoseRulesUnreadProvider.future),
        isFalse,
      );
    });
    group('a product whose detail could not be loaded', () {
      Future<ProviderContainer> failing(
        Future<Map<String, dynamic>?> Function() blob,
      ) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        // Nothing filled in: no condition could have made a rule apply.
        await userDb.saveProfile(const ProfileState().toCompanion());
        await _seedProduct(coreDb, dsldId: 'LOST', name: 'Lost');
        await _seedStack(userDb, dsldId: 'LOST', name: 'Lost');
        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
            evaluatorProfileFlagsProvider.overrideWith(
              (ref) async => const <String>{},
            ),
            detailBlobProvider.overrideWith((ref, dsldId) => blob()),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      test('a failed fetch reads as incomplete', () async {
        final container = await failing(() async => throw Exception('offline'));

        expect(
          await container.read(stackDoseRulesUnreadProvider.future),
          isTrue,
        );
      });

      test('a failure that is not an Exception reads as incomplete', () async {
        final container = await failing(() async => throw StateError('bad'));

        expect(
          await container.read(stackDoseRulesUnreadProvider.future),
          isTrue,
        );
      });

      test('an absent blob reads as incomplete', () async {
        final container = await failing(() async => null);

        expect(
          await container.read(stackDoseRulesUnreadProvider.future),
          isTrue,
        );
      });
    });
  });

  group('stackDoseThresholdAlertsProvider', () {
    test('feeds StackDoseSummer through ProductHealthFacts dose rows', () {
      final source = File(
        'lib/features/stack/providers/stack_nutrient_providers.dart',
      ).readAsStringSync();

      expect(source, contains('.doseRowsForThresholds'));
      expect(
        source,
        isNot(contains('.ingredientDoses;')),
        reason:
            'Stack dose threshold alerts must use the same parsed row boundary '
            'as pairwise checks instead of rebuilding rows ad hoc.',
      );
    });

    test(
      'aggregates cached product doses across the active stack and feeds diagnosis',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });

        await userDb.saveProfile(
          const ProfileState(
            ageBracket: '19-30',
            sex: 'Female',
            conditions: ['pregnancy'],
          ).toCompanion(),
        );

        for (final seed in const [
          (dsldId: 'CAFFEINE_A', name: 'Energy A', doseMg: 80),
          (dsldId: 'CAFFEINE_B', name: 'Energy B', doseMg: 80),
          (dsldId: 'CAFFEINE_C', name: 'Energy C', doseMg: 80),
        ]) {
          await _seedProduct(coreDb, dsldId: seed.dsldId, name: seed.name);
          await _seedStack(userDb, dsldId: seed.dsldId, name: seed.name);
          await userDb.cacheDetail(
            seed.dsldId,
            jsonEncode({
              'ingredients': [
                {
                  'name': 'Caffeine',
                  'standard_name': 'Caffeine',
                  'quantity': seed.doseMg,
                  'unit': 'mg',
                },
              ],
              'warnings': [_thresholdWarning('pregnancy', 'Caffeine', 200)],
            }),
            _blobSha,
          );
        }

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
        );
        addTearDown(container.dispose);

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.conditionId, 'pregnancy');
        expect(alerts.single.canonicalId, 'caffeine');
        expect(alerts.single.totalValue, 240);
        expect(alerts.single.unit, 'mg');
        expect(alerts.single.thresholdValue, 200);
        expect(alerts.single.contributions, hasLength(3));

        final intelligence = const StackIntelligenceEngine().diagnose(
          stackSize: 3,
          safetyReport: const StackSafetyReport(),
          recalledReport: RecalledIngredientsReport.empty(),
          synergyReport: SynergyReport.empty(),
          qualityScore: 95,
          doseThresholdAlerts: alerts,
        );

        expect(intelligence.nutrientWarningCount, 1);
        expect(intelligence.tier, StackTier.decent);
        expect(intelligence.issues.single.headline, contains('Caffeine'));
      },
    );

    test(
      'sums split EPA and DHA rows from cached blobs for omega-3 alerts',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });

        await userDb.saveProfile(
          const ProfileState(
            ageBracket: '19-30',
            sex: 'Male',
            conditions: ['bleeding_disorders'],
          ).toCompanion(),
        );

        await _seedProduct(coreDb, dsldId: 'OMEGA_A', name: 'Fish Oil A');
        await _seedProduct(coreDb, dsldId: 'OMEGA_B', name: 'Fish Oil B');
        await _seedStack(userDb, dsldId: 'OMEGA_A', name: 'Fish Oil A');
        await _seedStack(userDb, dsldId: 'OMEGA_B', name: 'Fish Oil B');

        await userDb.cacheDetail(
          'OMEGA_A',
          jsonEncode({
            'ingredients': [
              {'name': 'EPA', 'quantity': 1200, 'unit': 'mg'},
              {'name': 'DHA', 'quantity': 800, 'unit': 'mg'},
            ],
            'warnings': [
              _thresholdWarning('bleeding_disorders', 'Omega-3', 3000),
            ],
          }),
          _blobSha,
        );
        await userDb.cacheDetail(
          'OMEGA_B',
          jsonEncode({
            'ingredients': [
              {'name': 'EPA', 'quantity': 700, 'unit': 'mg'},
              {'name': 'DHA', 'quantity': 400, 'unit': 'mg'},
            ],
            'warnings': [
              _thresholdWarning('bleeding_disorders', 'Omega-3', 3000),
            ],
          }),
          _blobSha,
        );

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
        );
        addTearDown(container.dispose);

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.conditionId, 'bleeding_disorders');
        expect(alerts.single.canonicalId, 'omega_3');
        expect(alerts.single.totalValue, 3100);
        expect(alerts.single.thresholdValue, 3000);
        expect(alerts.single.contributions, hasLength(4));
      },
    );

    test(
      'uses pipeline-normalized semantic units for fresh catalog decisions',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        await userDb.saveProfile(
          const ProfileState(
            ageBracket: '19-30',
            sex: 'Male',
            conditions: ['heart_disease'],
          ).toCompanion(),
        );

        for (final seed in const [
          (dsldId: 'VITD_A', name: 'Vitamin D A', amountIu: 2000),
          (dsldId: 'VITD_B', name: 'Vitamin D B', amountIu: 2500),
        ]) {
          await _seedProduct(coreDb, dsldId: seed.dsldId, name: seed.name);
          await _seedStack(userDb, dsldId: seed.dsldId, name: seed.name);
          await userDb.cacheDetail(
            seed.dsldId,
            jsonEncode({
              // Deliberately incompatible with the IU rule. The app must use
              // the pipeline-normalized decision exposure, not convert this.
              'ingredients': [
                {'name': 'Vitamin D', 'quantity': 50, 'unit': 'mcg'},
              ],
              'warnings': [
                _compactThresholdWarning(
                  targetId: 'heart_disease',
                  ingredientName: 'Vitamin D',
                  ingredientCanonicalId: 'vitamin_d',
                  evaluatedAmount: seed.amountIu.toDouble(),
                  threshold: 4000,
                  unit: 'IU',
                  comparator: '>',
                ),
              ],
            }),
            _blobSha,
          );
        }

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
        );
        addTearDown(container.dispose);

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.totalValue, 4500);
        expect(alerts.single.unit, 'iu');
        expect(alerts.single.consumerDisposition, ConsumerDisposition.review);
      },
    );

    test(
      'mixed cache generations keep both normalized and legacy alerts',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        await userDb.saveProfile(
          const ProfileState(
            ageBracket: '19-30',
            sex: 'Female',
            conditions: ['heart_disease', 'pregnancy'],
          ).toCompanion(),
        );

        await _seedProduct(coreDb, dsldId: 'FRESH_VITD', name: 'Vitamin D');
        await _seedStack(userDb, dsldId: 'FRESH_VITD', name: 'Vitamin D');
        await userDb.cacheDetail(
          'FRESH_VITD',
          jsonEncode({
            'warnings': [
              _compactThresholdWarning(
                targetId: 'heart_disease',
                ingredientName: 'Vitamin D',
                ingredientCanonicalId: 'vitamin_d',
                evaluatedAmount: 4500,
                threshold: 4000,
                unit: 'IU',
                comparator: '>',
              ),
            ],
          }),
          _blobSha,
        );

        await _seedProduct(coreDb, dsldId: 'LEGACY_CAFF', name: 'Caffeine');
        await _seedStack(userDb, dsldId: 'LEGACY_CAFF', name: 'Caffeine');
        await userDb.cacheDetail(
          'LEGACY_CAFF',
          jsonEncode({
            'ingredients': [
              {
                'name': 'Caffeine',
                'standard_name': 'Caffeine',
                'quantity': 240,
                'unit': 'mg',
              },
            ],
            'warnings': [_thresholdWarning('pregnancy', 'Caffeine', 200)],
          }),
          _blobSha,
        );

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
        );
        addTearDown(container.dispose);

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts, hasLength(2));
        expect(
          alerts.map((alert) => alert.canonicalId),
          containsAll(const ['vitamin_d', 'caffeine']),
        );
      },
    );

    test(
      'mixed cache duplicate keeps the more protective authored policy',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        await userDb.saveProfile(
          const ProfileState(
            ageBracket: '19-30',
            sex: 'Female',
            conditions: ['pregnancy'],
          ).toCompanion(),
        );

        await _seedProduct(coreDb, dsldId: 'FRESH_CAFF', name: 'Caffeine A');
        await _seedStack(userDb, dsldId: 'FRESH_CAFF', name: 'Caffeine A');
        await userDb.cacheDetail(
          'FRESH_CAFF',
          jsonEncode({
            'ingredients': [
              {
                'name': 'Caffeine',
                'standard_name': 'Caffeine',
                'quantity': 240,
                'unit': 'mg',
              },
            ],
            'warnings': [
              _compactThresholdWarning(
                targetId: 'pregnancy',
                ingredientName: 'Caffeine',
                ingredientCanonicalId: 'caffeine',
                evaluatedAmount: 240,
                threshold: 200,
                unit: 'mg',
                comparator: '>=',
                severity: 'avoid',
                dispositionIfMet: 'block',
              ),
            ],
          }),
          _blobSha,
        );

        await _seedProduct(coreDb, dsldId: 'LEGACY_CAFF', name: 'Caffeine B');
        await _seedStack(userDb, dsldId: 'LEGACY_CAFF', name: 'Caffeine B');
        await userDb.cacheDetail(
          'LEGACY_CAFF',
          jsonEncode({
            'ingredients': [
              {
                'name': 'Caffeine',
                'standard_name': 'Caffeine',
                'quantity': 10,
                'unit': 'mg',
              },
            ],
            'warnings': [_thresholdWarning('pregnancy', 'Caffeine', 200)],
          }),
          _blobSha,
        );

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
        );
        addTearDown(container.dispose);

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.clinicalSeverity, Severity.avoid);
        expect(alerts.single.consumerDisposition, ConsumerDisposition.block);
      },
    );

    test(
      'aggregates drug-class thresholds using current-stack medication classes',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        await userDb.saveProfile(
          const ProfileState(ageBracket: '19-30', sex: 'Male').toCompanion(),
        );
        await userDb.addToStack(
          UserStacksLocalCompanion(
            id: const Value('med-statin'),
            type: const Value('medication'),
            name: const Value('Statin'),
            drugClassesCol: Value(jsonEncode(['class:statins'])),
          ),
        );

        for (final seed in const [
          (dsldId: 'NIACIN_A', name: 'Niacin A', amountMg: 600),
          (dsldId: 'NIACIN_B', name: 'Niacin B', amountMg: 500),
        ]) {
          await _seedProduct(coreDb, dsldId: seed.dsldId, name: seed.name);
          await _seedStack(userDb, dsldId: seed.dsldId, name: seed.name);
          await userDb.cacheDetail(
            seed.dsldId,
            jsonEncode({
              'warnings': [
                _compactThresholdWarning(
                  targetId: 'statins',
                  targetType: 'drug_class',
                  ingredientName: 'Niacin',
                  ingredientCanonicalId: 'vitamin_b3_niacin',
                  evaluatedAmount: seed.amountMg.toDouble(),
                  threshold: 1000,
                  unit: 'mg',
                  comparator: '>=',
                ),
              ],
            }),
            _blobSha,
          );
        }

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
        );
        addTearDown(container.dispose);

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.targetType, 'drug_class');
        expect(alerts.single.conditionId, 'statins');
        expect(alerts.single.totalValue, 1100);
      },
    );

    group('a dose rule with no amount the pipeline could stand behind', () {
      Map<String, Object?> card(
        String status, {
        String disposition = 'review',
        String ingredientName = 'Caffeine Anhydrous',
        String canonicalId = 'caffeine',
        String conditionId = 'hypertension',
        String comparator = '>',
        double threshold = 400,
        String? profileFlag,
      }) => {
        'type': 'interaction',
        'severity': 'caution',
        'evidence_level': 'established',
        'title': '$ingredientName / $conditionId',
        'ingredient_name': ingredientName,
        'ingredient_canonical_id': canonicalId,
        'condition_ids': [conditionId],
        'direction': 'harmful',
        'profile_gate': {
          'gate_type': profileFlag == null ? 'condition' : 'profile_flag',
          'requires': {
            'conditions_any': profileFlag == null ? [conditionId] : <String>[],
            'drug_classes_any': <String>[],
            'profile_flags_any': [?profileFlag],
          },
          'excludes': <String, Object?>{},
          'dose': null,
        },
        'dose_decision': {
          'clinical_severity': 'caution',
          'evaluation_status': status,
          'consumer_disposition': disposition,
          'evaluated_daily_amount': null,
          'evaluated_unit': null,
          'threshold': null,
          'threshold_unit': null,
          'comparator': null,
          'decision_rule': {
            'comparator': comparator,
            'threshold': threshold,
            'threshold_unit': 'mg',
            'consumer_disposition_if_met': 'review',
            'consumer_disposition_if_not_met': 'suppress',
          },
        },
      };

      Map<String, Object?> row(String name, double amount) => {
        'name': name,
        'standard_name': name,
        'quantity': amount,
        'unit': 'mg',
      };

      Future<ProviderContainer> stack(
        Map<String, Map<String, Object?>> blobs, {
        List<String> conditions = const ['hypertension'],
        Set<String> profileFlags = const <String>{},
      }) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        await userDb.saveProfile(
          ProfileState(
            ageBracket: '19-30',
            sex: 'Female',
            conditions: conditions,
          ).toCompanion(),
        );
        for (final entry in blobs.entries) {
          await _seedProduct(coreDb, dsldId: entry.key, name: entry.key);
          await _seedStack(userDb, dsldId: entry.key, name: entry.key);
          await userDb.cacheDetail(
            entry.key,
            jsonEncode(entry.value),
            _blobSha,
          );
        }
        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
            evaluatorProfileFlagsProvider.overrideWith(
              (ref) async => profileFlags,
            ),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      // 27808: the label prints 200 per scoop and 1-2 scoops, and its rows sum
      // to 650. The product page reads form_unknown as a review.
      Map<String, Object?> unreadProduct(String status, String disposition) => {
        'ingredients': [row('Caffeine', 350), row('Caffeine', 300)],
        'warnings': [card(status, disposition: disposition)],
      };

      Map<String, Object?> readProduct(double amount) => {
        'warnings': [
          _compactThresholdWarning(
            targetId: 'hypertension',
            ingredientName: 'Caffeine Anhydrous',
            ingredientCanonicalId: 'caffeine',
            evaluatedAmount: amount,
            threshold: 400,
            unit: 'mg',
            comparator: '>',
          ),
        ],
      };

      group('the replay labels', () {
        final caffeineAt400 = card('form_unknown');
        // 249741 prints 180 mg of caffeine anhydrous and 30 mg of di-caffeine
        // malate, and the malate's caffeine share is not on the label.
        final bulkRows = [row('Caffeine', 180), row('Caffeine', 30)];
        final cases =
            <
              String,
              ({Map<String, Object?> blob, String condition, Set<String> flags})
            >{
              '27808 hypertension': (
                blob: {
                  'ingredients': [row('Caffeine', 650)],
                  'warnings': [caffeineAt400],
                },
                condition: 'hypertension',
                flags: const {},
              ),
              '28993 hypertension': (
                blob: {
                  'ingredients': [row('Caffeine', 600)],
                  'warnings': [caffeineAt400],
                },
                condition: 'hypertension',
                flags: const {},
              ),
              '249741 pregnancy': (
                blob: {
                  'ingredients': bulkRows,
                  'warnings': [
                    card(
                      'form_unknown',
                      conditionId: 'pregnancy',
                      threshold: 200,
                      profileFlag: 'pregnant',
                    ),
                  ],
                },
                condition: 'pregnancy',
                flags: const {'pregnant'},
              ),
              '249741 ttc': (
                blob: {
                  'ingredients': bulkRows,
                  'warnings': [
                    card(
                      'form_unknown',
                      disposition: 'suppress',
                      conditionId: 'ttc',
                      comparator: '>=',
                      threshold: 200,
                    ),
                  ],
                },
                condition: 'ttc',
                flags: const {},
              ),
            };

        for (final MapEntry(key: name, value: label) in cases.entries) {
          test('$name claims no number and reads as incomplete', () async {
            final container = await stack(
              {'LABEL': label.blob},
              conditions: [label.condition],
              profileFlags: label.flags,
            );

            final alerts = await container.read(
              stackDoseThresholdAlertsProvider.future,
            );

            expect(alerts.map((alert) => alert.totalValue), isEmpty);
            expect(
              await container.read(stackDoseRulesUnreadProvider.future),
              isTrue,
            );
          });
        }
      });

      test(
        'claims no crossing from the rows and reads as incomplete',
        () async {
          for (final status in ['form_unknown', 'amount_unknown']) {
            for (final disposition in ['review', 'block', 'suppress']) {
              final reason = '$status $disposition';
              final container = await stack({
                'UNREAD': unreadProduct(status, disposition),
              });

              expect(
                await container.read(stackDoseThresholdAlertsProvider.future),
                isEmpty,
                reason: reason,
              );
              expect(
                await container.read(stackDoseRulesUnreadProvider.future),
                isTrue,
                reason: reason,
              );
            }
          }
        },
      );

      test('someone the rule does not apply to gets neither', () async {
        final container = await stack(
          {'UNREAD': unreadProduct('form_unknown', 'review')},
          conditions: const ['pregnancy'],
        );

        expect(
          await container.read(stackDoseThresholdAlertsProvider.future),
          isEmpty,
        );
        expect(
          await container.read(stackDoseRulesUnreadProvider.future),
          isFalse,
        );
      });

      test(
        'a partner that crosses counts alone and stays incomplete',
        () async {
          final container = await stack({
            'UNREAD': unreadProduct('form_unknown', 'review'),
            'READ': readProduct(500),
          });

          final alerts = await container.read(
            stackDoseThresholdAlertsProvider.future,
          );

          expect(alerts, hasLength(1));
          expect(alerts.single.totalValue, 500);
          expect(alerts.single.isIncomplete, isTrue);
          expect(alerts.single.contributions.single.productName, 'READ');
        },
      );

      test('a partner below the line is no all-clear', () async {
        final container = await stack({
          'UNREAD': unreadProduct('form_unknown', 'review'),
          'READ': readProduct(100),
        });

        expect(
          await container.read(stackDoseThresholdAlertsProvider.future),
          isEmpty,
        );
        expect(
          await container.read(stackDoseRulesUnreadProvider.future),
          isTrue,
        );
      });

      test('an unread rule sums no partner rows', () async {
        final container = await stack({
          'UNREAD': {
            'warnings': [card('amount_unknown')],
          },
          'ROWS': {
            'ingredients': [row('Caffeine', 650)],
          },
        });

        expect(
          await container.read(stackDoseThresholdAlertsProvider.future),
          isEmpty,
        );
      });

      // 62077: niacin at high_cholesterol. The rule names another form, so this
      // label's niacin is outside it, and that was read, not left unknown.
      test(
        'a form the rule excludes adds nothing and reads complete',
        () async {
          Map<String, Object?> excluded(double amount) => {
            'ingredients': [row('Niacin', amount)],
            'warnings': [
              card(
                'excluded_form',
                disposition: 'suppress',
                ingredientName: 'Niacin',
                canonicalId: 'vitamin_b3_niacin',
                conditionId: 'high_cholesterol',
                comparator: '>=',
                threshold: 1500,
              ),
            ],
          };
          final container = await stack(
            {'A': excluded(1000), 'B': excluded(600)},
            conditions: const ['high_cholesterol'],
          );

          expect(
            await container.read(stackDoseThresholdAlertsProvider.future),
            isEmpty,
          );
          expect(
            await container.read(stackDoseRulesUnreadProvider.future),
            isFalse,
          );
        },
      );

      test(
        'an unread rule with no decision rule sums no rows either',
        () async {
          final container = await stack({
            'UNREAD': {
              'ingredients': [row('Caffeine', 650)],
              'warnings': [
                {
                  ..._thresholdWarning('hypertension', 'Caffeine', 400),
                  'ingredient_canonical_id': 'caffeine',
                  'dose_decision': {
                    'clinical_severity': 'caution',
                    'evaluation_status': 'form_unknown',
                    'consumer_disposition': 'review',
                  },
                },
              ],
            },
          });

          expect(
            await container.read(stackDoseThresholdAlertsProvider.future),
            isEmpty,
          );
        },
      );

      test('a rule from an older blob still sums its rows', () async {
        final container = await stack({
          'OLD': {
            'ingredients': [row('Caffeine', 650)],
            'warnings': [_thresholdWarning('hypertension', 'Caffeine', 400)],
          },
        });

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts, hasLength(1));
        expect(alerts.single.totalValue, 650);
        expect(alerts.single.isIncomplete, isFalse);
      });
    });

    group('a beta-carotene mixture with no stated fraction', () {
      Future<ProviderContainer> stack(
        Map<String, Map<String, Object?>> blobs, {
        List<String> conditions = const ['current_smoker'],
      }) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        await userDb.saveProfile(
          ProfileState(
            ageBracket: '31-50',
            sex: 'Male',
            conditions: conditions,
          ).toCompanion(),
        );
        for (final entry in blobs.entries) {
          await _seedProduct(coreDb, dsldId: entry.key, name: entry.key);
          await _seedStack(userDb, dsldId: entry.key, name: entry.key);
          await userDb.cacheDetail(
            entry.key,
            jsonEncode(entry.value),
            _blobSha,
          );
        }
        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
            evaluatorProfileFlagsProvider.overrideWith(
              (ref) async => const <String>{},
            ),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      Future<void> expectRead(
        ProviderContainer container, {
        required List<double> totals,
        required bool incomplete,
      }) async {
        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );
        expect(alerts.map((alert) => alert.totalValue), totals);
        expect(alerts.where((alert) => alert.consumerBody != null), isEmpty);
        expect(
          await container.read(stackDoseRulesUnreadProvider.future),
          incomplete,
        );
      }

      // 184325-style: mcg RAE with no mass, so a range of nothing.
      Map<String, Object?> raeOnly(double rae) => {
        'ingredients': [_mixtureRow(rae: rae, maximum: 0)],
        'warnings': [
          _betaCaroteneCard(status: 'amount_unknown', disposition: 'suppress'),
          _betaCaroteneCard(
            status: 'amount_unknown',
            disposition: 'suppress',
            threshold: 10000,
            everyViewer: true,
          ),
        ],
      };

      // 293269 and 328639: a vitamin A row, whose figure is real but is not
      // beta-carotene, and no range.
      Map<String, Object?> vitaminARow(double rae) => {
        'ingredients': [
          {
            'name': 'Vitamin A',
            'standard_name': 'Vitamin A',
            'canonical_id': 'vitamin_a',
            'quantity': rae,
            'unit': 'mcg RAE',
          },
        ],
        'warnings': [
          _betaCaroteneCard(status: 'amount_unknown', disposition: 'suppress'),
          _betaCaroteneCard(
            status: 'amount_unknown',
            disposition: 'suppress',
            threshold: 10000,
            everyViewer: true,
          ),
        ],
      };

      // 10 mg confirmed + 8 mg mixture: 5,000 and at most 9,000 mcg RAE.
      Map<String, Object?> confirmedAndMixture() => {
        'ingredients': [_mixtureRow(maximum: 4000)],
        'warnings': [
          _betaCaroteneCard(
            status: 'form_unknown',
            disposition: 'suppress',
            amount: 5000,
          ),
          _betaCaroteneCard(
            status: 'below_threshold',
            disposition: 'suppress',
            threshold: 10000,
            amount: 5000,
            everyViewer: true,
          ),
        ],
      };

      // 25 mg mixture: at most 12,500 mcg RAE.
      Map<String, Object?> largeMixture() => {
        'ingredients': [_mixtureRow(maximum: 12500)],
        'warnings': [
          _betaCaroteneCard(status: 'form_unknown', disposition: 'suppress'),
          _betaCaroteneCard(
            status: 'form_unknown',
            disposition: 'suppress',
            threshold: 10000,
            everyViewer: true,
          ),
        ],
      };

      Map<String, Object?> smallMixture(double maximum) => {
        'ingredients': [_mixtureRow(maximum: maximum)],
        'warnings': [
          _betaCaroteneCard(
            status: 'below_threshold',
            disposition: 'suppress',
            amount: 0,
          ),
        ],
      };

      Map<String, Object?> confirmed(double amount) => {
        'warnings': [
          _betaCaroteneCard(
            status: amount >= 7500 ? 'above_threshold' : 'below_threshold',
            disposition: amount >= 7500 ? 'review' : 'suppress',
            amount: amount,
          ),
        ],
      };

      for (final conditions in const [
        ['current_smoker'],
        <String>[],
      ]) {
        final who = conditions.isEmpty ? 'no risk factor' : 'a smoker';

        test('a mcg RAE figure adds nothing, for $who', () async {
          await expectRead(
            await stack({'RAE': raeOnly(7500)}, conditions: conditions),
            totals: const [],
            incomplete: false,
          );
        });

        test('293269 and 328639 add nothing, for $who', () async {
          await expectRead(
            await stack({
              'A': vitaminARow(700),
              'B': vitaminARow(900),
            }, conditions: conditions),
            totals: const [],
            incomplete: false,
          );
        });
      }

      test('10 mg + 8 mg reads as a review, not an exceedance', () async {
        await expectRead(
          await stack({'MIX': confirmedAndMixture()}),
          totals: const [],
          incomplete: true,
        );
      });

      test('a 25 mg mixture reads as a review and claims no dose', () async {
        await expectRead(
          await stack({'MIX': largeMixture()}),
          totals: const [],
          incomplete: true,
        );
      });

      test('an unresolved amount does not reach every viewer', () async {
        for (final blob in [largeMixture(), confirmedAndMixture()]) {
          await expectRead(
            await stack({'MIX': blob}, conditions: const []),
            totals: const [],
            incomplete: false,
          );
        }
      });

      test('two mixtures under the line alone can reach it together', () async {
        await expectRead(
          await stack({'A': smallMixture(3000)}),
          totals: const [],
          incomplete: false,
        );
        await expectRead(
          await stack({'A': smallMixture(4000), 'B': smallMixture(4000)}),
          totals: const [],
          incomplete: true,
        );
      });

      test(
        'a maximum added to a confirmed amount can reach the line',
        () async {
          await expectRead(
            await stack({'A': confirmed(5000), 'B': smallMixture(1000)}),
            totals: const [],
            incomplete: false,
          );
          await expectRead(
            await stack({'A': confirmed(5000), 'B': smallMixture(2500)}),
            totals: const [],
            incomplete: true,
          );
        },
      );

      test('a confirmed crossing reads its confirmed amount alone', () async {
        await expectRead(
          await stack({'A': confirmed(7500), 'B': smallMixture(1000)}),
          totals: const [7500],
          incomplete: false,
        );
      });

      test(
        'a part confirmed beside a maximum counts toward the line',
        () async {
          final container = await stack({
            'A': confirmed(7500),
            'MIX': confirmedAndMixture(),
          });

          final alerts = await container.read(
            stackDoseThresholdAlertsProvider.future,
          );

          expect(alerts.single.totalValue, 12500);
          expect(alerts.single.isIncomplete, isTrue);
          expect(
            await container.read(stackDoseRulesUnreadProvider.future),
            isTrue,
          );
        },
      );

      test(
        'with nothing to read the maximum from it still reads as a review',
        () async {
          final blob = largeMixture()..remove('ingredients');

          await expectRead(
            await stack({'MIX': blob}),
            totals: const [],
            incomplete: true,
          );
        },
      );

      test('a mcg RAE partner leaves a confirmed crossing complete', () async {
        final container = await stack({
          'A': confirmed(7500),
          'RAE': raeOnly(7500),
        });

        final alerts = await container.read(
          stackDoseThresholdAlertsProvider.future,
        );

        expect(alerts.single.totalValue, 7500);
        expect(alerts.single.isIncomplete, isFalse);
      });

      test('someone with no card for it reads complete', () async {
        await expectRead(
          await stack(
            {'MIX': largeMixture()},
            conditions: const ['hypertension'],
          ),
          totals: const [],
          incomplete: false,
        );
      });
    });

    group('beta-carotene at 20 mg across a stack', () {
      Future<List<StackDoseThresholdAlert>> alertsFor(
        List<String> conditions,
      ) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });
        await userDb.saveProfile(
          ProfileState(
            ageBracket: '19-30',
            sex: 'Female',
            conditions: conditions,
          ).toCompanion(),
        );
        for (final dsldId in const ['CAROTENE_A', 'CAROTENE_B']) {
          await _seedProduct(coreDb, dsldId: dsldId, name: dsldId);
          await _seedStack(userDb, dsldId: dsldId, name: dsldId);
          await userDb.cacheDetail(
            dsldId,
            jsonEncode({
              'warnings': [_betaCaroteneDoseCard(7500)],
            }),
            _blobSha,
          );
        }
        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
        );
        addTearDown(container.dispose);
        return container.read(stackDoseThresholdAlertsProvider.future);
      }

      test('a profile with no conditions at all gets the card', () async {
        final alerts = await alertsFor(const []);

        expect(alerts, hasLength(1));
        expect(alerts.single.targetType, 'risk_status');
        expect(alerts.single.totalValue, 15000);
        expect(
          ClinicalSignal.fromDoseThreshold(alerts.single).body,
          kBetaCaroteneStackCardBody,
        );

        final intelligence = const StackIntelligenceEngine().diagnose(
          stackSize: 2,
          safetyReport: const StackSafetyReport(),
          recalledReport: RecalledIngredientsReport.empty(),
          synergyReport: SynergyReport.empty(),
          qualityScore: 95,
          doseThresholdAlerts: alerts,
        );
        expect(intelligence.tier, StackTier.decent);
        expect(intelligence.issues.single.headline, kBetaCaroteneStackCardBody);
      });

      test(
        'a condition that is not a risk factor still gets the card',
        () async {
          final alerts = await alertsFor(const ['pregnancy']);

          expect(alerts.single.targetType, 'risk_status');
        },
      );

      test('a risk factor gets its condition alert and no card', () async {
        final alerts = await alertsFor(const ['current_smoker']);

        expect(alerts, hasLength(1));
        expect(alerts.single.targetType, 'condition');
        expect(alerts.single.conditionId, 'current_smoker');
        expect(alerts.single.thresholdValue, 10000);
        expect(alerts.single.totalValue, 15000);
        expect(alerts.single.consumerBody, isNull);
      });
    });
  });
}

/// A `/ dose` card as the pipeline ships it: for every viewer, naming the risk
/// factors that share its tier.
Map<String, Object?> _mixtureRow({double? rae, required double maximum}) => {
  'name': 'Mixed Carotenoids',
  'standard_name': 'Mixed Carotenoids',
  'canonical_id': 'beta_carotene',
  'nutrient_group_id': 'vitamin_a',
  'quantity': ?rae,
  'unit': 'mcg RAE',
  'safety_exposure': {
    'low_per_day': 0.0,
    'high_per_day': maximum,
    'per_day': maximum,
    'unit': 'mcg RAE',
  },
};

Map<String, Object?> _betaCaroteneCard({
  required String status,
  required String disposition,
  double threshold = 7500,
  double? amount,
  bool everyViewer = false,
}) => {
  'type': 'interaction',
  'severity': 'caution',
  'evidence_level': 'established',
  'title': everyViewer ? 'Vitamin A / dose' : 'Vitamin A / current_smoker',
  'ingredient_name': 'Vitamin A',
  'ingredient_canonical_id': 'beta_carotene',
  'condition_ids': everyViewer
      ? const ['asbestos_exposure', 'current_smoker', 'former_smoker']
      : const ['current_smoker'],
  'direction': 'harmful',
  'profile_gate': {
    'gate_type': everyViewer ? 'dose' : 'condition',
    'requires': {
      'conditions_any': everyViewer ? <String>[] : const ['current_smoker'],
      'drug_classes_any': <String>[],
      'profile_flags_any': <String>[],
    },
    'excludes': <String, Object?>{},
    'dose': everyViewer
        ? {
            'basis': 'per_day',
            'comparator': '>=',
            'value': threshold,
            'unit': 'mcg RAE',
            'severity_if_met': 'caution',
            'severity_if_not_met': 'informational',
          }
        : null,
  },
  'dose_decision': {
    'clinical_severity': 'caution',
    'evaluation_status': status,
    'consumer_disposition': disposition,
    'evaluated_daily_amount': amount,
    'evaluated_unit': amount == null ? null : 'mcg rae',
    'decision_rule': {
      'comparator': '>=',
      'threshold': threshold,
      'threshold_unit': 'mcg RAE',
      'consumer_disposition_if_met': 'review',
      'consumer_disposition_if_not_met': 'suppress',
    },
  },
};

Map<String, Object?> _betaCaroteneDoseCard(double amount) => {
  ..._compactThresholdWarning(
    targetId: 'current_smoker',
    ingredientName: 'Vitamin A',
    ingredientCanonicalId: 'beta_carotene',
    evaluatedAmount: amount,
    threshold: 10000,
    unit: 'mcg rae',
    comparator: '>=',
    severity: 'informational',
  ),
  'title': 'Vitamin A / dose',
  'condition_ids': const [
    'asbestos_exposure',
    'current_smoker',
    'former_smoker',
  ],
  'profile_gate': const {
    'gate_type': 'dose',
    'requires': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': <String>[],
    },
    'dose': {
      'basis': 'per_day',
      'comparator': '>=',
      'value': 10000,
      'unit': 'mcg RAE',
      'severity_if_met': 'caution',
      'severity_if_not_met': 'informational',
    },
  },
};

Map<String, Object?> _compactThresholdWarning({
  required String targetId,
  String targetType = 'condition',
  required String ingredientName,
  required String ingredientCanonicalId,
  required double evaluatedAmount,
  required double threshold,
  required String unit,
  required String comparator,
  String severity = 'caution',
  String dispositionIfMet = 'review',
}) {
  return {
    'severity': severity,
    'evidence_level': 'established',
    'title': '$ingredientName / $targetId',
    'detail': 'Dose-aware fixture.',
    'action': 'Review cumulative dose.',
    if (targetType == 'condition') 'condition_ids': [targetId],
    if (targetType == 'drug_class') 'drug_class_ids': [targetId],
    'ingredient_name': ingredientName,
    'ingredient_canonical_id': ingredientCanonicalId,
    'dose_decision': {
      'clinical_severity': severity,
      'evaluation_status': 'below_threshold',
      'consumer_disposition': 'suppress',
      'evaluated_daily_amount': evaluatedAmount,
      'evaluated_unit': unit,
      'normalized_per_serving_amount': evaluatedAmount,
      'normalized_per_serving_unit': unit,
      'evaluated_serving_multiplier': 1,
      'decision_rule': {
        'comparator': comparator,
        'threshold': threshold,
        'threshold_unit': unit,
        'consumer_disposition_if_met': dispositionIfMet,
        'consumer_disposition_if_not_met': 'suppress',
      },
    },
  };
}

Map<String, Object?> _thresholdWarning(
  String conditionId,
  String ingredientName,
  double thresholdMg,
) {
  return {
    'severity': 'monitor',
    'evidence_level': 'established',
    'title': '$ingredientName / $conditionId',
    'detail': 'Stack threshold fixture.',
    'action': 'Review cumulative dose.',
    'condition_ids': [conditionId],
    'ingredient_name': ingredientName,
    'dose_threshold_evaluation': {
      'thresholds_checked': [
        {'threshold_value': thresholdMg, 'threshold_unit': 'mg'},
      ],
    },
  };
}

const _blobSha = 'cached-blob-sha';

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required String name,
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: name,
          exportVersion: 'test',
          exportedAt: '2026-05-21T00:00:00Z',
          productStatus: const Value('active'),
          detailBlobSha256: const Value(_blobSha),
        ),
      );
}

Future<void> _seedStack(
  UserDatabase userDb, {
  required String dsldId,
  required String name,
}) async {
  await userDb.addToStack(
    UserStacksLocalCompanion.insert(
      id: 'stack_$dsldId',
      type: const Value('supplement'),
      name: name,
      dsldId: Value(dsldId),
    ),
  );
}
