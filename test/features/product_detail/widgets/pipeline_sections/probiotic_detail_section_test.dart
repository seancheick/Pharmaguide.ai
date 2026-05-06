// Regression: the section reads the canonical v1.5.x probiotic_detail
// shape:
//   total_cfu_label      pre-formatted "25 billion CFU"
//   total_billion_count  numeric (5.0) — fallback for older blobs
//   probiotic_blends[]   carries strains[] (string list) per blend
//   clinical_strains[]   carries {strain, cfu_per_day, evidence_level, ...}
//
// Pre-rewire (2026-05-05) the widget read non-existent top-level
// 'strains' / 'total_cfu' (safeString of a numeric) and crashed when
// clinical_strains was a List. Tests below pin the new wiring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/probiotic_detail_section.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProbioticDetailSection — v1.5.x contract', () {
    testWidgets('renders pre-formatted CFU label + flattened strain count', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ProbioticDetailSection(
            probioticDetail: {
              'total_cfu_label': '25 billion CFU',
              'total_billion_count': 25.0,
              'probiotic_blends': [
                {
                  'name': 'Lactobacillus acidophilus',
                  'strains': ['Lactobacillus acidophilus'],
                  'strain_count': 1,
                },
                {
                  'name': 'Bifidobacterium lactis',
                  'strains': ['Bifidobacterium lactis Bi-07'],
                  'strain_count': 1,
                },
              ],
              'clinical_strains': [
                {
                  'strain': 'Lactobacillus acidophilus',
                  'clinical_id': 'STRAIN_ACIDOPHILUS_NCFM',
                  'cfu_per_day': 5e9,
                  'evidence_level': 'high',
                },
              ],
              'has_survivability_coating': true,
              'survivability_reason': 'spore-based',
              'has_postbiotic_strains': false,
              'prebiotic_present': false,
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // CFU chip uses the pre-formatted label.
      expect(find.text('25 billion CFU'), findsOneWidget);
      // Strain count is flattened across blends (2 unique).
      expect(find.text('Strains: '), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // Clinical chip reads list length.
      expect(find.text('Clinically studied: '), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      // Survivability chip uses humanized reason.
      expect(find.text('Survivability: '), findsOneWidget);
      expect(find.text('Spore'), findsOneWidget);
    });

    testWidgets('falls back to total_billion_count when label is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ProbioticDetailSection(
            probioticDetail: {
              'total_billion_count': 5.0,
              'probiotic_blends': [
                {
                  'strains': ['Bacillus coagulans'],
                },
              ],
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Numeric fallback formats to "5 billion CFU".
      expect(find.text('5 billion CFU'), findsOneWidget);
    });

    testWidgets('renders nothing for empty probiotic_detail', (tester) async {
      await tester.pumpWidget(
        _wrap(const ProbioticDetailSection(probioticDetail: {})),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Probiotic Profile'), findsNothing);
    });

    testWidgets('postbiotic flag renders the dedicated chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProbioticDetailSection(
            probioticDetail: {
              'total_cfu_label': '10 billion CFU',
              'has_postbiotic_strains': true,
              'probiotic_blends': [
                {
                  'strains': ['Lactobacillus rhamnosus (heat-killed)'],
                },
              ],
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Postbiotic: '), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
    });

    testWidgets('per-strain row shows cfu + evidence when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ProbioticDetailSection(
            probioticDetail: {
              'total_cfu_label': '5 billion CFU',
              'probiotic_blends': [
                {
                  'strains': ['Lactobacillus acidophilus'],
                },
              ],
              'clinical_strains': [
                {
                  'strain': 'Lactobacillus acidophilus',
                  'cfu_per_day': 5e9,
                  'evidence_level': 'moderate',
                },
              ],
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Per-strain row renders the CFU label.
      expect(find.text('5 billion'), findsOneWidget);
    });
  });
}
