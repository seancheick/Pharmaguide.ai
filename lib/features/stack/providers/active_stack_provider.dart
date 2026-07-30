// Active stack provider + imperative [StackActions] — the core CRUD surface
// for the user's supplement/medication stack.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/features/stack/providers/stack_provider_helpers.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';

/// Thrown when [StackActions.addProduct] is called with a product whose
/// verdict is BLOCKED or UNSAFE (FLTR-16). Safety-first defense in
/// depth: the product detail UI normally short-circuits via FLTR-10
/// so a blocked product never reaches the Add button, but the domain
/// layer rejects it anyway so any future path (deep links, bulk
/// import, automation) cannot silently add an unsafe product.
class StackAddBlockedException implements Exception {
  final String dsldId;
  final String verdict;
  const StackAddBlockedException({required this.dsldId, required this.verdict});

  @override
  String toString() =>
      'StackAddBlockedException(dsldId=$dsldId, verdict=$verdict)';
}

/// Thrown when a guest tries to save stack state. Guest mode allows
/// catalog lookups only; saved stack/profile/history are signed-in
/// early-access features.
class StackRequiresSignInException implements Exception {
  const StackRequiresSignInException();

  @override
  String toString() => 'StackRequiresSignInException()';
}

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

/// Imperative stack actions (add / remove / restore). Never call directly
/// from a build method — invoke from an onTap or an async user event.
class StackActions {
  final Ref _ref;
  StackActions(this._ref);

