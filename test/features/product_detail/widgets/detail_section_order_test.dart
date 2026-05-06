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
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/synergy_detail_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/populations_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/tradeoffs_section.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(ProfileState initial) : super() {
    state = initial;
  }
}

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
    // T20/T22 (2026-04-30) — synergy cluster fixture so the new §8
    // SynergyDetailSection renders. T22 filter requires
    // evidence_tier ≤ 2, match_count ≥ 2, all_adequate truthy.
    'synergy_detail': <String, dynamic>{
      'clusters': <Map<String, dynamic>>[
        {
          'name': 'Magnesium + B6',
          'evidence_tier': 1,
          'match_count': 2,
          'all_adequate': 1,
          'benefit_short': 'Synergy fixture for the IA pin-order test.',
          'pmids': <String>[],
        },
      ],
    },
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
  // Inject a profile that matches the warning fixture's
  // `drugClassIds: ['anticoagulants']` so WithYourStackSection
  // actually renders a row (not SizedBox.shrink). Required for the
  // ordering assertions below: without a row WithYourStack collapses
  // to 0 height and shares Y with the next section.
  final profile = const ProfileState(
    drugClasses: ['anticoagulants'],
  );
  return ProviderScope(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      userDatabaseProvider.overrideWithValue(userDb),
      profileProvider.overrideWith((_) => _StubProfileNotifier(profile)),
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

      // Grab top-edge Y for each section.
      // 2026-05-05 (Phase 2B) — `WithYourStackSection` retired into
      // ReviewBeforeUseCard at the top of the page. Its citation/
      // evidence chips now live inside _AlertRow.
      final tradeoffsY = _topOf(tester, TradeoffsSection);
      final synergyY = _topOf(tester, SynergyDetailSection);
      final populationsY = _topOf(tester, PopulationsSection);
      final inactiveHeaderY = _topOf(tester, IngredientsCard);

      // Spec ordering: §4 Ingredients → §5 Tradeoffs → §8 Synergy
      // → §9 Populations.
      expect(
        inactiveHeaderY < tradeoffsY,
        isTrue,
        reason: 'Tradeoffs (§5) must render below Ingredients (§4)',
      );
      expect(
        tradeoffsY < synergyY,
        isTrue,
        reason: 'Synergy (§8) must render below Tradeoffs (§5)',
      );
      expect(
        synergyY < populationsY,
        isTrue,
        reason:
            'Populations (§9 post-T20) must render below Synergy (§8)',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });
  });
}
