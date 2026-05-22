import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

class ProfileState {
  final String? nickname;
  final String? ageBracket;
  final String? sex;
  final List<String> goals;
  final List<String> conditions;
  final List<String> drugClasses;
  final List<String> allergens;

  /// v6.0 profile flags — additive to [conditions]. Stores the
  /// transient/history flag IDs that the v6.0 profile_gate evaluator
  /// requires: `post_op_recovery`, `hypoglycemia_history`,
  /// `bleeding_history`. The reproductive/perioperative flags
  /// (`pregnant`, `breastfeeding`, `trying_to_conceive`,
  /// `surgery_scheduled`) are derived from [conditions] in
  /// [evaluatorProfileFlags]; these three are NEW state captured
  /// only here.
  final List<String> profileFlags;

  const ProfileState({
    this.nickname,
    this.ageBracket,
    this.sex,
    this.goals = const [],
    this.conditions = const [],
    this.drugClasses = const [],
    this.allergens = const [],
    this.profileFlags = const [],
  });

  ProfileState copyWith({
    String? nickname,
    String? ageBracket,
    String? sex,
    List<String>? goals,
    List<String>? conditions,
    List<String>? drugClasses,
    List<String>? allergens,
    List<String>? profileFlags,
  }) {
    return ProfileState(
      nickname: nickname ?? this.nickname,
      ageBracket: ageBracket ?? this.ageBracket,
      sex: sex ?? this.sex,
      goals: goals ?? this.goals,
      conditions: conditions ?? this.conditions,
      drugClasses: drugClasses ?? this.drugClasses,
      allergens: allergens ?? this.allergens,
      profileFlags: profileFlags ?? this.profileFlags,
    );
  }

  // ---------------------------------------------------------------------------
  // "None" sentinel helpers — Phase 11.7L.B.6.
  //
  // The v2 ProfileSetup distinguishes "user hasn't decided yet" (empty
  // list) from "user explicitly opted out" (list contains the sentinel
  // ID from `SchemaIds.noneSentinels`). These getters surface that
  // distinction to UI without exposing the sentinel string.
  //
  // Important: `goals`, `conditions`, etc. ARE the raw lists with
  // sentinels included when set. Consumers that talk to the matcher
  // should call `goalsForEvaluator` / `conditionsForEvaluator` /
  // `drugClassesForEvaluator` / `allergensForEvaluator` to get the
  // sentinel-stripped view. The legacy ProfileSetup screen never
  // produces sentinels, so its rows continue to work unchanged.
  // ---------------------------------------------------------------------------
  bool get hasGoalNone => goals.contains(SchemaIds.goalNone);
  bool get hasConditionNone => conditions.contains(SchemaIds.conditionNone);
  bool get hasDrugClassNone => drugClasses.contains(SchemaIds.drugClassNone);
  bool get hasAllergenNone => allergens.contains(SchemaIds.allergenNone);

  /// Sentinel-stripped goals list — safe to hand to the evaluator /
  /// recommender. Use this anywhere the matcher would otherwise see
  /// `GOAL_NONE` and fail a taxonomy lookup.
  List<String> get goalsForEvaluator =>
      goals.where((g) => g != SchemaIds.goalNone).toList(growable: false);

  List<String> get conditionsForEvaluator => conditions
      .where((c) => c != SchemaIds.conditionNone)
      .toList(growable: false);

  List<String> get drugClassesForEvaluator => drugClasses
      .where((d) => d != SchemaIds.drugClassNone)
      .toList(growable: false);

  List<String> get allergensForEvaluator => allergens
      .where((a) => a != SchemaIds.allergenNone)
      .toList(growable: false);

  /// Profile-flag set for the v6.0 evaluator. Combines [profileFlags]
  /// (history flags) with derived flags from [conditions]:
  ///   conditions: 'pregnancy'         → 'pregnant'
  ///   conditions: 'lactation'         → 'breastfeeding'
  ///   conditions: 'ttc'               → 'trying_to_conceive'
  ///   conditions: 'surgery_scheduled' → 'surgery_scheduled'
  ///
  /// Single source of truth for the evaluator's `profile_flags_any`
  /// requires/excludes axis. Mirrors the migration mapping in
  /// `dsld_clean/scripts/tools/migrate_to_profile_gate.py`
  /// (`PROFILE_FLAG_CONDITION_MAP`).
  Set<String> get evaluatorProfileFlags {
    const conditionToFlag = <String, String>{
      'pregnancy': 'pregnant',
      'lactation': 'breastfeeding',
      'ttc': 'trying_to_conceive',
      'surgery_scheduled': 'surgery_scheduled',
    };
    final out = <String>{...profileFlags};
    for (final c in conditionsForEvaluator) {
      final flag = conditionToFlag[c.toLowerCase()];
      if (flag != null) out.add(flag);
    }
    return out;
  }

