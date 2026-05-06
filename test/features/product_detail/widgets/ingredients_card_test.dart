// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16 +
// 2026-04-30 follow-up (pipeline-driven severity + functional roles).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/data/functional_roles_vocab.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredients_card.dart';

Map<String, dynamic> _ing({
  required String name,
  String severity = '',
  List<String> roles = const [],
}) {
  return {
    'name': name,
    'harmful_severity': severity,
    'functional_roles': roles,
  };
}

Future<void> _pump(
  WidgetTester tester, {
  Widget? activeContent,
  required List<Map<String, dynamic>> inactiveIngredients,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: IngredientsCard(
              activeContent: activeContent,
              inactiveIngredients: inactiveIngredients,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    // Stub the vocab so modal tests don't need the asset bundle.
    debugSetFunctionalRolesVocabForTesting({
      'lubricant': const FunctionalRole(
        id: 'lubricant',
        name: 'Lubricant',
        notes: 'Keeps powder from sticking during pressing.',
        regulatoryReferences: [
          RegulatoryReference(jurisdiction: 'FDA', code: '21 CFR 170.3(o)(18)'),
        ],
        examples: ['magnesium stearate', 'stearic acid'],
      ),
      'anti_caking_agent': const FunctionalRole(
        id: 'anti_caking_agent',
        name: 'Anti-caking agent',
        notes: 'Prevents clumping in powdered formulations.',
        regulatoryReferences: [],
        examples: ['silicon dioxide'],
      ),
    });
  });

  tearDown(() {
    debugSetFunctionalRolesVocabForTesting(null);
  });

  group('inactiveColorRank — pipeline-driven severity', () {
    test('"high" → red', () {
      expect(inactiveColorRank({'harmful_severity': 'high'}), InactiveTone.red);
    });

    test('"moderate" → orange', () {
      expect(
        inactiveColorRank({'harmful_severity': 'moderate'}),
        InactiveTone.orange,
      );
    });

    test('"low" → yellow', () {
      expect(
        inactiveColorRank({'harmful_severity': 'low'}),
        InactiveTone.yellow,
      );
    });

    test('empty string → green', () {
      expect(inactiveColorRank({'harmful_severity': ''}), InactiveTone.green);
    });

    test('"none" → green (defensive — pipeline emits "" not "none")', () {
      expect(
        inactiveColorRank({'harmful_severity': 'none'}),
        InactiveTone.green,
      );
    });

    test('missing severity_level key → green', () {
      expect(inactiveColorRank({'name': 'X'}), InactiveTone.green);
    });

    test('case-insensitive match', () {
      expect(inactiveColorRank({'harmful_severity': 'HIGH'}), InactiveTone.red);
      expect(
        inactiveColorRank({'harmful_severity': '  Moderate  '}),
        InactiveTone.orange,
      );
    });

    test('non-string severity → green (defensive)', () {
      expect(inactiveColorRank({'harmful_severity': 5}), InactiveTone.green);
    });
  });

  group('IngredientsCard — render', () {
    testWidgets('both empty → SizedBox.shrink', (tester) async {
      await _pump(tester, inactiveIngredients: const []);
      await tester.pumpAndSettle();
      expect(find.text('Other ingredients'), findsNothing);
    });

    testWidgets('renders header + count badge', (tester) async {
      await _pump(
        tester,
        inactiveIngredients: [
          _ing(name: 'Gelatin'),
          _ing(name: 'Silica'),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Other ingredients'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('active + inactive → divider rendered between', (tester) async {
      await _pump(
        tester,
        activeContent: const Text('ACTIVE_BLOCK'),
        inactiveIngredients: [_ing(name: 'Gelatin')],
      );
      await tester.pumpAndSettle();
      expect(find.text('ACTIVE_BLOCK'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('≤ 5 inactives → auto-expanded', (tester) async {
      await _pump(
        tester,
        inactiveIngredients: [
          _ing(name: 'Gelatin'),
          _ing(name: 'Silica'),
          _ing(name: 'Cellulose'),
          _ing(name: 'Magnesium stearate'),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Gelatin'), findsOneWidget);
      expect(find.text('Magnesium stearate'), findsOneWidget);
    });

    testWidgets('> 5 inactives → collapsed by default; tap expands', (
      tester,
    ) async {
      final names = List.generate(8, (i) => _ing(name: 'Ingredient ${i + 1}'));
      await _pump(tester, inactiveIngredients: names);
      await tester.pumpAndSettle();

      // Pre-expand: rows hidden.
      expect(find.text('Ingredient 1'), findsNothing);

      // Tap header → expand.
      await tester.tap(find.text('Other ingredients'));
      await tester.pumpAndSettle();
      expect(find.text('Ingredient 1'), findsOneWidget);
      expect(find.text('Ingredient 8'), findsOneWidget);
    });
  });

  group('Tap modal — vocab-driven', () {
    testWidgets(
      'tap row with functional_roles → opens sheet w/ role name + notes',
      (tester) async {
        await _pump(
          tester,
          inactiveIngredients: [
            _ing(
              name: 'Magnesium Stearate',
              roles: const ['lubricant', 'anti_caking_agent'],
            ),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Magnesium Stearate'));
        await tester.pumpAndSettle();

        // Sheet header — ingredient name appears once in row, once
        // in modal.
        expect(find.text('Magnesium Stearate'), findsNWidgets(2));
        // T4D — inactive row's role helper line comma-joins matched
        // role names ("Lubricant, Anti-caking agent"). Modal renders
        // each role's name as its own section heading.
        expect(find.text('Lubricant, Anti-caking agent'), findsOneWidget);
        expect(find.text('Lubricant'), findsOneWidget);
        expect(
          find.text('Keeps powder from sticking during pressing.'),
          findsOneWidget,
        );
        expect(find.text('Anti-caking agent'), findsOneWidget);
      },
    );

    testWidgets('tap row with empty functional_roles → generic fallback copy', (
      tester,
    ) async {
      await _pump(
        tester,
        inactiveIngredients: [_ing(name: 'Mystery Excipient', roles: const [])],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mystery Excipient'));
      await tester.pumpAndSettle();

      expect(
        find.text('Inactive ingredient — added during manufacturing.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'tap row with unknown role IDs → generic fallback (vocab miss)',
      (tester) async {
        await _pump(
          tester,
          inactiveIngredients: [
            _ing(name: 'Edge Case', roles: const ['not_in_vocab']),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Edge Case'));
        await tester.pumpAndSettle();

        expect(
          find.text('Inactive ingredient — added during manufacturing.'),
          findsOneWidget,
        );
      },
    );
  });
}
