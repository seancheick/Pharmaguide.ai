import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _w({
  required String headline,
  required Severity severity,
  EvidenceLevel evidenceLevel = EvidenceLevel.probable,
  String? mechanism,
  String? management,
  String? ingredientName,
  List<String> sourceUrls = const [],
  List<String> conditionIds = const [],
  List<String> drugClassIds = const [],
  String displayModeDefault = 'informational',
  String? direction,
  Map<String, dynamic>? doseThresholdEvaluation,
  String? alertHeadline,
  String? alertBody,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: evidenceLevel,
    title: headline,
    mechanism: mechanism ?? 'mechanism for $headline',
    management: management ?? 'action for $headline',
    ingredientName: ingredientName,
    sourceUrls: sourceUrls,
    conditionIds: conditionIds,
    drugClassIds: drugClassIds,
    displayModeDefault: displayModeDefault,
    direction: direction,
    doseThresholdEvaluation: doseThresholdEvaluation,
    alertHeadline: alertHeadline,
    alertBody: alertBody,
  );
}

({List<InteractionWarning> profile, List<InteractionWarning> general})
_partition(
  List<InteractionWarning> warnings, {
  Set<String> userConditions = const {},
}) {
  return partitionProfileWarnings(
    warnings: warnings,
    userConditions: userConditions,
    userDrugClasses: const {},
    userProfileFlags: const {},
  );
}

List<InteractionWarning> _all(
  ({List<InteractionWarning> profile, List<InteractionWarning> general})
  partitioned,
) => [...partitioned.profile, ...partitioned.general];

