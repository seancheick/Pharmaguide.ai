import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/scanner/product_version_picker_sheet.dart';

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

  testWidgets('separates two editions by what is on the Facts panel', (
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
        keyIngredientTags: 'Folic Acid, Iron, DHA',
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
    expect(find.textContaining('Folic Acid'), findsOneWidget);
    expect(find.textContaining('Folate'), findsOneWidget);
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
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => choice =
                    await showProductVersionPickerSheet(
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

    expect(choice, isA<ProductVersionSelected>());
    expect((choice! as ProductVersionSelected).product.dsldId, 'two');
  });
}
