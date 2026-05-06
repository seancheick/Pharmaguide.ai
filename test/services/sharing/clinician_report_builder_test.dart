import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/sharing/clinician_report_builder.dart';

UserStacksLocalData _stack({
  required String id,
  required String name,
  String type = 'supplement',
  String? dosage,
  String? frequency,
}) {
  final ts = DateTime.utc(2026, 4, 29, 12);
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

UserProfile _profile({
  String? ageBracket,
  String? sex,
  String goals = '[]',
  String conditions = '[]',
  String drugClasses = '[]',
  String allergens = '[]',
  String profileFlags = '[]',
}) {
  final ts = DateTime.utc(2026, 4, 29, 12);
  return UserProfile(
    id: 1,
    nickname: null,
    ageBracket: ageBracket,
    sex: sex,
    goals: goals,
    conditions: conditions,
    drugClasses: drugClasses,
    allergens: allergens,
    profileFlags: profileFlags,
    createdAt: ts,
    lastUpdated: ts,
  );
}

const _builder = ClinicianReportBuilder();
final _generatedAt = DateTime.utc(2026, 4, 29, 17, 30);

const _emptyIntelligence = StackIntelligence(
  tier: StackTier.incomplete,
  stackSize: 0,
  issues: [],
  interactionCount: 0,
  nutrientWarningCount: 0,
  hasRecalledIngredient: false,
  hasContraindicatedInteraction: false,
  hasBannedIngredient: false,
);

void main() {
  group('ClinicianReportBuilder.build — privacy + disclaimer (T0.1 of C1)', () {
    test('always includes the on-device privacy note', () {
      final out = _builder.build(
        profile: null,
        stack: const [],
        intelligence: _emptyIntelligence,
        generatedAt: _generatedAt,
      );
      expect(out, contains('Generated on device'));
      expect(
        out,
        contains('PharmaGuide does not store this report on any server'),
      );
    });

    test('always includes the educational-not-medical-advice disclaimer', () {
      final out = _builder.build(
        profile: null,
        stack: const [],
        intelligence: _emptyIntelligence,
        generatedAt: _generatedAt,
      );
      // Top-of-document one-liner.
      expect(out, contains('Educational summary, not medical advice.'));
      // Footer disclaimer.
      expect(
        out,
        contains('This is an educational summary, not medical advice.'),
      );
      expect(out, contains('consult your healthcare provider'));
    });

    test('formats date as YYYY-MM-DD', () {
      final out = _builder.build(
        profile: null,
        stack: const [],
        intelligence: _emptyIntelligence,
        generatedAt: DateTime.utc(2026, 1, 5, 7),
      );
      expect(out, contains('2026-01-05'));
    });
  });

  group('ClinicianReportBuilder.build — section visibility', () {
    test('null profile + empty stack → no profile / med / supp sections', () {
      final out = _builder.build(
        profile: null,
        stack: const [],
        intelligence: _emptyIntelligence,
        generatedAt: _generatedAt,
      );
      expect(out, isNot(contains('## Profile')));
      expect(out, isNot(contains('## Medications')));
      expect(out, isNot(contains('## Supplements')));
      expect(out, isNot(contains('## Warnings')));
    });

    test(
      'profile populated → Profile section renders the populated fields',
      () {
        final out = _builder.build(
          profile: _profile(
            ageBracket: '35-44',
            sex: 'female',
            conditions: '["diabetes","hypertension"]',
            drugClasses: '["metformin","lisinopril"]',
          ),
          stack: const [],
          intelligence: _emptyIntelligence,
          generatedAt: _generatedAt,
        );
        expect(out, contains('## Profile'));
        expect(out, contains('- Age: 35-44'));
        expect(out, contains('- Sex: female'));
        expect(out, contains('- Conditions: diabetes, hypertension'));
        expect(out, contains('- Drug classes: metformin, lisinopril'));
      },
    );

    test('medications + supplements split into separate sections', () {
      final stack = [
        _stack(
          id: '1',
          name: 'Metformin',
          type: 'medication',
          dosage: '500 mg',
          frequency: 'twice daily',
        ),
        _stack(
          id: '2',
          name: 'Vitamin D3',
          type: 'supplement',
          dosage: '5000 IU',
          frequency: 'once daily',
        ),
        _stack(id: '3', name: 'Magnesium Glycinate', type: 'supplement'),
      ];
      final out = _builder.build(
        profile: null,
        stack: stack,
        intelligence: _emptyIntelligence,
        generatedAt: _generatedAt,
      );
      expect(out, contains('## Medications (1)'));
      expect(out, contains('- Metformin — 500 mg, twice daily'));
      expect(out, contains('## Supplements (2)'));
      expect(out, contains('- Vitamin D3 — 5000 IU, once daily'));
      // Bare name rendered when no dosage / frequency present.
      expect(out, contains('- Magnesium Glycinate'));
      expect(out, isNot(contains('Magnesium Glycinate —')));
    });
  });

  group('ClinicianReportBuilder.build — diagnosis + warnings', () {
    test('diagnosis section reports tier + counts + flag emojis', () {
      const intelligence = StackIntelligence(
        tier: StackTier.unsafe,
        stackSize: 5,
        issues: [],
        interactionCount: 2,
        nutrientWarningCount: 1,
        hasRecalledIngredient: true,
        hasContraindicatedInteraction: true,
        hasBannedIngredient: true,
      );
      final out = _builder.build(
        profile: null,
        stack: const [],
        intelligence: intelligence,
        generatedAt: _generatedAt,
      );
      expect(out, contains('## Stack Diagnosis'));
      expect(out, contains('- Tier: **Unsafe**'));
      expect(out, contains('- Stack size: 5'));
      expect(out, contains('- Interactions flagged: 2'));
      expect(out, contains('- Nutrient warnings: 1'));
      expect(out, contains('Banned ingredient detected'));
      expect(out, contains('Contraindicated interaction detected'));
      // hasRecalledIngredient is suppressed when hasBanned is true so
      // we don't double-flag.
      expect(out, isNot(contains('Recalled ingredient detected')));
    });

    test(
      'warnings section renders issues already severity-sorted by engine',
      () {
        const intelligence = StackIntelligence(
          tier: StackTier.concerning,
          stackSize: 4,
          issues: [
            // Engine emits in this order; builder must NOT re-sort.
            StackIssue(
              severity: Severity.contraindicated,
              headline: 'Warfarin + Vitamin K — direct contraindication',
            ),
            StackIssue(
              severity: Severity.avoid,
              headline: 'Iron + thyroid med — separate by 4h',
            ),
            StackIssue(
              severity: Severity.caution,
              headline: 'Calcium + iron — reduced absorption',
            ),
            StackIssue(
              severity: Severity.monitor,
              headline: 'Magnesium glucose tracking advised',
            ),
          ],
          interactionCount: 4,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: true,
          hasBannedIngredient: false,
        );
        final out = _builder.build(
          profile: null,
          stack: const [],
          intelligence: intelligence,
          generatedAt: _generatedAt,
        );

        expect(out, contains('## Warnings (most severe first)'));
        // Verify ordering: the contraindicated headline must appear
        // before avoid, which appears before caution, which appears
        // before monitor.
        final iCon = out.indexOf('direct contraindication');
        final iAvoid = out.indexOf('separate by 4h');
        final iCaution = out.indexOf('reduced absorption');
        final iMonitor = out.indexOf('glucose tracking');
        expect(iCon, greaterThan(0));
        expect(iAvoid, greaterThan(iCon));
        expect(iCaution, greaterThan(iAvoid));
        expect(iMonitor, greaterThan(iCaution));
        // 2026-04-30 — softer-tone vocab (severity.dart): labels are
        // sentence case, no longer screaming caps.
        expect(out, contains('**Do not use**'));
        expect(out, contains('**Not recommended**'));
        expect(out, contains('**Use caution**'));
        expect(out, contains('**Monitor**'));
      },
    );
  });

  group('ClinicianReportBuilder.build — golden-string contract', () {
    test('full known input → exact markdown shape', () {
      final out = _builder.build(
        profile: _profile(
          ageBracket: '35-44',
          sex: 'female',
          conditions: '["diabetes"]',
          drugClasses: '["metformin"]',
          goals: '["energy","sleep"]',
        ),
        stack: [
          _stack(
            id: 'm1',
            name: 'Metformin',
            type: 'medication',
            dosage: '500 mg',
            frequency: 'twice daily',
          ),
          _stack(
            id: 's1',
            name: 'Vitamin D3',
            type: 'supplement',
            dosage: '5000 IU',
          ),
        ],
        intelligence: const StackIntelligence(
          tier: StackTier.decent,
          stackSize: 2,
          issues: [
            StackIssue(
              severity: Severity.caution,
              headline: 'Magnesium — track glucose tolerance at high doses',
            ),
          ],
          interactionCount: 1,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        generatedAt: DateTime.utc(2026, 4, 29, 17, 30),
      );

      const expected = '''
# My Supplement Stack — Clinician Summary

**Generated on device · 2026-04-29**

> Educational summary, not medical advice. Generated entirely on this device — PharmaGuide does not store this report on any server.

## Profile
- Age: 35-44
- Sex: female
- Conditions: diabetes
- Drug classes: metformin
- Goals: energy, sleep

## Medications (1)
- Metformin — 500 mg, twice daily

## Supplements (1)
- Vitamin D3 — 5000 IU

## Stack Diagnosis
- Tier: **Decent**
- Stack size: 2
- Interactions flagged: 1
- Nutrient warnings: 0

## Warnings (most severe first)
- **Use caution** — Magnesium — track glucose tolerance at high doses

---

_This is an educational summary, not medical advice. Always consult your healthcare provider before starting or stopping a supplement._
''';

      expect(out, expected);
    });
  });

  group('ClinicianReportBuilder.build — JSON profile arrays decode safely', () {
    test('malformed JSON in profile field falls through to empty', () {
      // Should NOT throw; should just skip the field.
      final out = _builder.build(
        profile: _profile(conditions: 'not-json', goals: '[}'),
        stack: const [],
        intelligence: _emptyIntelligence,
        generatedAt: _generatedAt,
      );
      expect(out, isNot(contains('Conditions:')));
      expect(out, isNot(contains('Goals:')));
    });

    test('non-list JSON shape (object) is dropped silently', () {
      final out = _builder.build(
        profile: _profile(conditions: '{"key":"value"}'),
        stack: const [],
        intelligence: _emptyIntelligence,
        generatedAt: _generatedAt,
      );
      expect(out, isNot(contains('Conditions:')));
    });
  });
}
