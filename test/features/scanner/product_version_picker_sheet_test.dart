import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/scanner/product_version_picker_sheet.dart';
import 'package:pharmaguide/features/scanner/product_version_label_sheet.dart';

ProductsCoreData _product(
  String id,
  String name, {
  required double score,
  required double quantity,
  int? servingsPerContainer,
  String? keyIngredientTags,
}) => ProductsCoreData(
  dsldId: id,
  productName: name,
  brandName: 'Example Brand',
  formFactor: 'softgel',
  netContentsQuantity: quantity,
  netContentsUnit: 'Softgels',
  qualityScoreV4100: score,
  servingsPerContainer: servingsPerContainer,
  keyIngredientTags: keyIngredientTags,
  exportVersion: 'test',
  exportedAt: '2026-08-19T00:00:00Z',
);

void main() {
  testWidgets('previews preserve calcium and other-ingredient differences', (
    tester,
  ) async {
    final candidates = [
      _product('a', 'B1', score: 77, quantity: 100),
      _product('b', 'B1', score: 75, quantity: 100),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          detailBlobProvider('a').overrideWith(
            (ref) async => {
              'display_ingredients': [
                {
                  'label_display_name': 'Thiamine',
                  'label_display_form': 'Thiamine Mononitrate',
                  'exact_dose_text': '100 mg',
                  'dailyValue': 8333,
                  'display_disposition': 'scored',
                },
                {
                  'label_display_name': 'Calcium',
                  'exact_dose_text': '34 mg',
                  'dailyValue': 3,
                  'display_disposition': 'scored',
                },
                {
                  'label_display_name': 'Rapeseed Lecithin',
                  'display_disposition': 'other_ingredient',
                },
              ],
            },
          ),
          detailBlobProvider('b').overrideWith(
            (ref) async => {
              'display_ingredients': [
                {
                  'label_display_name': 'Thiamine',
                  'exact_dose_text': '100 mg',
                  'dailyValue': 6667,
                  'display_disposition': 'scored',
                },
                {
                  'label_display_name': 'Soy Lecithin',
                  'display_disposition': 'other_ingredient',
                },
              ],
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ProductVersionPickerSheet(candidates: candidates),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Calcium · 34 mg · 3% DV'), findsOneWidget);
    expect(find.textContaining('Thiamine Mononitrate'), findsOneWidget);
    expect(
      find.text('Other ingredients to compare: Soy Lecithin'),
      findsOneWidget,
    );
    expect(
      find.text('Other ingredients to compare: Rapeseed Lecithin'),
      findsOneWidget,
    );
    expect(find.textContaining('75'), findsNothing);
    expect(find.textContaining('77'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-name labels show printed dose and DV before selection', (
    tester,
  ) async {
    final candidates = [
      _product('old', 'B12', score: 91, quantity: 60),
      _product('new', 'B12', score: 91, quantity: 60),
    ];
    Map<String, dynamic> label(int dv) => {
      'display_ingredients': [
        {
          'label_display_name': 'Vitamin B12',
          'exact_dose_text': '5,000 mcg',
          'dailyValue': dv,
          'label_order': 0,
          'nested_depth': 0,
          'raw_source_path': 'ingredientRows[0]',
          'display_disposition': 'scored',
          'label_display_form': 'Cyanocobalamin',
        },
      ],
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          detailBlobProvider('old').overrideWith((ref) async => label(83333)),
          detailBlobProvider('new').overrideWith((ref) async => label(208333)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ProductVersionPickerSheet(candidates: candidates),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('83333% DV'), findsOneWidget);
    expect(find.textContaining('208333% DV'), findsOneWidget);
    expect(find.textContaining('5,000 mcg'), findsNWidgets(2));
    expect(find.textContaining('Cyanocobalamin'), findsNWidgets(2));
    expect(find.text('This matches my label'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nutrition-only editions use the canonical nutrition renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          detailBlobProvider('protein').overrideWith(
            (ref) async => {
              'display_ingredients': [
                {
                  'label_display_name': 'Protein',
                  'exact_dose_text': '20 g',
                  'display_type': 'nutrition_fact',
                  'label_order': 0,
                  'nested_depth': 0,
                  'raw_source_path': 'ingredientRows[0]',
                  'display_disposition': 'label_context',
                },
              ],
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showProductVersionLabelSheet(
                  context,
                  product: _product(
                    'protein',
                    'Protein powder',
                    score: 80,
                    quantity: 30,
                  ),
                ),
                child: const Text('Open label'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open label'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'This matches my label'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Nutrition Facts'));
    await tester.pumpAndSettle();
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('20 g'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('explains the collision using bottle details, not scores', (
    tester,
  ) async {
    final candidates = [
      _product('one', 'Omega 3 — 60 count', score: 95, quantity: 60),
      _product('two', 'Omega 3 — 120 count', score: 40, quantity: 120),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ProductVersionPickerSheet(candidates: candidates),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Which bottle matches yours?'), findsOneWidget);
    expect(find.textContaining('more than one label'), findsOneWidget);
    expect(find.textContaining('60 Softgels'), findsOneWidget);
    expect(find.textContaining('120 Softgels'), findsOneWidget);
    expect(find.textContaining('95'), findsNothing);
    expect(find.textContaining('40'), findsNothing);
  });

  testWidgets('package summary never presents internal tags as label facts', (
    tester,
  ) async {
    // Same barcode, same bottle art, different label. The picture cannot tell
    // these apart; the panel can.
    final candidates = [
      _product(
        '178392',
        'Prenatal',
        score: 60,
        quantity: 30,
        servingsPerContainer: 30,
        keyIngredientTags: '["folic_acid","iron","dha"]',
      ),
      _product(
        'PG_SUB_1',
        'Prenatal',
        score: 70,
        quantity: 30,
        servingsPerContainer: 60,
        keyIngredientTags: 'Folate, Iron, Choline',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ProductVersionPickerSheet(candidates: candidates),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('30 servings'), findsOneWidget);
    expect(find.textContaining('60 servings'), findsOneWidget);
    expect(find.textContaining('folic_acid'), findsNothing);
    expect(find.textContaining('Folate'), findsNothing);
  });

  testWidgets('none of these is an answer, not a dismissal', (tester) async {
    final candidates = [
      _product('one', 'Omega 3 — 60 count', score: 95, quantity: 60),
      _product('two', 'Omega 3 — 120 count', score: 40, quantity: 120),
    ];
    ProductVersionChoice? choice;
    var opened = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  opened = true;
                  choice = await showProductVersionPickerSheet(
                    context,
                    candidates: candidates,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);

    expect(find.text('My bottle has a different label.'), findsOneWidget);
    expect(find.textContaining("we'll add it"), findsNothing);
    await tester.ensureVisible(find.text('None of these match'));
    await tester.tap(find.text('None of these match'));
    await tester.pumpAndSettle();

    expect(choice, isA<ProductVersionUnmatched>());
  });

  testWidgets('picking a bottle answers with that product', (tester) async {
    final candidates = [
      _product('one', 'Omega 3 — 60 count', score: 95, quantity: 60),
      _product('two', 'Omega 3 — 120 count', score: 40, quantity: 120),
    ];
    ProductVersionChoice? choice;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          detailBlobProvider('two').overrideWith(
            (ref) async => {
              'display_ingredients': [
                {
                  'label_display_name': 'Fish oil',
                  'label_order': 0,
                  'nested_depth': 0,
                  'raw_source_path': 'ingredientRows[0]',
                  'display_disposition': 'scored',
                  'form_display_state': 'known',
                },
              ],
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async =>
                    choice = await showProductVersionPickerSheet(
                      context,
                      candidates: candidates,
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Omega 3 — 120 count'));
    await tester.pumpAndSettle();

    expect(choice, isNull);
    expect(find.text('Fish oil'), findsNWidgets(2));
    expect(find.text('Match the Facts panel'), findsOneWidget);
    await tester.tap(find.text('This matches my label'));
    await tester.pumpAndSettle();

    expect(choice, isA<ProductVersionSelected>());
    expect((choice! as ProductVersionSelected).product.dsldId, 'two');
  });

  testWidgets('unavailable label cannot confirm a version', (tester) async {
    final candidates = [
      _product('one', 'First label', score: 95, quantity: 60),
      _product('two', 'Second label', score: 40, quantity: 60),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          detailBlobProvider('one').overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ProductVersionPickerSheet(candidates: candidates),
          ),
        ),
      ),
    );
    await tester.tap(find.text('First label'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'This matches my label'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Don’t guess'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
