import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';

class _FakeCoreDatabase extends CoreDatabase {
  final ProductsCoreData product;

  _FakeCoreDatabase(this.product) : super.memory();

  @override
  Future<ProductsCoreData?> findById(String dsldId) async {
    return dsldId == product.dsldId ? product : null;
  }

  @override
  Future<List<ProductsCoreData>> findAlternatives(
    String category,
    double minScore, {
    String? excludeDsldId,
    int limit = 5,
  }) async {
    return <ProductsCoreData>[];
  }
}

void main() {
  late _FakeCoreDatabase coreDb;
  late UserDatabase userDb;

  setUp(() async {
    coreDb = _FakeCoreDatabase(
      const ProductsCoreData(
        dsldId: 'TEST_DETAIL_001',
        productName: 'Guided Vitamin D',
        productStatus: 'active',
        scoreQuality80: 72.5,
        score100Equivalent: 91.0,
        grade: 'A-',
        verdict: 'RECOMMENDED',
        mappedCoverage: 0.95,
        scoreIngredientQuality: 22.0,
        scoreSafetyPurity: 27.0,
        scoreEvidenceResearch: 18.0,
        scoreBrandTrust: 5.0,
        primaryCategory: 'single_nutrient',
        exportVersion: 'test',
        exportedAt: '2026-04-09T00:00:00Z',
      ),
    );
    userDb = UserDatabase.memory();
  });

  testWidgets('score education sheet describes the core product score accurately',
      (tester) async {
    await userDb.cacheDetail(
      'TEST_DETAIL_001',
      jsonEncode(<String, Object>{'warnings': <Object>[]}),
      null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
        child: const MaterialApp(
          home: ProductDetailScreen(dsldId: 'TEST_DETAIL_001'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guided Vitamin D'), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    Finder richTextContaining(String text) {
      return find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains(text),
        description: 'RichText containing "$text"',
      );
    }

    expect(find.textContaining('core product score'), findsOneWidget);
    expect(
      richTextContaining('Ingredient Quality  Up to 25 pts'),
      findsOneWidget,
    );
    expect(
      richTextContaining('Safety & Purity  Up to 30 pts'),
      findsOneWidget,
    );
    expect(
      richTextContaining('Evidence & Research  Up to 20 pts'),
      findsOneWidget,
    );
    expect(
      richTextContaining('Brand Trust  Up to 5 pts'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
