import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/product_list_item.dart';
import 'package:pharmaguide/data/database/core_database.dart';

ProductsCoreData _product({required String verdict, double? mappedCoverage}) {
  return ProductsCoreData(
    dsldId: 'P1',
    productName: 'Test Supplement',
    brandName: 'Test Brand',
    verdict: verdict,
    score100Equivalent: 92,
    mappedCoverage: mappedCoverage,
    exportVersion: 'test',
    exportedAt: '2026-05-21T00:00:00Z',
  );
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('verdictForMappedCoverage', () {
    test('does not display positive verdicts when mapped coverage is low', () {
      expect(verdictForMappedCoverage('SAFE', 0.29), 'NOT_SCORED');
      expect(verdictForMappedCoverage('GOOD', 0.0), 'NOT_SCORED');
      expect(verdictForMappedCoverage('RECOMMENDED', null), 'NOT_SCORED');
    });

    test('keeps caution and blocked verdicts even with low coverage', () {
      expect(verdictForMappedCoverage('CAUTION', 0.1), 'CAUTION');
      expect(verdictForMappedCoverage('BLOCKED', 0.1), 'BLOCKED');
    });
  });

  group('scoreForMappedCoverage', () {
    test('suppresses scores below the mapped coverage confidence floor', () {
      expect(scoreForMappedCoverage(92, 0.29), isNull);
      expect(scoreForMappedCoverage(92, null), isNull);
    });

    test('keeps scores at or above the mapped coverage confidence floor', () {
      expect(scoreForMappedCoverage(92, 0.3), 92);
      expect(scoreForMappedCoverage(null, 0.9), isNull);
    });
  });

  testWidgets('list item does not show SAFE when mapped coverage is low', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 420,
          child: ProductListItem(product: _product(verdict: 'SAFE')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SAFE'), findsNothing);
    expect(find.text('NOT SCORED'), findsOneWidget);
    expect(find.text('92'), findsNothing);
  });

  testWidgets('grid item does not show SAFE when mapped coverage is low', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 220,
          height: 220,
          child: ProductGridItem(product: _product(verdict: 'SAFE')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SAFE'), findsNothing);
    expect(find.text('NOT SCORED'), findsOneWidget);
    expect(find.text('92'), findsNothing);
  });
}
