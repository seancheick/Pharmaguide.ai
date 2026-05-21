// Sprint: docs/sprints/product_detail_page_sprint.md — T3.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_confidence_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  double mappedCoverage = 1.0,
  bool hasProprietaryBlends = false,
  bool isNotScored = false,
  Map<String, dynamic>? productStatus,
  Map<String, dynamic>? unmappedActives,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (context) => buildLabelConfidenceSection(
              context: context,
              mappedCoverage: mappedCoverage,
              hasProprietaryBlends: hasProprietaryBlends,
              isNotScored: isNotScored,
              productStatus: productStatus,
              unmappedActives: unmappedActives,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('labelConfidenceHasAnySignal', () {
    test('high confidence (no signals) → false', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
        ),
        isFalse,
      );
    });

    test('low coverage → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 0.4,
          hasProprietaryBlends: false,
          isNotScored: false,
        ),
        isTrue,
      );
    });

    test('blend → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: true,
          isNotScored: false,
        ),
        isTrue,
      );
    });

    test('not scored → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: true,
        ),
        isTrue,
      );
    });

    test('product status → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
          productStatus: const {'display': 'Reformulated'},
        ),
        isTrue,
      );
    });

    test('unmapped actives total > 0 → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
          unmappedActives: const {'total': 2},
        ),
        isTrue,
      );
    });
  });

  group('LabelConfidence v2 rendering', () {
    testWidgets('high confidence → renders nothing', (tester) async {
      await _pump(tester);
      expect(find.textContaining('Label confidence'), findsNothing);
    });

    testWidgets('low coverage → Limited tier with coverage row', (
      tester,
    ) async {
      await _pump(tester, mappedCoverage: 0.2);
      expect(find.text('Label confidence: Limited'), findsOneWidget);
      expect(find.text('Limited label data available'), findsOneWidget);
    });

    testWidgets('partial coverage → Partial tier', (tester) async {
      await _pump(tester, mappedCoverage: 0.4);
      expect(find.text('Label confidence: Partial'), findsOneWidget);
      expect(
        find.text('Some ingredients could not be fully verified'),
        findsOneWidget,
      );
    });

    testWidgets('proprietary blend → blend row visible', (tester) async {
      await _pump(tester, hasProprietaryBlends: true);
      expect(find.text('Label confidence: Partial'), findsOneWidget);
      expect(find.text('Blend amounts not disclosed'), findsOneWidget);
    });

    testWidgets('product status → status row visible', (tester) async {
      await _pump(
        tester,
        productStatus: const {
          'type': 'reformulated',
          'date': '2026-01-15',
          'display': 'Reformulated · 2026-01-15',
        },
      );
      // Status-only renders as a compact product-status row in v2.
      // Calling it "Label confidence: Partial" would mislead.
      expect(find.text('Product note'), findsNothing);
      expect(find.textContaining('Reformulated'), findsWidgets);
    });

    testWidgets('unmapped actives → row with count + names', (tester) async {
      await _pump(
        tester,
        unmappedActives: const {
          'total': 2,
          'names': ['Exotic A', 'Typo B'],
        },
      );
      expect(find.text('Label confidence: Partial'), findsOneWidget);
      expect(find.text('2 ingredients could not be mapped'), findsOneWidget);
      expect(find.textContaining('Exotic A'), findsOneWidget);
    });

    testWidgets('not scored → Limited tier with not-scored row', (
      tester,
    ) async {
      await _pump(tester, isNotScored: true);
      expect(find.text('Label confidence: Limited'), findsOneWidget);
      expect(find.text('Not enough verified data to score'), findsOneWidget);
    });

    testWidgets('all signals together → Limited tier with multiple rows', (
      tester,
    ) async {
      await _pump(
        tester,
        mappedCoverage: 0.2,
        hasProprietaryBlends: true,
        isNotScored: true,
        productStatus: const {'display': 'Reformulated'},
        unmappedActives: const {
          'total': 1,
          'names': ['A'],
        },
      );
      expect(find.text('Label confidence: Limited'), findsOneWidget);
      expect(find.text('Not enough verified data to score'), findsOneWidget);
      expect(find.text('Limited label data available'), findsOneWidget);
      expect(find.text('Blend amounts not disclosed'), findsOneWidget);
      expect(find.text('1 ingredient could not be mapped'), findsOneWidget);
      expect(find.text('Reformulated'), findsOneWidget);
    });
  });
}
