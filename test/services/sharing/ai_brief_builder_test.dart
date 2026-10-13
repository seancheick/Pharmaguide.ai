import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/sharing/ai_brief_builder.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/sharing/clinician_report_data.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

UserStacksLocalData _stack({
  required String id,
  required String name,
  required String type,
  String? dosage,
  String? frequency,
}) {
  final ts = DateTime.utc(2026, 10, 12, 12);
  return UserStacksLocalData(
    id: id,
    type: type,
    name: name,
    dsldId: null,
    rxcui: null,
    ingredientKeys: null,
    drugClassesCol: null,
    genericRxcui: null,
    ingredientRxcuisCol: null,
    dosage: dosage,
    frequency: frequency,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: null,
  );
}

UserProfile _profile() {
  final ts = DateTime.utc(2026, 10, 12, 12);
  return UserProfile(
    id: 1,
    nickname: null,
    ageBracket: '35-44',
    sex: 'female',
    goals: '["sleep"]',
    conditions: '["hypertension","pregnant"]',
    drugClasses: '["ace_inhibitors"]',
    allergens: '["soy"]',
    profileFlags: '[]',
    createdAt: ts,
    lastUpdated: ts,
  );
}

const _drugSupplementInteraction = InteractionResult(
  id: 'levothyroxine_iron',
  type: InteractionType.drugSupplement,
  severity: Severity.avoid,
  evidenceLevel: EvidenceLevel.established,
  agent1Name: 'Levothyroxine',
  agent2Name: 'Iron',
  mechanism: 'Iron can reduce levothyroxine absorption.',
  management: 'Separate administration by at least four hours.',
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: ['https://dailymed.nlm.nih.gov/dailymed/example'],
  source: InteractionSource.pipeline,
);

const _supplementSupplementInteraction = InteractionResult(
  id: 'calcium_iron',
  type: InteractionType.supplementSupplement,
  severity: Severity.caution,
  evidenceLevel: EvidenceLevel.probable,
  agent1Name: 'Calcium',
  agent2Name: 'Iron',
  mechanism: 'Calcium can lower iron absorption when taken together.',
  management: 'Take them at different times of day.',
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: ['https://ods.od.nih.gov/example'],
  source: InteractionSource.pipeline,
);

const _conditionInteraction = InteractionResult(
  id: 'pregnancy_vitamin_a',
  type: InteractionType.conditionSupplement,
  severity: Severity.avoid,
  evidenceLevel: EvidenceLevel.established,
  agent1Name: 'Pregnancy',
  agent2Name: 'Vitamin A',
  mechanism: 'High preformed vitamin A intake in pregnancy carries risk.',
  management: 'Worth a conversation with your clinician.',
  doseDependant: true,
  doseThreshold: null,
  sourceUrls: [],
  source: InteractionSource.pipeline,
);

const _vitaminDStatus = NutrientStatus(
  total: NutrientTotal(
    canonicalId: 'vitamin_d',
    displayName: 'Vitamin D',
    totalAmount: 5000,
    unit: 'IU',
    contributions: [
      NutrientContribution(
        stackEntryId: 'supp-1',
        productName: 'Vitamin D3',
        amount: 5000,
        unit: 'IU',
      ),
    ],
  ),
  tier: NutrientTier.approachingUl,
  rda: 600,
  ul: 4000,
  pctOfRda: 833.3,
  pctOfUl: 125,
  warning: 'Above the upper limit for many adults.',
);

const _medicationTiming = TimingOptimization(
  ruleId: 'timing_calcium_lisinopril',
  ingredient1: 'Calcium',
  ingredient2: 'Lisinopril',
  advice: 'Separate calcium and this medication.',
  relation: TimingRelation(
    type: TimingRelationType.separateFrom,
    minimumHours: 2,
  ),
  category: TimingCategory.importantSeparation,
  actionability: TimingActionability.recommended,
  sourceAuthority: SourceAuthority.clinicalStudy,
  scoreImpact: -2,
  evidenceLevel: EvidenceLevel.probable,
  product1Name: 'Calcium Citrate',
  product1StackEntryId: 'supp-2',
  involvesMedication: true,
);