  /// Convert to Drift companion for DB persistence.
  UserProfilesCompanion toCompanion() {
    return UserProfilesCompanion(
      id: const Value(1), // Single-row profile
      nickname: Value(nickname),
      ageBracket: Value(ageBracket),
      sex: Value(sex),
      goals: Value(jsonEncode(goals)),
      conditions: Value(jsonEncode(conditions)),
      drugClasses: Value(jsonEncode(drugClasses)),
      allergens: Value(jsonEncode(allergens)),
      profileFlags: Value(jsonEncode(profileFlags)),
      lastUpdated: Value(DateTime.now()),
    );
  }

  /// Create from a Drift row read from the DB.
  factory ProfileState.fromDbRow(UserProfile row) {
    return ProfileState(
      nickname: row.nickname,
      ageBracket: row.ageBracket,
      sex: row.sex,
      goals: _decodeList(row.goals),
      conditions: _decodeList(row.conditions),
      drugClasses: _migrateLegacyDrugClasses(_decodeList(row.drugClasses)),
      allergens: migrateLegacyAllergenIds(_decodeList(row.allergens)),
      profileFlags: _decodeList(row.profileFlags),
    );
  }

  static List<String> _decodeList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) return decoded.cast<String>();
    } on Exception catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        fatal: true,
        hint: 'profile:decode_list',
      );
    }
    return [];
  }

  /// One-shot migration for legacy allergen IDs that drifted from the
  /// pipeline canonical set (`scripts/data/allergens.json`).
  ///
  /// Idempotent: canonical IDs map to themselves, legacy IDs are rewritten,
  /// and IDs the pipeline cannot detect are silently dropped (no point
  /// keeping them in the profile if they will never match).
  ///
  /// Drift fixes:
  ///   ALLERGEN_EGG       → ALLERGEN_EGGS
  ///   ALLERGEN_PEANUT    → ALLERGEN_PEANUTS
  ///   ALLERGEN_SULFITE   → ALLERGEN_SULFITES
  /// Group expansions (legacy single ID → multiple canonical IDs):
  ///   ALLERGEN_SHELLFISH → ALLERGEN_CRUSTACEANS + ALLERGEN_MOLLUSCS
  ///   ALLERGEN_GLUTEN    → ALLERGEN_WHEAT + BARLEY + RYE + OATS
  /// Dropped (not detected by pipeline today, no clinical signoff yet):
  ///   ALLERGEN_CORN, _YEAST, _GELATIN, _LATEX_FRUIT, _NIGHTSHADE, _SALICYLATE
  static List<String> migrateLegacyAllergenIds(List<String> stored) {
    const renames = <String, String>{
      'ALLERGEN_EGG': 'ALLERGEN_EGGS',
      'ALLERGEN_PEANUT': 'ALLERGEN_PEANUTS',
      'ALLERGEN_SULFITE': 'ALLERGEN_SULFITES',
    };
    const groupExpansions = <String, List<String>>{
      'ALLERGEN_SHELLFISH': ['ALLERGEN_CRUSTACEANS', 'ALLERGEN_MOLLUSCS'],
      'ALLERGEN_GLUTEN': [
        'ALLERGEN_WHEAT',
        'ALLERGEN_BARLEY',
        'ALLERGEN_RYE',
        'ALLERGEN_OATS',
      ],
    };
    const supported = <String>{
      'ALLERGEN_MILK',
      'ALLERGEN_EGGS',
      'ALLERGEN_FISH',
      'ALLERGEN_CRUSTACEANS',
      'ALLERGEN_MOLLUSCS',
      'ALLERGEN_TREE_NUTS',
      'ALLERGEN_PEANUTS',
      'ALLERGEN_WHEAT',
      'ALLERGEN_BARLEY',
      'ALLERGEN_RYE',
      'ALLERGEN_OATS',
      'ALLERGEN_SOY',
      'ALLERGEN_SESAME',
      'ALLERGEN_SULFITES',
      'ALLERGEN_CELERY',
      'ALLERGEN_MUSTARD',
      'ALLERGEN_LUPIN',
    };

    final out = <String>{};
    for (final id in stored) {
      // Phase 11.7L.B.6 — preserve the v2 None sentinel verbatim. It's
      // not a pipeline-canonical allergen and would otherwise be
      // silently dropped by the `supported` filter below.
      if (id == SchemaIds.allergenNone) {
        out.add(id);
        continue;
      }
      final renamed = renames[id] ?? id;
      final expanded = groupExpansions[renamed];
      if (expanded != null) {
        out.addAll(expanded);
      } else if (supported.contains(renamed)) {
        out.add(renamed);
      }
      // Else: unsupported sensitivity (corn, yeast, etc.) — silently dropped.
    }
    return out.toList();
  }

  /// One-shot migration for the v6.1.0 hypoglycemics split.
  ///
  /// Users who selected the broad "hypoglycemics" before the split get
  /// mapped to "hypoglycemics_unknown" (honest uncertainty — middle-ground
  /// caution severity). The profile-setup screen shows all three options so
  /// users can refine to high_risk or lower_risk for more accurate warnings.
  ///
  /// Also normalizes IDs with trim + lowercase since the taxonomy uses
  /// lowercase canonical IDs.
  static List<String> _migrateLegacyDrugClasses(List<String> stored) {
    // Phase 11.7L.B.6 — preserve the v2 None sentinel verbatim. The
    // `.toLowerCase()` below would otherwise rewrite `DRUG_CLASS_NONE`
    // → `drug_class_none`, breaking the sentinel string match.
    final normalized = stored
        .map(
          (id) => id == SchemaIds.drugClassNone ? id : id.trim().toLowerCase(),
        )
        .toList();
    if (!normalized.contains('hypoglycemics')) return normalized;
    final out = normalized.where((id) => id != 'hypoglycemics').toList();
    if (!out.contains('hypoglycemics_unknown')) {
      out.add('hypoglycemics_unknown');
    }
    return out.toSet().toList();
  }

  static const _listEq = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileState &&
          nickname == other.nickname &&
          ageBracket == other.ageBracket &&
          sex == other.sex &&
          _listEq.equals(goals, other.goals) &&
          _listEq.equals(conditions, other.conditions) &&
          _listEq.equals(drugClasses, other.drugClasses) &&
          _listEq.equals(allergens, other.allergens) &&
          _listEq.equals(profileFlags, other.profileFlags);

  @override
  int get hashCode => Object.hash(
    nickname,
    ageBracket,
    sex,
    _listEq.hash(goals),
    _listEq.hash(conditions),
    _listEq.hash(drugClasses),
    _listEq.hash(allergens),
    _listEq.hash(profileFlags),
  );
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final UserDatabase? _db;
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  ProfileNotifier([this._db]) : super(const ProfileState());

  void setNickname(String? value) => state = state.copyWith(nickname: value);
  void setAgeBracket(String? value) =>
      state = state.copyWith(ageBracket: value);
  void setSex(String? value) => state = state.copyWith(sex: value);
  void setGoals(List<String> value) => state = state.copyWith(goals: value);
  void setConditions(List<String> value) =>
      state = state.copyWith(conditions: value);
  void setDrugClasses(List<String> value) =>
      state = state.copyWith(drugClasses: value);
  void setAllergens(List<String> value) =>
      state = state.copyWith(allergens: value);

  void toggleGoal(String goalId) {
    // Strip the None sentinel as a side-effect of picking a real ID —
    // the two are mutually exclusive (see `setGoalsWithNone`). Note we
    // also count goals BEFORE the sentinel strip so a user opting out
    // of None still gets to pick up to 2 fresh goals.
    final current = List<String>.from(state.goals)
      ..removeWhere((g) => g == SchemaIds.goalNone);
    if (current.contains(goalId)) {
      current.remove(goalId);
    } else if (current.length < 2) {
      current.add(goalId);
    }
    state = state.copyWith(goals: current);
  }

  void toggleCondition(String conditionId) {
    final current = List<String>.from(state.conditions)
      ..removeWhere((c) => c == SchemaIds.conditionNone);
    if (current.contains(conditionId)) {
      current.remove(conditionId);
    } else {
      current.add(conditionId);
    }
    state = state.copyWith(conditions: current);
  }

  void toggleDrugClass(String drugClassId) {
    final current = List<String>.from(state.drugClasses)
      ..removeWhere((d) => d == SchemaIds.drugClassNone);
    if (current.contains(drugClassId)) {
      current.remove(drugClassId);
    } else {
      current.add(drugClassId);
    }
    state = state.copyWith(drugClasses: current);
  }

  void toggleAllergen(String allergenId) {
    final current = List<String>.from(state.allergens)
      ..removeWhere((a) => a == SchemaIds.allergenNone);
    if (current.contains(allergenId)) {
      current.remove(allergenId);
    } else {
      current.add(allergenId);
    }
    state = state.copyWith(allergens: current);
  }

  // ---------------------------------------------------------------------------
  // "None" sentinel setters — Phase 11.7L.B.6.
  //
  // Each `set...WithNone` accepts the resolved (selected, noneSelected)
  // pair from a `PGSelectionSheet` Save callback and writes the
  // appropriate canonical list. Mutual exclusion is enforced here so
  // call sites don't have to think about it:
  //   noneSelected=true  → list = [<sentinel>] (clears any real picks)
  //   noneSelected=false → list = selected.toList() (drops any sentinel)
  // The pre-existing `toggle*` methods (toggleGoal, toggleCondition,
  // toggleDrugClass, toggleAllergen, toggleAllergenGroup) keep their
  // legacy single-tap semantics for backward compat, but each one now
  // strips the sentinel when adding a real ID so the two paths agree
  // on the invariant "sentinel and real IDs never co-exist."
  // ---------------------------------------------------------------------------
  void setGoalsWithNone({
    required Set<String> selected,
    required bool noneSelected,
  }) {
    state = state.copyWith(
      goals: noneSelected ? [SchemaIds.goalNone] : selected.toList(),
    );
  }

  void setConditionsWithNone({
    required Set<String> selected,
    required bool noneSelected,
  }) {
    state = state.copyWith(
      conditions: noneSelected ? [SchemaIds.conditionNone] : selected.toList(),
    );
  }

  void setDrugClassesWithNone({
    required Set<String> selected,
    required bool noneSelected,
  }) {
    state = state.copyWith(
      drugClasses: noneSelected ? [SchemaIds.drugClassNone] : selected.toList(),
    );
  }

  void setAllergensWithNone({
    required Set<String> selected,
    required bool noneSelected,
  }) {
    state = state.copyWith(
      allergens: noneSelected ? [SchemaIds.allergenNone] : selected.toList(),
    );
  }

  /// Toggle a group of canonical allergen IDs all-or-nothing.
  ///
  /// Used by user-facing grouped chips like "Shellfish"
  /// (CRUSTACEANS + MOLLUSCS) and "Gluten-free"
  /// (WHEAT + BARLEY + RYE + OATS). Selected when every member is
  /// present; tapping clears all members. Tapping an unselected (or
  /// partially selected) chip adds every missing member.
  void toggleAllergenGroup(List<String> allergenIds) {
    if (allergenIds.isEmpty) return;
    final current = List<String>.from(state.allergens)
      ..removeWhere((a) => a == SchemaIds.allergenNone);
    final allPresent = allergenIds.every(current.contains);
    if (allPresent) {
      current.removeWhere(allergenIds.contains);
    } else {
      for (final id in allergenIds) {
        if (!current.contains(id)) current.add(id);
      }
    }
    state = state.copyWith(allergens: current);
  }

  /// Load profile from DB into state. Call once at startup.
  /// Sets [isLoaded] to true when complete (even if no row found).
  Future<void> loadFromDb() async {
    if (_db == null) {
      _isLoaded = true;
      return;
    }
    try {
      final row = await _db.getProfile();
      if (row != null) {
        state = ProfileState.fromDbRow(row);
      }
    } on Exception catch (e, st) {
      // DB read failed — keep default empty state. fatal=false intentionally:
      // loadFromDb fires on every cold start, so a single user with corrupt
      // profile data would otherwise trigger a fatal alert storm. Recoverable
      // on next session, so we surface as a non-fatal Sentry event.
      CrashReportingService().recordError(
        e,
        st,
        hint: 'profile:load_from_db',
      );
    }
    _isLoaded = true;
  }

  /// Persist current state to DB.
  Future<void> saveToDb() async {
    if (_db == null) return;
    await _db.saveProfile(state.toCompanion());
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>((
  ref,
) {
  UserDatabase? db;
  try {
    db = ref.watch(userDatabaseProvider);
  } on Object catch (e, st) {
    // userDatabaseProvider not overridden (e.g. in tests) — no persistence.
    // Catches Error (UnimplementedError from the default provider stub)
    // AND Exception — both map to "no DB available" here. fatal=true: in
    // production the provider is always overridden in main.dart, so hitting
    // this path means a real bootstrap failure that silently degrades the
    // profile for every downstream screen.
    CrashReportingService().recordError(
      e,
      st,
      fatal: true,
      hint: 'profile:provider_init',
    );
  }
  final notifier = ProfileNotifier(db);
  // Kick off load — consumers can check notifier.isLoaded if needed.
  notifier.loadFromDb();
  return notifier;
});

/// Resolves when the profile has been loaded from DB.
/// Use `ref.watch(profileLoadedProvider)` to gate UI on profile readiness.
final profileLoadedProvider = FutureProvider<void>((ref) async {
  final notifier = ref.watch(profileProvider.notifier);
  // Poll briefly — loadFromDb is already running from provider init.
  while (!notifier.isLoaded) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
});
