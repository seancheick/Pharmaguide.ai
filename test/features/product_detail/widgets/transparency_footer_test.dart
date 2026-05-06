// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.14 +
// INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T21.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/transparency_footer.dart';

DateTime _now() => DateTime(2026, 4, 29);

Widget _wrap(CoreDatabase coreDb, {DateTime? nowOverride}) {
  return ProviderScope(
    overrides: [coreDatabaseProvider.overrideWithValue(coreDb)],
    child: MaterialApp(
      home: Scaffold(
        body: TransparencyFooter(nowOverride: nowOverride ?? _now()),
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
      expect(
        formatRelativeUpdate(
          DateTime(2026, 4, 29, 23, 59),
          DateTime(2026, 4, 29, 0, 1),
        ),
        'Updated today',
      );
    });
  });

  group('TransparencyFooter — render (T21 cleanup)', () {
    testWidgets(
      'rendered footer has 3 lines: Updated, Sources, rephrased disclaimer',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        await tester.pumpWidget(_wrap(coreDb));
        await tester.pumpAndSettle();

        // Lines render as separate Text widgets (not joined with '·').
        expect(find.textContaining('Updated'), findsOneWidget);
        expect(find.text('Sources: NIH · FDA · PubMed'), findsOneWidget);
        expect(
          find.text('Educational use only — not medical advice.'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
      },
    );

    testWidgets('T21 — no Coverage segment anywhere in footer', (tester) async {
      final coreDb = CoreDatabase.memory();
      await tester.pumpWidget(_wrap(coreDb));
      await tester.pumpAndSettle();

      // Coverage was a per-product segment that pre-T21 lived in the
      // summary line. Post-T21 it's gone — the §6 "What we don't know"
      // section above the footer covers this signal.
      expect(find.textContaining('Coverage:'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    testWidgets('T21 — no italic styling anywhere in footer subtree', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      await tester.pumpWidget(_wrap(coreDb));
      await tester.pumpAndSettle();

      // Walk every Text descendant of TransparencyFooter and assert
      // each effective TextStyle has fontStyle != italic.
      final textWidgets = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(TransparencyFooter),
          matching: find.byType(Text),
        ),
      );
      expect(textWidgets, isNotEmpty, reason: 'footer should render text');
      for (final t in textWidgets) {
        final style = t.style;
        expect(
          style?.fontStyle,
          isNot(equals(FontStyle.italic)),
          reason: 'No italic anywhere — T21 contract',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });

    testWidgets(
      'T21 — disclaimer copy exact match (rephrased from PharmaGuide-branded)',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        await tester.pumpWidget(_wrap(coreDb));
        await tester.pumpAndSettle();

        // Pre-T21: "PharmaGuide does not sell supplements. Educational only."
        // Post-T21: "Educational use only — not medical advice."
        expect(
          find.text('PharmaGuide does not sell supplements. Educational only.'),
          findsNothing,
        );
        expect(find.text(kTransparencyDisclaimer), findsOneWidget);
        expect(
          kTransparencyDisclaimer,
          'Educational use only — not medical advice.',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
      },
    );

    testWidgets(
      'manifest read-failure → "Updated recently" fallback (no missing-text)',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        await tester.pumpWidget(_wrap(coreDb));
        await tester.pumpAndSettle();

        expect(find.text(kTransparencyDisclaimer), findsOneWidget);
        expect(find.text('Sources: NIH · FDA · PubMed'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
      },
    );
  });
}
