// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T12.
//
// Verifies the Personal Fit card's:
//   - headline copy per FitDisplay state
//   - causal bullets prioritize T3 Path A's
//     `generatePositiveProfileBullets` over fitReasons fallback
//   - 2-bullet cap
//   - edit pencil fires the onEditProfile callback
//   - hidden / not-recommended / incomplete states render headline
//     only (no bullets — bullets would be inappropriate or premature)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/personal_fit_card.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(ProfileState initial) : super() {
    state = initial;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required FitDisplay fit,
  List<String> ingredientNames = const [],
  List<String> fitReasons = const [],
  String? topGoalLabel,
  ProfileState? profile,
  VoidCallback? onEditProfile,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (profile != null)
          profileProvider.overrideWith((_) => _StubProfileNotifier(profile)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: PersonalFitCard(
              fit: fit,
              ingredientNames: ingredientNames,
              fitReasons: fitReasons,
              topGoalLabel: topGoalLabel,
              onEditProfile: onEditProfile ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('PersonalFitCard — headline per FitDisplay state', () {
    testWidgets(
      'FitStrongMatch with goal label → "Strong match for your X goal"',
      (tester) async {
        await _pump(tester, fit: const FitStrongMatch(), topGoalLabel: 'sleep');
        expect(find.text('Strong match for your sleep goal'), findsOneWidget);
      },
    );

    testWidgets('FitGoodMatch with goal label → "Good match for your X goal"', (
      tester,
    ) async {
      await _pump(tester, fit: const FitGoodMatch(), topGoalLabel: 'energy');
      expect(find.text('Good match for your energy goal'), findsOneWidget);
    });

    testWidgets('FitLimitedFit + null goal → "Limited fit for your profile"', (
      tester,
    ) async {
      await _pump(tester, fit: const FitLimitedFit());
      expect(find.text('Limited fit for your profile'), findsOneWidget);
    });

    testWidgets('FitNotRecommended → "Not recommended for your profile"', (
      tester,
    ) async {
      await _pump(tester, fit: const FitNotRecommended());
      expect(find.text('Not recommended for your profile'), findsOneWidget);
    });

    testWidgets('FitHidden → renders nothing (T16.1 dedup with hero banner)', (
      tester,
    ) async {
      // T16.1 (2026-04-30) — FitHidden fires exactly when verdict ≥
      // avoid (see fit_display.dart:127-128). The hero card already
      // surfaces a BlockedBanner / "Avoid — relevant to your
      // profile" banner for those severities; PersonalFit drops to
      // SizedBox.shrink to avoid duplicating the message.
      await _pump(tester, fit: const FitHidden(verdict: Severity.avoid));
      expect(find.text('Not recommended for your profile'), findsNothing);
      // The card's headline icon (Icons.do_not_disturb_alt_outlined
      // for FitHidden state) and edit pencil should NOT render.
      expect(find.byIcon(Icons.do_not_disturb_alt_outlined), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('FitIncomplete → "Add your profile to personalize"', (
      tester,
    ) async {
      await _pump(tester, fit: const FitIncomplete());
      expect(find.text('Add your profile to personalize'), findsOneWidget);
    });
  });

  group('PersonalFitCard — causal bullets', () {
    testWidgets(
      'positive-profile bullets surface for matching condition × ingredient',
      (tester) async {
        // User with hypertension scans a magnesium product → T3 says
        // magnesium is positive for hypertension → bullet fires.
        await _pump(
          tester,
          fit: const FitGoodMatch(),
          topGoalLabel: 'sleep',
          ingredientNames: const ['Magnesium'],
          profile: const ProfileState(
            goals: ['sleep'],
            conditions: ['hypertension'],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Magnesium supports your blood pressure goal'),
          findsOneWidget,
        );
      },
    );

    testWidgets('cap at 2 bullets — multi-condition + multi-ingredient', (
      tester,
    ) async {
      // 3 positive overlaps possible: Vit D × diabetes, Mg ×
      // hypertension, Mg × diabetes. Card must cap at 2.
      await _pump(
        tester,
        fit: const FitGoodMatch(),
        ingredientNames: const ['Vitamin D', 'Magnesium'],
        profile: const ProfileState(conditions: ['hypertension', 'diabetes']),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Padding), findsWidgets);
      // Count bullet rows: each bullet renders as a Row with a circular
      // dot Container + Expanded Text. Find the Text widgets by their
      // tier-prefix shapes.
      final bps = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('supports your') ?? false),
      );
      expect(bps.evaluate().length, lessThanOrEqualTo(2));
    });

    testWidgets('falls back to fitReasons when no positive bullets fit', (
      tester,
    ) async {
      // User has NO conditions → no positive bullets generated. Card
      // falls through to fitReasons.
      await _pump(
        tester,
        fit: const FitGoodMatch(),
        ingredientNames: const ['Vitamin D'],
        fitReasons: const [
          'Supports your sleep quality goal.',
          'Backed by clinical evidence.',
        ],
        profile: const ProfileState(),
      );
      await tester.pumpAndSettle();
      // Trailing period stripped to match the no-period bullet style.
      expect(find.text('Supports your sleep quality goal'), findsOneWidget);
      expect(find.text('Backed by clinical evidence'), findsOneWidget);
    });

    testWidgets('mixes positive bullet + fallback when only 1 positive fires', (
      tester,
    ) async {
      // 1 positive (Mg × hypertension) + fitReasons fallback fills slot 2.
      await _pump(
        tester,
        fit: const FitGoodMatch(),
        ingredientNames: const ['Magnesium'],
        fitReasons: const ['Backed by clinical evidence.'],
        profile: const ProfileState(conditions: ['hypertension']),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Magnesium supports your blood pressure goal'),
        findsOneWidget,
      );
      expect(find.text('Backed by clinical evidence'), findsOneWidget);
    });

    testWidgets('FitHidden state renders nothing (T16.1 — entire card hidden, '
        'not just bullets)', (tester) async {
      // T16.1 (2026-04-30) — pre-T16.1 this test verified bullets
      // were suppressed for FitHidden. Now the entire card is
      // suppressed (the hero banner already conveys the avoid/
      // contraindicated state). Even with positive ingredient ×
      // condition matches present, nothing renders.
      await _pump(
        tester,
        fit: const FitHidden(verdict: Severity.avoid),
        ingredientNames: const ['Magnesium'],
        profile: const ProfileState(conditions: ['hypertension']),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not recommended for your profile'), findsNothing);
      expect(find.textContaining('supports your'), findsNothing);
    });

    testWidgets('FitIncomplete suppresses bullets — premature', (tester) async {
      await _pump(
        tester,
        fit: const FitIncomplete(),
        fitReasons: const ['some reason'],
      );
      await tester.pumpAndSettle();
      expect(find.text('Add your profile to personalize'), findsOneWidget);
      expect(find.text('some reason'), findsNothing);
    });

    testWidgets(
      'T12.1 — drops condition-warning reasons that leaked from fit engine',
      (tester) async {
        // Sean's live walkthrough caught "Diabetes: monitor from
        // Vitamin D" rendering as bullet 2 even though T4 had
        // suppressed that warning. The fit engine generates reasons
        // through a separate code path; this filter drops them at
        // the bullet-rendering layer.
        await _pump(
          tester,
          fit: const FitGoodMatch(),
          fitReasons: const [
            'Diabetes: monitor from Vitamin D',
            'Hypertension: monitor from Magnesium',
            'Backed by clinical evidence.',
            'Supports your sleep quality goal.',
          ],
        );
        await tester.pumpAndSettle();
        // Condition-warning reasons NOT rendered.
        expect(find.textContaining('Diabetes: monitor'), findsNothing);
        expect(find.textContaining('Hypertension: monitor'), findsNothing);
        // Positive reasons surface.
        expect(find.text('Backed by clinical evidence'), findsOneWidget);
        expect(find.text('Supports your sleep quality goal'), findsOneWidget);
      },
    );
  });

  group('PersonalFitCard — edit pencil', () {
    testWidgets('tap fires onEditProfile callback', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        fit: const FitGoodMatch(),
        onEditProfile: () => taps++,
      );
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('edit pencil renders for all visible fit states', (
      tester,
    ) async {
      // Pencil should be present whenever the card renders — it's
      // the user's escape hatch to fix the profile data. T16.1
      // suppresses the entire card for FitHidden (verdict ≥ avoid),
      // so that state is excluded — the hero banner is the surface
      // there, and the user's primary action is the in-hero CTA,
      // not a profile edit.
      for (final fit in [
        const FitStrongMatch(),
        const FitGoodMatch(),
        const FitLimitedFit(),
        const FitNotRecommended(),
        const FitIncomplete(),
      ]) {
        await _pump(tester, fit: fit);
        expect(
          find.byIcon(Icons.edit_outlined),
          findsOneWidget,
          reason: 'Edit pencil missing for $fit',
        );
      }
    });
  });
}
