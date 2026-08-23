// Golden-image tests for the restored probiotic research qualification, in
// both themes.
//
// To regenerate:
//   flutter test --update-goldens \
//     test/features/product_detail/v2/sections/probiotic_section_golden_test.dart
//
// The card was deleted on a false "no authoritative producer" premise and then
// restored, and the affirmative badge was subsequently gated on clinician
// review. These goldens pin what a reviewed strain and an unreviewed strain
// each look like, so neither the deletion nor the gate can regress silently in
// light or dark.

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/probiotic_section.dart';

import '../../../../support/app_fonts.dart';

Map<String, dynamic> _strain({
  required String name,
  required String matchStatus,
  required String reviewStatus,
}) => <String, dynamic>{
  'strain': name,
  'research_match_status': matchStatus,
  'review_status': reviewStatus,
  'cfu_per_day': 10000000000,
  'indication_primary': 'prevention of antibiotic-associated diarrhea',
  'clinical_support_level': 'high',
  'source_urls': const ['https://pubmed.ncbi.nlm.nih.gov/12345678/'],
  'is_inactivated': false,
};

Map<String, dynamic> _detail() => <String, dynamic>{
  'total_cfu_label': '20 billion CFU',
  'has_survivability_coating': true,
  'survivability_reason': 'delayed_release_capsule',
  'prebiotic_present': true,
  'probiotic_blends': <Map<String, dynamic>>[
    {
      'name': 'Probiotic Blend',
      'strains': ['Lactobacillus rhamnosus GG', 'Bifidobacterium lactis BB-12'],
    },
  ],
  'clinical_strains': <Map<String, dynamic>>[
    // Reviewed: earns an affirmative badge.
    _strain(
      name: 'Lactobacillus rhamnosus GG',
      matchStatus: 'exact_strain',
      reviewStatus: 'clinician_verified',
    ),
    // Unreviewed formula-level match: the case that used to render
    // "Research applies to the formula" with nobody having reviewed it.
    // Must show no affirmative badge.
    _strain(
      name: 'Bifidobacterium lactis BB-12',
      matchStatus: 'formula_only',
      reviewStatus: 'pending_review',
    ),
  ],
};

Widget _wrap(Brightness brightness) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: buildProbioticSection(probioticDetail: _detail()),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  for (final entry in {
    'light': Brightness.light,
    'dark': Brightness.dark,
  }.entries) {
    testWidgets('probiotic research qualification — ${entry.key}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 1800);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(entry.value));
      await tester.pumpAndSettle();

      // The reviewed strain states its research; the unreviewed one does not.
      expect(find.text('Research found for this exact strain'), findsOneWidget);
      expect(
        find.text('Research applies to the formula, not necessarily each strain'),
        findsNothing,
        reason: 'an unreviewed formula match must not present affirmatively',
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/probiotic_section_${entry.key}.png'),
      );
    });
  }
}
