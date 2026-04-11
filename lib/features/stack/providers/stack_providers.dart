// Riverpod providers for Sprint 5a Stack wiring.
//
// What lives here:
// - [activeStackProvider] — FutureProvider exposing the user's current
//   active stack (soft-deletes excluded, newest first).
// - [stackEntryForDsldIdProvider] — FutureProvider.family so any widget
//   can ask "is this product already in the stack?" without re-fetching
//   the whole stack.
// - [safetyCheckForAddProvider] — FutureProvider.family that runs the
//   existing StackInteractionChecker against the current stack + the
//   candidate product, returning a list of [InteractionResult]. The UI
//   shows these in the pre-add confirmation sheet (Sprint 5b UI wiring).
// - [stackActionsProvider] — Provider exposing a [StackActions] service
//   with imperative `add` / `remove` / `restore` methods. After every
//   mutation, all dependent providers are invalidated so the UI updates
//   within a frame.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';

/// All non-deleted stack entries, newest first.
final activeStackProvider = FutureProvider<List<UserStacksLocalData>>((ref) {
  final userDb = ref.watch(userDatabaseProvider);
  return userDb.getActiveStack();
});

/// Returns the active (non-deleted) stack entry for a given product, or
/// null if the user has not added that product. Used by product detail
/// screens to toggle between Add-to-Stack / In-Stack states.
///
/// This re-fetches on every call rather than filtering [activeStackProvider]
/// because it's used in a different part of the tree and we want it
/// separately keyed for rebuild isolation.
final stackEntryForDsldIdProvider = FutureProvider.family
    .autoDispose<UserStacksLocalData?, String>((ref, dsldId) async {
  // Take a dependency on the active stack so mutations propagate.
  await ref.watch(activeStackProvider.future);
  final userDb = ref.watch(userDatabaseProvider);
  return userDb.findStackEntryByDsldId(dsldId);
});

/// Runs [StackInteractionChecker] for the candidate product against the
/// current stack. Returns an empty list when the stack is empty or when
/// the product has no flags that could trigger a warning.
///
/// This runs off the bundled core DB only — no network. It's fast enough
/// to await inside a "Verifying safety…" confirmation step.
final safetyCheckForAddProvider = FutureProvider.family
    .autoDispose<List<InteractionResult>, String>((ref, dsldId) async {
  final coreDb = ref.watch(coreDatabaseProvider);
  final userDb = ref.watch(userDatabaseProvider);

  final candidate = await coreDb.findById(dsldId);
  if (candidate == null) return const [];

  final stack = await userDb.getActiveStack();
  if (stack.isEmpty) return const [];

  // Pair each stack entry with its core product row (skip items missing a
  // dsldId — those are hand-entered medications that don't have a fingerprint).
  final stackProducts = <ProductsCoreData>[];
  for (final entry in stack) {
    final id = entry.dsldId;
    if (id == null || id.isEmpty) continue;
    try {
      final product = await coreDb.findById(id);
      if (product != null) stackProducts.add(product);
    } on Exception {
      // Skip broken entries — we're best-effort here.
    }
  }

  if (stackProducts.isEmpty) return const [];

  // Build the fingerprint inputs for the checker.
  Map<String, dynamic> parseFingerprint(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Silently fall through.
    }
    return const {};
  }

  final newFp = parseFingerprint(candidate.ingredientFingerprint);
  final stackFps = stackProducts
      .map((p) => parseFingerprint(p.ingredientFingerprint))
      .toList(growable: false);

  bool flag(int? v) => v == 1;

  return StackInteractionChecker().checkSafety(
    newProductFingerprint: newFp,
    stackFingerprints: stackFps,
    newContainsStimulants: flag(candidate.containsStimulants),
    newContainsSedatives: flag(candidate.containsSedatives),
    newContainsBloodThinners: flag(candidate.containsBloodThinners),
    stackContainsStimulants:
        stackProducts.map((p) => flag(p.containsStimulants)).toList(),
    stackContainsSedatives:
        stackProducts.map((p) => flag(p.containsSedatives)).toList(),
    stackContainsBloodThinners:
        stackProducts.map((p) => flag(p.containsBloodThinners)).toList(),
    stackProductNames:
        stackProducts.map((p) => p.productName).toList(growable: false),
    newProductName: candidate.productName,
  );
});

/// Imperative stack actions (add / remove / restore). Never call directly
/// from a build method — invoke from an onTap or an async user event.
class StackActions {
  final Ref _ref;
  StackActions(this._ref);

  /// Generate a reasonably unique local id. We don't have the `uuid`
  /// package in pubspec, and since stack ids are scoped to a single device
  /// (server assigns its own id on sync), `dsldId + microseconds` is
  /// collision-proof for all realistic uses.
  String _newId(String? dsldId) {
    final base = dsldId ?? 'manual';
    return '${base}_${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Add a product to the stack. Returns the new entry's id so the caller
  /// can show an undo snackbar that references it.
  Future<String> addProduct(ProductsCoreData product) async {
    final userDb = _ref.read(userDatabaseProvider);
    final id = _newId(product.dsldId);
    await userDb.addToStack(
      UserStacksLocalCompanion(
        id: Value(id),
        type: const Value('supplement'),
        name: Value(product.productName),
        dsldId: Value(product.dsldId),
        ingredientKeys: Value(product.ingredientFingerprint),
      ),
    );
    _invalidate();
    _triggerSync();
    return id;
  }

  /// Soft-delete a stack entry (sets `deletedAt`).
  Future<void> remove(String entryId) async {
    final userDb = _ref.read(userDatabaseProvider);
    await userDb.removeFromStack(entryId);
    _invalidate();
    _triggerSync();
  }

  /// Reverse a soft-delete — clears `deletedAt` so the entry re-appears.
  /// Used to implement "Undo" on the remove snackbar.
  Future<void> restore(String entryId) async {
    final userDb = _ref.read(userDatabaseProvider);
    await (userDb.update(userDb.userStacksLocal)
          ..where((t) => t.id.equals(entryId)))
        .write(
      UserStacksLocalCompanion(
        deletedAt: const Value(null),
        clientUpdatedAt: Value(DateTime.now()),
      ),
    );
    _invalidate();
    _triggerSync();
  }

  void _invalidate() {
    _ref.invalidate(activeStackProvider);
    // Family providers invalidate per-key when the root is invalidated;
    // force a broad invalidate so every currently-listening detail screen
    // rebuilds its "in stack?" state.
    _ref.invalidate(stackEntryForDsldIdProvider);
    _ref.invalidate(safetyCheckForAddProvider);
  }

  /// Fire-and-forget sync attempt after every mutation. Silently skips
  /// when offline / guest — the [stackSyncListenerProvider] will catch up
  /// later when the user signs in or connectivity returns.
  void _triggerSync() {
    final service = _ref.read(stackSyncServiceProvider);
    unawaited(service.pushAll());
    _ref.invalidate(pendingSyncCountProvider);
  }
}

final stackActionsProvider = Provider<StackActions>((ref) {
  return StackActions(ref);
});
