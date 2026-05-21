import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/search/search_screen.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';

class _FakeCoreDatabase extends CoreDatabase {
  final List<ProductsCoreData> products;

  _FakeCoreDatabase(this.products) : super.memory();

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());

  @override
  Future<List<ProductsCoreData>> searchProducts(
    String query, {
    int limit = 50,
  }) async {
    if (query.trim().isEmpty) return const [];
    return products.take(limit).toList();
  }
}

class _DeferredSearchCoreDatabase extends _FakeCoreDatabase {
  final Completer<List<ProductsCoreData>> completer;

  _DeferredSearchCoreDatabase(super.products, this.completer);

  @override
  Future<List<ProductsCoreData>> searchProducts(
    String query, {
    int limit = 50,
  }) {
    return completer.future;
  }
}

class _DeferredCategoryCoreDatabase extends _FakeCoreDatabase {
  final Completer<List<ProductsCoreData>> categoryCompleter;

  _DeferredCategoryCoreDatabase(super.products, this.categoryCompleter);

  @override
  Future<List<ProductsCoreData>> filterProducts({
    String? category,
    bool? omega3,
    bool? probiotics,
    bool? collagen,
    bool? adaptogens,
    bool? nootropics,
    bool? vegan,
    bool? glutenFree,
    bool? organic,
    bool? diabetesFriendly,
    bool? hypertensionFriendly,
    String? sortBy,
    int limit = 50,
  }) {
    return categoryCompleter.future;
  }
}

class _ThrowingCategoryCoreDatabase extends _FakeCoreDatabase {
  _ThrowingCategoryCoreDatabase() : super(const []);

  @override
  Future<List<ProductsCoreData>> filterProducts({
    String? category,
    bool? omega3,
    bool? probiotics,
    bool? collagen,
    bool? adaptogens,
    bool? nootropics,
    bool? vegan,
    bool? glutenFree,
    bool? organic,
    bool? diabetesFriendly,
    bool? hypertensionFriendly,
    String? sortBy,
    int limit = 50,
  }) async {
    throw Exception('category load failed');
  }
}

class _FakeRecentSearchesService extends RecentSearchesService {
  final List<String> _searches = [];

  @override
  Future<List<String>> getRecent() async => List<String>.from(_searches);

  @override
  Future<void> addSearch(String query) async {
    if (!_searches.contains(query)) _searches.insert(0, query);
  }

  @override
  Future<void> removeSearch(String query) async {
    _searches.remove(query);
  }

  @override
  Future<void> clearAll() async {
    _searches.clear();
  }
}

