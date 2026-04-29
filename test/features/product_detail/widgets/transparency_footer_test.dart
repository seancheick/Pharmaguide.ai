// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.14.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/transparency_footer.dart';

DateTime _now() => DateTime(2026, 4, 29);

Widget _wrap(
  CoreDatabase coreDb, {
  double? mappedCoverage = 0.75,
  int? totalIngredientCount = 20,
  DateTime? nowOverride,
}) {
  return ProviderScope(
    overrides: [coreDatabaseProvider.overrideWithValue(coreDb)],
    child: MaterialApp(
      home: Scaffold(
        body: TransparencyFooter(
          mappedCoverage: mappedCoverage,
          totalIngredientCount: totalIngredientCount,
          nowOverride: nowOverride ?? _now(),
        ),
      ),
    ),
  );
}

void main() {
  group('formatRelativeUpdate — pure logic', () {
    test('null buildDate → "Updated recently" (defensive)', () {
      expect(formatRelativeUpdate(null, _now()), 'Updated recently');
    });

    test('same day → "Updated today"', () {
      expect(
        formatRelativeUpdate(DateTime(2026, 4, 29), _now()),
        'Updated today',
      );
    });

    test('1 day ago → "Updated yesterday"', () {
      expect(
        formatRelativeUpdate(DateTime(2026, 4, 28), _now()),
        'Updated yesterday',
      );
    });

    test('2 days ago → "Updated 2 days ago"', () {
      expect(
        formatRelativeUpdate(DateTime(2026, 4, 27), _now()),
        'Updated 2 days ago',
      );
    });

    test('6 days ago → "Updated 6 days ago"', () {
      expect(
        formatRelativeUpdate(DateTime(2026, 4, 23), _now()),
        'Updated 6 days ago',
      );
    });

    test('7 days ago → flips to absolute "Updated Apr 22"', () {
      // ≥ 7 days, relative form would read as "1 week" — switch to
      // absolute "Apr DD" for cleaner copy.
      expect(
        formatRelativeUpdate(DateTime(2026, 4, 22), _now()),
        'Updated Apr 22',
      );
    });

    test('30 days ago → absolute', () {
      expect(
        formatRelativeUpdate(DateTime(2026, 3, 30), _now()),
        'Updated Mar 30',
      );
    });

    test('time-of-day ignored — same calendar day reads "today"', () {
      // 23:59 on the build day vs 00:01 on "now" should still be
      // "today" — relative phrasing is calendar-day, not 24-hour.
      expect(
        formatRelativeUpdate(
          DateTime(2026, 4, 29, 23, 59),
          DateTime(2026, 4, 29, 0, 1),
        ),
        'Updated today',
      );
    });
  });

  group('formatCoverage — pure logic', () {
    test('mapped + total present → "Coverage: n/total"', () {
      expect(formatCoverage(0.75, 20), 'Coverage: 15/20');
    });

    test('rounds n to nearest whole', () {
      // 0.74 * 20 = 14.8 → rounds to 15. 0.71 * 20 = 14.2 → 14.
      expect(formatCoverage(0.74, 20), 'Coverage: 15/20');
      expect(formatCoverage(0.71, 20), 'Coverage: 14/20');
    });

    test('full coverage → n equals total', () {
      expect(formatCoverage(1.0, 12), 'Coverage: 12/12');
    });

    test('zero coverage → "Coverage: 0/N"', () {
      expect(formatCoverage(0.0, 8), 'Coverage: 0/8');
    });

    test('null coverage → null (segment dropped from footer)', () {
      expect(formatCoverage(null, 20), isNull);
    });

    test('null total → null', () {
      expect(formatCoverage(0.5, null), isNull);
    });

    test('zero total → null (avoid divide-by-zero placeholder)', () {
      // Defensive — a product with no ingredients shouldn't render
      // "Coverage: 0/0" since the segment would be meaningless.
      expect(formatCoverage(0.5, 0), isNull);
    });

    test('out-of-band coverage clamped to [0..1]', () {
      // Stale catalog might emit > 1.0; clamp prevents inflated counts.
      expect(formatCoverage(1.5, 10), 'Coverage: 10/10');
      expect(formatCoverage(-0.1, 10), 'Coverage: 0/10');
    });
  });

  group('TransparencyFooter — render', () {
    testWidgets('disclaimer always present (acceptance — site-wide trust)', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();

      // Render with full data.
      await tester.pumpWidget(_wrap(coreDb));
      await tester.pumpAndSettle();
      expect(find.text(kTransparencyDisclaimer), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    testWidgets('disclaimer renders even when coverage data is null', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();

      await tester.pumpWidget(
        _wrap(coreDb, mappedCoverage: null, totalIngredientCount: null),
      );
      await tester.pumpAndSettle();
      expect(find.text(kTransparencyDisclaimer), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    testWidgets('renders sources list', (tester) async {
      final coreDb = CoreDatabase.memory();
      await tester.pumpWidget(_wrap(coreDb));
      await tester.pumpAndSettle();

      // The sources line is concatenated into the summary row, not
      // each as separate widgets — so use textContaining.
      expect(
        find.textContaining('Sources: NIH · FDA · PubMed'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    testWidgets('renders coverage segment when both inputs present', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      await tester.pumpWidget(_wrap(coreDb));
      await tester.pumpAndSettle();

      // 0.75 * 20 = 15 → "Coverage: 15/20"
      expect(find.textContaining('Coverage: 15/20'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    testWidgets(
      'omits coverage segment when data missing — disclaimer + sources still render',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        await tester.pumpWidget(_wrap(coreDb, mappedCoverage: null));
        await tester.pumpAndSettle();

        expect(find.textContaining('Coverage:'), findsNothing);
        expect(find.textContaining('Sources: NIH'), findsOneWidget);
        expect(find.text(kTransparencyDisclaimer), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
      },
    );

    testWidgets(
      'manifest read-failure → "Updated recently" fallback (no missing-text)',
      (tester) async {
        // Empty in-memory DB has no manifest — readManifestValue
        // returns null. The footer should still render gracefully.
        final coreDb = CoreDatabase.memory();
        await tester.pumpWidget(_wrap(coreDb));
        await tester.pumpAndSettle();

        // catalogInfoProvider may resolve to a CatalogInfo with
        // null buildDate, OR be still loading. Either way we must
        // not crash and the disclaimer must still render.
        expect(find.text(kTransparencyDisclaimer), findsOneWidget);
        expect(find.textContaining('Sources: NIH'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
      },
    );
  });
}
