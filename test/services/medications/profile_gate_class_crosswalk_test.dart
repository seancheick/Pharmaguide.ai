import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';

// Contract tests for the interaction-bridge `class:*` -> profile/rule vocab
// crosswalk (MedicationClassBridge.profileGateIdsForClasses). The policy:
// fail open, and seed ONLY from verified sources — never infer clinical
// equivalence without sign-off.
void main() {
  group('profileGateIdsForClasses — vocab crosswalk contract', () {
    test('applies the seeded override (antiplatelet_agents -> antiplatelets)', () {
      expect(
        MedicationClassBridge.profileGateIdsForClasses([
          'class:antiplatelet_agents',
        ]),
        ['antiplatelets'],
      );
    });

    test('fails open: an unmapped class: id passes through class-stripped', () {
      // Not dropped — passes through as its bare id so it still matches a
      // rule keyed on the same id.
      expect(
        MedicationClassBridge.profileGateIdsForClasses([
          'class:nsaids',
          'class:diabetes_meds',
          'class:ssris',
        ]),
        ['nsaids', 'diabetes_meds', 'ssris'],
      );
    });

    test('ignores non-class: ids', () {
      expect(
        MedicationClassBridge.profileGateIdsForClasses(['nsaids', '', 'statins']),
        isEmpty,
      );
    });

    test('dedupes and preserves order', () {
      expect(
        MedicationClassBridge.profileGateIdsForClasses([
          'class:nsaids',
          'class:nsaids',
          'class:statins',
        ]),
        ['nsaids', 'statins'],
      );
    });

    test('does NOT infer unverified clinical crosswalks (discipline guard)', () {
      // If someone later seeds one of these clinical mappings WITHOUT sign-off,
      // this test breaks and forces the review the policy requires.
      final out = MedicationClassBridge.profileGateIdsForClasses([
        'class:diabetes_meds',
        'class:vitamin_k_antagonists',
        'class:ssris',
      ]);
      expect(out, isNot(contains('hypoglycemics_high_risk')));
      expect(out, isNot(contains('hypoglycemics_lower_risk')));
      expect(out, isNot(contains('hypoglycemics_unknown')));
      expect(out, isNot(contains('anticoagulants')));
      expect(out, isNot(contains('antidepressants_ssri_snri')));
    });
  });
}
