// Personalized interaction warnings for the product detail screen.
//
// Sprint: docs/sprints/product_detail_page_sprint.md — T1B.
//
// Why a provider instead of a one-shot Future in the screen's initState:
// the previous load wrote to a `_personalizedWarnings` field via setState
// and never re-ran when the user mutated their stack. After adding an
// interacting medication on the Stack tab and returning to a product
// page, the page would still claim "no interactions". The provider
// watches `activeStackProvider` (which `StackActions._invalidate` already
// invalidates on every mutation) so the UI always reflects current state.
//
// FitScoreResult and gating behavior live elsewhere; this provider only
// produces the personalized "Because you're taking X" warning rows that
// supplement the static blob-parsed warnings.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

final personalizedInteractionWarningsProvider = FutureProvider.family
    .autoDispose<List<InteractionWarning>, String>((ref, dsldId) async {
      // Watching the active stack ties this provider's lifecycle to stack
      // mutations. addProduct/remove/restore all invalidate
      // activeStackProvider via StackActions._invalidate, which causes
      // this provider to recompute and the screen to rebuild with fresh
      // warnings.
      final List<UserStacksLocalData> stack;
      try {
        stack = await ref.watch(activeStackProvider.future);
      } on UnimplementedError {
        // Test stub for the stack provider — fall back to empty.
        return const [];
      } on Exception catch (e, st) {
        // DB unavailable or transient — degrade to empty rather than
        // surfacing an error in the UI for a non-critical signal, but
        // record it so silent degradation is observable in Sentry.
        CrashReportingService().recordError(
          e,
          st,
          fatal: false,
          hint: 'personalized_warnings:stack_fetch_failed',
        );
        return const [];
      }
      if (stack.isEmpty) return const [];

      final coreDb = ref.watch(coreDatabaseProvider);
      final ProductsCoreData? product;
      try {
        product = await coreDb.findById(dsldId);
      } on UnimplementedError {
        return const [];
      } on Exception catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          fatal: false,
          hint: 'personalized_warnings:product_fetch_failed',
        );
        return const [];
      }
      if (product == null) return const [];

      Map<String, dynamic>? detailBlob;
      try {
        detailBlob = await ref.watch(detailBlobProvider(dsldId).future);
      } on Exception {
        detailBlob = null;
      }
      final canonicalIds = canonicalIdsForProduct(
        product,
        detailBlob: detailBlob,
      );
      if (canonicalIds.isEmpty) return const [];

      final InteractionDatabase interactionDb;
      try {
        interactionDb = ref.watch(interactionDatabaseProvider);
      } on Object catch (e, st) {
        // DB-UNAVAILABLE, not no-hits. When the bundled interaction DB
        // fails to materialize at bootstrap, main.dart leaves
        // interactionDatabaseProvider at its default throwing definition,
        // so this watch fails (a raw UnimplementedError, or a Riverpod
        // ProviderException wrapping it). The ONLY failure mode of this
        // watch is "provider not overridden / in error", so catching
        // broadly is safe here. The previous `on UnimplementedError {
        // return const []; }` was a latent trap: a wrapped or raw error
        // could be swallowed into an empty list that reads byte-for-byte
        // like "no interactions found", silently disabling every
        // med×supplement check while the product page's hedge banner never
        // fires. Record + rethrow so the provider exposes an AsyncError →
        // `personalizedWarningsFailed` flips true and the "couldn't check"
        // banner shows, mirroring Quick Check's "Database unavailable"
        // state. Never suppress this into an empty list.
        CrashReportingService().recordError(
          e,
          st,
          fatal: false,
          hint: 'personalized_warnings:interaction_db_unavailable',
        );
        rethrow;
      }

      return _computePersonalizedWarnings(
        product: product,
        canonicalIds: canonicalIds,
        stack: stack,
        interactionDb: interactionDb,
      );
    });

/// Pure-ish lookup against the bundled InteractionDatabase. Catches
/// non-fatal errors (db missing, test stubs) and degrades to empty.
Future<List<InteractionWarning>> _computePersonalizedWarnings({
  required ProductsCoreData product,
  required List<String> canonicalIds,
  required List<UserStacksLocalData> stack,
  required InteractionDatabase interactionDb,
}) async {
  try {
    final checker = StackInteractionChecker();
    final warnings = <InteractionWarning>[];
    final seenIds = <String>{};

    final supplements = stack
        .where((e) => e.type == 'supplement')
        .toList(growable: false);
    if (supplements.isNotEmpty) {
      final hits = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: canonicalIds,
        stackSupplements: supplements,
        db: interactionDb,
        newProductName: product.productName,
      );
      for (final hit in hits) {
        if (seenIds.add(hit.id)) {
          warnings.add(_interactionResultToWarning(hit));
        }
      }
    }

    final medications = stack
        .where((e) => e.type == 'medication')
        .toList(growable: false);
    if (medications.isNotEmpty) {
      final hits = await checker.checkMedicationInteractions(
        newProductCanonicalIds: canonicalIds,
        stackMedications: medications,
        db: interactionDb,
        newProductName: product.productName,
      );
      for (final hit in hits) {
        if (seenIds.add(hit.id)) {
          warnings.add(_interactionResultToWarning(hit));
        }
      }
    }

    return warnings;
  } on UnimplementedError {
    return const [];
  } on Exception catch (e, st) {
    // Safety-critical: swallowing this would render "no interactions"
    // when the check actually failed. Record + rethrow so the provider
    // exposes an AsyncError the UI can hedge on.
    CrashReportingService().recordError(
      e,
      st,
      hint: 'personalized_warnings:lookup_failed',
    );
    rethrow;
  }
}

/// Maps an [InteractionResult] from the curated DB to an
/// [InteractionWarning] that the existing list widget can render.
/// Adds "Because you're taking [X]" context.
InteractionWarning _interactionResultToWarning(InteractionResult result) {
  return InteractionWarning(
    severity: result.severity,
    evidenceLevel: result.evidenceLevel,
    title: "Because you're taking ${result.agent2Name}",
    mechanism: result.mechanism,
    management: result.management,
    sourceUrls: result.sourceUrls,
  );
}
