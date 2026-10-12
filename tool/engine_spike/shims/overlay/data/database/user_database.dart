// SPIKE OVERLAY for lib/data/database/user_database.dart.
//
// The engine only touches the Drift-generated `UserStacksLocalData` row class.
// Field names/types match the generated class (user_database.g.dart).
// Production fix: the engine takes a plain `StackEntry` value type and the
// Drift row maps onto it at the app boundary.
class UserStacksLocalData {
  const UserStacksLocalData({
    required this.id,
    required this.type,
    required this.name,
    this.dsldId,
    this.rxcui,
    this.ingredientKeys,
    this.drugClassesCol,
    this.genericRxcui,
    this.ingredientRxcuisCol,
    this.medicationContextCol,
    this.dosage,
    this.frequency,
    required this.addedAt,
    this.startedAt,
    this.reminderMinutes,
    required this.clientUpdatedAt,
    this.deletedAt,
    this.syncedAt,
    this.syncBlockedAt,
  });

  final String id;
  final String type;
  final String name;
  final String? dsldId;
  final String? rxcui;
  final String? ingredientKeys;
  final String? drugClassesCol;
  final String? genericRxcui;
  final String? ingredientRxcuisCol;
  final String? medicationContextCol;
  final String? dosage;
  final String? frequency;
  final DateTime addedAt;
  final DateTime? startedAt;
  final int? reminderMinutes;
  final DateTime clientUpdatedAt;
  final DateTime? deletedAt;
  final DateTime? syncedAt;
  final DateTime? syncBlockedAt;

  /// Spike-only: the app uses Drift's `copyWith(drugClassesCol: Value(x))`.
  UserStacksLocalData withDrugClasses(String? drugClassesCol) =>
      UserStacksLocalData(
        id: id,
        type: type,
        name: name,
        dsldId: dsldId,
        rxcui: rxcui,
        ingredientKeys: ingredientKeys,
        drugClassesCol: drugClassesCol,
        genericRxcui: genericRxcui,
        ingredientRxcuisCol: ingredientRxcuisCol,
        medicationContextCol: medicationContextCol,
        dosage: dosage,
        frequency: frequency,
        addedAt: addedAt,
        startedAt: startedAt,
        reminderMinutes: reminderMinutes,
        clientUpdatedAt: clientUpdatedAt,
        deletedAt: deletedAt,
        syncedAt: syncedAt,
        syncBlockedAt: syncBlockedAt,
      );
}
