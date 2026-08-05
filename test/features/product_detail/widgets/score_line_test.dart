// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T10.
//
// Widget tests for the text-based score line. Catalog tests pass the
// pipeline's authoritative `quality_tier`; fallback tests omit it to
// cover old cached records.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';

Future<void> _pump(WidgetTester tester, int score, {String? qualityTier}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: PGScoreLine(score: score, qualityTier: qualityTier),
        ),
      ),
    ),
  );
}

void main() {
  group('PGScoreLine — renders score + tier + description', () {
    testWidgets('97 + Elite → Elite (deep green)', (tester) async {
      await _pump(tester, 97, qualityTier: 'Elite');
      expect(find.text('97/100'), findsOneWidget);
      expect(find.text('Elite'), findsOneWidget);
      expect(find.textContaining('High-quality ingredients'), findsOneWidget);
    });

    testWidgets('92 + Excellent → Excellent', (tester) async {
      await _pump(tester, 92, qualityTier: 'Excellent');
      expect(find.text('92/100'), findsOneWidget);
      expect(find.text('Excellent'), findsOneWidget);
      expect(find.textContaining('Well-formulated'), findsOneWidget);
    });

    testWidgets('82 + Strong → Strong (teal)', (tester) async {
      await _pump(tester, 82, qualityTier: 'Strong');
      expect(find.text('82/100'), findsOneWidget);
      expect(find.text('Strong'), findsOneWidget);
      expect(find.textContaining('Reliable option'), findsOneWidget);
    });

    testWidgets('75 + Acceptable → Acceptable', (tester) async {
      await _pump(tester, 75, qualityTier: 'Acceptable');
      expect(find.text('75/100'), findsOneWidget);
      expect(find.text('Acceptable'), findsOneWidget);
      expect(find.textContaining('Adequate formulation'), findsOneWidget);
    });

    testWidgets('60 + Weak → Weak', (tester) async {
      await _pump(tester, 60, qualityTier: 'Weak');
      expect(find.text('60/100'), findsOneWidget);
      expect(find.text('Weak'), findsOneWidget);
      expect(find.textContaining('Notable concerns'), findsOneWidget);
    });

    testWidgets('30 → Poor (red)', (tester) async {
      await _pump(tester, 30, qualityTier: 'Poor');
      expect(find.text('30/100'), findsOneWidget);
      expect(find.text('Poor'), findsOneWidget);
      expect(find.textContaining('Significant concerns'), findsOneWidget);
    });

    testWidgets('shipped tier wins when rounded score suggests another band', (
      tester,
    ) async {
      await _pump(tester, 80, qualityTier: 'Acceptable');
      expect(find.text('80/100'), findsOneWidget);
      expect(find.text('Acceptable'), findsOneWidget);
      expect(find.text('Strong'), findsNothing);
    });
  });

  group('PGScoreLine — boundary inputs', () {
    testWidgets('0 → Poor, displays 0/100', (tester) async {
      await _pump(tester, 0);
      expect(find.text('0/100'), findsOneWidget);
      expect(find.text('Poor'), findsOneWidget);
    });

    testWidgets('100 → Elite, displays 100/100', (tester) async {
      await _pump(tester, 100);
      expect(find.text('100/100'), findsOneWidget);
      expect(find.text('Elite'), findsOneWidget);
    });

    testWidgets('out-of-range high (105) clamps tier but keeps display', (
      tester,
    ) async {
      // Defensive: a future score-overflow bug shouldn't crash the
      // widget. Tier clamps to Elite, score-text shows the raw
      // value so a data-quality issue is visible.
      await _pump(tester, 105);
      expect(find.text('105/100'), findsOneWidget);
      expect(find.text('Elite'), findsOneWidget);
    });

    testWidgets('out-of-range low (-5) clamps tier but keeps display', (
      tester,
    ) async {
      await _pump(tester, -5);
      expect(find.text('-5/100'), findsOneWidget);
      expect(find.text('Poor'), findsOneWidget);
    });
  });

  group('PGScoreLine — tier dot color', () {
    testWidgets('dot uses tier color (Container with circle decoration)', (
      tester,
    ) async {
      // Structural smoke test — the tier dot is the only Container
      // with a circle BoxDecoration in the widget tree, so its
      // presence alone is the contract. Detailed pixel-color
      // assertions live in the score_tier_test boundary suite.
      await _pump(tester, 85);
      final containers = tester.widgetList<Container>(find.byType(Container));
      final dots = containers.where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
      expect(dots, isNotEmpty);
    });
  });

  group('PGScoreLine — descriptionOverride', () {
    testWidgets('override replaces the tier-default description', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGScoreLine(
              score: 92,
              qualityTier: 'Elite',
              descriptionOverride: 'Custom blurb for this product',
            ),
          ),
        ),
      );
      expect(find.text('Custom blurb for this product'), findsOneWidget);
      // Default description should NOT render.
      expect(find.textContaining('High-quality ingredients'), findsNothing);
    });
  });
}
