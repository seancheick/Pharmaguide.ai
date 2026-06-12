import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/search/v2/search_v2_screen.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';

class _FakeRecentSearchesService extends RecentSearchesService {
  _FakeRecentSearchesService([List<String> initial = const []])
    : _items = [...initial];

  final List<String> _items;
  int addCount = 0;

  List<String> get items => List.unmodifiable(_items);

  @override
  Future<List<String>> getRecent() async => _items;

  @override
  Future<void> addSearch(String query) async {
    addCount++;
    _items.removeWhere((e) => e.toLowerCase() == query.toLowerCase());
    _items.insert(0, query);
  }

  @override
  Future<void> removeSearch(String query) async {
    _items.remove(query);
  }

  @override
  Future<void> clearAll() async {
    _items.clear();
  }
}

void main() {
  Future<void> seedSearchProduct(
    CoreDatabase coreDb, {
    String dsldId = 'search-v2-1',
    String productName = 'Search V2 Magnesium',
    String brandName = 'V2 Brand',
    String primaryCategory = 'magnesium',
    double score = 86,
  }) async {
    await coreDb
        .into(coreDb.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: dsldId,
            productName: productName,
            brandName: drift.Value(brandName),
            primaryCategory: drift.Value(primaryCategory),
            score100Equivalent: drift.Value(score),
            verdict: const drift.Value('GOOD'),
            exportVersion: 'test',
            exportedAt: '2026-05-18T00:00:00Z',
          ),
        );
  }

  testWidgets('keyboard-open layout does not reserve shell nav padding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentSearchesServiceProvider.overrideWithValue(
            _FakeRecentSearchesService(),
          ),
        ],
        child: const MaterialApp(home: SearchV2Screen()),
      ),
    );
    await tester.pump();

    final bottomPaddings = tester
        .widgetList<Padding>(find.byType(Padding))
        .map((w) => w.padding.resolve(TextDirection.ltr).bottom);

    expect(bottomPaddings, contains(V2Spacing.space8));
  });

  testWidgets('idle state renders modern recent and featured sections', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    await seedSearchProduct(coreDb);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          recentSearchesServiceProvider.overrideWithValue(
            _FakeRecentSearchesService(['thorne creatine']),
          ),
        ],
        child: const MaterialApp(home: SearchV2Screen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Recent Searches'), findsOneWidget);
    expect(find.text('Clear All'), findsOneWidget);
    expect(find.text('thorne creatine'), findsOneWidget);
    expect(find.text('Featured Products'), findsOneWidget);
    expect(find.text('Search V2 Magnesium'), findsOneWidget);
  });

  testWidgets('query state renders suggestions above suggested products', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    await seedSearchProduct(
      coreDb,
      productName: 'Magnesium Citrate Capsules',
      brandName: 'Pure Encapsulations',
      primaryCategory: 'magnesium',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          recentSearchesServiceProvider.overrideWithValue(
            _FakeRecentSearchesService(),
          ),
        ],
        child: const MaterialApp(home: SearchV2Screen(initialQuery: 'magn')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Suggested Searches'), findsOneWidget);
    expect(find.text('Suggested Products'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SuggestionGlyph',
      ),
      findsWidgets,
    );
    expect(find.text('Magnesium Citrate Capsules'), findsOneWidget);
  });

  testWidgets(
    'category results render v2 rows instead of legacy product rows',
    (tester) async {
      final coreDb = CoreDatabase.memory();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
      });

      await seedSearchProduct(coreDb);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            recentSearchesServiceProvider.overrideWithValue(
              _FakeRecentSearchesService(),
            ),
          ],
          child: const MaterialApp(
            home: SearchV2Screen(initialCategory: 'magnesium'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Search V2 Magnesium'), findsOneWidget);
      expect(find.text('V2 Brand'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'ProductListItem',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('typing does not record recent searches; submit does', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final recents = _FakeRecentSearchesService();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    await seedSearchProduct(
      coreDb,
      productName: 'Magnesium Citrate Capsules',
      brandName: 'Pure Encapsulations',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          recentSearchesServiceProvider.overrideWithValue(recents),
        ],
        child: const MaterialApp(home: SearchV2Screen()),
      ),
    );
    await tester.pump();

    // Simulate per-keystroke typing through the debounce.
    for (final partial in ['ma', 'mag', 'magn']) {
      await tester.enterText(find.byType(TextField), partial);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    // Results rendered, but nothing was recorded while exploring.
    expect(find.text('Magnesium Citrate Capsules'), findsOneWidget);
    expect(recents.addCount, 0);

    // Keyboard submit commits and records exactly once.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(recents.addCount, 1);
    expect(recents.items, ['magn']);
  });

  testWidgets('suggestion tap records the query and hides suggestions; '
      'editing brings them back', (tester) async {
    final coreDb = CoreDatabase.memory();
    final recents = _FakeRecentSearchesService();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    await seedSearchProduct(
      coreDb,
      productName: 'Magnesium Citrate Capsules',
      brandName: 'Pure Encapsulations',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          recentSearchesServiceProvider.overrideWithValue(recents),
        ],
        child: const MaterialApp(home: SearchV2Screen(initialQuery: 'magn')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Suggested Searches'), findsOneWidget);
    expect(recents.addCount, 0);

    // Tap the first suggested search row.
    final suggestionRow = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_SuggestedSearchRow',
    );
    expect(suggestionRow, findsWidgets);
    await tester.tap(suggestionRow.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Committed: suggestions hidden, results lead, query recorded once.
    expect(find.text('Suggested Searches'), findsNothing);
    expect(find.text('Suggested Products'), findsOneWidget);
    expect(recents.addCount, 1);

    // Editing the query returns to exploring: suggestions come back,
    // and no extra recent entry is recorded.
    await tester.enterText(find.byType(TextField), 'magnes');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Suggested Searches'), findsOneWidget);
    expect(recents.addCount, 1);
  });
}
