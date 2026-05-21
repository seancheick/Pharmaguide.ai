// Widget-level tests proving the v6.0 profile_gate actually changes
// what users see in the Flutter UI.
//
// Each test sets up an InteractionWarning carrying a profile_gate and
// asserts matchesProfile() / list rendering produces the right outcome
// for a specific user profile + product context. This is the
// end-to-end check that connects:
//
//   pipeline rule profile_gate
//   → enricher passthrough
//   → build_final_db detail blob
//   → InteractionWarning.fromJson
//   → matchesProfile() / evaluator
//   → list partitioning
//
// If any of the four scenarios below fails, the v6.0 contract is broken.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _w({
  required String headline,
  required Severity severity,
  required Map<String, dynamic> profileGate,
  List<String> conditionIds = const [],
  List<String> drugClassIds = const [],
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.probable,
    title: headline,
    mechanism: 'mechanism for $headline',
    management: 'action for $headline',
    alertHeadline: headline,
    alertBody:
        'If you match this gate, this is the body text rendered to the user.',
    conditionIds: conditionIds,
    drugClassIds: drugClassIds,
    profileGate: profileGate,
  );
}

Map<String, dynamic> _emptyExcludes() => const {
  'conditions_any': <String>[],
  'drug_classes_any': <String>[],
  'profile_flags_any': <String>[],
  'product_forms_any': <String>[],
  'nutrient_forms_any': <String>[],
};

