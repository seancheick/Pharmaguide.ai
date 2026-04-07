import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(const ProfileState());

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
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>(
  (ref) => ProfileNotifier(),
);
