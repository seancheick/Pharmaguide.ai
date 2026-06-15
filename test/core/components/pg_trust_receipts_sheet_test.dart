// Widget tests for the Trust Receipts sheet ("Why trust this?").
//
// Covers:
//   - both sections render (How scoring works + Our sources)
//   - live counts render when provided
//   - counts are OMITTED (not faked) when null
//   - the score-breakdown "How scoring works" link opens the sheet
//
// Run: flutter test test/core/components/pg_trust_receipts_sheet_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_trust_receipts_sheet.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/data/providers/trust_receipts_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

/// The sheet's ListView builds lazily; a tall test surface ensures every
/// row (including the closing privacy block) is laid out for the finders.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('PGTrustReceiptsSheet', () {
    testWidgets('renders both sections and all source rows', (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_host(const PGTrustReceiptsSheet(data: null)));

      expect(find.text('Why trust this?'), findsOneWidget);
      // PGEyebrow renders uppercase.
      expect(find.text('HOW SCORING WORKS'), findsOneWidget);
      expect(find.text('OUR SOURCES'), findsOneWidget);

      // Six pillars with their maxes — derived from kV4PillarSpec (the
      // single source of truth) so the test can never drift from it.
      final maxCounts = <int, int>{};
      for (final (_, label, max) in kV4PillarSpec) {
        expect(find.text(label), findsOneWidget);
        maxCounts[max] = (maxCounts[max] ?? 0) + 1;
      }
      for (final entry in maxCounts.entries) {
        expect(find.text('/${entry.key}'), findsNWidgets(entry.value));
      }

      // Source rows.
      expect(
        find.text('NIH Dietary Supplement Label Database'),
        findsOneWidget,
      );
      expect(
        find.text('PubMed — curated clinical study clusters'),
        findsOneWidget,
      );
      expect(find.text('Hand-reviewed, evidence-graded'), findsOneWidget);
      expect(find.text('supp.ai PubMed co-occurrence'), findsOneWidget);
      expect(
        find.text('FDA — synced with each catalog update'),
        findsOneWidget,
      );

      // Closing block: truthful privacy line.
      expect(
        find.textContaining(
          'Your health profile and medications never leave your device.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows live counts when provided', (tester) async {
      _useTallSurface(tester);
      final data = TrustReceiptsData(
        productCount: 9270,
        catalogGeneratedAt: DateTime.utc(2026, 6, 12, 9, 7),
        interactionCount: 148,
        researchPairCount: 30474,
      );
      await tester.pumpWidget(_host(PGTrustReceiptsSheet(data: data)));

      expect(find.text('9,270 products'), findsOneWidget);
      expect(find.text('148 interactions'), findsOneWidget);
      expect(find.text('30,474 pairs'), findsOneWidget);
      expect(find.textContaining('Catalog updated'), findsOneWidget);
    });

    testWidgets('omits counts when null — never invents a number', (
      tester,
    ) async {
      _useTallSurface(tester);
      // Partial data: only the interaction count made it through.
      const data = TrustReceiptsData(interactionCount: 1);
      await tester.pumpWidget(_host(const PGTrustReceiptsSheet(data: data)));

      // Singular form for 1.
      expect(find.text('1 interaction'), findsOneWidget);
      // Missing counts are absent, not zero/faked.
      expect(find.textContaining(RegExp(r'\d+ products?')), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ pairs?')), findsNothing);
      expect(find.textContaining('Catalog updated'), findsNothing);
    });
  });

  group('score breakdown entry point', () {
    testWidgets('"How scoring works" link opens the Trust Receipts sheet', (
      tester,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trustReceiptsProvider.overrideWith(
              (ref) async => const TrustReceiptsData(productCount: 42),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: buildScoreBreakdownSection(
                  ingredientQuality: 20,
                  safetyPurity: 25,
                  evidenceResearch: 15,
                  brandTrust: 4,
                  hasThirdPartyTesting: false,
                  isTrustedManufacturer: false,
                  heroScore: 80,
                  mappedCoverage: 0.9,
                  qualityPillarsV4: const {
                    'formulation': {
                      'score': 16,
                      'max': 20,
                      'reason': 'Form, dosage, and bioavailability',
                    },
                    'dose': {
                      'score': 16,
                      'max': 20,
                      'reason': 'Serving strength and studied ranges',
                    },
                    'evidence': {
                      'score': 16,
                      'max': 20,
                      'reason': 'Clinical support behind ingredients',
                    },
                    'transparency': {
                      'score': 12,
                      'max': 15,
                      'reason': 'Label clarity and disclosure',
                    },
                    'verification': {
                      'score': 12,
                      'max': 15,
                      'reason': 'Independent testing and brand signals',
                    },
                    'safety_hygiene': {
                      'score': 8,
                      'max': 10,
                      'reason': 'Clean-label and contaminant risk checks',
                    },
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('How scoring works'), findsOneWidget);
      await tester.tap(find.text('How scoring works'));
      await tester.pumpAndSettle();

      // Sheet is open with the live count from the (overridden) provider.
      expect(find.text('Why trust this?'), findsOneWidget);
      expect(find.text('OUR SOURCES'), findsOneWidget);
      expect(find.text('42 products'), findsOneWidget);
    });
  });
}
