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
      'duplicate prenatal warning collapses after partition and profile placement wins',
      () {
        const body =
            'Vitamin C is required in pregnancy, but high intakes need review.';
        const action = 'Review total intake with your clinician.';
        final generic = _w(
          headline: 'Keep vitamin C within prenatal range',
          severity: Severity.caution,
          mechanism: body,
          management: action,
          ingredientName: 'Vitamin C',
        );
        final profileMatched = _w(
          headline: '  KEEP VITAMIN C WITHIN PRENATAL RANGE  ',
          severity: Severity.caution,
          mechanism:
              ' vitamin C is required in pregnancy,   but high intakes need review. ',
          management: ' review TOTAL intake with your clinician. ',
          ingredientName: ' vitamin c ',
          conditionIds: const ['pregnancy'],
        );

        final result = _partition(
          [generic, profileMatched],
          userConditions: const {'pregnancy'},
        );

        expect(result.profile, hasLength(1));
        expect(identical(result.profile.single, profileMatched), isTrue);
        expect(result.general, isEmpty);
      },
    );

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

    test('different severities are not collapsed before final display', () {
      final guarded = composeGuardedWarnings(
        detailBlob: const {
          'warnings': [
            {
              'severity': 'monitor',
              'evidence_level': 'probable',
              'title': 'Standard nutrient guidance',
              'detail': 'Review this nutrient in context.',
              'action': 'Discuss it with your clinician.',
              'display_mode_default': 'informational',
            },
          ],
          'warnings_profile_gated': [
            {
              'severity': 'caution',
              'evidence_level': 'probable',
              'title': 'Standard nutrient guidance',
              'detail': 'Review this nutrient in context.',
              'action': 'Discuss it with your clinician.',
              'display_mode_default': 'informational',
            },
          ],
        },
        personalizedWarnings: const [],
        userConditions: const {},
        userDrugClasses: const {},
        userProfileFlags: const {},
      );

      final result = _partition(guarded);

      expect(_all(result).map((warning) => warning.severity), [
        Severity.monitor,
        Severity.caution,
      ]);
    });

    test('consumer-meaningful differences remain distinct', () {
      final baseline = _w(
        headline: 'Standard nutrient guidance',
        severity: Severity.caution,
        mechanism: 'Review this nutrient in context.',
        management: 'Discuss it with your clinician.',
        ingredientName: 'Magnesium',
        sourceUrls: const ['https://example.test/detail-a'],
      );
      final variants = <String, InteractionWarning>{
        'severity': _w(
          headline: baseline.title,
          severity: Severity.monitor,
          mechanism: baseline.mechanism,
          management: baseline.management,
          ingredientName: baseline.ingredientName,
          sourceUrls: baseline.sourceUrls,
        ),
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
        'ingredient': _w(
          headline: baseline.title,
          severity: baseline.severity,
          mechanism: baseline.mechanism,
          management: baseline.management,
          ingredientName: 'Calcium',
          sourceUrls: baseline.sourceUrls,
        ),
        'action': _w(
          headline: baseline.title,
          severity: baseline.severity,
          mechanism: baseline.mechanism,
          management: 'Use a different follow-up action.',
          ingredientName: baseline.ingredientName,
          sourceUrls: baseline.sourceUrls,
        ),
        'detail target': _w(
          headline: baseline.title,
          severity: baseline.severity,
          mechanism: baseline.mechanism,
          management: baseline.management,
          ingredientName: baseline.ingredientName,
          sourceUrls: const ['https://example.test/detail-b'],
        ),
      };

      for (final entry in variants.entries) {
        final result = _partition([baseline, entry.value]);
        expect(
          _all(result),
          hasLength(2),
          reason: '${entry.key} is part of warning identity',
        );
      }
    });

    test('different rendered evidence levels remain distinct', () {
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

      expect(result.general, hasLength(2));
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