const _depletions = [
  DepletionMatch(
    depletionId: 'metformin_b12',
    drugDisplayName: 'Metformin',
    drugClassId: 'biguanides',
    nutrientName: 'Vitamin B12',
    nutrientCanonicalId: 'vitamin_b12',
    severity: 'moderate',
    mechanism: 'May reduce absorption over long-term use.',
    recommendation: 'Discuss B12 monitoring with a clinician.',
    evidenceLevel: 'established',
    sourceUrls: ['https://www.gov.uk/drug-safety-update/metformin-b12'],
    alertHeadline: 'Metformin may lower B12 over time',
  ),
];

ClinicianReportData _data({
  List<UserStacksLocalData>? stack,
  StackIntelligence? intelligence,
  StackSafetyReport? safetyReport,
  List<DepletionMatch> depletions = _depletions,
  Map<String, MedicationIdentityStatus> identity = const {},
}) {
  return ClinicianReportData(
    profile: _profile(),
    stack:
        stack ??
        [
          _stack(
            id: 'med-1',
            name: 'Lisinopril',
            type: 'medication',
            dosage: '10 mg',
            frequency: 'daily',
          ),
          _stack(
            id: 'supp-1',
            name: 'Vitamin D3',
            type: 'supplement',
            dosage: '5000 IU',
            frequency: 'daily',
          ),
          _stack(id: 'supp-2', name: 'Calcium Citrate', type: 'supplement'),
        ],
    intelligence:
        intelligence ??
        const StackIntelligence(
          tier: StackTier.concerning,
          stackSize: 3,
          issues: [
            StackIssue(
              severity: Severity.caution,
              headline: 'Calcium may affect medication timing',
            ),
          ],
          interactionCount: 2,
          nutrientWarningCount: 1,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
    safetyReport:
        safetyReport ??
        const StackSafetyReport(
          nutrientStatuses: [_vitaminDStatus],
          stackInteractions: [_supplementSupplementInteraction],
          medicationInteractions: [_drugSupplementInteraction],
          categoryWarnings: [_conditionInteraction],
          timingOptimizations: [_medicationTiming],
        ),
    depletions: depletions,
    medicationIdentityStatuses: identity,
    conditionLabels: const {
      'hypertension': 'Hypertension',
      'pregnant': 'Pregnant',
    },
    productCatalogVersion: '2026.10.12.142202',
    interactionRulesVersion: '1.0.14',
    clinicalDataVersion: 'clinical-db-2026.10.12.2',
    generatedAt: DateTime.utc(2026, 10, 12, 16, 30),
  );
}

/// Any sentence that declares a product or regimen safe is an unsupported
/// reassurance; pipeline classifications and the quoted rule are not.
final _unsupportedSafe = RegExp(
  r'\b(is|are|it.s|looks|seems) safe\b|\bsafe to (take|add|use|combine)\b',
  caseSensitive: false,
);

void main() {
  const builder = AiBriefBuilder();

  group('AiBriefBuilder default scope (medications and profile off)', () {
    late String text;
    setUp(() => text = builder.build(_data(), AiShareScope.detailedReport));

    test('lists supplements and provenance, never medications', () {
      expect(text, contains('# PharmaGuide stack brief'));
      expect(text, contains('Product catalog: 2026.10.12.142202'));
      expect(text, contains('Interaction rules: 1.0.14'));
      expect(text, contains('- Vitamin D3'));
      expect(text, contains('- Calcium Citrate'));
      expect(text, isNot(contains('Lisinopril')));
      expect(text, isNot(contains('10 mg')));
      expect(text, contains('Medications: not shared'));
      expect(text, contains('Ask the user before assuming none are taken'));
    });

    test('withholds every finding that would disclose a medication', () {
      // Drug-supplement interaction and the medication-nutrient relationship
      // name the medication; the untyped issue cannot be classified.
      expect(text, isNot(contains('Levothyroxine')));
      expect(text, isNot(contains('Metformin')));
      expect(text, isNot(contains('Calcium may affect medication timing')));
      expect(text, isNot(contains('Separate calcium and this medication')));
      expect(text, contains('withheld because they involve categories'));
      expect(text, contains('timing item involving medications withheld'));
      expect(
        text,
        contains('Medication-related checks are not part of this brief'),
      );
    });

    test('withholds profile-dependent findings and profile fields', () {
      expect(text, isNot(contains('Pregnan')));
      expect(text, isNot(contains('Hypertension')));
      expect(text, isNot(contains('Vitamin A')));
      expect(text, contains('Health profile: not shared'));
      expect(text, isNot(contains('% of target')));
      expect(text, contains('Targets depend on the health profile'));
    });

    test('keeps supplement-only findings with evidence and sources', () {
      expect(text, contains('Calcium can lower iron absorption'));
      expect(text, contains('Evidence level: probable'));
      expect(text, contains('Source: https://ods.od.nih.gov/example'));
      expect(text, contains('| Vitamin D | 5,000 IU | Vitamin D3 |'));
      expect(text, isNot(contains('125%')));
      expect(text, isNot(contains('Approaching upper limit')));
    });

    test('never declares anything safe', () {
      expect(_unsupportedSafe.hasMatch(text), isFalse, reason: text);
      expect(text, contains('say "no known concerns"'));
    });
  });

  test(
    'generic fallback UL warning survives while personal UL is withheld',
    () {
      for (final generic in [true, false]) {
        final status = NutrientStatus(
          total: _vitaminDStatus.total,
          tier: NutrientTier.exceedsUl,
          ul: 4000,
          pctOfUl: 125,
          ulIsFallback: generic,
          warning: 'UL warning control',
        );
        final text = builder.build(
          _data(safetyReport: StackSafetyReport(nutrientStatuses: [status])),
          AiShareScope.detailedReport,
        );
        expect(text.contains('UL warning control'), generic);
        expect(text, isNot(contains('% of target')));
      }
    },
  );

  test('findings cannot disclose excluded supplement names', () {
    final text = builder.build(
      _data(),
      const AiShareScope(supplementNames: false),
    );
    expect(text, isNot(contains('Calcium')));
    expect(text, isNot(contains('Vitamin D')));
  });

  group('AiBriefBuilder full scope', () {
    const scope = AiShareScope(
      medicationNames: true,
      medicationSchedule: true,
      profile: true,
      supplementSchedule: true,
    );
    late String text;
    setUp(
      () => text = builder.build(
        _data(identity: {'med-1': MedicationIdentityStatus.complete}),
        scope,
      ),
    );

    test('includes medications with schedule and identity coverage', () {
      expect(text, contains('- Lisinopril - as entered: 10 mg, daily'));
      expect(text, contains('identity: reviewed matching available'));
    });

    test('includes profile labels, never raw ids', () {
      expect(text, contains('Conditions: Hypertension, Pregnant'));
      expect(text, contains('Allergies/intolerances: Soy'));
      expect(text, isNot(contains('ace_inhibitors')));
      expect(text, contains('% of target'));
      expect(text, contains('833.3%'));
    });

    test('includes medication findings with evidence levels', () {
      expect(text, contains('Iron can reduce levothyroxine absorption'));
      expect(text, contains('Evidence level: established'));
      expect(text, contains('Management: Separate administration'));
      expect(text, contains('Source: https://dailymed.nlm.nih.gov'));
      expect(text, contains('Calcium may affect medication timing'));
      expect(text, contains('Metformin may lower B12 over time'));
      expect(text, contains('Relationship:'));
      expect(text, contains('High preformed vitamin A intake'));
      expect(text, contains('Separate calcium and this medication'));
      expect(text, isNot(contains('withheld')));
    });

    test('supplement schedule is marked as user-entered', () {
      expect(
        text,
        contains(
          '- Vitamin D3 - as entered by the user (not verified against the '
          'label): 5000 IU, daily',
        ),
      );
    });

    test('flags an unresolved declared medication class as partial', () {
      // The profile declares ACE inhibitors but the entered medication
      // carries no class, so the bridge cannot resolve it: not an all-clear.
      expect(text, contains('Partial: no entered medication resolves'));
      expect(text, contains('This is not an all-clear'));
    });
  });

  test('simple list preset shares names only', () {
    final text = builder.build(_data(), AiShareScope.simpleList);
    expect(text, contains('- Vitamin D3'));
    expect(text, isNot(contains('## PharmaGuide findings')));
    expect(text, isNot(contains('## Nutrient totals')));
    expect(text, isNot(contains('Evidence level')));
    expect(text, isNot(contains('Lisinopril')));
    expect(text, contains('PharmaGuide findings: not shared'));
  });

  test('findings off keeps label amounts but drops every comparison', () {
    final text = builder.build(_data(), const AiShareScope(findings: false));
    expect(text, contains('| Nutrient | Amount | From |'));
    expect(text, contains('| Vitamin D | 5,000 IU | Vitamin D3 |'));
    expect(text, isNot(contains('upper limit')));
    expect(text, isNot(contains('Approaching')));
    expect(text, isNot(contains('## PharmaGuide findings')));
  });

  test('normalizes a schedule switch without its name switch', () {
    final text = builder.build(
      _data(),
      const AiShareScope(medicationSchedule: true),
    );
    expect(text, isNot(contains('Lisinopril')));
    expect(text, isNot(contains('10 mg')));
  });

  test('empty stack says there is nothing to check against yet', () {
    final text = builder.build(
      _data(
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.incomplete,
          stackSize: 0,
          issues: [],
          interactionCount: 0,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(),
        depletions: const [],
      ),
      AiShareScope.detailedReport,
    );
    expect(text, contains('No supplements are saved in this stack.'));
    expect(text, contains('Nothing to check against yet'));
    expect(_unsupportedSafe.hasMatch(text), isFalse);
  });

  test('states incomplete checks before any finding', () {
    final text = builder.build(
      _data(
        safetyReport: const StackSafetyReport(
          checksIncomplete: true,
          coverageIncomplete: true,
          stackInteractions: [_supplementSupplementInteraction],
        ),
        depletions: const [],
      ),
      AiShareScope.detailedReport,
    );
    final incompleteIndex = text.indexOf('could not be completed');
    final coverageIndex = text.indexOf('could not be fully analyzed');
    final findingIndex = text.indexOf('Calcium can lower iron absorption');
    expect(incompleteIndex, isNonNegative);
    expect(coverageIndex, isNonNegative);
    expect(findingIndex, greaterThan(incompleteIndex));
    expect(findingIndex, greaterThan(coverageIndex));
  });

  test('a recall is stated as a fact even when its details are withheld', () {
    const recallHeadline =
        'WARNING — Example Product is subject to a recall involving lead.';
    final data = _data(
      intelligence: const StackIntelligence(
        tier: StackTier.unsafe,
        stackSize: 3,
        issues: [
          StackIssue(
            severity: Severity.contraindicated,
            headline: recallHeadline,
          ),
        ],
        interactionCount: 0,
        nutrientWarningCount: 0,
        hasRecalledIngredient: true,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
      ),
      safetyReport: const StackSafetyReport(),
      depletions: const [],
    );

    final limited = builder.build(data, AiShareScope.detailedReport);
    expect(limited, contains('flags a recalled ingredient'));
    expect(limited, isNot(contains('Example Product')));

    final full = builder.build(
      data,
      const AiShareScope(medicationNames: true, profile: true),
    );
    expect(full, contains('Example Product is subject to a recall'));
    // The clinical severity label passes through verbatim.
    expect(full, contains('**${Severity.contraindicated.label}**'));
  });

  test('unavailable medication-nutrient analysis is never silent', () {
    final text = builder.build(
      _data(
        depletions: const [],
      ).copyWithDepletionStatus(MedNutrientLoadStatus.unavailable),
      const AiShareScope(medicationNames: true),
    );
    expect(text, contains('Medication-nutrient analysis was unavailable'));
    expect(text, contains('the check could not run'));
  });
}

extension on ClinicianReportData {
  ClinicianReportData copyWithDepletionStatus(MedNutrientLoadStatus status) {
    return ClinicianReportData(
      profile: profile,
      stack: stack,
      intelligence: intelligence,
      safetyReport: safetyReport,
      depletions: depletions,
      depletionStatus: status,
      doseThresholdAlerts: doseThresholdAlerts,
      clinicalDataVersion: clinicalDataVersion,
      clinicalDataHash: clinicalDataHash,
      productCatalogVersion: productCatalogVersion,
      interactionRulesVersion: interactionRulesVersion,
      medicationIdentityStatuses: medicationIdentityStatuses,
      conditionLabels: conditionLabels,
      generatedAt: generatedAt,
    );
  }
}
