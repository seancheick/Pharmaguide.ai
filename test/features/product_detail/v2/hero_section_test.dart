import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';
import 'package:pharmaguide/core/presentation/package_identity.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/hero_section.dart';

void main() {
  group('hero package identity', () {
    test('uses net contents instead of servings as package quantity', () {
      expect(
        packageSizeLabel(
          quantity: 90,
          unit: 'Softgel(s)',
          fallbackFormFactor: 'softgel',
        ),
        '90 softgels',
      );
      expect(packageServingCountLabel(45), '45 servings');
    });

    test('keeps powder net weight truthful', () {
      expect(
        packageSizeLabel(
          quantity: 2.8,
          unit: 'Ounce(s)',
          fallbackFormFactor: 'powder',
        ),
        '2.8 oz',
      );
    });
  });

  group('score confidence drivers', () {
    test('selects consumer labels from sections matching the overall band', () {
      expect(
        scoreConfidenceDriverLabels({
          'band': 'low',
          'evidence': {
            'level': 'low',
            'drivers': ['no_clinical_evidence_matched'],
          },
          'verification': {
            'level': 'moderate',
            'drivers': ['no_verified_third_party_certification'],
          },
        }),
        ['Clinical evidence review is incomplete'],
      );
    });

    test(
      'renders the typed provisional-review driver without judging quality',
      () {
        expect(
          scoreConfidenceDriverLabels({
            'band': 'moderate',
            'evidence': {
              'level': 'moderate',
              'drivers': ['evidence_review_incomplete'],
            },
          }),
          ['Clinical evidence review is incomplete'],
        );
      },
    );

    test('returns at most two distinct dominant moderate drivers', () {
      expect(
        scoreConfidenceDriverLabels({
          'band': 'moderate',
          'label_completeness': {
            'level': 'moderate',
            'drivers': ['dose_not_disclosed'],
          },
          'identity': {
            'level': 'moderate',
            'drivers': ['form_factor_inferred'],
          },
          'verification': {
            'level': 'moderate',
            'drivers': ['no_verified_third_party_certification'],
          },
        }),
        ['Dose disclosure incomplete', 'Product form inferred'],
      );
    });

    test('malformed or positive-only detail emits no consumer driver', () {
      expect(scoreConfidenceDriverLabels(null), isEmpty);
      expect(
        scoreConfidenceDriverLabels({
          'band': 'high',
          'verification': {
            'level': 'high',
            'drivers': ['cert_sku_verified'],
          },
        }),
        isEmpty,
      );
    });
  });

  testWidgets('package, servings, and dosing are separate subtitle facts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PGHeroSection(
            imageWidget: SizedBox.shrink(),
            productName: 'Ultimate Omega',
            brandName: 'Nordic Naturals',
            servingsLabel: '90 softgels',
            servingCountLabel: '45 servings',
            dosingSummary: 'Take 2 softgels daily',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('90 softgels'), findsOneWidget);
    expect(find.textContaining('45 servings'), findsOneWidget);
    expect(find.textContaining('Take 2 softgels daily'), findsOneWidget);
  });

  testWidgets('hero renders the pipeline tier instead of re-banding score', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PGHeroSection(
            imageWidget: SizedBox.shrink(),
            productName: 'Rounded score canary',
            brandName: 'Test',
            score: 80,
            qualityTier: 'Acceptable',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('80/100'), findsOneWidget);
    expect(find.text('Acceptable'), findsOneWidget);
    expect(find.text('Strong'), findsNothing);
  });
}
