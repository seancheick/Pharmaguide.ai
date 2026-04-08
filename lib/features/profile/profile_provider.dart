import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

class ProfileState {
  final String? nickname;
  final String? ageBracket;
  final String? sex;
  final List<String> goals;
  final List<String> conditions;
  final List<String> drugClasses;
  final List<String> allergens;

  const ProfileState({
    this.nickname,
    this.ageBracket,
    this.sex,
    this.goals = const [],
    this.conditions = const [],
    this.drugClasses = const [],
    this.allergens = const [],
  });

  ProfileState copyWith({
    String? nickname,
    String? ageBracket,
    String? sex,
    List<String>? goals,
    List<String>? conditions,
    List<String>? drugClasses,
    List<String>? allergens,
  }) {
    return ProfileState(
      nickname: nickname ?? this.nickname,
      ageBracket: ageBracket ?? this.ageBracket,
      sex: sex ?? this.sex,
      goals: goals ?? this.goals,
      conditions: conditions ?? this.conditions,
      drugClasses: drugClasses ?? this.drugClasses,
      allergens: allergens ?? this.allergens,
    );
  }

  /// Profile completeness as 0-100.
  int get completeness {
    int score = 0;
    if (ageBracket != null) score += 20;
    if (sex != null) score += 20;
    if (goals.isNotEmpty) score += 20;
    if (conditions.isNotEmpty || drugClasses.isNotEmpty) score += 20;
    if (allergens.isNotEmpty) score += 10;
    if (nickname != null && nickname!.isNotEmpty) score += 10;
    return score;
  }

  String get completenessLabel {
    final c = completeness;
    if (c >= 80) return 'Complete';
    if (c >= 60) return 'Good';
    if (c >= 40) return 'Basic';
    return 'Incomplete';
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
      drugClasses: _decodeList(row.drugClasses),
      allergens: _decodeList(row.allergens),
    );
  }

  static List<String> _decodeList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) return decoded.cast<String>();
    } on Exception catch (_) {}
    return [];
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
          _listEq.equals(allergens, other.allergens);

  @override
  int get hashCode => Object.hash(
        nickname,
        ageBracket,
        sex,
        _listEq.hash(goals),
        _listEq.hash(conditions),
        _listEq.hash(drugClasses),
        _listEq.hash(allergens),
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
    final current = List<String>.from(state.goals);
    if (current.contains(goalId)) {
      current.remove(goalId);
    } else if (current.length < 2) {
      current.add(goalId);
    }
    state = state.copyWith(goals: current);
  }

  void toggleCondition(String conditionId) {
    final current = List<String>.from(state.conditions);
    if (current.contains(conditionId)) {
      current.remove(conditionId);
    } else {
      current.add(conditionId);
    }
    state = state.copyWith(conditions: current);
  }

  void toggleDrugClass(String drugClassId) {
    final current = List<String>.from(state.drugClasses);
    if (current.contains(drugClassId)) {
      current.remove(drugClassId);
    } else {
      current.add(drugClassId);
    }
    state = state.copyWith(drugClasses: current);
  }

  void toggleAllergen(String allergenId) {
    final current = List<String>.from(state.allergens);
    if (current.contains(allergenId)) {
      current.remove(allergenId);
    } else {
      current.add(allergenId);
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
    } on Exception catch (_) {
      // DB read failed — keep default empty state, log if needed.
    }
    _isLoaded = true;
  }

  /// Persist current state to DB.
  Future<void> saveToDb() async {
    if (_db == null) return;
    await _db.saveProfile(state.toCompanion());
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>(
  (ref) {
    UserDatabase? db;
    try {
      db = ref.watch(userDatabaseProvider);
    } catch (_) {
      // userDatabaseProvider not overridden (e.g. in tests) — no persistence.
    }
    final notifier = ProfileNotifier(db);
    // Kick off load — consumers can check notifier.isLoaded if needed.
    notifier.loadFromDb();
    return notifier;
  },
);

/// Resolves when the profile has been loaded from DB.
/// Use `ref.watch(profileLoadedProvider)` to gate UI on profile readiness.
final profileLoadedProvider = FutureProvider<void>((ref) async {
  final notifier = ref.watch(profileProvider.notifier);
  // Poll briefly — loadFromDb is already running from provider init.
  while (!notifier.isLoaded) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
});
