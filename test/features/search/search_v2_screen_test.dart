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
  @override
  Future<List<String>> getRecent() async => const [];
}

void main() {
  Future<void> seedSearchProduct(CoreDatabase coreDb) async {
    await coreDb
        .into(coreDb.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: 'search-v2-1',
            productName: 'Search V2 Magnesium',
            brandName: const drift.Value('V2 Brand'),
            primaryCategory: const drift.Value('magnesium'),
            score100Equivalent: const drift.Value(86),
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
}
