// A firm pregnancy or nursing warning printed on a label reaches the Stack
// through the existing condition-supplement signal, for the people it names,
// and only adds to the tier: it never moves the internal stack score.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/utils/stack_intelligence_helpers.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

const _dsldId = '241881';
const _name = 'Moringa 1000 mg';
const _text =
    'Do not use Moringa if you are pregnant, nursing or under 18 years of age.';

Map<String, dynamic> _labelWarning({
  String severity = 'avoid',
  String text = _text,
  List<String> flags = const ['pregnant', 'breastfeeding'],
}) => {
  'type': 'label_statement',
  'source': 'label_statements',
  'severity': severity,
  'display_mode_default': 'suppress',
  'evidence_level': 'ungraded',
  'title': 'Label warning',
  'detail': text,
  'alert_body': text,
  'sources': <String>[],
  'condition_ids': <String>[],
  'drug_class_ids': <String>[],
  'profile_gate': {
    'gate_type': 'profile_flag',
    'requires': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': flags,
    },
    'excludes': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': <String>[],
      'product_forms_any': <String>[],
      'nutrient_forms_any': <String>[],
    },
    'dose': null,
  },
};

Future<StackSafetyReport> _report({
  required Set<String> flags,
  required Future<Map<String, dynamic>?> Function() blob,
}) async {
  final coreDb = CoreDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  addTearDown(coreDb.close);
  addTearDown(interactionDb.close);
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: _name,
          exportVersion: 'test',
          exportedAt: '2026-11-03T00:00:00Z',
          mappedCoverage: const Value(1),
        ),
      );
  final now = DateTime.utc(2026, 11, 3);
  final container = ProviderContainer(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      interactionDatabaseProvider.overrideWithValue(interactionDb),
      activeStackProvider.overrideWith(
        (ref) async => [
          UserStacksLocalData(
            id: 'stack_$_dsldId',
            type: 'supplement',
            name: _name,
            dsldId: _dsldId,
            addedAt: now,
            clientUpdatedAt: now,
          ),
        ],
      ),
      loadedProfileProvider.overrideWith((ref) async => const ProfileState()),
      evaluatorProfileFlagsProvider.overrideWith((ref) async => flags),
      stackNutrientStatusesProvider.overrideWith(
        (ref) async => const StackNutrientStatuses.empty(),
      ),
      detailBlobProvider.overrideWith((ref, dsldId) => blob()),
    ],
  );
  addTearDown(container.dispose);
  return container.read(stackSafetyReportProvider.future);
}

StackIntelligence _diagnose(StackSafetyReport report) =>
    const StackIntelligenceEngine().diagnoseFromReports(
      stackSize: 1,
      safetyReport: report,
      recalledReport: RecalledIngredientsReport.empty(),
      synergyReport: SynergyReport.empty(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a pregnant user gets the label text once, as health-context guidance',
    () async {
      final report = await _report(
        flags: const {'pregnant'},
        // The pipeline lists a warning in both arrays when it is not suppressed.
        blob: () async => {
          'warnings': [_labelWarning(), _labelWarning()],
          'warnings_profile_gated': [_labelWarning()],
        },
      );

      expect(report.stackInteractions, hasLength(1));
      final result = report.stackInteractions.single;
      expect(result.type, InteractionType.conditionSupplement);
      expect(result.severity, Severity.avoid);
      expect(result.evidenceLevel, EvidenceLevel.ungraded);
      expect(result.mechanism, _text);

      final signals = allClinicalSignalsFrom(report: report);
      expect(signals, hasLength(1));
      expect(signals.single.body, _text);
      // A concern on the stack, but not an interaction, so the summary never
      // calls it one.
      final intelligence = _diagnose(report);
      expect(intelligence.tier, StackTier.concerning);
      expect(intelligence.interactionCount, 0);
      expect(
        describeStackSummary(intelligence),
        'Important issues found — review this stack.',
      );
    },
  );

  test(
    'a nursing user gets it, and a label naming only pregnancy skips them',
    () async {
      final both = await _report(
        flags: const {'breastfeeding'},
        blob: () async => {
          'warnings': [_labelWarning()],
        },
      );
      expect(both.stackInteractions, hasLength(1));

      final pregnancyOnly = await _report(
        flags: const {'breastfeeding'},
        blob: () async => {
          'warnings': [
            _labelWarning(flags: const ['pregnant']),
          ],
        },
      );
      expect(pregnancyOnly.stackInteractions, isEmpty);
    },
  );

  test('two different statements on one label stay two', () async {
    final report = await _report(
      flags: const {'pregnant'},
      blob: () async => {
        'warnings': [
          _labelWarning(),
          _labelWarning(text: 'Caution: Do not take if pregnant or nursing.'),
        ],
      },
    );
    expect(report.stackInteractions, hasLength(2));
    expect(allClinicalSignalsFrom(report: report), hasLength(2));
  });

  test('someone with no life-stage flag sees nothing', () async {
    final report = await _report(
      flags: const {},
      blob: () async => {
        'warnings': [_labelWarning()],
      },
    );
    expect(report.stackInteractions, isEmpty);
    expect(report.checksIncomplete, isFalse);
  });

  test(
    'other warning types stay on the product page, not in this signal',
    () async {
      final report = await _report(
        flags: const {'pregnant'},
        blob: () async => {
          'warnings': [
            {
              ..._labelWarning(),
              'type': 'interaction',
              'source': 'interaction_rules',
            },
          ],
        },
      );
      expect(report.stackInteractions, isEmpty);
    },
  );

  test('a label warning moves the tier but never the internal score', () async {
    final clean = await _report(
      flags: const {'pregnant'},
      blob: () async => <String, dynamic>{'warnings': <Object>[]},
    );
    final avoid = await _report(
      flags: const {'pregnant'},
      blob: () async => {
        'warnings': [_labelWarning()],
      },
    );
    final caution = await _report(
      flags: const {'pregnant'},
      blob: () async => {
        'warnings': [_labelWarning(severity: 'caution')],
      },
    );

    final baseline = _diagnose(clean);
    expect(baseline.tier, StackTier.optimized);
    expect(_diagnose(avoid).tier, StackTier.concerning);
    expect(_diagnose(caution).tier, StackTier.decent);
    expect(_diagnose(avoid).qualityScore, baseline.qualityScore);
    expect(_diagnose(caution).qualityScore, baseline.qualityScore);
  });

  test('an unreadable blob hedges instead of reading as clean', () async {
    final failed = await _report(
      flags: const {'pregnant'},
      blob: () async => throw StateError('blob unavailable'),
    );
    expect(failed.checksIncomplete, isTrue);

    final missing = await _report(
      flags: const {'pregnant'},
      blob: () async => null,
    );
    expect(missing.checksIncomplete, isTrue);
  });

  test(
    'a malformed warning list is skipped without failing the report',
    () async {
      final report = await _report(
        flags: const {'pregnant'},
        blob: () async => {
          'warnings': ['not a map', 7, null, _labelWarning()],
          'warnings_profile_gated': 'not a list',
        },
      );
      expect(report.stackInteractions, hasLength(1));
    },
  );
}
