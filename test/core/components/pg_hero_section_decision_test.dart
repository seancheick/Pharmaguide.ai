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
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';

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

  group('catalogScoreConfidenceLabel — consumer confidence vocabulary', () {
    test('suppresses routine bands and keeps limited assessments visible', () {
      expect(catalogScoreConfidenceLabel('high'), isNull);
      expect(catalogScoreConfidenceLabel('moderate'), isNull);
      expect(catalogScoreConfidenceLabel('medium'), isNull);
      expect(catalogScoreConfidenceLabel('low'), 'Limited');
      expect(catalogScoreConfidenceLabel('very_low'), 'Limited');
    });

    test('unknown populated bands fail closed to Limited', () {
      expect(catalogScoreConfidenceLabel('experimental'), 'Limited');
    });

    test('missing confidence stays absent', () {
      expect(catalogScoreConfidenceLabel(null), isNull);
      expect(catalogScoreConfidenceLabel('  '), isNull);
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
          scoreConfidenceDrivers: [
            'No clinical evidence matched',
            'Product-level certification not verified',
          ],
        ),
      );
      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Product quality score unavailable.'), findsNothing);
      expect(find.text('Strong'), findsNothing);
      expect(find.text('Limited assessment'), findsOneWidget);
      expect(find.textContaining('Score confidence'), findsNothing);
      expect(find.textContaining('Why:'), findsNothing);
    });

    testWidgets('trusted score renders no confidence band', (tester) async {
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
      expect(find.text('Strong'), findsOneWidget);
      // See the limited-assessment case above — the band is not a hero field.
      expect(find.textContaining('Score confidence'), findsNothing);
    });

    testWidgets('unknown confidence still fails closed on the tier adjective', (
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
      // Unknown bands must STILL fail closed on the tier adjective — that
      // gating is independent of whether the band itself is displayed.
      expect(find.textContaining('Score confidence'), findsNothing);
    });

    testWidgets('confidence drivers stay hidden without a scored result', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Test Product',
          brandName: 'Test Brand',
          isNotScored: true,
          scoreConfidence: 'low',
          scoreConfidenceDrivers: ['No clinical evidence matched'],
        ),
      );
      expect(find.textContaining('Why:'), findsNothing);
      expect(find.textContaining('Score confidence:'), findsNothing);
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