void main() {
  group('partitionProfileWarnings', () {
    test('global informational note → general bucket', () {
      final note = _w(
        headline: 'May lower blood sugar',
        severity: Severity.monitor,
      );

      final result = partitionProfileWarnings(
        warnings: [note],
        userConditions: const {},
        userDrugClasses: const {},
        userProfileFlags: const {},
      );

      expect(result.general, [note]);
      expect(result.profile, isEmpty);
    });

    test('warning matching the profile → profile bucket', () {
      final matched = _w(
        headline: 'Diabetes-med effect',
        severity: Severity.monitor,
        conditionIds: const ['diabetes'],
      );

      final result = partitionProfileWarnings(
        warnings: [matched],
        userConditions: const {'diabetes'},
        userDrugClasses: const {},
        userProfileFlags: const {},
      );

      expect(result.profile, [matched]);
      expect(result.general, isEmpty);
    });

    test('hard safety warning stays in profile bucket even unmatched', () {
      final ul = _w(
        headline: 'Exceeds upper limit',
        severity: Severity.avoid,
        displayModeDefault: 'critical',
      );

      final result = partitionProfileWarnings(
        warnings: [ul],
        userConditions: const {},
        userDrugClasses: const {},
        userProfileFlags: const {},
      );

      expect(result.profile, [ul]);
      expect(result.general, isEmpty);
    });

    test(
      'critical product-quality caution without profile gate → general bucket',
      () {
        final additive = _w(
          headline: 'Synthetic emulsifier with gut-disruption signals',
          severity: Severity.caution,
          displayModeDefault: 'critical',
        );

        final result = partitionProfileWarnings(
          warnings: [additive],
          userConditions: const {'diabetes'},
          userDrugClasses: const {'hypoglycemics_high_risk'},
          userProfileFlags: const {},
        );

        expect(result.general, [additive]);
        expect(result.profile, isEmpty);
      },
    );

    test('matched informational benefit → general bucket, not review', () {
      final benefit = _w(
        headline: 'B12 recommended preconception',
        severity: Severity.informational,
        conditionIds: const ['ttc'],
      );

      final result = partitionProfileWarnings(
        warnings: [benefit],
        userConditions: const {'ttc'},
        userDrugClasses: const {},
        userProfileFlags: const {},
      );

      expect(result.general, [benefit]);
      expect(result.profile, isEmpty);
    });

    test('matched safe note → general bucket, not review', () {
      final note = _w(
        headline: 'Fine for your profile',
        severity: Severity.safe,
        conditionIds: const ['ttc'],
      );

      final result = partitionProfileWarnings(
        warnings: [note],
        userConditions: const {'ttc'},
        userDrugClasses: const {},
        userProfileFlags: const {},
      );

      expect(result.general, [note]);
      expect(result.profile, isEmpty);
    });

    test('matched actionable caution → profile bucket', () {
      final caution = _w(
        headline: 'May affect glucose control',
        severity: Severity.caution,
        conditionIds: const ['diabetes'],
      );

      final result = partitionProfileWarnings(
        warnings: [caution],
        userConditions: const {'diabetes'},
        userDrugClasses: const {},
        userProfileFlags: const {},
      );

      expect(result.profile, [caution]);
      expect(result.general, isEmpty);
    });

    test(
      'matched informational breastfeeding advisory → calm general bucket',
      () {
        final advisory = _w(
          headline: 'High-dose B6 may affect milk supply',
          severity: Severity.informational,
          conditionIds: const ['lactation'],
          displayModeDefault: 'informational',
          direction: 'harmful',
        );

        final result = _partition(
          [advisory],
          userConditions: const {'lactation'},
        );

        expect(result.profile, isEmpty);
        expect(result.general, [advisory]);
      },
    );

    test('harmful actionable life-stage warning stays in warning bucket', () {
      final warning = _w(
        headline: 'Limited pregnancy safety data',
        severity: Severity.caution,
        conditionIds: const ['pregnancy'],
        displayModeDefault: 'informational',
        direction: 'harmful',
      );

      final result = _partition([warning], userConditions: const {'pregnancy'});

      expect(result.profile, [warning]);
      expect(result.general, isEmpty);
    });

    test('neutral profile guidance moves to the calm information lane', () {
      final note = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.monitor,
        conditionIds: const ['pregnancy'],
        direction: 'neutral',
      );

      final result = _partition([note], userConditions: const {'pregnancy'});

      expect(result.profile, isEmpty);
      expect(result.general, [note]);
    });

    test('neutral non-life-stage guidance stays review-worthy', () {
      final warning = _w(
        headline: 'High-dose vitamin D needs monitoring',
        severity: Severity.monitor,
        conditionIds: const ['heart_disease'],
        direction: 'neutral',
      );

      final result = _partition(
        [warning],
        userConditions: const {'heart_disease'},
      );

      expect(result.profile, [warning]);
      expect(result.general, isEmpty);
    });

    test('critical breastfeeding warning stays in the warning bucket', () {
      final warning = _w(
        headline: 'Do not use while breastfeeding',
        severity: Severity.caution,
        conditionIds: const ['lactation'],
        displayModeDefault: 'critical',
      );

      final result = _partition([warning], userConditions: const {'lactation'});

      expect(result.profile, [warning]);
      expect(result.general, isEmpty);
    });

    test('breastfeeding medication interaction stays in warning bucket', () {
      final warning = _w(
        headline: 'May interact with your medication',
        severity: Severity.caution,
        conditionIds: const ['lactation'],
        drugClassIds: const ['anticoagulants'],
        displayModeDefault: 'informational',
      );

      final result = partitionProfileWarnings(
        warnings: [warning],
        userConditions: const {'lactation'},
        userDrugClasses: const {'anticoagulants'},
        userProfileFlags: const {},
      );

      expect(result.profile, [warning]);
      expect(result.general, isEmpty);
    });

    test('matched no-data advisory → general bucket, not review', () {
      final advisory = _w(
        headline: 'Limited safety data',
        severity: Severity.monitor,
        evidenceLevel: EvidenceLevel.noData,
        conditionIds: const ['lactation'],
      );

      final result = _partition(
        [advisory],
        userConditions: const {'lactation'},
      );

      expect(result.profile, isEmpty);
      expect(result.general, [advisory]);
    });

    test('duplicate prenatal advisory collapses into one calm profile note', () {
      const body =
          'Vitamin C is required in pregnancy, but high intakes need review.';
      const action = 'Review total intake with your clinician.';
      final generic = _w(
        headline: 'Keep vitamin C within prenatal range',
        severity: Severity.caution,
        mechanism: body,
        management: action,
        ingredientName: 'Vitamin C',
        direction: 'neutral',
      );
      final profileMatched = _w(
        headline: '  KEEP VITAMIN C WITHIN PRENATAL RANGE  ',
        severity: Severity.caution,
        mechanism:
            ' vitamin C is required in pregnancy,   but high intakes need review. ',
        management: ' review TOTAL intake with your clinician. ',
        ingredientName: ' vitamin c ',
        conditionIds: const ['pregnancy'],
        direction: 'neutral',
      );

      final result = _partition(
        [generic, profileMatched],
        userConditions: const {'pregnancy'},
      );

      expect(result.profile, isEmpty);
      expect(result.general, hasLength(1));
      expect(result.general.single.conditionIds, const ['pregnancy']);
    });

    test(
      'same mechanism from separate sources keeps distinct consumer copy',
      () {
        const sharedMechanism = 'The same technical mechanism.';
        final personalized = _w(
          headline: 'Personalized warning',
          severity: Severity.caution,
          mechanism: sharedMechanism,
          management: 'Personalized action.',
        );
        final guarded = composeGuardedWarnings(
          detailBlob: const {
            'warnings': [
              {
                'severity': 'caution',
                'evidence_level': 'probable',
                'title': 'Different product warning',
                'detail': sharedMechanism,
                'action': 'Different product action.',
                'display_mode_default': 'informational',
              },
            ],
          },
          personalizedWarnings: [personalized],
          userConditions: const {},
          userDrugClasses: const {},
          userProfileFlags: const {},
        );

        final result = _partition(guarded);

        expect(_all(result), hasLength(2));
      },
    );

    test('duplicate visible copy keeps the strongest severity once', () {
      final monitor = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.monitor,
        mechanism: 'Review this nutrient in context.',
      );
      final caution = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.caution,
        mechanism: 'Review this nutrient in context.',
      );

      final result = _partition([monitor, caution]);

      expect(_all(result), hasLength(1));
      expect(_all(result).single.severity, Severity.caution);
    });

    test('dose-evaluated duplicate outranks generic higher severity', () {
      final evaluated = _w(
        headline: 'Vitamin B6 / lactation',
        alertHeadline: 'High-dose B6 may affect milk supply',
        alertBody: 'Normal multivitamin levels do not trigger this concern.',
        severity: Severity.informational,
        ingredientName: 'Vitamin B6',
        conditionIds: const ['lactation'],
        direction: 'harmful',
        doseThresholdEvaluation: const {'evaluated': true},
      );
      final generic = _w(
        headline: 'Vitamin B6 / lactation',
        alertHeadline: 'High-dose B6 may affect milk supply',
        alertBody: 'Pharmacologic doses may reduce milk supply.',
        severity: Severity.caution,
        ingredientName: 'Vitamin B6',
        conditionIds: const ['lactation'],
        direction: 'harmful',
      );

      final result = _partition(
        [generic, evaluated],
        userConditions: const {'lactation'},
      );

      expect(_all(result), hasLength(1));
      expect(_all(result).single.severity, Severity.informational);
      expect(
        _all(result).single.displayBody,
        'Normal multivitamin levels do not trigger this concern.',
      );
      expect(result.profile, isEmpty);
      expect(result.general, hasLength(1));
    });

    test('dose specificity never crosses ingredient subjects', () {
      final evaluated = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.informational,
        ingredientName: 'Vitamin B6',
        doseThresholdEvaluation: const {'evaluated': true},
      );
      final caution = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.caution,
        ingredientName: 'Vitamin D',
      );

      final result = _partition([evaluated, caution]);

      expect(_all(result), hasLength(1));
      expect(_all(result).single.severity, Severity.caution);
    });

    test(
      'duplicate critical hazard keeps strongest severity and merges citations',
      () {
        final activeSide = _w(
          headline: 'Avoid DHEA',
          severity: Severity.avoid,
          ingredientName: 'DHEA',
          sourceUrls: const ['https://example.test/active'],
          displayModeDefault: 'critical',
        );
        final inactiveSide = _w(
          headline: 'High-risk hormonal ingredient',
          severity: Severity.caution,
          ingredientName: ' dhea ',
          sourceUrls: const ['https://example.test/inactive'],
          displayModeDefault: 'critical',
        );

        final result = _partition([inactiveSide, activeSide]);

        expect(_all(result), hasLength(1));
        expect(_all(result).single.severity, Severity.avoid);
        expect(_all(result).single.sourceUrls, {
          'https://example.test/active',
          'https://example.test/inactive',
        });
      },
    );

    test('only consumer-visible differences remain distinct', () {
      final baseline = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.caution,
        mechanism: 'Review this nutrient in context.',
        management: 'Discuss it with your clinician.',
        ingredientName: 'Magnesium',
        sourceUrls: const ['https://example.test/detail-a'],
      );
      final distinctVariants = <String, InteractionWarning>{
        'title': _w(
          headline: 'Different nutrient guidance',
          severity: baseline.severity,
          mechanism: baseline.mechanism,
          management: baseline.management,
          ingredientName: baseline.ingredientName,
          sourceUrls: baseline.sourceUrls,
        ),
        'message': _w(
          headline: baseline.title,
          severity: baseline.severity,
          mechanism: 'A meaningfully different message.',
          management: baseline.management,
          ingredientName: baseline.ingredientName,
          sourceUrls: baseline.sourceUrls,
        ),
      };

      for (final entry in distinctVariants.entries) {
        final result = _partition([baseline, entry.value]);
        expect(
          _all(result),
          hasLength(2),
          reason: '${entry.key} is part of warning identity',
        );
      }

      final hiddenMetadataVariants = <String, InteractionWarning>{
        'ingredient': _w(
          headline: baseline.title,
          severity: baseline.severity,
          mechanism: baseline.mechanism,
          management: baseline.management,
          ingredientName: 'Calcium',
          sourceUrls: baseline.sourceUrls,
        ),
        'clinical action': _w(
          headline: baseline.title,
          severity: baseline.severity,
          mechanism: baseline.mechanism,
          management: 'Use a different follow-up action.',
          ingredientName: baseline.ingredientName,
          sourceUrls: baseline.sourceUrls,
        ),
        'citation target': _w(
          headline: baseline.title,
          severity: baseline.severity,
          mechanism: baseline.mechanism,
          management: baseline.management,
          ingredientName: baseline.ingredientName,
          sourceUrls: const ['https://example.test/detail-b'],
        ),
      };

      for (final entry in hiddenMetadataVariants.entries) {
        final result = _partition([baseline, entry.value]);
        expect(
          _all(result),
          hasLength(1),
          reason: '${entry.key} is not visible in the collapsed warning row',
        );
      }
    });

    test('duplicate visible copy with different evidence renders once', () {
      final probable = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.caution,
        mechanism: 'Review this nutrient in context.',
        management: 'Discuss it with your clinician.',
        evidenceLevel: EvidenceLevel.probable,
      );
      final established = _w(
        headline: probable.title,
        severity: probable.severity,
        mechanism: probable.mechanism,
        management: probable.management,
        evidenceLevel: EvidenceLevel.established,
      );

      final result = _partition([probable, established]);

      expect(result.general, hasLength(1));
    });

    test('same citation target set in different order dedupes', () {
      final first = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.caution,
        mechanism: 'Review this nutrient in context.',
        management: 'Discuss it with your clinician.',
        sourceUrls: const [
          'https://example.test/source-a',
          'https://example.test/source-b',
        ],
      );
      final reordered = _w(
        headline: first.title,
        severity: first.severity,
        mechanism: first.mechanism,
        management: first.management,
        sourceUrls: const [
          'https://example.test/source-b',
          'https://example.test/source-a',
        ],
      );

      final result = _partition([first, reordered]);

      expect(result.general, hasLength(1));
    });

    test(
      'informational and critical display modes remain distinct regardless of order',
      () {
        final informational = _w(
          headline: 'Global product note',
          severity: Severity.caution,
          mechanism: 'The same visible explanation.',
          management: 'The same follow-up action.',
          displayModeDefault: 'informational',
        );
        final critical = _w(
          headline: 'Global product note',
          severity: Severity.caution,
          mechanism: 'The same visible explanation.',
          management: 'The same follow-up action.',
          displayModeDefault: 'critical',
        );

        for (final warnings in [
          [informational, critical],
          [critical, informational],
        ]) {
          final result = _partition(warnings);
          expect(result.general, hasLength(2));
          expect(
            result.general.any(
              (warning) => warning.displayModeDefault == 'critical',
            ),
            isTrue,
            reason: 'critical mode must survive in either source order',
          );
        }
      },
    );

    test('legacy null and explicit informational display modes dedupe', () {
      const legacy = InteractionWarning(
        severity: Severity.caution,
        evidenceLevel: EvidenceLevel.probable,
        title: 'Global product note',
        mechanism: 'The same visible explanation.',
        management: 'The same follow-up action.',
      );
      final explicit = _w(
        headline: ' global PRODUCT note ',
        severity: Severity.caution,
        mechanism: ' the same visible explanation. ',
        management: ' the same follow-up action. ',
        displayModeDefault: ' INFORMATIONAL ',
      );

      final result = _partition([legacy, explicit]);

      expect(result.general, hasLength(1));
    });

    test('dedupe preserves first-occurrence order for distinct warnings', () {
      final first = _w(headline: 'First warning', severity: Severity.caution);
      final duplicate = _w(
        headline: ' first   WARNING ',
        severity: Severity.caution,
        mechanism: ' MECHANISM for first warning ',
        management: ' ACTION for first warning ',
      );
      final second = _w(headline: 'Second warning', severity: Severity.caution);

      final result = _partition([first, duplicate, second]);

      expect(result.general.map((warning) => warning.title), [
        'First warning',
        'Second warning',
      ]);
    });
  });
}
