import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _w({
  required String headline,
  required Severity severity,
  List<String> conditionIds = const [],
  List<String> drugClassIds = const [],
  String displayModeDefault = 'informational',
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.probable,
    title: headline,
    mechanism: 'mechanism for $headline',
    management: 'action for $headline',
    conditionIds: conditionIds,
    drugClassIds: drugClassIds,
    displayModeDefault: displayModeDefault,
  );
}

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

    test('critical product-quality caution without profile gate → general bucket', () {
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
    });

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
  });
}
