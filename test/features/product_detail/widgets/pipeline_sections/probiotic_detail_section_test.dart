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
import 'package:pharmaguide/features/product_detail/v2/sections/probiotic_section.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('Probiotic section — v1.5.x contract', () {
    testWidgets('renders pre-formatted CFU label + flattened strain count', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
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
      expect(find.text('25 billion CFU total per serving'), findsOneWidget);
      expect(find.text('2 named microorganisms'), findsOneWidget);
      expect(
        find.text('No verified strain-specific research matches'),
        findsOneWidget,
      );
      // Survivability chip uses humanized reason.
      expect(find.text('Spore'), findsOneWidget);
    });

    testWidgets('falls back to total_billion_count when label is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
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
      expect(find.text('5 billion CFU total per serving'), findsOneWidget);
    });

    testWidgets('renders nothing for empty probiotic_detail', (tester) async {
      await tester.pumpWidget(
        _wrap(buildProbioticSection(probioticDetail: {})),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Probiotic strains'), findsNothing);
    });

    testWidgets('postbiotic flag renders the dedicated chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
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
      expect(find.text('Postbiotic included'), findsOneWidget);
    });

    testWidgets('per-strain row shows cfu + evidence when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
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
      expect(find.text('5 billion per serving'), findsOneWidget);
    });

    testWidgets(
      'legacy multi-serving blend header is not rendered or counted as a strain',
      (tester) async {
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
                  {
                    'name': 'Bifidobacterium lactis (Bl-04)',
                    'strains': ['Bifidobacterium lactis (Bl-04)'],
                  },
                  {
                    'name': 'Lactobacillus acidophilus (La-14)',
                    'strains': ['Lactobacillus acidophilus (La-14)'],
                  },
                ],
              },
            ),
          ),
        );

        expect(find.text('2.25 billion CFU total per serving'), findsOneWidget);
        expect(find.text('3 named microorganisms'), findsOneWidget);
        expect(find.text('Probiotic Blend'), findsNothing);
        expect(find.text('Bifidobacterium bifidum (Bb-06)'), findsOneWidget);
        expect(find.text('Bifidobacterium lactis (Bl-04)'), findsOneWidget);
        expect(find.text('Lactobacillus acidophilus (La-14)'), findsOneWidget);
      },
    );

    testWidgets('verified exact-strain evidence uses explicit research copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'total_cfu_label': '5 billion CFU',
              'probiotic_blends': [
                {
                  'strains': [
                    'Lactobacillus acidophilus NCFM',
                    'Bifidobacterium bifidum Bb-06',
                  ],
                },
              ],
              'clinical_strains': [
                {
                  'strain': 'Lactobacillus acidophilus NCFM',
                  'cfu_per_day': 5e9,
                  'research_match_status': 'exact_strain',
                  'evidence_scope': 'strain_specific',
                  'review_status': 'clinician_verified',
                  'human_evidence': true,
                  'clinical_support_level': 'moderate',
                  'indication_primary': 'digestive support',
                  'source_urls': ['https://pubmed.ncbi.nlm.nih.gov/12345678/'],
                  'source_count': 1,
                },
              ],
            },
          ),
        ),
      );

      expect(find.text('Probiotic label & research'), findsOneWidget);
      expect(find.text('1 of 2 matched to verified research'), findsOneWidget);
      expect(find.text('Research match found'), findsOneWidget);
      expect(find.text('Moderate support · Digestive support'), findsOneWidget);
      expect(
        find.text('No strain-specific research match in our database'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.circle_outlined), findsNothing);
    });

    testWidgets('pending formula and rejected states never get positive copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'probiotic_blends': [
                {
                  'strains': ['Pending P-1', 'Formula F-1', 'Rejected R-1'],
                },
              ],
              'clinical_strains': [
                {
                  'strain': 'Pending P-1',
                  'research_match_status': 'pending_review',
                },
                {
                  'strain': 'Formula F-1',
                  'research_match_status': 'formula_only',
                },
                {
                  'strain': 'Rejected R-1',
                  'research_match_status': 'rejected',
                  'is_blocked': true,
                },
              ],
            },
          ),
        ),
      );

      expect(find.text('Research match found'), findsNothing);
      expect(find.text('Research match under review'), findsOneWidget);
      expect(find.text('Studied only as part of a formula'), findsOneWidget);
      expect(find.text('Research match not eligible'), findsOneWidget);
    });

    testWidgets('explains the card and exposes accessible research sources', (
      tester,
    ) async {
      List<String>? openedSources;
      await tester.pumpWidget(
        _wrap(
          buildProbioticSection(
            probioticDetail: {
              'total_cfu_label': '5 billion CFU',
              'probiotic_blends': [
                {
                  'strains': ['Lactobacillus acidophilus NCFM'],
                },
              ],
              'clinical_strains': [
                {
                  'strain': 'Lactobacillus acidophilus NCFM',
                  'research_match_status': 'exact_strain',
                  'review_status': 'clinician_verified',
                  'human_evidence': true,
                  'clinical_support_level': 'high',
                  'indication_primary': 'digestive support',
                  'source_urls': ['https://pubmed.ncbi.nlm.nih.gov/12345678/'],
                },
              ],
            },
            onTapSources: (sources) => openedSources = sources,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('About probiotic label and research'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Lactobacillus acidophilus NCFM.*Research match found'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsLabel('About probiotic label and research'),
      );
      await tester.pumpAndSettle();
      expect(find.text('What this card means'), findsOneWidget);
      expect(
        find.textContaining('does not mean this exact product'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.text('What this card means'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('View 1 source'));
      expect(openedSources, ['https://pubmed.ncbi.nlm.nih.gov/12345678/']);
    });
  });
}
