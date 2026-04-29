import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  Widget buildTestWidget({List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: SearchScreen()),
    );
  }

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

      expect(find.text('High Quality (80+)'), findsOneWidget);
      expect(find.text('Needs Review'), findsOneWidget);
      final chipScroller = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      await tester.dragUntilVisible(
        find.text('Blocked / Unsafe'),
        chipScroller,
        const Offset(-250, 0),
      );
      await tester.pump();
      expect(find.text('Blocked / Unsafe'), findsOneWidget);
      expect(find.text('Single Nutrient'), findsNothing);
    });

    testWidgets('shows result count and blocked verdict filter', (
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
          verdict: 'RECOMMENDED',
          score100Equivalent: 91.0,
          primaryCategory: 'single_nutrient',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S2',
          productName: 'Focus Blend',
          brandName: 'Brand B',
          verdict: 'REVIEW',
          score100Equivalent: 64.0,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S3',
          productName: 'Extreme Pre',
          brandName: 'Brand C',
          verdict: 'BLOCKED',
          score100Equivalent: 22.0,
          primaryCategory: 'pre_workout',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);

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

      expect(find.text('Showing 3 results'), findsOneWidget);
      expect(find.text('Needs Review'), findsOneWidget);
      final chipScroller = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      await tester.dragUntilVisible(
        find.text('Blocked / Unsafe'),
        chipScroller,
        const Offset(-250, 0),
      );
      await tester.pump();

      expect(find.text('Blocked / Unsafe'), findsOneWidget);

      await tester.tap(find.text('Blocked / Unsafe'));
      await tester.pump();

      expect(find.text('Showing 1 of 3 results'), findsOneWidget);
      expect(find.text('Extreme Pre'), findsOneWidget);
      expect(find.text('Magnesium Glycinate'), findsNothing);
      expect(find.text('Focus Blend'), findsNothing);
    });

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
          verdict: 'RECOMMENDED',
          score100Equivalent: 91.0,
          primaryCategory: 'single_nutrient',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
        const ProductsCoreData(
          dsldId: 'S2',
          productName: 'Focus Blend',
          brandName: 'Brand B',
          verdict: 'REVIEW',
          score100Equivalent: 64.0,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      ]);

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
