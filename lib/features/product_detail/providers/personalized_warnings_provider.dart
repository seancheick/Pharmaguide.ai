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

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
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
      } on Exception {
        // DB unavailable or transient — degrade to empty rather than
        // surfacing an error in the UI for a non-critical signal.
        return const [];
      }
      if (stack.isEmpty) return const [];

      final coreDb = ref.read(coreDatabaseProvider);
      final ProductsCoreData? product;
      try {
        product = await coreDb.findById(dsldId);
      } on UnimplementedError {
        return const [];
      } on Exception {
        return const [];
      }
      if (product == null) return const [];

      final canonicalIds = _extractCanonicalIds(
        product.keyIngredientTags,
        product.ingredientFingerprint,
      );
      if (canonicalIds.isEmpty) return const [];

      final InteractionDatabase interactionDb;
      try {
        interactionDb = ref.read(interactionDatabaseProvider);
      } on UnimplementedError {
        return const [];
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
  } on Exception {
    return const [];
  }
}

/// Extract canonical ingredient IDs for interaction matching.
///
/// Primary source: [tagsJson] from `key_ingredient_tags` column — a JSON
/// array like `["iron", "calcium", "vitamin_d"]`.
///
/// Secondary source: `herbs` list inside [fingerprintJson] for herbal
/// products whose canonical IDs live in the fingerprint's herbs array.
List<String> _extractCanonicalIds(String? tagsJson, String? fingerprintJson) {
  final ids = <String>{};

  if (tagsJson != null && tagsJson.isNotEmpty) {
    try {
      final decoded = jsonDecode(tagsJson);
      if (decoded is List) {
        for (final tag in decoded) {
          final s = tag.toString().toLowerCase().trim();
          if (s.isNotEmpty) ids.add(s);
        }
      }
    } on FormatException {
      // Fall through.
    }
  }

  if (fingerprintJson != null && fingerprintJson.isNotEmpty) {
    try {
      final decoded = jsonDecode(fingerprintJson);
      if (decoded is Map) {
        final herbs = decoded['herbs'];
        if (herbs is List) {
          for (final h in herbs) {
            final s = h.toString().toLowerCase().trim();
            if (s.isNotEmpty) ids.add(s);
          }
        }
      }
    } on FormatException {
      // Best-effort.
    }
  }

  return ids.toList(growable: false);
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
