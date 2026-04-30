// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, "IA structure".
//
// Pin-the-order regression test for the post-2026-04-29 dev-review
// fix. The pre-review render was:
//   §5 Tradeoffs FIRST, then §4 Ingredients (wrong)
//   _InteractionConditionDetails between §4 and §6 (wrong — should
//   be in the §7 grouping)
//
// This test catches both regressions by mounting `DetailSection`
// with enough fixture data to fire every branch and asserting the
// vertical order (top→bottom) of the rendered section widgets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredients_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/populations_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/tradeoffs_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/unknowns_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/with_your_stack_section.dart';

/// Minimal `detail_blob` shape that fires every section branch:
/// has actives + inactives, has score_bonuses + score_penalties
/// (Tradeoffs), has interaction_summary (legacy condition block),
/// has populationWarnings on the warnings (Populations).
Map<String, dynamic> _fullDetailBlob() {
  return {
    'ingredients': [
      {'name': 'Magnesium glycinate', 'dose_amount': 200, 'dose_unit': 'mg'},
    ],
    'inactive_ingredients': [
      {'name': 'Vegetable cellulose'},
    ],
    // score_bonuses / score_penalties are list-of-Map per
    // _extractWhyItems (line 1455-1463). Plain strings would be
    // filtered out by `whereType<Map<String, dynamic>>()`.
    'score_bonuses': <Map<String, dynamic>>[
      {'label': 'Third-party tested', 'detail': 'NSF certified'},
    ],
    'score_penalties': <Map<String, dynamic>>[
      {'label': 'Proprietary blend', 'detail': 'Hides individual doses'},
    ],
    // `interaction_summary` is a Map in the live pipeline shape — see
    // product_detail_screen.dart:2231 (`blob['interaction_summary'] as
    // Map`). Passing a String here would crash with a type error
    // before the section even tries to render.
    'interaction_summary': <String, dynamic>{
      'condition_details': <Map<String, dynamic>>[],
      'drug_class_details': <Map<String, dynamic>>[],
    },
    'manufacturer_info': {'name': 'Test Manufacturer', 'country': 'USA'},
  };
}

/// Drug-class-tagged warning so WithYourStackSection has a row to
/// render against the user profile we'll inject.
List<InteractionWarning> _warningsWithStackMatch() {
  return [
    const InteractionWarning(
      severity: Severity.caution,
      evidenceLevel: EvidenceLevel.theoretical,
      title: 'May increase bleeding risk',
      mechanism: 'Antiplatelet effect',
      management: 'Discuss with your doctor before combining.',
      drugClassIds: ['anticoagulants'],
      populationWarnings: ['Pregnancy', 'Children'],
    ),
  ];
}

Widget _wrap(CoreDatabase coreDb, UserDatabase userDb, Widget child) {
  return ProviderScope(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      userDatabaseProvider.overrideWithValue(userDb),
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// Returns the vertical Y-coordinate (top edge) of the first widget
/// of [type] in the tree. Throws if not found.
double _topOf(WidgetTester tester, Type type) {
  final element = tester.elementList(find.byType(type)).firstOrNull;
  if (element == null) {
    throw StateError('Widget of type $type not in tree');
  }
  final renderBox = element.renderObject as RenderBox?;
  if (renderBox == null) {
    throw StateError('No RenderBox for $type');
  }
  return renderBox.localToGlobal(Offset.zero).dy;
}

void main() {
  group('DetailSection — IA section ordering (post-2026-04-29 dev review)', () {
    testWidgets('sections render in spec order: §4 → §5 → §6 → §7 → §8 → §10', (
      tester,
    ) async {
      // Larger viewport so SingleChildScrollView lays out everything
      // in one frame — we read top-edges and need them all visible.
      tester.view.physicalSize = const Size(420, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        _wrap(
          coreDb,
          userDb,
          DetailSection(
            detailBlob: _fullDetailBlob(),
            warnings: _warningsWithStackMatch(),
            isTrustedManufacturer: false,
            hasThirdPartyTesting: false,
            mappedCoverage: 0.3,
            scoreEvidenceResearch: 4,
            scoreEvidenceResearchMax: 20,
            dosingSummary: '1 capsule daily',
            servingsPerContainer: 60,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Grab top-edge Y for each section. Tradeoffs must come AFTER
      // ingredients; UnknownsSection AFTER Tradeoffs; the §7 group
      // (WithYourStack + InteractionWarningsList) AFTER Unknowns;
      // PopulationsSection AFTER §7. T17 (2026-04-30) — bottom
      // ProductDetailsSection deleted, no longer asserted.
      final tradeoffsY = _topOf(tester, TradeoffsSection);
      final unknownsY = _topOf(tester, UnknownsSection);
      final withYourStackY = _topOf(tester, WithYourStackSection);
      final interactionListY = _topOf(tester, InteractionWarningsList);
      final populationsY = _topOf(tester, PopulationsSection);

      // T16 (2026-04-30) — ingredients now live inside an
      // `IngredientsCard` (single elevated card containing both
      // active + inactive sub-sections). Anchor via the widget type
      // instead of the previous "Other Ingredients" header text.
      // T20 will rebuild this whole pin-the-order test against the
      // post-S2.2 IA; this fix keeps the existing assertion passing
      // until then.
      final inactiveHeaderY = _topOf(tester, IngredientsCard);

      // Spec ordering: §4 (ingredients) → §5 (Tradeoffs) → §6
      // (Unknowns) → §7 (WithYourStack + InteractionWarningsList)
      // → §8 (Populations) → §10 (Product Details).
      expect(
        inactiveHeaderY < tradeoffsY,
        isTrue,
        reason:
            'Tradeoffs (§5) must render below Inactive '
            'Ingredients (§4)',
      );
      expect(
        tradeoffsY < unknownsY,
        isTrue,
        reason: 'Unknowns (§6) must render below Tradeoffs (§5)',
      );
      expect(
        unknownsY < withYourStackY,
        isTrue,
        reason:
            'WithYourStack (§7.1) must render below Unknowns '
            '(§6)',
      );
      expect(
        withYourStackY < interactionListY,
        isTrue,
        reason:
            'InteractionWarningsList (§7.2 legacy) must '
            'render below WithYourStack (§7.1) — both inside the '
            '§7 grouping',
      );
      expect(
        interactionListY < populationsY,
        isTrue,
        reason:
            'Populations (§8) must render below the §7 '
            'interaction grouping',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });
  });
}
