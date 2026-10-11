import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';

void main() {
  final rules = MedicationProfileGateRule.listFromJson(
    jsonDecode(
          File(
            'assets/reference_data/medication_profile_gate_rules.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  List<String> warnings(
    String id,
    MedicationUseContext context, {
    bool nsaid = true,
  }) => const MedicationProfileGateEvaluator()
      .evaluate(
        rules: rules,
        medicationName: 'selected medication',
        medicationIngredientRxcuis: {id},
        medicationContext: context,
        medicationProfileGateClassIds: nsaid ? {'nsaids'} : {},
        userProfileFlags: {'pregnant'},
        userConditions: {'kidney_disease'},
      )
      .map((w) => w.ruleId)
      .toList();
  test(
    'clinician-directed81mg pregnancy exception exact; unknown and unqualified retain warning',
    () {
      expect(
        warnings(
          '1191',
          const MedicationUseContext(
            dailyDoseMg: 81,
            useContext: 'clinician_directed_pregnancy_condition',
          ),
          nsaid: false,
        ),
        isNot(contains('MCR_PREGNANCY_NSAIDS')),
      );
      for (final c in [
        const MedicationUseContext(),
        const MedicationUseContext(dailyDoseMg: 81),
        const MedicationUseContext(
          dailyDoseMg: 82,
          useContext: 'clinician_directed_pregnancy_condition',
        ),
      ]) {
        expect(
          warnings('1191', c, nsaid: false),
          contains('MCR_PREGNANCY_NSAIDS'),
        );
      }
      expect(
        warnings(
          '5640',
          const MedicationUseContext(
            dailyDoseMg: 81,
            useContext: 'clinician_directed_pregnancy_condition',
          ),
        ),
        contains('MCR_PREGNANCY_NSAIDS'),
      );
    },
  );
  test('kidney aspirin81–100daily requires cardiovascular confirmation', () {
    for (final dose in [81.0, 100.0]) {
      expect(
        warnings(
          '1191',
          MedicationUseContext(
            dailyDoseMg: dose,
            useContext: 'cardiovascular_protection',
          ),
          nsaid: false,
        ),
        isNot(contains('MCR_KIDNEY_DISEASE_NSAIDS')),
      );
    }
    for (final dose in [80.0, 101.0, 325.0, 326.0, 650.0]) {
      expect(
        warnings(
          '1191',
          MedicationUseContext(
            dailyDoseMg: dose,
            useContext: 'cardiovascular_protection',
          ),
          nsaid: false,
        ),
        contains('MCR_KIDNEY_DISEASE_NSAIDS'),
      );
    }
    expect(
      warnings(
        '1191',
        const MedicationUseContext(dailyDoseMg: 81),
        nsaid: false,
      ),
      contains('MCR_KIDNEY_DISEASE_NSAIDS'),
    );
  });
  test(
    'direct eye scope pregnancy only; qualified topicaldiclofenac kidney only',
    () {
      expect(
        warnings('4502', const MedicationUseContext(route: 'ophthalmic')),
        isNot(contains('MCR_PREGNANCY_NSAIDS')),
      );
      expect(
        warnings('4502', const MedicationUseContext(route: 'ophthalmic')),
        contains('MCR_KIDNEY_DISEASE_NSAIDS'),
      );
      expect(
        warnings(
          '3355',
          const MedicationUseContext(
            route: 'topical',
            useContext: 'within_product_label_directions',
          ),
        ),
        isNot(contains('MCR_KIDNEY_DISEASE_NSAIDS')),
      );
      for (final c in [
        const MedicationUseContext(route: 'topical'),
        const MedicationUseContext(
          route: 'oral',
          useContext: 'within_product_label_directions',
        ),
        const MedicationUseContext(),
      ]) {
        expect(warnings('3355', c), contains('MCR_KIDNEY_DISEASE_NSAIDS'));
      }
      expect(
        warnings(
          '5640',
          const MedicationUseContext(
            route: 'topical',
            useContext: 'within_product_label_directions',
          ),
        ),
        contains('MCR_KIDNEY_DISEASE_NSAIDS'),
      );
    },
  );
  test('unknown stored context and invalid doses conservative', () {
    for (final value in [
      null,
      'not json',
      '[]',
      '{"daily_dose_mg":-1}',
      '{"daily_dose_mg":"81"}',
    ]) {
      expect(
        warnings('1191', MedicationUseContext.fromStored(value), nsaid: false),
        containsAll(['MCR_PREGNANCY_NSAIDS', 'MCR_KIDNEY_DISEASE_NSAIDS']),
      );
    }
  });
  test(
    'local medication context persists independently of free-text dose and old rows',
    () async {
      final dir = Directory.systemTemp.createTempSync('pg_context_migration');
      final file = File('${dir.path}/user.sqlite');
      var db = UserDatabase(file);
      await db.addToStack(
        const UserStacksLocalCompanion(
          id: Value('legacy'),
          name: Value('Aspirin'),
          type: Value('medication'),
          dosage: Value('81 mg'),
          frequency: Value('Daily'),
        ),
      );
      await db.customStatement(
        'ALTER TABLE user_stacks_local DROP COLUMN medication_context',
      );
      await db.customStatement('PRAGMA user_version = 11');
      await db.close();
      db = UserDatabase(file);
      final legacy = await (db.select(
        db.userStacksLocal,
      )..where((t) => t.id.equals('legacy'))).getSingle();
      expect(legacy.medicationContextCol, isNull);
      expect(legacy.dosage, '81 mg');
      expect(legacy.frequency, 'Daily');
      const context = MedicationUseContext(
        dailyDoseMg: 81,
        useContext: 'clinician_directed_pregnancy_condition',
      );
      await db.addToStack(
        UserStacksLocalCompanion(
          id: const Value('confirmed'),
          name: const Value('Aspirin'),
          type: const Value('medication'),
          medicationContextCol: Value(jsonEncode(context.toJson())),
        ),
      );
      final row = await (db.select(
        db.userStacksLocal,
      )..where((t) => t.id.equals('confirmed'))).getSingle();
      expect(
        MedicationUseContext.fromStored(row.medicationContextCol).dailyDoseMg,
        81,
      );
      expect(
        MedicationUseContext.fromStored(row.medicationContextCol).useContext,
        'clinician_directed_pregnancy_condition',
      );
      await db.close();
      dir.deleteSync(recursive: true);
    },
  );

  test(
    'aspirin exception cannot clear a combination containing another NSAID',
    () {
      final result = const MedicationProfileGateEvaluator().evaluate(
        rules: rules,
        medicationName: 'combination',
        medicationIngredientRxcuis: {'1191', '5640'},
        medicationContext: const MedicationUseContext(
          dailyDoseMg: 81,
          useContext: 'clinician_directed_pregnancy_condition',
        ),
        medicationProfileGateClassIds: {'nsaids'},
        userProfileFlags: {'pregnant'},
      );
      expect(result.map((w) => w.ruleId), contains('MCR_PREGNANCY_NSAIDS'));
    },
  );
  test('nonfinite daily dose cannot fulfill numeric exception', () {
    for (final dose in [double.nan, double.infinity, -1.0]) {
      expect(
        warnings(
          '1191',
          MedicationUseContext(
            dailyDoseMg: dose,
            useContext: 'cardiovascular_protection',
          ),
          nsaid: false,
        ),
        contains('MCR_KIDNEY_DISEASE_NSAIDS'),
      );
    }
  });
  test('present null malformed exception fields fail closed', () {
    final base =
        jsonDecode(
              File(
                'assets/reference_data/medication_profile_gate_rules.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final exception in [
      <String, dynamic>{'dose_mg_exact': null},
      <String, dynamic>{'dose_mg_range_inclusive': null},
      <String, dynamic>{'ingredient_rxcuis': null},
      <String, dynamic>{'route': null},
      <String, dynamic>{'use_context': null},
      <String, dynamic>{'ingredient_rxcuis': <String>[]},
      <String, dynamic>{
        'dose_mg_range_inclusive': [81],
      },
      <String, dynamic>{'dose_mg_exact': '81'},
    ]) {
      final copy = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      (copy['medication_profile_gate_rules']
          as List)[0]['medication_exceptions'] = [
        exception,
      ];
      final result = const MedicationProfileGateEvaluator().evaluate(
        rules: MedicationProfileGateRule.listFromJson(copy),
        medicationName: 'Aspirin',
        medicationIngredientRxcuis: {'1191'},
        medicationProfileGateClassIds: {},
        userProfileFlags: {'pregnant'},
      );
      expect(
        result.map((w) => w.ruleId),
        contains('MCR_PREGNANCY_NSAIDS'),
        reason: exception.toString(),
      );
    }
  });
  test(
    'malformed authored IDs and nonfinite bounds cannot qualify known context',
    () async {
      final base =
          jsonDecode(
                File(
                  'assets/reference_data/medication_profile_gate_rules.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final exception in <Map<String, dynamic>>[
        {
          'ingredient_rxcuis': ['1191', 12],
        },
        {
          'dose_mg_range_inclusive': [double.nan, 100],
        },
        {
          'dose_mg_range_inclusive': [81, double.infinity],
        },
        {
          'dose_mg_range_inclusive': [100, 81],
        },
        {'route': ''},
        {'use_context': ''},
      ]) {
        final copy = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
        (copy['medication_profile_gate_rules']
            as List)[0]['medication_exceptions'] = [
          exception,
        ];
        final result = const MedicationProfileGateEvaluator().evaluate(
          rules: MedicationProfileGateRule.listFromJson(copy),
          medicationName: 'Aspirin',
          medicationIngredientRxcuis: {'1191'},
          medicationProfileGateClassIds: {},
          userProfileFlags: {'pregnant'},
          medicationContext: const MedicationUseContext(
            dailyDoseMg: 81,
            route: '',
            useContext: '',
          ),
        );
        expect(
          result.map((w) => w.ruleId),
          contains('MCR_PREGNANCY_NSAIDS'),
          reason: exception.toString(),
        );
      }
    },
  );
}
