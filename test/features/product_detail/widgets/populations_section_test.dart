// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.9.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/populations_section.dart';

InteractionWarning _w({List<String> populationWarnings = const []}) {
  return InteractionWarning(
    severity: Severity.caution,
    evidenceLevel: EvidenceLevel.theoretical,
    title: 't',
    mechanism: 'm',
    management: 'mgmt',
    populationWarnings: populationWarnings,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<InteractionWarning> warnings,
  Set<String> userConditions = const {},
  Set<String> userDrugClasses = const {},
  String? ageBracket,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PopulationsSection(
          warnings: warnings,
          userConditions: userConditions,
          userDrugClasses: userDrugClasses,
          ageBracket: ageBracket,
        ),
      ),
    ),
  );
}

void main() {
  group('splitPopulations — pure logic', () {
    test('empty input → both lists empty', () {
      final s = splitPopulations(
        populations: const [],
        userConditions: const {},
        userDrugClasses: const {},
      );
      expect(s.mainList, isEmpty);
      expect(s.alreadyCovered, isEmpty);
    });

    test('no user signals → all populations go to main list', () {
      final s = splitPopulations(
        populations: const [
          'Pregnancy',
          'Children — immature gut barrier',
          'People with IBD',
        ],
        userConditions: const {},
        userDrugClasses: const {},
      );
      expect(s.mainList, hasLength(3));
      expect(s.alreadyCovered, isEmpty);
    });

    test('user has pregnancy + a Pregnancy population → covered', () {
      final s = splitPopulations(
        populations: const ['Pregnancy', 'Children — immature gut barrier'],
        userConditions: const {'pregnancy'},
        userDrugClasses: const {},
      );
      expect(s.mainList, ['Children — immature gut barrier']);
      expect(s.alreadyCovered, ['Pregnancy']);
    });

    test('keyword match — "diabetic" in population matches diabetes condition',
        () {
      // The keyword map maps "diabetic" → "diabetes" signal.
      final s = splitPopulations(
        populations: const ['Diabetic patients should monitor closely'],
        userConditions: const {'diabetes'},
        userDrugClasses: const {},
      );
      expect(s.mainList, isEmpty);
      expect(s.alreadyCovered, ['Diabetes']);
    });

    test('word-boundary — "fish" doesn\'t match inside "fishing"', () {
      // Defensive — make sure substring matches respect word
      // boundaries. The keyword map doesn't have "fish" but the
      // structural rule is the same for any keyword.
      final s = splitPopulations(
        populations: const [
          'People who go fishing should consult their doctor',
        ],
        userConditions: const {'pregnancy'},
        userDrugClasses: const {},
      );
      // No match expected — "pregnancy" / "pregnant" don't appear
      // and "fish" is not a keyword.
      expect(s.mainList, hasLength(1));
      expect(s.alreadyCovered, isEmpty);
    });

    test('case-insensitive — "PREGNANT" matches pregnancy', () {
      final s = splitPopulations(
        populations: const ['PREGNANT WOMEN should avoid'],
        userConditions: const {'pregnancy'},
        userDrugClasses: const {},
      );
      expect(s.mainList, isEmpty);
      expect(s.alreadyCovered, ['Pregnancy']);
    });

    test('multiple populations match the same user signal → covered once',
        () {
      // Both "Pregnancy" and "Pregnant women" map to the pregnancy
      // signal. The covered-list should mention it once.
      final s = splitPopulations(
        populations: const [
          'Pregnancy',
          'Pregnant women',
          'Children',
        ],
        userConditions: const {'pregnancy'},
        userDrugClasses: const {},
      );
      expect(s.mainList, ['Children']);
      expect(s.alreadyCovered, ['Pregnancy']);
    });

    test('all populations match → main empty, all covered', () {
      final s = splitPopulations(
        populations: const ['Pregnancy', 'Diabetic patients'],
        userConditions: const {'pregnancy', 'diabetes'},
        userDrugClasses: const {},
      );
      expect(s.mainList, isEmpty);
      expect(s.alreadyCovered, ['Diabetes', 'Pregnancy']);
    });

    test('drug-class match — "anticoagulants" in population', () {
      final s = splitPopulations(
        populations: const [],
        userConditions: const {},
        userDrugClasses: const {'anticoagulants'},
      );
      // No populations to test, but verify the user signal flows
      // through without error. Add a test population:
      final s2 = splitPopulations(
        populations: const [
          // (Note: drug class names aren't typical population
          // strings. Drug-class dedupe happens via Section 7. This
          // covers the case where pipeline emits drug class as a
          // population for some reason — defensive.)
          'People taking anticoagulants',
        ],
        userConditions: const {},
        userDrugClasses: const {'anticoagulants'},
      );
      // The keyword map doesn't include "anticoagulants" yet, so
      // this currently goes to mainList. Documenting current
      // behavior — pipeline rarely emits drug classes as
      // populations and Section 7 already covers them.
      expect(s.mainList, isEmpty);
      expect(s2.mainList, hasLength(1));
    });

    test('age bracket — under_18 user matches "children" population', () {
      final s = splitPopulations(
        populations: const ['Children should avoid', 'Pregnant women'],
        userConditions: const {},
        userDrugClasses: const {},
        ageBracket: 'under_18',
      );
      expect(s.mainList, ['Pregnant women']);
      expect(s.alreadyCovered, ['Under 18']);
    });

    test('dedup — duplicate strings appear once in main list', () {
      final s = splitPopulations(
        populations: const [
          'Children — immature gut barrier',
          'Children — immature gut barrier',
          'Pregnancy',
        ],
        userConditions: const {},
        userDrugClasses: const {},
      );
      expect(s.mainList, hasLength(2));
    });

    test('blank entries are dropped defensively', () {
      final s = splitPopulations(
        populations: const ['', '   ', 'Pregnancy'],
        userConditions: const {},
        userDrugClasses: const {},
      );
      expect(s.mainList, ['Pregnancy']);
    });

    test('alreadyCovered list is alphabetically sorted (deterministic)',
        () {
      final s = splitPopulations(
        populations: const ['Pregnancy', 'Diabetic'],
        userConditions: const {'pregnancy', 'diabetes'},
        userDrugClasses: const {},
      );
      // Diabetes before Pregnancy alphabetically.
      expect(s.alreadyCovered, ['Diabetes', 'Pregnancy']);
    });
  });

  group('aggregatePopulations', () {
    test('flattens populationWarnings across multiple warnings', () {
      final aggregate = aggregatePopulations([
        _w(populationWarnings: const ['Pregnancy', 'Children']),
        _w(populationWarnings: const ['Diabetic']),
        _w(),
      ]);
      expect(aggregate, ['Pregnancy', 'Children', 'Diabetic']);
    });
  });

  group('PopulationsSection — render', () {
    testWidgets('no populations → section hides entirely', (tester) async {
      await _pump(tester, warnings: [_w()]);
      await tester.pumpAndSettle();
      expect(find.text('At-risk populations'), findsNothing);
    });

    testWidgets(
      'populations + no user profile → renders main list, no covered line',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _w(populationWarnings: const ['Pregnancy', 'Children']),
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text('At-risk populations'), findsOneWidget);
        expect(
          find.text('Extra caution for: Pregnancy, Children'),
          findsOneWidget,
        );
        expect(find.textContaining('already covered'), findsNothing);
      },
    );

    testWidgets(
      'population matches user condition → covered line; non-match → main',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _w(populationWarnings: const [
              'Pregnancy',
              'Children — immature gut barrier',
            ]),
          ],
          userConditions: {'pregnancy'},
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Extra caution for: Children — immature gut barrier'),
          findsOneWidget,
        );
        expect(
          find.text('(You are already covered for Pregnancy)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'all populations match user → main hidden, only covered line renders',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _w(populationWarnings: const ['Pregnancy', 'Diabetic patients']),
          ],
          userConditions: {'pregnancy', 'diabetes'},
        );
        await tester.pumpAndSettle();

        expect(find.text('At-risk populations'), findsOneWidget);
        // Main list line absent.
        expect(find.textContaining('Extra caution for'), findsNothing);
        // Covered line lists both, sorted alpha.
        expect(
          find.text('(You are already covered for Diabetes, Pregnancy)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'all populations match AND nothing else → section visible only with '
      'covered line (no orphan empty card)',
      (tester) async {
        // Edge case: ensure we don't render an empty card when
        // dedupe wipes out the main list and there's a covered line
        // — at minimum the covered line carries the value.
        await _pump(
          tester,
          warnings: [
            _w(populationWarnings: const ['Pregnancy']),
          ],
          userConditions: {'pregnancy'},
        );
        await tester.pumpAndSettle();

        expect(find.text('At-risk populations'), findsOneWidget);
        expect(
          find.text('(You are already covered for Pregnancy)'),
          findsOneWidget,
        );
      },
    );

    testWidgets('age bracket flows through to dedupe', (tester) async {
      await _pump(
        tester,
        warnings: [
          _w(populationWarnings: const ['Children should avoid']),
        ],
        ageBracket: 'under_18',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('(You are already covered for Under 18)'),
        findsOneWidget,
      );
    });
  });
}
