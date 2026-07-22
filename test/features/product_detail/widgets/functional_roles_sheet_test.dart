// Tests for the functional-roles bottom sheet (the inactive-ingredient
// tap target). Ported from the legacy `ingredients_card_test.dart` to
// exercise the public `showFunctionalRolesSheet` helper directly so
// these tests survive after the v1 IngredientsCard widget is retired
// (Phase 11.11 hygiene — Sean 2026-05-17 "leaving nothing behind").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/data/functional_roles_vocab.dart';
import 'package:pharmaguide/features/product_detail/widgets/functional_roles_sheet.dart';

/// Mounts a tiny host widget that exposes a Button which calls
/// `showFunctionalRolesSheet(ctx, ingredient)`. Lets us assert sheet
/// content without coupling to any specific parent widget.
Future<void> _pumpAndOpenSheet(
  WidgetTester tester,
  Map<String, dynamic> ingredient,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showFunctionalRolesSheet(ctx, ingredient),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    debugSetFunctionalRolesVocabForTesting({
      'lubricant': const FunctionalRoleEntry(
        id: 'lubricant',
        name: 'Lubricant',
        notes: 'Keeps powder from sticking during pressing.',
        regulatoryReferences: [
          RegulatoryReference(jurisdiction: 'FDA', code: '21 CFR 170.3(o)(18)'),
        ],
        examples: ['magnesium stearate', 'stearic acid'],
      ),
      'anti_caking_agent': const FunctionalRoleEntry(
        id: 'anti_caking_agent',
        name: 'Anti-caking agent',
        notes: 'Prevents clumping in powdered formulations.',
        regulatoryReferences: [],
        examples: ['silicon dioxide'],
      ),
    });
  });

  tearDown(() {
    debugSetFunctionalRolesVocabForTesting(null);
  });

  testWidgets(
    'sheet with known functional_roles renders matched role sections',
    (tester) async {
      await _pumpAndOpenSheet(tester, const {
        'name': 'Magnesium Stearate',
        'functional_roles': ['lubricant', 'anti_caking_agent'],
      });

      // Header echoes the ingredient name.
      expect(find.text('Magnesium Stearate'), findsOneWidget);

      // Each matched role renders its own section with vocab name +
      // verbatim notes (clinician-locked copy).
      expect(find.text('Lubricant'), findsOneWidget);
      expect(
        find.text('Keeps powder from sticking during pressing.'),
        findsOneWidget,
      );
      expect(find.text('Anti-caking agent'), findsOneWidget);
      expect(
        find.text('Prevents clumping in powdered formulations.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('sheet with empty functional_roles renders generic fallback', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'name': 'Mystery Excipient',
      'functional_roles': <String>[],
    });

    expect(find.text('Mystery Excipient'), findsOneWidget);
    expect(
      find.text('Inactive ingredient — added during manufacturing.'),
      findsOneWidget,
    );
  });

  testWidgets('sheet with unknown role ids falls back when vocab misses', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'name': 'Edge Case',
      'functional_roles': ['not_in_vocab'],
    });

    expect(find.text('Edge Case'), findsOneWidget);
    expect(
      find.text('Inactive ingredient — added during manufacturing.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'sheet header falls back to raw_source_text when name is missing',
    (tester) async {
      await _pumpAndOpenSheet(tester, const {
        'raw_source_text': 'Microcrystalline cellulose',
        'functional_roles': <String>[],
      });

      expect(find.text('Microcrystalline cellulose'), findsOneWidget);
    },
  );

  testWidgets(
    'sheet header falls back to "Inactive ingredient" when both name and raw_source_text are missing',
    (tester) async {
      await _pumpAndOpenSheet(tester, const {'functional_roles': <String>[]});

      expect(find.text('Inactive ingredient'), findsOneWidget);
    },
  );
}
