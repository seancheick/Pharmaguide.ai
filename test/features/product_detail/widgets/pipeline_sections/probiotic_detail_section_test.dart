import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/probiotic_section.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('Probiotic label details', () {
    testWidgets('renders total CFU, strain count, and label-only copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'total_cfu_label': '25 billion CFU',
              'probiotic_blends': [
                {
                  'strains': [
                    'Lactobacillus acidophilus',
                    'Bifidobacterium lactis Bi-07',
                  ],
                },
              ],
              'has_survivability_coating': true,
              'survivability_reason': 'spore-based',
            },
          ),
        ),
      );

      expect(find.text('Probiotic label details'), findsOneWidget);
      expect(find.text('25 billion CFU total per serving'), findsOneWidget);
      expect(find.text('2 named microorganisms'), findsOneWidget);
      expect(find.text('Spore'), findsOneWidget);
      expect(find.textContaining('verified research'), findsNothing);
      expect(find.textContaining('Research found'), findsNothing);
    });

    testWidgets('falls back to numeric total without rounding small values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'total_billion_count': 0.000025,
              'probiotic_blends': [
                {
                  'strains': ['Lactobacillus test strain'],
                },
              ],
            },
          ),
        ),
      );

      expect(find.text('25 thousand CFU total per serving'), findsOneWidget);
      expect(find.textContaining('0.0 billion'), findsNothing);
    });

    testWidgets('renders nothing for empty probiotic detail', (tester) async {
      await tester.pumpWidget(
        _wrap(buildProbioticSection(probioticDetail: {})),
      );

      expect(find.text('Probiotic label details'), findsNothing);
    });

    testWidgets('renders postbiotic and per-strain label facts', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'total_cfu_label': '5 billion CFU',
              'has_postbiotic_strains': true,
              'probiotic_blends': [
                {
                  'strains': ['Lactobacillus acidophilus'],
                },
              ],
              'clinical_strains': [
                {
                  'strain': 'Lactobacillus acidophilus',
                  'cfu_per_day': 5e9,
                  'is_inactivated': true,
                  // Deliberately ignored until an authoritative producer exists.
                  'research_match_status': 'exact_strain',
                  'source_urls': ['https://example.test/not-rendered'],
                },
              ],
            },
          ),
        ),
      );

      expect(find.text('5 billion CFU per serving'), findsOneWidget);
      expect(find.text('Postbiotic included'), findsOneWidget);
      expect(
        find.text('Postbiotic · inactivated microorganism'),
        findsOneWidget,
      );
      expect(find.textContaining('Research'), findsNothing);
      expect(find.textContaining('source'), findsNothing);
    });

    testWidgets('legacy blend header is not rendered or counted as a strain', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'total_cfu_label': '3.37 billion CFU',
              'total_billion_count': 3.37,
              'probiotic_blends': [
                {
                  'name': 'Probiotic Blend',
                  'strains': ['Probiotic Blend'],
                  'cfu_data': {'billion_count': 1.12},
                },
                {
                  'name': 'Probiotic Blend',
                  'strains': <String>[],
                  'is_blend_header_total': true,
                  'cfu_data': {'billion_count': 2.25},
                },
                {
                  'name': 'Bifidobacterium bifidum (Bb-06)',
                  'strains': ['Bifidobacterium bifidum (Bb-06)'],
                },
              ],
            },
          ),
        ),
      );

      expect(find.text('2.25 billion CFU total per serving'), findsOneWidget);
      expect(find.text('1 named microorganism'), findsOneWidget);
      expect(find.text('Probiotic Blend'), findsNothing);
      expect(find.text('Bifidobacterium bifidum (Bb-06)'), findsOneWidget);
    });

    testWidgets('generic clinical container echo is not rendered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'total_cfu_label': '2 billion CFU',
              'probiotic_blends': [
                {
                  'name': 'Probiotic Blend',
                  'strains': ['Lactobacillus acidophilus La-14'],
                },
              ],
              'clinical_strains': [
                {'strain': 'Probiotic Blend'},
              ],
            },
          ),
        ),
      );

      expect(find.text('1 named microorganism'), findsOneWidget);
      expect(find.text('Probiotic Blend'), findsNothing);
    });
  });
}
