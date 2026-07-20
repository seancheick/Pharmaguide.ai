import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';
import 'package:pharmaguide/core/presentation/package_identity.dart';

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
}
