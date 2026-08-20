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
}) => ProductsCoreData(
  dsldId: id,
  productName: name,
  brandName: 'Example Brand',
  formFactor: 'softgel',
  netContentsQuantity: quantity,
  netContentsUnit: 'Softgels',
  qualityScoreV4100: score,
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
}
