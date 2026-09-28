import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';

void main() {
  Future<void> seedRecentScan(
    CoreDatabase coreDb,
    UserDatabase userDb, {
    String dsldId = 'recent-1',
    String productName = 'Recent Scan Product',
    String brandName = 'Good Brand',
  }) async {
    await coreDb
        .into(coreDb.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: dsldId,
            productName: productName,
            brandName: drift.Value(brandName),
            imageThumbnailUrl: const drift.Value('https://example.com/a.png'),
            qualityScoreV4100: const drift.Value(82),
            exportVersion: 'test',
            exportedAt: '2026-05-18T00:00:00Z',
          ),
        );
    await userDb.recordScanEvent(dsldId: dsldId, productName: productName);
  }

  Future<void> pumpHomeV2(
    WidgetTester tester,
    CoreDatabase coreDb,
    UserDatabase userDb, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
        child: MaterialApp(
          theme: theme,
          home: const HomeV2Screen(showNavBar: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('recent scan image has an inset frame', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await seedRecentScan(coreDb, userDb);

    await pumpHomeV2(tester, coreDb, userDb);

    expect(find.text('Recent Scan Product'), findsOneWidget);
    final frameFinder = find.byKey(
      const ValueKey('home-recent-scan-image-frame'),
    );
    expect(frameFinder, findsWidgets);

    final frame = tester.widget<Container>(frameFinder.first);
    expect(frame.constraints?.maxWidth, V2Spacing.space64 + V2Spacing.space8);
    expect(frame.constraints?.maxHeight, V2Spacing.space64 + V2Spacing.space8);
    expect(frame.padding, const EdgeInsets.all(V2Spacing.space8));
  });

  testWidgets('recent scans never fall back to fixture cards', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await pumpHomeV2(tester, coreDb, userDb);

    expect(find.text('Nothing scanned yet'), findsOneWidget);
    expect(find.text('Ultimate Omega 2X'), findsNothing);
    expect(find.text('Basic Nutrients 2/Day'), findsNothing);
    expect(find.text('L-Theanine 200mg'), findsNothing);
    expect(find.text('Magnesium Glycinate'), findsNothing);
  });

  // The section padded itself by 24 inside a sliver that already padded 24,
  // so "Recent scans" and its empty card sat at 48pt while every other
  // section starts at the 24pt page gutter.
  for (final withScan in [false, true]) {
    testWidgets('recent scans aligns to the page gutter (scan: $withScan)', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      });
      if (withScan) await seedRecentScan(coreDb, userDb);

      await pumpHomeV2(tester, coreDb, userDb);

      final header = find.text('Recent scans');
      await tester.ensureVisible(header);
      await tester.pump();
      expect(tester.getTopLeft(header).dx, V2Spacing.space24);
      final firstCardText = withScan
          ? find.text('Recent Scan Product')
          : find.text('Nothing scanned yet');
      expect(firstCardText, findsOneWidget);
    });
  }

  // The tile asked "Safe to take together?", a yes/no safety question the
  // feature deliberately never answers ("No interaction catalogued").
  testWidgets('quick check tile does not ask a safety question', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await pumpHomeV2(tester, coreDb, userDb);
    await tester.scrollUntilVisible(
      find.text('Check two together'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Check two together'), findsOneWidget);
    expect(find.textContaining('Safe'), findsNothing);
    // Navigation wears the brand accent, not the caution severity amber.
    final icon = tester.widget<Icon>(find.byIcon(Icons.compare_arrows_rounded));
    expect(icon.color, V2Palette.light.accent);
  });

  testWidgets('recent scan cards do not overflow with long names', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await seedRecentScan(
      coreDb,
      userDb,
      productName:
          'Pure Encapsulations Liposomal Vitamin C Capsules Extra Strength',
      brandName: 'Pure Encapsulations',
    );

    await pumpHomeV2(tester, coreDb, userDb);

    expect(tester.takeException(), isNull);
  });

  testWidgets('search launcher stays pinned and hit-testable after scroll', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await seedRecentScan(coreDb, userDb);
    await pumpHomeV2(tester, coreDb, userDb);

    final search = find.text('Search supplements');
    final scannedProduct = find.text('Recent Scan Product');
    expect(search, findsOneWidget);
    final before = tester.getTopLeft(search);
    final productBefore = tester.getTopLeft(scannedProduct);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(search, findsOneWidget);
    final after = tester.getTopLeft(search);
    final productAfter = tester.getTopLeft(scannedProduct);
    expect(after.dy, before.dy);
    expect(productAfter.dy, lessThan(productBefore.dy));

    final searchTapTarget = find.ancestor(
      of: search,
      matching: find.byType(InkWell),
    );
    expect(
      tester.widget<InkWell>(searchTapTarget).onTap,
      isNotNull,
      reason: 'search launcher must remain tappable while pinned',
    );
    expect(find.bySemanticsLabel('Search supplements'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('pinned search background follows a live appearance change', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await pumpHomeV2(tester, coreDb, userDb, theme: V2Theme.light);
    ColoredBox header() => tester.widget<ColoredBox>(
      find.byKey(const ValueKey('home-pinned-search-background')),
    );
    expect(header().color, V2Theme.light.scaffoldBackgroundColor);

    await pumpHomeV2(tester, coreDb, userDb, theme: V2Theme.dark);
    await tester.pumpAndSettle();
    expect(header().color, V2Theme.dark.scaffoldBackgroundColor);
  });
}