void main() {
  Widget buildTestWidget({
    List<Override> overrides = const [],
    String? initialCategory,
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: SearchScreen(initialCategory: initialCategory)),
    );
  }

  ProductsCoreData product({
    required String id,
    required String name,
    String? brand,
    String? verdict = 'SAFE',
    double? score = 80,
    double? coverage = 0.8,
    int? tested = 0,
  }) {
    return ProductsCoreData(
      dsldId: id,
      productName: name,
      brandName: brand,
      verdict: verdict,
      score100Equivalent: score,
      mappedCoverage: coverage,
      hasThirdPartyTesting: tested,
      exportVersion: 'test',
      exportedAt: '2026-04-26T00:00:00Z',
    );
  }

  group('rankSearchResultsForDisplay', () {
    test('prioritizes exact product and brand matches over score', () {
      final ranked = rankSearchResultsForDisplay('magnesium', [
        product(id: 'A', name: 'Magnesium Complex', score: 98, coverage: 0.9),
        product(id: 'B', name: 'Daily Mineral', brand: 'Magnesium'),
        product(id: 'C', name: 'Magnesium', score: 40, coverage: 0.3),
      ]);

      expect(ranked.map((p) => p.dsldId), ['C', 'B', 'A']);
    });

    test(
      'keeps exact unsafe matches visible but demotes broad unsafe hits',
      () {
        final explicit = rankSearchResultsForDisplay('extreme pre', [
          product(
            id: 'A',
            name: 'Extreme Pre Safer Alternative',
            score: 90,
            coverage: 0.9,
          ),
          product(
            id: 'B',
            name: 'Extreme Pre',
            verdict: 'BLOCKED',
            score: 10,
            coverage: 0.9,
          ),
        ]);
        expect(explicit.map((p) => p.dsldId), ['B', 'A']);

        final broad = rankSearchResultsForDisplay('pre', [
          product(
            id: 'A',
            name: 'Pre Workout Tested',
            score: 70,
            coverage: 0.8,
            tested: 1,
          ),
          product(
            id: 'B',
            name: 'Pre Workout Sparse',
            score: 95,
            coverage: 0.2,
          ),
          product(
            id: 'C',
            name: 'Pre Workout Unsafe',
            verdict: 'BLOCKED',
            score: 99,
            coverage: 1.0,
          ),
        ]);

        expect(broad.map((p) => p.dsldId), ['A', 'B', 'C']);
      },
    );
  });

  group('SearchScreen', () {
    testWidgets('shows search input field', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows empty state when no query', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Search supplements'), findsOneWidget);
    });

    // SKIPPED: at the default 800×600 test viewport, the search
    // screen's recent-searches list overflows by 27px (RenderFlex
    // exception). The search field + clear-button logic is correct at
    // normal device sizes; this is a test-viewport issue. Fix by
    // setting `tester.view.physicalSize = Size(400, 2000)` in setUp.
    // Tech debt tracked in Sprint 18.

    testWidgets('shows clear button when text is entered', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsWidgets);
    });

    testWidgets('clear button clears text and returns to empty state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), 'vitamin');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Search supplements'), findsOneWidget);
    });

    testWidgets('clear button ignores stale in-flight search results', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final completer = Completer<List<ProductsCoreData>>();
      final db = _DeferredSearchCoreDatabase(const [], completer);
      addTearDown(db.close);

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            coreDatabaseProvider.overrideWithValue(db),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();

      completer.complete([
        const ProductsCoreData(
          dsldId: 'S1',
          productName: 'Late Magnesium Result',
          brandName: 'Brand A',
          verdict: 'SAFE',
          score100Equivalent: 91.0,
          mappedCoverage: 0.82,
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);
      await tester.pump();

      expect(find.text('Search supplements'), findsOneWidget);
      expect(find.text('Late Magnesium Result'), findsNothing);
    });

    testWidgets('typing ignores stale in-flight category results', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final categoryCompleter = Completer<List<ProductsCoreData>>();
      final db = _DeferredCategoryCoreDatabase([
        const ProductsCoreData(
          dsldId: 'S1',
          productName: 'Search Magnesium Result',
          brandName: 'Brand A',
          verdict: 'SAFE',
          score100Equivalent: 91.0,
          mappedCoverage: 0.82,
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ], categoryCompleter);
      addTearDown(db.close);

      await tester.pumpWidget(
        buildTestWidget(
          initialCategory: 'single_nutrient',
          overrides: [
            coreDatabaseProvider.overrideWithValue(db),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Search Magnesium Result'), findsOneWidget);

      categoryCompleter.complete([
        const ProductsCoreData(
          dsldId: 'C1',
          productName: 'Late Category Result',
          brandName: 'Brand C',
          verdict: 'SAFE',
          score100Equivalent: 95.0,
          mappedCoverage: 0.9,
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);
      await tester.pump();

      expect(find.text('Search Magnesium Result'), findsOneWidget);
      expect(find.text('Late Category Result'), findsNothing);
    });

    testWidgets('category load failure renders no-results state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = _ThrowingCategoryCoreDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(
        buildTestWidget(
          initialCategory: 'single_nutrient',
          overrides: [
            coreDatabaseProvider.overrideWithValue(db),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('No products in single nutrient'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows base filter chips as soon as typing starts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();

      expect(find.text('Top rated'), findsOneWidget);
      expect(find.text('High confidence'), findsOneWidget);
      final chipScroller = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      await tester.dragUntilVisible(
        find.text('Third-party tested'),
        chipScroller,
        const Offset(-250, 0),
      );
      await tester.pump();
      expect(find.text('Third-party tested'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Review before use'),
        chipScroller,
        const Offset(-250, 0),
      );
      await tester.pump();
      expect(find.text('Review before use'), findsOneWidget);
      expect(find.text('Blocked / Unsafe'), findsNothing);
      expect(find.text('Single Nutrient'), findsNothing);
    });

    testWidgets('shows result count and review filter without unsafe chip', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = _FakeCoreDatabase([
        const ProductsCoreData(
          dsldId: 'S1',
          productName: 'Magnesium Glycinate',
          brandName: 'Brand A',
          verdict: 'SAFE',
          score100Equivalent: 91.0,
          primaryCategory: 'single_nutrient',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S2',
          productName: 'Focus Blend',
          brandName: 'Brand B',
          verdict: 'CAUTION',
          score100Equivalent: 64.0,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S3',
          productName: 'Low Quality Blend',
          brandName: 'Brand C',
          verdict: 'POOR',
          score100Equivalent: 35.0,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S4',
          productName: 'Extreme Pre',
          brandName: 'Brand D',
          verdict: 'BLOCKED',
          score100Equivalent: 22.0,
          primaryCategory: 'pre_workout',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);
      addTearDown(db.close);

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            coreDatabaseProvider.overrideWithValue(db),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Showing 4 results'), findsOneWidget);
      expect(find.text('Extreme Pre'), findsOneWidget);
      expect(find.text('Blocked / Unsafe'), findsNothing);
      final chipScroller = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );

      await tester.dragUntilVisible(
        find.text('Review before use'),
        chipScroller,
        const Offset(-250, 0),
      );
      await tester.pump();

      await tester.tap(find.text('Review before use'));
      await tester.pump();

      expect(find.text('Showing 2 of 4 results'), findsOneWidget);
      expect(find.text('Focus Blend'), findsOneWidget);
      expect(find.text('Low Quality Blend'), findsOneWidget);
      expect(find.text('Magnesium Glycinate'), findsNothing);
      expect(find.text('Extreme Pre'), findsNothing);
    });

    testWidgets('top rated filter excludes low-coverage positive scores', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = _FakeCoreDatabase([
        const ProductsCoreData(
          dsldId: 'S1',
          productName: 'Confident Magnesium',
          brandName: 'Brand A',
          verdict: 'SAFE',
          score100Equivalent: 91.0,
          mappedCoverage: 0.82,
          primaryCategory: 'single_nutrient',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S2',
          productName: 'Low Coverage Multi',
          brandName: 'Brand B',
          verdict: 'SAFE',
          score100Equivalent: 95.0,
          mappedCoverage: 0.2,
          primaryCategory: 'multivitamin',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S3',
          productName: 'Unknown Coverage Blend',
          brandName: 'Brand C',
          verdict: 'GOOD',
          score100Equivalent: 88.0,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);
      addTearDown(db.close);

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            coreDatabaseProvider.overrideWithValue(db),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      await tester.tap(find.text('Top rated'));
      await tester.pump();

      expect(find.text('Showing 1 of 3 results'), findsOneWidget);
      expect(find.text('Confident Magnesium'), findsOneWidget);
      expect(find.text('Low Coverage Multi'), findsNothing);
      expect(find.text('Unknown Coverage Blend'), findsNothing);
    });

    testWidgets('confidence and testing filters use product trust signals', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = _FakeCoreDatabase([
        const ProductsCoreData(
          dsldId: 'S1',
          productName: 'Verified Magnesium',
          brandName: 'Brand A',
          verdict: 'SAFE',
          score100Equivalent: 91.0,
          mappedCoverage: 0.9,
          hasThirdPartyTesting: 1,
          primaryCategory: 'single_nutrient',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S2',
          productName: 'Mapped But Untested Blend',
          brandName: 'Brand B',
          verdict: 'SAFE',
          score100Equivalent: 86.0,
          mappedCoverage: 0.74,
          hasThirdPartyTesting: 0,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S3',
          productName: 'Sparse Label Multi',
          brandName: 'Brand C',
          verdict: 'SAFE',
          score100Equivalent: 92.0,
          mappedCoverage: 0.2,
          hasThirdPartyTesting: 1,
          primaryCategory: 'multivitamin',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);
      addTearDown(db.close);

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            coreDatabaseProvider.overrideWithValue(db),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      await tester.tap(find.text('High confidence'));
      await tester.pump();

      expect(find.text('Showing 2 of 3 results'), findsOneWidget);
      expect(find.text('Verified Magnesium'), findsOneWidget);
      expect(find.text('Mapped But Untested Blend'), findsOneWidget);
      expect(find.text('Sparse Label Multi'), findsNothing);

      final chipScroller = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      await tester.dragUntilVisible(
        find.text('Third-party tested'),
        chipScroller,
        const Offset(-250, 0),
      );
      await tester.pump();

      await tester.tap(find.text('Third-party tested'));
      await tester.pump();

      expect(find.text('Showing 2 of 3 results'), findsOneWidget);
      expect(find.text('Verified Magnesium'), findsOneWidget);
      expect(find.text('Sparse Label Multi'), findsOneWidget);
      expect(find.text('Mapped But Untested Blend'), findsNothing);
    });

    testWidgets(
      'shows an actionable empty state when a filter has no matches',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final db = _FakeCoreDatabase([
          const ProductsCoreData(
            dsldId: 'S1',
            productName: 'Low Coverage Magnesium',
            brandName: 'Brand A',
            verdict: 'SAFE',
            score100Equivalent: 91.0,
            mappedCoverage: 0.2,
            primaryCategory: 'single_nutrient',
            exportVersion: 'test',
            exportedAt: '2026-04-26T00:00:00Z',
          ),
          const ProductsCoreData(
            dsldId: 'S2',
            productName: 'Sparse Magnesium Blend',
            brandName: 'Brand B',
            verdict: 'SAFE',
            score100Equivalent: 86.0,
            mappedCoverage: 0.1,
            primaryCategory: 'blend',
            exportVersion: 'test',
            exportedAt: '2026-04-26T00:00:00Z',
          ),
        ]);
        addTearDown(db.close);

        await tester.pumpWidget(
          buildTestWidget(
            overrides: [
              coreDatabaseProvider.overrideWithValue(db),
              recentSearchesServiceProvider.overrideWithValue(
                _FakeRecentSearchesService(),
              ),
            ],
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'magnesium');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        await tester.tap(find.text('High confidence'));
        await tester.pump();

        expect(find.text('Showing 0 of 2 results'), findsOneWidget);
        expect(find.text('No matches for High confidence'), findsOneWidget);
        expect(find.text('Clear filter'), findsOneWidget);
        expect(find.text('Low Coverage Magnesium'), findsNothing);

        await tester.tap(find.text('Clear filter'));
        await tester.pump();

        expect(find.text('Showing 2 results'), findsOneWidget);
        expect(find.text('Low Coverage Magnesium'), findsOneWidget);
        expect(find.text('Sparse Magnesium Blend'), findsOneWidget);
      },
    );

    testWidgets('shows dynamic category chips from search results', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = _FakeCoreDatabase([
        const ProductsCoreData(
          dsldId: 'S1',
          productName: 'Magnesium Glycinate',
          brandName: 'Brand A',
          verdict: 'SAFE',
          score100Equivalent: 91.0,
          primaryCategory: 'single_nutrient',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S2',
          productName: 'Focus Blend',
          brandName: 'Brand B',
          verdict: 'CAUTION',
          score100Equivalent: 64.0,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);
      addTearDown(db.close);

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            coreDatabaseProvider.overrideWithValue(db),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      final chipScroller = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      await tester.dragUntilVisible(
        find.text('Single Nutrient'),
        chipScroller,
        const Offset(-250, 0),
      );
      await tester.pump();

      expect(find.text('Single Nutrient'), findsOneWidget);
      expect(find.text('Blend'), findsOneWidget);
    });
  });
}
