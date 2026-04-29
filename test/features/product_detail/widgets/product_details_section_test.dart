// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.11.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/product_details_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? servingSize,
  int? servingsPerContainer,
  String? manufacturer,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProductDetailsSection(
          servingSize: servingSize,
          servingsPerContainer: servingsPerContainer,
          manufacturer: manufacturer,
        ),
      ),
    ),
  );
}

void main() {
  group('buildProductDetailFields — pure logic', () {
    test('all three fields present → 3 entries in display order', () {
      final f = buildProductDetailFields(
        servingSize: '2 capsules daily',
        servingsPerContainer: 60,
        manufacturer: "Nature's Best Inc.",
      );
      expect(f.map((e) => e.label).toList(), [
        'Serving size',
        'Servings per container',
        'Manufacturer',
      ]);
      expect(f[0].value, '2 capsules daily');
      expect(f[1].value, '60');
      expect(f[2].value, "Nature's Best Inc.");
    });

    test('all nulls → empty', () {
      expect(
        buildProductDetailFields(
          servingSize: null,
          servingsPerContainer: null,
          manufacturer: null,
        ),
        isEmpty,
      );
    });

    test('blank serving + manufacturer dropped, 0 servings dropped', () {
      // Defensive: pipeline can ship empty strings for missing data
      // and 0 servings is a degenerate sentinel ("we don't know") —
      // none of these should render.
      final f = buildProductDetailFields(
        servingSize: '   ',
        servingsPerContainer: 0,
        manufacturer: '',
      );
      expect(f, isEmpty);
    });

    test('only one field present → just that field renders', () {
      final f = buildProductDetailFields(
        servingSize: null,
        servingsPerContainer: 30,
        manufacturer: null,
      );
      expect(f.length, 1);
      expect(f[0].label, 'Servings per container');
      expect(f[0].value, '30');
    });

    test('serving size whitespace trimmed', () {
      final f = buildProductDetailFields(
        servingSize: '  1 tablet  ',
        servingsPerContainer: null,
        manufacturer: null,
      );
      expect(f[0].value, '1 tablet');
    });
  });

  group('ProductDetailsSection — render', () {
    testWidgets('all nulls → section hides entirely', (tester) async {
      await _pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Product details'), findsNothing);
    });

    testWidgets('renders 3 fields when all present, collapsed by default',
        (tester) async {
      await _pump(
        tester,
        servingSize: '2 capsules daily',
        servingsPerContainer: 60,
        manufacturer: "Nature's Best Inc.",
      );
      await tester.pumpAndSettle();

      // Header always renders.
      expect(find.text('Product details'), findsOneWidget);

      // Field rows are HIDDEN by default (collapsed) — no field
      // labels in the visible widget tree until tap.
      expect(find.text('Serving size'), findsNothing);
      expect(find.text('Servings per container'), findsNothing);
      expect(find.text('Manufacturer'), findsNothing);
      expect(find.text("Nature's Best Inc."), findsNothing);
    });

    testWidgets('tap header → expands and reveals field rows',
        (tester) async {
      await _pump(
        tester,
        servingSize: '2 capsules daily',
        servingsPerContainer: 60,
        manufacturer: "Nature's Best Inc.",
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Product details'));
      await tester.pumpAndSettle();

      expect(find.text('Serving size'), findsOneWidget);
      expect(find.text('2 capsules daily'), findsOneWidget);
      expect(find.text('Servings per container'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Manufacturer'), findsOneWidget);
      expect(find.text("Nature's Best Inc."), findsOneWidget);
    });

    testWidgets('tap a second time → collapses back', (tester) async {
      await _pump(
        tester,
        servingSize: '2 capsules daily',
        servingsPerContainer: 60,
        manufacturer: "Nature's Best Inc.",
      );
      await tester.pumpAndSettle();

      // Expand.
      await tester.tap(find.text('Product details'));
      await tester.pumpAndSettle();
      expect(find.text('Serving size'), findsOneWidget);

      // Collapse.
      await tester.tap(find.text('Product details'));
      await tester.pumpAndSettle();
      expect(find.text('Serving size'), findsNothing);
    });

    testWidgets('partial data → renders only the present fields',
        (tester) async {
      await _pump(tester, servingSize: '1 scoop daily');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Product details'));
      await tester.pumpAndSettle();

      expect(find.text('Serving size'), findsOneWidget);
      expect(find.text('1 scoop daily'), findsOneWidget);
      // Other rows absent.
      expect(find.text('Servings per container'), findsNothing);
      expect(find.text('Manufacturer'), findsNothing);
    });
  });
}
