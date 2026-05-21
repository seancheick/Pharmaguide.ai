// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.9.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/populations_section.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Walks RichText widgets and matches when their concatenated plain-
/// text contains [substring]. Needed because the population bullet is
/// a styled span (head bold + tail muted) — `find.textContaining`
/// only inspects `Text.data`, which is null for RichText.
Finder _richTextContaining(String substring) {
  return find.byWidgetPredicate((w) {
    if (w is! RichText) return false;
    return w.text.toPlainText().contains(substring);
  });
}

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

    test(
      'keyword match — "diabetic" in population matches diabetes condition',
      () {
        // The keyword map maps "diabetic" → "diabetes" signal.
        final s = splitPopulations(
          populations: const ['Diabetic patients should monitor closely'],
          userConditions: const {'diabetes'},
          userDrugClasses: const {},
        );
        expect(s.mainList, isEmpty);
        expect(s.alreadyCovered, ['Diabetes']);
      },
    );

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

    test('multiple populations match the same user signal → covered once', () {
      // Both "Pregnancy" and "Pregnant women" map to the pregnancy
      // signal. The covered-list should mention it once.
      final s = splitPopulations(
        populations: const ['Pregnancy', 'Pregnant women', 'Children'],
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

    test('age bracket — schema "14-18" maps to under_18 signal', () {
      // Regression: SchemaIds.ageBrackets stores '14-18' verbatim and
      // it flows directly into this helper. Earlier mapping only
      // checked startsWith('under')/contains('child'/'65'/'over'), so
      // every real production user fell through to '' and dedupe never
      // fired.
      final s = splitPopulations(
        populations: const ['Children should avoid', 'Pregnant women'],
        userConditions: const {},
        userDrugClasses: const {},
        ageBracket: '14-18',
      );
      expect(s.mainList, ['Pregnant women']);
      expect(s.alreadyCovered, ['Under 18']);
    });

    test('age bracket — schema "71+" maps to over_65 signal', () {
      final s = splitPopulations(
        populations: const ['Older adults should monitor closely', 'Children'],
        userConditions: const {},
        userDrugClasses: const {},
        ageBracket: '71+',
      );
      expect(s.mainList, ['Children']);
      expect(s.alreadyCovered, ['Over 65']);
    });

    test('age bracket — "51-70" deliberately stays unmapped', () {
      // 51-70 spans 51-64 (not elderly) and 65-70 (elderly). Mapping
      // it would silently suppress legitimate warnings for the
      // majority of the bracket. Conservative call: leave it
      // unmapped so warnings still surface.
      final s = splitPopulations(
        populations: const ['Older adults should monitor closely'],
        userConditions: const {},
        userDrugClasses: const {},
        ageBracket: '51-70',
      );
      expect(s.mainList, ['Older adults should monitor closely']);
      expect(s.alreadyCovered, isEmpty);
    });

    test('age bracket — middle-age brackets do not match either signal', () {
      for (final b in ['19-30', '31-50']) {
        final s = splitPopulations(
          populations: const ['Children should avoid'],
          userConditions: const {},
          userDrugClasses: const {},
          ageBracket: b,
        );
        expect(s.mainList, [
          'Children should avoid',
        ], reason: 'bracket "$b" should not map');
        expect(s.alreadyCovered, isEmpty);
      }
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

    test('alreadyCovered list is alphabetically sorted (deterministic)', () {
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
      expect(find.text('Extra caution if you are…'), findsNothing);
    });

    testWidgets(
      'populations + no user profile → bullet list, no "already covered" line',
      (tester) async {
        // 2026-05-05 — content revision: comma-joined "Extra caution
        // for: A, B" replaced with bulleted list under "Extra caution
        // if you are…". The "already covered" parenthetical was
        // dropped (silence in ReviewBeforeUseCard is the signal).
        await _pump(
          tester,
          warnings: [
            _w(populationWarnings: const ['Pregnancy', 'Children']),
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text('Extra caution if you are…'), findsOneWidget);
        // Each population renders as a RichText bullet — find via
        // plain-text walk on the rendered span.
        expect(_richTextContaining('Pregnancy'), findsOneWidget);
        expect(_richTextContaining('Children'), findsOneWidget);
        expect(find.textContaining('already covered'), findsNothing);
      },
    );

    testWidgets(
      'population matches user condition → only the non-match remains',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _w(
              populationWarnings: const [
                'Pregnancy',
                'Children — immature gut barrier',
              ],
            ),
          ],
          userConditions: {'pregnancy'},
        );
        await tester.pumpAndSettle();

        // Non-matching population renders.
        expect(_richTextContaining('Children'), findsOneWidget);
        // Matching population dropped from main list.
        expect(_richTextContaining('Pregnancy'), findsNothing);
        // No "already covered" line.
        expect(find.textContaining('already covered'), findsNothing);
      },
    );

    testWidgets('all populations match user → section hides entirely', (
      tester,
    ) async {
      // 2026-05-05 — when every population is in the user's profile,
      // the section hides instead of rendering a confusing
      // "(already covered for ...)" parenthetical.
      await _pump(
        tester,
        warnings: [
          _w(populationWarnings: const ['Pregnancy', 'Diabetic patients']),
        ],
        userConditions: {'pregnancy', 'diabetes'},
      );
      await tester.pumpAndSettle();

      expect(find.text('Extra caution if you are…'), findsNothing);
      expect(find.textContaining('Extra caution for'), findsNothing);
      expect(find.textContaining('already covered'), findsNothing);
    });

    testWidgets('age bracket dedupes a population from the main list', (
      tester,
    ) async {
      await _pump(
        tester,
        warnings: [
          _w(populationWarnings: const ['Children should avoid']),
        ],
        ageBracket: 'under_18',
      );
      await tester.pumpAndSettle();

      // Whole section hides (only population was deduped).
      expect(find.text('Extra caution if you are…'), findsNothing);
    });
  });
}