  /// Generate a client-local stack entry id. Sync preserves it remotely, but
  /// resolves state by the authenticated user and DSLD product identity so a
  /// replacement local entry cannot create a second active product row.
  String _newId(String? dsldId) {
    final base = dsldId ?? 'manual';
    return '${base}_${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Add a product to the stack. Returns the new entry's id so the caller
  /// can show an undo snackbar that references it.
  ///
  /// FLTR-16 — rejects BLOCKED/UNSAFE products with
  /// [StackAddBlockedException]. Callers should check verdict up front
  /// and show a friendly message; this guard is the last line of
  /// defense.
  Future<String> addProduct(ProductsCoreData product) async {
    if (isUnsafeVerdict(product.verdict)) {
      throw StackAddBlockedException(
        dsldId: product.dsldId,
        verdict: product.verdict ?? '',
      );
    }
    _requireSignedIn();
    final userDb = _ref.read(userDatabaseProvider);
    final history = _ref.read(healthEventRepositoryProvider);
    final id = _newId(product.dsldId);
    final now = DateTime.now();
    await history.mutateAndAppend(
      () => userDb.addToStack(
        UserStacksLocalCompanion(
          id: Value(id),
          type: const Value('supplement'),
          name: Value(product.productName),
          dsldId: Value(product.dsldId),
          ingredientKeys: Value(jsonEncode(canonicalIdsForProduct(product))),
        ),
      ),
      HealthEventDraft(
        eventType: HealthEventTypes.stackItemAdded,
        source: HealthEventSource.stack,
        subjectType: 'supplement',
        subjectId: id,
        title: 'Started ${product.productName}',
        summary: 'Added to your supplement stack.',
        effectiveAt: now,
        currentValue: {
          'name': product.productName,
          'dsld_id': product.dsldId,
          if (product.brandName != null) 'brand': product.brandName,
        },
      ),
    );
    _invalidate();
    CrashReportingService().log('stack_add_supplement');
    _triggerSync();
    return id;
  }

  /// Add a medication to the stack (M4 §8.5).
  ///
  /// Medications are PHI: they get `type='medication'` so the Supabase
  /// sync layer can refuse to push them. The privacy grep test
  /// (`test/release_gate/phi_medication_no_sync_test.dart`) build-fails
  /// if any sync code path touches a `'medication'` row.
  ///
  /// [rxcui] is the NLM RxNorm concept id (string) — present when the
  /// user picked a specific drug from the autocomplete; null when they
  /// fell back to the offline class picker (`drugClasses` is set
  /// instead).
  ///
  /// [drugClasses] is the list of `class:*` ids the medication belongs
  /// to, JSON-encoded into the `drug_classes` column. Either [rxcui] or
  /// at least one entry in [drugClasses] must be non-empty so the
  /// curated interaction lookup has something to match on.
  ///
  /// We deliberately do NOT call [_triggerSync] for medications — the
  /// sync layer would skip them anyway, but skipping the call entirely
  /// makes the no-sync contract obvious in code review.
  Future<String> addMedication({
    required String name,
    String? rxcui,
    String? genericRxcui,
    List<String> drugClasses = const <String>[],
    List<String> ingredientRxcuis = const <String>[],
    String? dosage,
    String? frequency,
  }) async {
    _requireSignedIn();
    assert(
      (rxcui != null && rxcui.isNotEmpty) || drugClasses.isNotEmpty,
      'medication needs at least one of rxcui or drugClasses to participate '
      'in interaction checks',
    );

    final userDb = _ref.read(userDatabaseProvider);
    final history = _ref.read(healthEventRepositoryProvider);
    final classResolution =
        await MedicationClassBridge(
          db: _ref.read(interactionDatabaseProvider),
        ).resolve(
          selectedRxcui: rxcui,
          genericRxcui: genericRxcui,
          ingredientRxcuis: ingredientRxcuis,
          runtimeClassIds: drugClasses,
        );
    final id = _newId(rxcui != null ? 'rx_$rxcui' : 'med');
    final mergedDrugClasses = classResolution.mergedInteractionClassIds;
    final classesJson = mergedDrugClasses.isEmpty
        ? null
        : jsonEncode(mergedDrugClasses);
    final ingredientsJson = ingredientRxcuis.isEmpty
        ? null
        : jsonEncode(ingredientRxcuis);

    final now = DateTime.now();
    await history.mutateAndAppend(
      () => userDb.addToStack(
        UserStacksLocalCompanion(
          id: Value(id),
          type: const Value('medication'),
          name: Value(name),
          rxcui: Value(rxcui),
          genericRxcui: Value(genericRxcui),
          drugClassesCol: Value(classesJson),
          ingredientRxcuisCol: Value(ingredientsJson),
          dosage: Value(dosage),
          frequency: Value(frequency),
        ),
      ),
      HealthEventDraft(
        eventType: HealthEventTypes.stackItemAdded,
        source: HealthEventSource.stack,
        subjectType: 'medication',
        subjectId: id,
        title: 'Started $name',
        summary: 'Added to your medication list.',
        effectiveAt: now,
        currentValue: {
          'name': name,
          if (dosage != null) 'dosage': dosage,
          if (frequency != null) 'frequency': frequency,
        },
      ),
    );
    _invalidate();
    CrashReportingService().log('stack_add_medication');
    // Intentionally NOT calling _triggerSync — medications never leave
    // the device. See spec §8.5.
    return id;
  }

  /// Soft-delete a stack entry (sets `deletedAt`).
  Future<void> remove(String entryId) async {
    final userDb = _ref.read(userDatabaseProvider);
    final entry =
        await (userDb.select(userDb.userStacksLocal)
              ..where((table) => table.id.equals(entryId))
              ..limit(1))
            .getSingleOrNull();
    if (entry == null || entry.deletedAt != null) return;
    final now = DateTime.now();
    await _ref
        .read(healthEventRepositoryProvider)
        .mutateAndAppend(
          () => userDb.removeFromStack(entryId),
          HealthEventDraft(
            eventType: HealthEventTypes.stackItemRemoved,
            source: HealthEventSource.stack,
            subjectType: entry.type,
            subjectId: entry.id,
            title: 'Stopped ${entry.name}',
            summary: 'Removed from your ${entry.type} list.',
            effectiveAt: now,
            previousValue: _stackHistoryValue(entry),
          ),
        );
    _invalidate();
    if (entry.type == 'supplement') _triggerSync();
  }

  /// Reverse a soft-delete — clears `deletedAt` so the entry re-appears.
  /// Used to implement "Undo" on the remove snackbar.
  Future<void> restore(String entryId) async {
    final userDb = _ref.read(userDatabaseProvider);
    final entry =
        await (userDb.select(userDb.userStacksLocal)
              ..where((table) => table.id.equals(entryId))
              ..limit(1))
            .getSingleOrNull();
    if (entry == null || entry.deletedAt == null) return;
    final now = DateTime.now();
    await _ref
        .read(healthEventRepositoryProvider)
        .mutateAndAppend(
          () =>
              (userDb.update(
                userDb.userStacksLocal,
              )..where((t) => t.id.equals(entryId))).write(
                UserStacksLocalCompanion(
                  deletedAt: const Value(null),
                  clientUpdatedAt: Value(now),
                ),
              ),
          HealthEventDraft(
            eventType: HealthEventTypes.stackItemRestored,
            source: HealthEventSource.stack,
            subjectType: entry.type,
            subjectId: entry.id,
            title: 'Restarted ${entry.name}',
            summary: 'Restored to your ${entry.type} list.',
            effectiveAt: now,
            currentValue: _stackHistoryValue(entry),
          ),
        );
    _invalidate();
    if (entry.type == 'supplement') _triggerSync();
  }

  /// Update the user-entered dose/schedule and append the change to the
  /// canonical Health History transactionally.
  ///
  /// These are saved notes about how the user takes the item. They do not
  /// rewrite catalog label amounts or clinical dose calculations.
  Future<bool> updateSchedule({
    required String entryId,
    String? dosage,
    String? frequency,
  }) async {
    _requireSignedIn();
    final userDb = _ref.read(userDatabaseProvider);
    final entry =
        await (userDb.select(userDb.userStacksLocal)
              ..where((table) => table.id.equals(entryId))
              ..limit(1))
            .getSingleOrNull();
    if (entry == null || entry.deletedAt != null) return false;

    final nextDosage = _cleanScheduleValue(dosage);
    final nextFrequency = _cleanScheduleValue(frequency);
    if (entry.dosage == nextDosage && entry.frequency == nextFrequency) {
      return false;
    }

    final now = DateTime.now();
    final previous = _stackHistoryValue(entry);
    final current = {
      ...previous,
      'dosage': nextDosage,
      'frequency': nextFrequency,
    };
    await _ref
        .read(healthEventRepositoryProvider)
        .mutateAndAppend(
          () =>
              (userDb.update(
                userDb.userStacksLocal,
              )..where((table) => table.id.equals(entryId))).write(
                UserStacksLocalCompanion(
                  dosage: Value(nextDosage),
                  frequency: Value(nextFrequency),
                  clientUpdatedAt: Value(now),
                ),
              ),
          HealthEventDraft(
            eventType: HealthEventTypes.stackItemChanged,
            source: HealthEventSource.stack,
            subjectType: entry.type,
            subjectId: entry.id,
            title: 'Updated ${entry.name}',
            summary: 'Changed the saved dose or schedule.',
            effectiveAt: now,
            previousValue: previous,
            currentValue: current,
            metadata: const {
              'changed_fields': ['dosage', 'frequency'],
            },
          ),
        );
    _invalidate();
    CrashReportingService().log('stack_update_schedule');
    if (entry.type == 'supplement') _triggerSync();
    return true;
  }

  void _invalidate() {
    _ref.invalidate(activeStackProvider);
    // Family providers invalidate per-key when the root is invalidated;
    // force a broad invalidate so every currently-listening detail screen
    // rebuilds its "in stack?" state.
    _ref.invalidate(stackEntryForDsldIdProvider);
    _ref.invalidate(safetyCheckForAddProvider);
    // The aggregated banner report re-runs on every mutation so the
    // top-of-stack banner updates in the same frame as the product
    // list. activeStackProvider is already listed above, but we spell
    // this out explicitly so a future refactor that drops the stack
    // dependency can't accidentally freeze the banner.
    _ref.invalidate(stackSafetyReportProvider);
    // Synergy and recall detection also depend on the active stack, so they
    // must rebuild whenever the stack changes.
    _ref.invalidate(synergyReportProvider);
    _ref.invalidate(recalledIngredientsReportProvider);
    // The Nutrients tab reads this provider directly, so stack CRUD must
    // invalidate it explicitly; otherwise removed items can leave stale
    // nutrient totals visible after the stack list has already updated.
    _ref.invalidate(stackNutrientStatusesProvider);
    _ref.invalidate(stackDoseThresholdAlertsProvider);
  }

  /// Fire-and-forget sync attempt after every mutation. Silently skips
  /// when offline / guest — the [stackSyncListenerProvider] will catch up
  /// later when the user signs in or connectivity returns.
  void _triggerSync() {
    final service = _ref.read(stackSyncServiceProvider);
    unawaited(service.pushAll());
    _ref.invalidate(pendingSyncCountProvider);
  }

  void _requireSignedIn() {
    if (_ref.read(authStateProvider) == AuthMode.guest) {
      throw const StackRequiresSignInException();
    }
  }
}

Map<String, Object?> _stackHistoryValue(UserStacksLocalData entry) {
  return {
    'name': entry.name,
    if (entry.dsldId != null) 'dsld_id': entry.dsldId,
    if (entry.dosage != null) 'dosage': entry.dosage,
    if (entry.frequency != null) 'frequency': entry.frequency,
  };
}

String? _cleanScheduleValue(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

final stackActionsProvider = Provider<StackActions>((ref) {
  return StackActions(ref);
});
