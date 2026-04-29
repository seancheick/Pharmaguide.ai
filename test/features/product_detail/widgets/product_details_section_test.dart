// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.11.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/product_details_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? servingSize,
  int? servingsPerContainer,
  String? manufacturer,
  double? netContentsQuantity,
  String? netContentsUnit,
  String? formFactor,
  String? country,
  Size? screenSize,
}) {
  if (screenSize != null) {
    tester.view.physicalSize = screenSize * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProductDetailsSection(
          servingSize: servingSize,
          servingsPerContainer: servingsPerContainer,
          manufacturer: manufacturer,
          netContentsQuantity: netContentsQuantity,
          netContentsUnit: netContentsUnit,
          formFactor: formFactor,
          country: country,
        ),
      ),
    ),
  );
}

void main() {
  group('formatNetContents — pure logic', () {
    test('whole-number qty drops the decimal', () {
      expect(formatNetContents(60.0, 'capsules'), '60 capsules');
    });

    test('fractional qty keeps the decimal', () {
      expect(formatNetContents(1.5, 'kg'), '1.5 kg');
    });

    test('null qty → null', () {
      expect(formatNetContents(null, 'capsules'), isNull);
    });

    test('null unit → null', () {
      expect(formatNetContents(60.0, null), isNull);
    });

    test('blank unit → null (defensive — pipeline shouldn\'t emit empties)',
        () {
      expect(formatNetContents(60.0, '   '), isNull);
    });

    test('unit whitespace trimmed', () {
      expect(formatNetContents(60.0, '  capsules  '), '60 capsules');
    });
  });

  group('buildProductDetailFields — pure logic', () {
    test('all six fields present → 6 entries in display order', () {
      final f = buildProductDetailFields(
        servingSize: '2 capsules daily',
        servingsPerContainer: 60,
        manufacturer: "Nature's Best Inc.",
        netContentsQuantity: 60.0,
        netContentsUnit: 'capsules',
        formFactor: 'capsule',
        country: 'USA',
      );
      expect(f.map((e) => e.label).toList(), [
        'Serving size',
        'Servings per container',
        'Net contents',
        'Form',
        'Manufacturer',
        'Country',
      ]);
      expect(f[2].value, '60 capsules');
      expect(f[3].value, 'Capsule'); // humanized
      expect(f[5].value, 'USA');
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
      // and 0 servings is a degenerate sentinel ("we don't know").
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

    test('form factor humanized — "softgel" → "Softgel"', () {
      final f = buildProductDetailFields(
        servingSize: null,
        servingsPerContainer: null,
        manufacturer: null,
        formFactor: 'softgel',
      );
      expect(f[0].label, 'Form');
      expect(f[0].value, 'Softgel');
    });

    test('net contents skipped when only quantity present', () {
      final f = buildProductDetailFields(
        servingSize: null,
        servingsPerContainer: null,
        manufacturer: null,
        netContentsQuantity: 60.0,
        netContentsUnit: null,
      );
      expect(f, isEmpty);
    });

    test('country whitespace trimmed', () {
      final f = buildProductDetailFields(
        servingSize: null,
        servingsPerContainer: null,
        manufacturer: null,
        country: '  USA  ',
      );
      expect(f[0].value, 'USA');
    });
  });

  group('ProductDetailsSection — render', () {
    testWidgets('all nulls → section hides entirely', (tester) async {
      await _pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Product details'), findsNothing);
    });

    testWidgets(
      'all six fields present → header renders, body collapsed by default',
      (tester) async {
        await _pump(
          tester,
          servingSize: '2 capsules daily',
          servingsPerContainer: 60,
          manufacturer: "Nature's Best Inc.",
          netContentsQuantity: 60.0,
          netContentsUnit: 'capsules',
          formFactor: 'capsule',
          country: 'USA',
        );
        await tester.pumpAndSettle();
        expect(find.text('Product details'), findsOneWidget);
        // None of the field rows visible until tap.
        for (final label in const [
          'Serving size',
          'Servings per container',
          'Net contents',
          'Form',
          'Manufacturer',
          'Country',
        ]) {
          expect(find.text(label), findsNothing,
              reason: '"$label" should be hidden when collapsed');
        }
      },
    );

    testWidgets('tap header → expands and reveals all six fields',
        (tester) async {
      await _pump(
        tester,
        servingSize: '2 capsules daily',
        servingsPerContainer: 60,
        manufacturer: "Nature's Best Inc.",
        netContentsQuantity: 60.0,
        netContentsUnit: 'capsules',
        formFactor: 'capsule',
        country: 'USA',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Product details'));
      await tester.pumpAndSettle();

      expect(find.text('Serving size'), findsOneWidget);
      expect(find.text('2 capsules daily'), findsOneWidget);
      expect(find.text('Servings per container'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Net contents'), findsOneWidget);
      expect(find.text('60 capsules'), findsOneWidget);
      expect(find.text('Form'), findsOneWidget);
      expect(find.text('Capsule'), findsOneWidget);
      expect(find.text('Manufacturer'), findsOneWidget);
      expect(find.text("Nature's Best Inc."), findsOneWidget);
      expect(find.text('Country'), findsOneWidget);
      expect(find.text('USA'), findsOneWidget);
    });

    testWidgets('tap a second time → collapses back', (tester) async {
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
      expect(find.text('Country'), findsNothing);
      expect(find.text('Net contents'), findsNothing);
      expect(find.text('Form'), findsNothing);
    });

    testWidgets(
      'narrow screen (iPhone SE 320pt) → values still render after expand',
      (tester) async {
        // Below the 380pt breakpoint each row stacks label-above-value
        // instead of a side-by-side label/value split. The fixed 140pt
        // label column would otherwise squeeze long values like
        // "Nature's Best Incorporated".
        await _pump(
          tester,
          servingSize: '2 capsules daily',
          servingsPerContainer: 60,
          manufacturer: "Nature's Best Incorporated",
          screenSize: const Size(320, 800),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Product details'));
        await tester.pumpAndSettle();

        expect(find.text('Serving size'), findsOneWidget);
        expect(find.text('2 capsules daily'), findsOneWidget);
        expect(find.text("Nature's Best Incorporated"), findsOneWidget);
      },
    );

    testWidgets('wide screen → values still render after expand',
        (tester) async {
      // Sanity that the side-by-side path still works post-refactor.
      await _pump(
        tester,
        servingSize: '2 capsules daily',
        servingsPerContainer: 60,
        manufacturer: "Nature's Best Inc.",
        screenSize: const Size(390, 800),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Product details'));
      await tester.pumpAndSettle();

      expect(find.text('Serving size'), findsOneWidget);
      expect(find.text("Nature's Best Inc."), findsOneWidget);
    });
  });
}
