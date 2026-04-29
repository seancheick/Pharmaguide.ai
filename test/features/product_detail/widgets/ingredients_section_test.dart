// Tests for InactiveIngredientChip + the inactive-purpose lookup.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.5.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredients_section.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('inactiveIngredientPurpose — lookup contract', () {
    test('known name → returns entry', () {
      final p = inactiveIngredientPurpose('magnesium stearate');
      expect(p, isNotNull);
      expect(p!.role, 'Manufacturing lubricant');
      expect(p.detail, contains('sticking'));
    });

    test('case-insensitive — "Magnesium Stearate" matches', () {
      final p = inactiveIngredientPurpose('Magnesium Stearate');
      expect(p, isNotNull);
      expect(p!.role, 'Manufacturing lubricant');
    });

    test('whitespace-tolerant — "  Gelatin  " matches', () {
      final p = inactiveIngredientPurpose('  Gelatin  ');
      expect(p, isNotNull);
      expect(p!.role, 'Capsule shell');
    });

    test('unknown name → null', () {
      expect(
        inactiveIngredientPurpose('made-up-additive-7'),
        isNull,
      );
    });

    test('empty string → null (defensive)', () {
      expect(inactiveIngredientPurpose(''), isNull);
    });

    test('whitespace-only → null', () {
      expect(inactiveIngredientPurpose('   '), isNull);
    });

    test('all locked excipients (T0.5 whitelist) have a purpose entry', () {
      // Cross-spec gate: the standard-excipients whitelist used by
      // T0.5's purity card lists ingredients the user is most likely
      // to encounter. Every one of those should have an explanation
      // when the user taps the chip — silent fallback is acceptable
      // for niche/unexpected names but not for the canonical set.
      const requiredCoverage = [
        'gelatin',
        'hpmc',
        'hydroxypropyl methylcellulose',
        'vegetable cellulose',
        'plant cellulose',
        'pullulan',
        'magnesium stearate',
        'vegetable magnesium stearate',
        'stearic acid',
        'microcrystalline cellulose',
        'mcc',
        'silicon dioxide',
        'silica',
        'dicalcium phosphate',
        'water',
        'purified water',
      ];
      for (final name in requiredCoverage) {
        expect(
          inactiveIngredientPurpose(name),
          isNotNull,
          reason: 'T0.5 whitelist excipient "$name" must have a '
              'purpose entry — leaving it null falls through to the '
              'generic "added during manufacturing" copy and the user '
              'loses the specific explanation.',
        );
      }
    });

    test('attention-tier names (sucralose, titanium dioxide) explain why', () {
      // For ingredients users have legitimate concerns about, the
      // detail copy should be honest about what they are. Pin a few
      // specifics so future copy edits don't accidentally erase the
      // honesty.
      expect(inactiveIngredientPurpose('sucralose')?.role,
          contains('sweetener'));
      expect(inactiveIngredientPurpose('titanium dioxide')?.role,
          contains('colorant'));
      expect(
        inactiveIngredientPurpose('titanium dioxide')?.detail,
        contains('EU'),
        reason: 'TiO2 detail copy should surface the EU regulatory '
            'context — that\'s why a user would tap the chip.',
      );
    });
  });

  group('InactiveIngredientChip — render', () {
    testWidgets('renders chip with the ingredient name', (tester) async {
      await tester.pumpWidget(
        wrap(const InactiveIngredientChip(name: 'Magnesium Stearate')),
      );
      expect(find.text('Magnesium Stearate'), findsOneWidget);
    });

    testWidgets(
      'long ingredient name doesn\'t crash and stays a chip (no overflow)',
      (tester) async {
        // The chip is intentionally not ellipsis-clipped at the chip
        // level — it can wrap inside the Wrap parent. Just verify
        // the widget renders without throwing.
        const longName = 'Hydroxypropylmethylcellulose Acetate Succinate '
            '(HPMC-AS) — Sustained Release Polymer';
        await tester.pumpWidget(wrap(
          const SizedBox(
            width: 320,
            child: InactiveIngredientChip(name: longName),
          ),
        ));
        expect(find.text(longName), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('InactiveIngredientChip — tap behavior', () {
    testWidgets(
      'tapping a known-name chip opens a sheet with the role + detail copy',
      (tester) async {
        await tester.pumpWidget(
          wrap(const InactiveIngredientChip(name: 'Magnesium Stearate')),
        );

        await tester.tap(find.text('Magnesium Stearate'));
        await tester.pumpAndSettle();

        // The sheet renders the name in a header position (now
        // appears twice in the tree: once on the chip, once on the
        // sheet).
        expect(find.text('Magnesium Stearate'), findsNWidgets(2));
        expect(find.text('Manufacturing lubricant'), findsOneWidget);
        // Detail copy is rendered in the sheet body.
        expect(find.textContaining('sticking'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping an unknown-name chip opens a sheet with generic fallback copy',
      (tester) async {
        await tester.pumpWidget(
          wrap(const InactiveIngredientChip(name: 'made-up-additive-7')),
        );

        await tester.tap(find.text('made-up-additive-7'));
        await tester.pumpAndSettle();

        // No purpose entry → role falls back to "Inactive ingredient"
        // and detail is the generic manufacturing copy.
        expect(find.text('Inactive ingredient'), findsOneWidget);
        expect(
          find.textContaining('manufacturing'),
          findsAtLeastNWidgets(1),
        );
      },
    );

    testWidgets(
      'tapping a sucralose chip surfaces the "artificial sweetener" copy',
      (tester) async {
        // Verify the attention-tier ingredients aren't whitewashed
        // in the bottom sheet.
        await tester.pumpWidget(
          wrap(const InactiveIngredientChip(name: 'Sucralose')),
        );

        await tester.tap(find.text('Sucralose'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Artificial sweetener'), findsOneWidget);
        expect(find.textContaining('sweeter than sugar'), findsOneWidget);
      },
    );
  });

  group('IngredientsSection — wrapper', () {
    testWidgets('passes child through unchanged', (tester) async {
      await tester.pumpWidget(
        wrap(const IngredientsSection(
          child: Text('inner content marker'),
        )),
      );

      expect(find.text('inner content marker'), findsOneWidget);
    });
  });
}
