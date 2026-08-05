// FIX 2 (P1) + FIX 4 (P2) regression locks for the hero card.
//
// FIX 2 — the hero score line previously gated only on
// `score != null && !isBlocked && !isNotScored`, so a scored product with
// mapped_coverage < 0.3 rendered a confident tier-colored "85/100" line.
// The pure decision `heroScoreDisplayFor` now owns that gate: low coverage
// renders the neutral score-unavailable line instead (same treatment as
// isNotScored), without exposing catalog diagnostics to consumers.
//
// FIX 4 — positive trust/cert chips ("Third-Party Tested") previously
// rendered on BLOCKED products, above the does-not-recommend banner.
// `heroShowsTrustChips` suppresses the row when isBlocked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';

void main() {
  group('heroScoreDisplayFor — pure render decision', () {
    test('scored + trusted coverage renders the tier score line', () {
      expect(
        heroScoreDisplayFor(
          score: 85,
          isBlocked: false,
          isNotScored: false,
          lowCoverage: false,
        ),
        HeroScoreDisplay.tierScore,
      );
    });

    test('low scoring confidence retains a neutral score presentation', () {
      expect(
        heroScoreDisplayFor(
          score: 84,
          isBlocked: false,
          isNotScored: false,
          lowCoverage: false,
          limitedAssessment: true,
        ),
        HeroScoreDisplay.limitedScore,
      );
    });

    test('blocked renders nothing in the score slot (banner owns it)', () {
      expect(
        heroScoreDisplayFor(
          score: 85,
          isBlocked: true,
          isNotScored: false,
          lowCoverage: false,
        ),
        HeroScoreDisplay.none,
      );
    });

    test('blocked wins over low coverage', () {
      expect(
        heroScoreDisplayFor(
          score: null,
          isBlocked: true,
          isNotScored: false,
          lowCoverage: true,
        ),
        HeroScoreDisplay.none,
      );
    });

    test('not-scored renders the not-scored hedge', () {
      expect(
        heroScoreDisplayFor(
          score: null,
          isBlocked: false,
          isNotScored: true,
          lowCoverage: false,
        ),
        HeroScoreDisplay.notScored,
      );
    });

    test('not-scored wins over low coverage (more specific hedge)', () {
      expect(
        heroScoreDisplayFor(
          score: null,
          isBlocked: false,
          isNotScored: true,
          lowCoverage: true,
        ),
        HeroScoreDisplay.notScored,
      );
    });

    test('null score without the isNotScored flag still renders the '
        'not-scored hedge — a tier line can never be fabricated', () {
      expect(
        heroScoreDisplayFor(
          score: null,
          isBlocked: false,
          isNotScored: false,
          lowCoverage: false,
        ),
        HeroScoreDisplay.notScored,
      );
    });

    test('scored but mapped_coverage < 0.3 suppresses the quality verdict', () {
      expect(
        heroScoreDisplayFor(
          score: 85,
          isBlocked: false,
          isNotScored: false,
          lowCoverage: true,
        ),
        HeroScoreDisplay.notScored,
      );
    });
  });

  group('scoreConfidenceLabel — consumer confidence vocabulary', () {
    test('maps known confidence bands', () {
      expect(scoreConfidenceLabel('high'), 'High');
      expect(scoreConfidenceLabel('moderate'), 'Moderate');
      expect(scoreConfidenceLabel('low'), 'Limited');
      expect(scoreConfidenceLabel('very_low'), 'Limited');
    });

    test('unknown populated bands fail closed to Limited', () {
      expect(scoreConfidenceLabel('experimental'), 'Limited');
    });

    test('missing confidence stays absent', () {
      expect(scoreConfidenceLabel(null), isNull);
      expect(scoreConfidenceLabel('  '), isNull);
    });
  });

  test('catalog caution remains visible on a limited-confidence score', () {
    expect(
      heroShowsCautionCue(
        hasCatalogCaution: true,
        scoreDisplay: HeroScoreDisplay.limitedScore,
      ),
      isTrue,
    );
  });

  group('heroShowsTrustChips — FIX 4 gate', () {
    test('blocked product never shows positive trust chips', () {
      expect(heroShowsTrustChips(isBlocked: true, tagCount: 3), isFalse);
    });

    test('non-blocked product with tags shows the row', () {
      expect(heroShowsTrustChips(isBlocked: false, tagCount: 3), isTrue);
    });

    test('no tags, no row', () {
      expect(heroShowsTrustChips(isBlocked: false, tagCount: 0), isFalse);
    });
  });

  group('PGHeroSection widget', () {
    Future<void> pump(WidgetTester tester, Widget hero) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: hero)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'low coverage replaces the tier score with a neutral fallback',
      (tester) async {
        await pump(
          tester,
          const PGHeroSection(
            imageWidget: SizedBox(),
            productName: 'Test Product',
            brandName: 'Test Brand',
            score: 85,
            lowCoverage: true,
          ),
        );
        expect(find.text('85/100'), findsNothing);
        expect(find.text('Product quality score unavailable.'), findsOneWidget);
      },
    );

    testWidgets('trusted coverage still renders the tier score line', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Test Product',
          brandName: 'Test Brand',
          score: 85,
        ),
      );
      expect(find.text('85/100'), findsOneWidget);
    });

    testWidgets('limited assessment retains score without a tier adjective', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Test Product',
          brandName: 'Test Brand',
          score: 85,
          limitedAssessment: true,
          scoreConfidence: 'low',
        ),
      );
      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Product quality score unavailable.'), findsNothing);
      expect(find.text('Excellent'), findsNothing);
      expect(find.text('Score confidence: Limited'), findsOneWidget);
    });

    testWidgets('trusted score makes its confidence band visible', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Test Product',
          brandName: 'Test Brand',
          score: 85,
          scoreConfidence: 'moderate',
        ),
      );
      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Excellent'), findsOneWidget);
      expect(find.text('Score confidence: Moderate'), findsOneWidget);
    });

    testWidgets('unknown confidence fails closed without hiding the score', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Test Product',
          brandName: 'Test Brand',
          score: 85,
          scoreConfidence: 'future_band',
        ),
      );
      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Excellent'), findsNothing);
      expect(find.text('Score confidence: Limited'), findsOneWidget);
    });

    testWidgets('blocked product hides positive trust chips', (tester) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Test Product',
          brandName: 'Test Brand',
          isBlocked: true,
          trustTags: [
            PGTrustTag(label: 'Third-Party Tested', isCertification: true),
            PGTrustTag(label: 'Gluten-Free', isCertification: false),
          ],
        ),
      );
      expect(find.text('Third-Party Tested'), findsNothing);
      expect(find.text('Gluten-Free'), findsNothing);
    });

    testWidgets('non-blocked product keeps trust chips', (tester) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Test Product',
          brandName: 'Test Brand',
          score: 85,
          trustTags: [
            PGTrustTag(label: 'Third-Party Tested', isCertification: true),
          ],
        ),
      );
      expect(find.text('Third-Party Tested'), findsOneWidget);
    });
  });
}
