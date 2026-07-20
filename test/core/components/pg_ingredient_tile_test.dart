import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/components/pg_ingredients_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

Widget _wrap(PGActiveIngredient ingredient) => MaterialApp(
  home: Scaffold(body: PGActiveIngredientTile(ingredient: ingredient)),
);

Widget _wrapTiles(List<Widget> tiles) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: PGActiveIngredientsSection(tiles: tiles),
    ),
  ),
);

class _CountingIngredientTile extends PGActiveIngredientTile {
  final VoidCallback onBuild;

  const _CountingIngredientTile({
    required super.ingredient,
    required this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    onBuild();
    return super.build(context);
  }
}

void main() {
  testWidgets('preserves the form-label casing verbatim (never lowercased)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PGActiveIngredient(
          name: 'EPA',
          formLabel: 'as Ethyl Esters',
          formQuality: FormQuality.excellent,
          formDisplayState: PGIngredientFormDisplayState.assessed,
        ),
      ),
    );

    expect(find.text('as Ethyl Esters'), findsOneWidget);
    expect(find.text('as ethyl esters'), findsNothing);
  });

  testWidgets('form chip renders the explicit "{tier} form" label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PGActiveIngredient(
          name: 'Magnesium',
          formQuality: FormQuality.excellent,
          formDisplayState: PGIngredientFormDisplayState.assessed,
        ),
      ),
    );

    expect(find.text('Excellent form'), findsOneWidget);
  });

  testWidgets(
    'identity-review row shows the normalized review state and hides every '
    'form/dose/safety claim',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PGActiveIngredient(
            name: 'Marine Lipid Concentrate',
            identityNeedsReview: true,
            // Even if a stale typed model still carries claims, the tile must
            // suppress them all when the identity needs review.
            formLabel: 'as Ethyl Esters',
            dose: '660 mg',
            formQuality: FormQuality.excellent,
            doseCallOut: DoseCallOut.high,
            isSafetyConcern: true,
          ),
        ),
      );

      expect(find.text('Marine Lipid Concentrate'), findsOneWidget);
      expect(find.text('Data needs review'), findsOneWidget);
      expect(find.text('Identity needs review'), findsNothing);
      expect(find.text('Excellent form'), findsNothing);
      expect(find.text('High dose'), findsNothing);
      expect(find.text('Safety concern'), findsNothing);
      expect(find.text('as Ethyl Esters'), findsNothing);
      expect(find.text('660 mg'), findsNothing);
    },
  );

  testWidgets('renders each explicit non-quality form state without inventing '
      'a quality badge', (tester) async {
    const cases = <(PGIngredientFormDisplayState, String)>[
      (PGIngredientFormDisplayState.notDisclosed, 'Form not disclosed'),
      (
        PGIngredientFormDisplayState.listedNotAssessed,
        'Form listed · not yet assessed',
      ),
      (PGIngredientFormDisplayState.needsReview, 'Data needs review'),
    ];

    for (final (state, label) in cases) {
      await tester.pumpWidget(
        _wrap(
          PGActiveIngredient(
            name: 'Label ingredient',
            formLabel: state == PGIngredientFormDisplayState.listedNotAssessed
                ? 'as printed on label'
                : null,
            // A stale score must never leak through a non-assessed state.
            formQuality: FormQuality.excellent,
            formDisplayState: state,
          ),
        ),
      );

      expect(find.text(label), findsOneWidget);
      expect(find.text('Excellent form'), findsNothing);
    }
  });

  testWidgets(
    'not-applicable form state stays silent even with stale quality',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PGActiveIngredient(
            name: 'Gelatin',
            formQuality: FormQuality.excellent,
            formDisplayState: PGIngredientFormDisplayState.notApplicable,
          ),
        ),
      );

      expect(find.text('Excellent form'), findsNothing);
      expect(find.textContaining('Form '), findsNothing);
    },
  );

  testWidgets(
    'form status uses visible text and a supplementary color surface',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PGActiveIngredient(
            name: 'Fish Oil',
            formDisplayState: PGIngredientFormDisplayState.notDisclosed,
          ),
        ),
      );

      final statusText = find.text('Form not disclosed');
      expect(statusText, findsOneWidget);

      final statusContainer = find
          .ancestor(of: statusText, matching: find.byType(Container))
          .first;
      final decoration =
          tester.widget<Container>(statusContainer).decoration!
              as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.color, isNot(Colors.transparent));
    },
  );

  testWidgets('shows exact dose plus one parenthetical component on one row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PGActiveIngredient(
          name: 'Folate',
          dose: '665 mcg DFE',
          parentheticalDoseText: '400 mcg folic acid',
          formDisplayState: PGIngredientFormDisplayState.listedNotAssessed,
          formLabel: 'folic acid',
        ),
      ),
    );

    expect(find.text('Folate'), findsOneWidget);
    expect(find.text('665 mcg DFE'), findsOneWidget);
    expect(find.text('(400 mcg folic acid)'), findsOneWidget);
  });

  testWidgets('indents nested label rows according to source hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PGActiveIngredientTile(
                ingredient: PGActiveIngredient(name: 'Fish Oil'),
              ),
              PGActiveIngredientTile(
                ingredient: PGActiveIngredient(
                  name: 'EPA',
                  nestedDepth: 2,
                  parentLabel: 'Total Omega-3 Fatty Acids',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('EPA')).dx,
      greaterThan(tester.getTopLeft(find.text('Fish Oil')).dx),
    );
  });

  testWidgets(
    'semantics announce hierarchy, form state, and score participation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          const PGActiveIngredient(
            name: 'EPA',
            dose: '360 mg',
            nestedDepth: 2,
            parentLabel: 'Total Omega-3 Fatty Acids',
            scoreIncluded: true,
            formDisplayState: PGIngredientFormDisplayState.notDisclosed,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'EPA. Nested level 2 under Total Omega-3 Fatty Acids. 360 mg. '
          'Form not disclosed. Included in analysis.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('count badge counts logical ingredient rows, not headers or '
      'folded parenthetical lines', (tester) async {
    await tester.pumpWidget(
      _wrapTiles(const [
        Text('Proprietary blend'),
        PGActiveIngredientTile(
          ingredient: PGActiveIngredient(
            name: 'Folate',
            dose: '665 mcg DFE',
            parentheticalDoseText: '400 mcg folic acid',
          ),
        ),
      ]),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Folate'), findsOneWidget);
    expect(find.text('(400 mcg folic acid)'), findsOneWidget);
  });

  testWidgets('progress semantics count logical ingredients in a mixed raw '
      'chunk', (tester) async {
    final semantics = tester.ensureSemantics();
    final tiles = <Widget>[
      const Text('Blend header'),
      for (var index = 0; index < 25; index++)
        PGActiveIngredientTile(
          ingredient: PGActiveIngredient(name: 'Ingredient $index'),
        ),
    ];
    await tester.pumpWidget(_wrapTiles(tiles));

    expect(
      find.bySemanticsLabel('What the label lists, 25 ingredients'),
      findsOneWidget,
    );
    await tester.tap(find.text('What the label lists'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Show more label ingredients, 19 of 25 shown'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('large sections reveal bounded chunks in source order without '
      'an inner scrollable', (tester) async {
    final semantics = tester.ensureSemantics();
    final outerController = ScrollController();
    addTearDown(outerController.dispose);
    final builtRows = <int>{};
    final tiles = List<Widget>.generate(
      100,
      (index) => _CountingIngredientTile(
        ingredient: PGActiveIngredient(
          name: 'Ingredient $index',
          labelOrder: index,
        ),
        onBuild: () => builtRows.add(index),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: outerController,
            slivers: [
              SliverToBoxAdapter(
                child: PGActiveIngredientsSection(tiles: tiles),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('What the label lists'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('Ingredient 0'), findsNothing);
    final header = find.bySemanticsLabel(
      'What the label lists, 100 ingredients',
    );
    expect(header, findsOneWidget);
    expect(tester.widget<Semantics>(header).properties.onTap, isNotNull);

    await tester.tap(find.text('What the label lists'));
    await tester.pumpAndSettle();

    expect(find.byType(Scrollable), findsOneWidget);
    expect(builtRows, orderedEquals(List.generate(20, (index) => index)));
    expect(builtRows, isNot(contains(99)));
    expect(find.text('Ingredient 99'), findsNothing);

    final firstShowMore = find.bySemanticsLabel(
      'Show more label ingredients, 20 of 100 shown',
    );
    expect(firstShowMore, findsOneWidget);
    final showMoreProperties = tester
        .widget<Semantics>(firstShowMore)
        .properties;
    expect(showMoreProperties.button, isTrue);
    expect(showMoreProperties.onTap, isNotNull);
    expect(tester.getSize(firstShowMore).height, greaterThanOrEqualTo(44));
    expect(find.text('Show more'), findsOneWidget);

    showMoreProperties.onTap!();
    await tester.pumpAndSettle();
    expect(builtRows, orderedEquals(List.generate(40, (index) => index)));

    await tester.tap(find.text('What the label lists'));
    await tester.pumpAndSettle();
    expect(find.text('Ingredient 39'), findsNothing);
    await tester.tap(find.text('What the label lists'));
    await tester.pumpAndSettle();
    expect(find.text('Ingredient 39'), findsOneWidget);
    expect(find.text('Ingredient 40'), findsNothing);
    expect(
      find.bySemanticsLabel('Show more label ingredients, 40 of 100 shown'),
      findsOneWidget,
    );

    for (final shownCount in [40, 60, 80]) {
      final showMore = find.bySemanticsLabel(
        'Show more label ingredients, $shownCount of 100 shown',
      );
      expect(showMore, findsOneWidget);
      tester.widget<Semantics>(showMore).properties.onTap!();
      await tester.pumpAndSettle();
    }

    expect(builtRows, contains(99));
    expect(find.text('Ingredient 99'), findsOneWidget);
    expect(find.text('Show more'), findsNothing);
    expect(builtRows, orderedEquals(List.generate(100, (index) => index)));
    expect(find.byType(Scrollable), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(outerController.offset, greaterThan(0));
    semantics.dispose();
  });

  testWidgets(
    'Other ingredients header exposes disclosure semantics and a 44 point target',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGIngredientsCard(
              activeContent: null,
              inactiveIngredients: [
                PGInactiveIngredient(name: 'Gelatin', tone: InactiveTone.green),
              ],
            ),
          ),
        ),
      );

      final header = find.bySemanticsLabel('Other ingredients, 1 ingredient');
      expect(header, findsOneWidget);
      final properties = tester.widget<Semantics>(header).properties;
      expect(properties.button, isTrue);
      expect(properties.expanded, isTrue);
      expect(properties.onTap, isNotNull);
      expect(tester.getSize(header).height, greaterThanOrEqualTo(44));
      expect(find.text('Gelatin'), findsOneWidget);

      properties.onTap!();
      await tester.pumpAndSettle();

      expect(tester.widget<Semantics>(header).properties.expanded, isFalse);
      expect(find.text('Gelatin'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('both ingredient headers reflow at narrow width and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGIngredientsCard(
              activeContent: PGActiveIngredientsSection(
                tiles: [
                  PGActiveIngredientTile(
                    ingredient: PGActiveIngredient(name: 'Fish Oil'),
                  ),
                ],
              ),
              inactiveIngredients: [
                PGInactiveIngredient(name: 'Gelatin', tone: InactiveTone.green),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.bySemanticsLabel('What the label lists, 1 ingredient'))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(find.bySemanticsLabel('Other ingredients, 1 ingredient'))
          .height,
      greaterThanOrEqualTo(44),
    );
  });
}
