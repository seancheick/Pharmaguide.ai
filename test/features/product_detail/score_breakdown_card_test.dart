import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';

void main() {
  Widget buildTestWidget({
    double? formulation,
    double? dose,
    double? evidence,
    double? transparency,
    double? verification,
    double? safetyHygiene,
    double? heroScore,
    double? mappedCoverage,
    bool hasThirdPartyTesting = false,
    bool isTrustedManufacturer = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: buildScoreBreakdownSection(
          ingredientQuality: 99,
          safetyPurity: 99,
          evidenceResearch: 99,
          brandTrust: 99,
          hasThirdPartyTesting: hasThirdPartyTesting,
          isTrustedManufacturer: isTrustedManufacturer,
          heroScore: heroScore,
          mappedCoverage: mappedCoverage,
          qualityPillarsV4: _v4Pillars(
            formulation: formulation,
            dose: dose,
            evidence: evidence,
            transparency: transparency,
            verification: verification,
            safetyHygiene: safetyHygiene,
          ),
        ),
      ),
    );
  }

  group('Score breakdown section', () {
    testWidgets('header reads "Why this scored {N}" when heroScore present', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(heroScore: 84));

      expect(find.text('Why this scored 84'), findsOneWidget);
      expect(find.text('Product Analysis'), findsNothing);
    });

    testWidgets('header omits the number when heroScore is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Why this scored'), findsOneWidget);
    });

    testWidgets('renders locked pillar labels in order', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Formulation'), findsOneWidget);
      expect(find.text('Dose'), findsOneWidget);
      expect(find.text('Evidence'), findsOneWidget);
      expect(find.text('Transparency'), findsOneWidget);
      expect(find.text('Verification'), findsOneWidget);
      expect(find.text('Safety Hygiene'), findsOneWidget);
      expect(find.text('Brand trust'), findsNothing);
    });

    testWidgets('renders each v4 pillar on its native score/max scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          formulation: 17.6,
          dose: 16,
          evidence: 18.9,
          transparency: 12.5,
          verification: 13,
          safetyHygiene: 9.3,
        ),
      );

      expect(find.text('17.6/20'), findsOneWidget);
      expect(find.text('16/20'), findsOneWidget);
      expect(find.text('18.9/20'), findsOneWidget);
      expect(find.text('12.5/15'), findsOneWidget);
      expect(find.text('13/15'), findsOneWidget);
      expect(find.text('9.3/10'), findsOneWidget);
      expect(find.text('8/10'), findsNothing);
    });

    testWidgets('shows "No data" for null pillar scores', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('No data'), findsNWidgets(6));
    });

    testWidgets('reveals micro-explanation and badges when tapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(verification: 13, hasThirdPartyTesting: true),
      );

      await tester.tap(find.text('Verification'));
      await tester.pumpAndSettle();

      expect(
        find.text('Independent testing and brand verification'),
        findsOneWidget,
      );
      expect(find.text('Third-party tested'), findsOneWidget);
    });

    testWidgets('coverage 0.92 shows percentage and high-confidence copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.92));

      expect(find.text('92%'), findsOneWidget);
      expect(find.textContaining('high-confidence'), findsOneWidget);
    });

    testWidgets('coverage 0.5 shows percentage and partial-coverage copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.5));

      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('partial coverage'), findsOneWidget);
    });

    testWidgets('coverage 0.15 shows percentage and limited-data copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.15));

      expect(find.text('15%'), findsOneWidget);
      expect(find.textContaining('Limited data'), findsOneWidget);
    });

    testWidgets('coverage clamps out-of-range values to 100%', (tester) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 1.5));

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('150%'), findsNothing);
    });

    testWidgets('coverage line hidden when mappedCoverage is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(formulation: 20));

      expect(find.textContaining('database'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });
  });
}

Map<String, dynamic> _v4Pillars({
  double? formulation,
  double? dose,
  double? evidence,
  double? transparency,
  double? verification,
  double? safetyHygiene,
}) {
  return {
    'formulation': {
      'score': formulation,
      'max': 20,
      'reason': 'Form, dosage, and bioavailability',
    },
    'dose': {
      'score': dose,
      'max': 20,
      'reason': 'Serving strength and studied ranges',
    },
    'evidence': {
      'score': evidence,
      'max': 20,
      'reason': 'Clinical support behind ingredients',
    },
    'transparency': {
      'score': transparency,
      'max': 15,
      'reason': 'Label clarity and disclosure',
    },
    'verification': {
      'score': verification,
      'max': 15,
      'reason': 'Independent testing and brand verification',
    },
    'safety_hygiene': {
      'score': safetyHygiene,
      'max': 10,
      'reason': 'Clean-label and contaminant risk checks',
    },
  };
}
