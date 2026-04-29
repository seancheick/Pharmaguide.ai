// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.7.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/unknowns_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool isTrustedManufacturer = false,
  bool hasThirdPartyTesting = false,
  double? mappedCoverage,
  double? scoreEvidenceResearch,
  double? scoreEvidenceResearchMax,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UnknownsSection(
          isTrustedManufacturer: isTrustedManufacturer,
          hasThirdPartyTesting: hasThirdPartyTesting,
          mappedCoverage: mappedCoverage,
          scoreEvidenceResearch: scoreEvidenceResearch,
          scoreEvidenceResearchMax: scoreEvidenceResearchMax,
        ),
      ),
    ),
  );
}

void main() {
  group('buildUnknowns — pure logic', () {
    test('all positive signals → empty list', () {
      // Trusted + third-party tested + 90% mapped + strong evidence
      // → nothing to flag.
      expect(
        buildUnknowns(
          isTrustedManufacturer: true,
          hasThirdPartyTesting: true,
          mappedCoverage: 0.9,
          scoreEvidenceResearch: 18,
          scoreEvidenceResearchMax: 20,
        ),
        isEmpty,
      );
    });

    test('untrusted manufacturer → "no recent COAs" bullet', () {
      final unknowns = buildUnknowns(
        isTrustedManufacturer: false,
        hasThirdPartyTesting: true,
        mappedCoverage: 0.9,
        scoreEvidenceResearch: 18,
        scoreEvidenceResearchMax: 20,
      );
      expect(unknowns, hasLength(1));
      expect(unknowns.first, contains('COA'));
    });

    test('no third-party testing → "no heavy metal test" bullet', () {
      final unknowns = buildUnknowns(
        isTrustedManufacturer: true,
        hasThirdPartyTesting: false,
        mappedCoverage: 0.9,
        scoreEvidenceResearch: 18,
        scoreEvidenceResearchMax: 20,
      );
      expect(unknowns, hasLength(1));
      expect(unknowns.first, contains('third-party'));
      expect(unknowns.first, contains('heavy metal'));
    });

    test('mappedCoverage at 0.49 (just below threshold) → coverage bullet', () {
      final unknowns = buildUnknowns(
        isTrustedManufacturer: true,
        hasThirdPartyTesting: true,
        mappedCoverage: 0.49,
        scoreEvidenceResearch: 18,
        scoreEvidenceResearchMax: 20,
      );
      expect(unknowns, hasLength(1));
      expect(unknowns.first, contains('mapped to our database'));
    });

    test('mappedCoverage at 0.5 (boundary) → no coverage bullet', () {
      // The threshold is `< 0.5` strictly — 0.5 exactly is fine.
      expect(
        buildUnknowns(
          isTrustedManufacturer: true,
          hasThirdPartyTesting: true,
          mappedCoverage: 0.5,
          scoreEvidenceResearch: 18,
          scoreEvidenceResearchMax: 20,
        ),
        isEmpty,
      );
    });

    test('evidence < 40% of max → "limited clinical research" bullet', () {
      // 7/20 = 35% — below the 40% threshold.
      final unknowns = buildUnknowns(
        isTrustedManufacturer: true,
        hasThirdPartyTesting: true,
        mappedCoverage: 0.9,
        scoreEvidenceResearch: 7,
        scoreEvidenceResearchMax: 20,
      );
      expect(unknowns, hasLength(1));
      expect(unknowns.first, contains('Limited clinical'));
    });

    test('evidence at exactly 40% → no evidence bullet (boundary)', () {
      // 8/20 = 40% — on the threshold.
      expect(
        buildUnknowns(
          isTrustedManufacturer: true,
          hasThirdPartyTesting: true,
          mappedCoverage: 0.9,
          scoreEvidenceResearch: 8,
          scoreEvidenceResearchMax: 20,
        ),
        isEmpty,
      );
    });

    test('null mappedCoverage → coverage check skipped', () {
      // No coverage data shipped → can't evaluate; should NOT
      // surface as an unknown (the absence of the data is itself
      // worth flagging via a different surface, but not here).
      expect(
        buildUnknowns(
          isTrustedManufacturer: true,
          hasThirdPartyTesting: true,
          mappedCoverage: null,
          scoreEvidenceResearch: 18,
          scoreEvidenceResearchMax: 20,
        ),
        isEmpty,
      );
    });

    test('null scoreEvidenceResearch / max → evidence check skipped', () {
      expect(
        buildUnknowns(
          isTrustedManufacturer: true,
          hasThirdPartyTesting: true,
          mappedCoverage: 0.9,
          scoreEvidenceResearch: null,
          scoreEvidenceResearchMax: null,
        ),
        isEmpty,
      );
    });

    test('scoreEvidenceResearchMax == 0 (defensive) → no divide-by-zero', () {
      expect(
        buildUnknowns(
          isTrustedManufacturer: true,
          hasThirdPartyTesting: true,
          mappedCoverage: 0.9,
          scoreEvidenceResearch: 0,
          scoreEvidenceResearchMax: 0,
        ),
        isEmpty,
      );
    });

    test('all four unknowns trigger → 4 bullets in display order', () {
      // Spec display order: third-party → COA → coverage → evidence.
      final unknowns = buildUnknowns(
        isTrustedManufacturer: false,
        hasThirdPartyTesting: false,
        mappedCoverage: 0.2,
        scoreEvidenceResearch: 2,
        scoreEvidenceResearchMax: 20,
      );
      expect(unknowns, hasLength(4));
      expect(unknowns[0], contains('third-party'));
      expect(unknowns[1], contains('COA'));
      expect(unknowns[2], contains('mapped'));
      expect(unknowns[3], contains('Limited clinical'));
    });
  });

  group('UnknownsSection — render', () {
    testWidgets('all positive signals → section hides entirely', (
      tester,
    ) async {
      await _pump(
        tester,
        isTrustedManufacturer: true,
        hasThirdPartyTesting: true,
        mappedCoverage: 0.9,
        scoreEvidenceResearch: 18,
        scoreEvidenceResearchMax: 20,
      );
      await tester.pumpAndSettle();

      expect(find.text('What we don\'t know'), findsNothing);
    });

    testWidgets('one unknown → header + 1 bullet renders', (tester) async {
      await _pump(
        tester,
        isTrustedManufacturer: true,
        hasThirdPartyTesting: false,
        mappedCoverage: 0.9,
        scoreEvidenceResearch: 18,
        scoreEvidenceResearchMax: 20,
      );
      await tester.pumpAndSettle();

      expect(find.text('What we don\'t know'), findsOneWidget);
      expect(
        find.text('No third-party heavy metal test available'),
        findsOneWidget,
      );
    });

    testWidgets('multiple unknowns → all render', (tester) async {
      await _pump(
        tester,
        isTrustedManufacturer: false,
        hasThirdPartyTesting: false,
        mappedCoverage: 0.3,
      );
      await tester.pumpAndSettle();

      expect(find.text('What we don\'t know'), findsOneWidget);
      expect(
        find.text('No third-party heavy metal test available'),
        findsOneWidget,
      );
      expect(
        find.text('Manufacturer hasn\'t published recent COAs'),
        findsOneWidget,
      );
      expect(
        find.text('Some ingredients couldn\'t be mapped to our database'),
        findsOneWidget,
      );
    });

    testWidgets('low coverage product → coverage line renders', (tester) async {
      await _pump(
        tester,
        isTrustedManufacturer: true,
        hasThirdPartyTesting: true,
        mappedCoverage: 0.25,
        scoreEvidenceResearch: 18,
        scoreEvidenceResearchMax: 20,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Some ingredients couldn\'t be mapped to our database'),
        findsOneWidget,
      );
    });

    testWidgets('all 4 unknowns → all 4 bullets render with no overflow line', (
      tester,
    ) async {
      await _pump(
        tester,
        isTrustedManufacturer: false,
        hasThirdPartyTesting: false,
        mappedCoverage: 0.2,
        scoreEvidenceResearch: 2,
        scoreEvidenceResearchMax: 20,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No third-party heavy metal test available'),
        findsOneWidget,
      );
      expect(
        find.text('Manufacturer hasn\'t published recent COAs'),
        findsOneWidget,
      );
      expect(
        find.text('Some ingredients couldn\'t be mapped to our database'),
        findsOneWidget,
      );
      expect(find.text('Limited clinical research data'), findsOneWidget);

      // 4 is the cap — at exactly 4 there's no overflow line.
      expect(find.textContaining('… and'), findsNothing);
    });
  });
}