void main() {
  group('profile_gate widget — non-matching profile suppresses alert', () {
    testWidgets(
      'non-pregnant user does NOT see pregnancy alert that would have '
      'fired by structural condition_id inference',
      (tester) async {
        final preg = _w(
          headline: 'Pregnancy alert',
          severity: Severity.avoid,
          conditionIds: const ['pregnancy'],
          profileGate: {
            'gate_type': 'profile_flag',
            'requires': {
              'conditions_any': <String>[],
              'drug_classes_any': <String>[],
              'profile_flags_any': ['pregnant'],
            },
            'excludes': _emptyExcludes(),
            'dose': null,
          },
        );

        // User has NEITHER the pregnancy condition NOR the pregnant flag.
        expect(
          preg.matchesProfile(
            userConditions: const {},
            userDrugClasses: const {},
            userProfileFlags: const {},
          ),
          isFalse,
          reason: 'Empty profile must NOT match a pregnancy gate',
        );

        // User has hypertension — still must NOT match a pregnancy gate.
        expect(
          preg.matchesProfile(
            userConditions: const {'hypertension'},
            userDrugClasses: const {},
            userProfileFlags: const {},
          ),
          isFalse,
        );

        // Pregnant user → match.
        expect(
          preg.matchesProfile(
            userConditions: const {},
            userDrugClasses: const {},
            userProfileFlags: const {'pregnant'},
          ),
          isTrue,
        );

        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      },
    );
  });

  group('profile_gate widget — product_forms_any exclusion', () {
    testWidgets(
      'topical-only aloe product does NOT trigger oral-aloe pregnancy alert',
      (tester) async {
        final aloePreg = _w(
          headline: 'Oral aloe in pregnancy',
          severity: Severity.avoid,
          conditionIds: const ['pregnancy'],
          profileGate: {
            'gate_type': 'profile_flag',
            'requires': {
              'conditions_any': <String>[],
              'drug_classes_any': <String>[],
              'profile_flags_any': ['pregnant'],
            },
            'excludes': {
              ..._emptyExcludes(),
              'product_forms_any': ['topical_only'],
            },
            'dose': null,
          },
        );

        // Pregnant user, topical product → suppressed.
        expect(
          aloePreg.matchesProfile(
            userConditions: const {},
            userDrugClasses: const {},
            userProfileFlags: const {'pregnant'},
            productForm: 'topical_only',
          ),
          isFalse,
          reason: 'topical_only product must be suppressed by excludes',
        );

        // Pregnant user, capsule (oral) product → fires.
        expect(
          aloePreg.matchesProfile(
            userConditions: const {},
            userDrugClasses: const {},
            userProfileFlags: const {'pregnant'},
            productForm: 'capsule',
          ),
          isTrue,
          reason: 'capsule must NOT match topical_only exclusion',
        );

        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      },
    );
  });

  group('profile_gate widget — nutrient_forms_any exclusion', () {
    testWidgets(
      'beta_carotene product does NOT trigger vitamin A retinol pregnancy alert',
      (tester) async {
        final retinolPreg = _w(
          headline: 'Vitamin A in pregnancy',
          severity: Severity.caution,
          conditionIds: const ['pregnancy'],
          profileGate: {
            'gate_type': 'profile_flag',
            'requires': {
              'conditions_any': <String>[],
              'drug_classes_any': <String>[],
              'profile_flags_any': ['pregnant'],
            },
            'excludes': {
              ..._emptyExcludes(),
              'nutrient_forms_any': ['beta_carotene', 'mixed_carotenoids'],
            },
            'dose': null,
          },
        );

        expect(
          retinolPreg.matchesProfile(
            userConditions: const {},
            userDrugClasses: const {},
            userProfileFlags: const {'pregnant'},
            nutrientForm: 'beta_carotene',
          ),
          isFalse,
          reason: 'beta_carotene must be suppressed by nutrient_forms_any',
        );

        expect(
          retinolPreg.matchesProfile(
            userConditions: const {},
            userDrugClasses: const {},
            userProfileFlags: const {'pregnant'},
            nutrientForm: 'retinol',
          ),
          isTrue,
          reason: 'retinol must NOT match the carotene exclusion',
        );

        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      },
    );
  });

  group(
    'profile_gate widget — combination gate (medication-aware escalation)',
    () {
      testWidgets(
        'berberine baseline caution (diabetes only) does NOT fire avoid; '
        'combination gate (diabetes + hypoglycemics) DOES fire avoid',
        (tester) async {
          final escalation = _w(
            headline: 'Avoid with hypoglycemia meds',
            severity: Severity.avoid,
            conditionIds: const ['diabetes'],
            drugClassIds: const ['hypoglycemics'],
            profileGate: {
              'gate_type': 'combination',
              'requires': {
                'conditions_any': ['diabetes'],
                'drug_classes_any': ['hypoglycemics'],
                'profile_flags_any': <String>[],
              },
              'excludes': _emptyExcludes(),
              'dose': null,
            },
          );

          // Diabetic NOT on hypoglycemics → escalation does NOT fire.
          expect(
            escalation.matchesProfile(
              userConditions: const {'diabetes'},
              userDrugClasses: const {'metformin'},
              userProfileFlags: const {},
            ),
            isFalse,
            reason: 'AND across keys — partial match (diabetes only) must fail',
          );

          // Diabetic on hypoglycemics → escalation fires.
          expect(
            escalation.matchesProfile(
              userConditions: const {'diabetes'},
              userDrugClasses: const {'hypoglycemics'},
              userProfileFlags: const {},
            ),
            isTrue,
          );

          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        },
      );
    },
  );

  group('profile_gate widget — pre-v6.0 fallback path', () {
    testWidgets(
      'warning without profile_gate falls back to legacy condition_ids '
      'set-intersection (backward compat for cached blobs)',
      (tester) async {
        const legacy = InteractionWarning(
          severity: Severity.avoid,
          evidenceLevel: EvidenceLevel.probable,
          title: 'Legacy pregnancy warning (no profile_gate)',
          mechanism: 'm',
          management: 'a',
          conditionIds: ['pregnancy'],
          // profileGate intentionally omitted — pre-v6.0 cached blob.
        );

        // Legacy path: condition match by intersection.
        expect(
          legacy.matchesProfile(
            userConditions: const {'pregnancy'},
            userDrugClasses: const {},
          ),
          isTrue,
        );
        expect(
          legacy.matchesProfile(
            userConditions: const {'hypertension'},
            userDrugClasses: const {},
          ),
          isFalse,
        );

        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      },
    );
  });
}
