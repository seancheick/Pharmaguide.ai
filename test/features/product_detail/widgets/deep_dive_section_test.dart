// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.13.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';
import 'package:pharmaguide/features/product_detail/widgets/excipient_density_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/heavy_metal_warning_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/nutrition_panel.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_detail_sections.dart';
import 'package:pharmaguide/features/product_detail/widgets/unmapped_actives_disclosure.dart';

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

DeepDiveSection _buildSection() {
  // Minimal child params — every inner section either short-circuits
  // on null/empty data (returns SizedBox.shrink) or renders defensively.
  // The point of these tests is the COLLAPSED-BY-DEFAULT toggle, not
  // the inner sections' rendering correctness.
  return const DeepDiveSection(
    dsldId: 'dsld-test',
    activeIngredients: [],
    inactiveIngredients: [],
  );
}

void main() {
  group('DeepDiveSection — T1.13 collapsed-by-default behavior', () {
    testWidgets('renders the toggle header always', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(_wrap(coreDb, userDb, _buildSection()));
      await tester.pump();

      expect(find.text('Deep dive'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('collapsed by default — toggle label reads "Show details"', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(_wrap(coreDb, userDb, _buildSection()));
      await tester.pump();

      // Spec acceptance #1: collapsed initially.
      expect(find.text('Show details'), findsOneWidget);
      expect(find.text('Hide'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('tap header → toggle label flips to "Hide" (expanded state)', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(_wrap(coreDb, userDb, _buildSection()));
      await tester.pump();

      await tester.tap(find.text('Deep dive'));
      // 280ms expand animation.
      await tester.pumpAndSettle();

      // Spec acceptance #2: tap → expands.
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Show details'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('tap a second time → collapses back', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(_wrap(coreDb, userDb, _buildSection()));
      await tester.pump();

      // Expand.
      await tester.tap(find.text('Deep dive'));
      await tester.pumpAndSettle();
      expect(find.text('Hide'), findsOneWidget);

      // Collapse.
      await tester.tap(find.text('Deep dive'));
      await tester.pumpAndSettle();
      expect(find.text('Show details'), findsOneWidget);
      expect(find.text('Hide'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets(
      'all existing deep-dive content preserved (11 inner widgets in tree)',
      (tester) async {
        // Spec acceptance #3: all existing deep-dive content preserved.
        // The Align(heightFactor: 0.0) collapse mechanism keeps inner
        // widgets in the tree (just clipped to 0 height), so find.byType
        // works regardless of expanded state. That's exactly what this
        // test wants to verify — the wrapper didn't drop any sections.
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();

        await tester.pumpWidget(_wrap(coreDb, userDb, _buildSection()));
        await tester.pump();

        // T17 (2026-04-30) — `PairsWellSection` removed from the
        // Deep Dive composition.
        // T20/T22 (2026-04-30) — `SynergyDetailSection` promoted out
        // of Deep Dive to top-level §8. Down to 9 inner widget types.
        expect(find.byType(CertificationDetailSection), findsOneWidget);
        expect(find.byType(EvidenceDetailSection), findsOneWidget);
        expect(find.byType(HeavyMetalWarningCard), findsOneWidget);
        expect(find.byType(ExcipientDensityCard), findsOneWidget);
        expect(find.byType(FormulationDetailSection), findsOneWidget);
        expect(find.byType(ProbioticDetailSection), findsOneWidget);
        expect(find.byType(ManufacturerViolationsSection), findsOneWidget);
        // T18 (2026-04-30) — collapsed inline NutritionPanel into a
        // `NutritionFactsLink` that opens a bottom sheet on tap.
        expect(find.byType(NutritionFactsLink), findsOneWidget);
        expect(find.byType(UnmappedActivesDisclosure), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );
  });
}
