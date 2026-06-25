import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_personal_fit_card.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/personal_fit_helpers.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required FitDisplay fit,
  required String headline,
  List<String> bullets = const [],
  VoidCallback? onEditProfile,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: PGPersonalFitCard(
            fit: fit,
            headline: headline,
            bullets: bullets,
            onEditProfile: onEditProfile ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Personal fit helpers — headline per FitDisplay state', () {
    test('FitStrongMatch with goal label', () {
      expect(
        personalFitHeadline(const FitStrongMatch(), 'sleep'),
        'Strong match for your sleep goal',
      );
    });

    test('FitGoodMatch with goal label', () {
      expect(
        personalFitHeadline(const FitGoodMatch(), 'energy'),
        'Good match for your energy goal',
      );
    });

    test('FitLimitedFit without goal label', () {
      expect(
        personalFitHeadline(const FitLimitedFit(), null),
        'Neutral for your profile',
      );
    });

    test('FitNotRecommended', () {
      expect(
        personalFitHeadline(const FitNotRecommended(), null),
        'Not recommended for your profile',
      );
    });

    test('FitIncomplete', () {
      expect(
        personalFitHeadline(const FitIncomplete(), null),
        'Add your profile to personalize',
      );
    });
  });

  group('Personal fit helpers — causal bullets', () {
    test(
      'positive-profile bullets surface for matching condition and ingredient',
      () {
        final bullets = personalFitBullets(
          fit: const FitGoodMatch(),
          fitReasons: const [],
          ingredientNames: const ['Magnesium'],
          userConditions: const ['hypertension'],
        );

        expect(
          bullets,
          contains('Magnesium supports your blood pressure goal'),
        );
      },
    );

    test('cap at 2 bullets across positive and fallback reasons', () {
      final bullets = personalFitBullets(
        fit: const FitGoodMatch(),
        ingredientNames: const ['Vitamin D', 'Magnesium'],
        userConditions: const ['hypertension', 'diabetes'],
        fitReasons: const ['Backed by clinical evidence.'],
      );

      expect(bullets.length, lessThanOrEqualTo(2));
    });

    test('falls back to fitReasons when no positive bullets fit', () {
      final bullets = personalFitBullets(
        fit: const FitGoodMatch(),
        ingredientNames: const ['Vitamin D'],
        userConditions: const [],
        fitReasons: const [
          'Supports your sleep quality goal.',
          'Backed by clinical evidence.',
        ],
      );

      expect(bullets, [
        'Supports your sleep quality goal',
        'Backed by clinical evidence',
      ]);
    });

    test(
      'mixes positive bullet with fallback when only one positive fires',
      () {
        final bullets = personalFitBullets(
          fit: const FitGoodMatch(),
          ingredientNames: const ['Magnesium'],
          userConditions: const ['hypertension'],
          fitReasons: const ['Backed by clinical evidence.'],
        );

        expect(bullets, [
          'Magnesium supports your blood pressure goal',
          'Backed by clinical evidence',
        ]);
      },
    );

    test('FitHidden suppresses bullets', () {
      final bullets = personalFitBullets(
        fit: const FitHidden(verdict: Severity.avoid),
        ingredientNames: const ['Magnesium'],
        userConditions: const ['hypertension'],
        fitReasons: const ['Backed by clinical evidence.'],
      );

      expect(bullets, isEmpty);
    });

    test('FitIncomplete suppresses bullets', () {
      final bullets = personalFitBullets(
        fit: const FitIncomplete(),
        ingredientNames: const ['Magnesium'],
        userConditions: const ['hypertension'],
        fitReasons: const ['Backed by clinical evidence.'],
      );

      expect(bullets, isEmpty);
    });

    test('drops condition-warning reasons that leaked from fit engine', () {
      final bullets = personalFitBullets(
        fit: const FitGoodMatch(),
        ingredientNames: const [],
        userConditions: const [],
        fitReasons: const [
          'Diabetes: monitor from Vitamin D',
          'Hypertension: monitor from Magnesium',
          'Backed by clinical evidence.',
          'Supports your sleep quality goal.',
        ],
      );

      expect(bullets, [
        'Backed by clinical evidence',
        'Supports your sleep quality goal',
      ]);
    });
  });

  group('PGPersonalFitCard rendering', () {
    testWidgets('renders headline and causal bullets', (tester) async {
      await _pumpCard(
        tester,
        fit: const FitGoodMatch(),
        headline: 'Good match for your sleep goal',
        bullets: const [
          'Magnesium supports your blood pressure goal',
          'Backed by clinical evidence',
        ],
      );

      expect(find.text('PROFILE RELEVANCE'), findsOneWidget);
      expect(find.text('Good match for your sleep goal'), findsOneWidget);
      expect(
        find.text('Magnesium supports your blood pressure goal'),
        findsOneWidget,
      );
      expect(find.text('Backed by clinical evidence'), findsOneWidget);
    });

    testWidgets('FitHidden renders nothing', (tester) async {
      await _pumpCard(
        tester,
        fit: const FitHidden(verdict: Severity.avoid),
        headline: 'Not recommended for your profile',
      );

      expect(find.text('Not recommended for your profile'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('edit pencil tap fires callback', (tester) async {
      var taps = 0;
      await _pumpCard(
        tester,
        fit: const FitGoodMatch(),
        headline: 'Good match for your profile',
        onEditProfile: () => taps++,
      );

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('edit pencil renders for all visible fit states', (
      tester,
    ) async {
      for (final fit in [
        const FitStrongMatch(),
        const FitGoodMatch(),
        const FitLimitedFit(),
        const FitNotRecommended(),
        const FitIncomplete(),
      ]) {
        await _pumpCard(
          tester,
          fit: fit,
          headline: personalFitHeadline(fit, null),
        );

        expect(
          find.byIcon(Icons.edit_outlined),
          findsOneWidget,
          reason: 'Edit pencil missing for $fit',
        );
      }
    });
  });
}
