/// What a user has chosen to include in an AI-assistant share.
///
/// One scope type serves every share surface: the pasted AI brief today and
/// the consented connector snapshot later (ADR-009). Sensitive categories are
/// off by default. Dependent switches are normalized by [normalized] so a
/// schedule can never be shared without the name it belongs to.
///
/// Derived-findings rule: a finding that would disclose an excluded category
/// (a medication interaction, a medication-driven nutrient relationship, a
/// profile gate) is excluded together with that category. The brief builder
/// enforces it; this type only records the choice.
class AiShareScope {
  const AiShareScope({
    this.supplementNames = true,
    this.supplementAmounts = true,
    this.supplementSchedule = false,
    this.medicationNames = false,
    this.medicationSchedule = false,
    this.profile = false,
    this.findings = true,
  });

  /// Preset: names only, nothing derived.
  static const AiShareScope simpleList = AiShareScope(
    supplementAmounts: false,
    findings: false,
  );

  /// Preset: the detailed AI report with PharmaGuide findings.
  static const AiShareScope detailedReport = AiShareScope();

  /// Supplement product names and brands.
  final bool supplementNames;

  /// Verified label amounts as nutrient totals (never free-text doses).
  final bool supplementAmounts;

  /// Free-text dose and frequency the user typed for a supplement.
  final bool supplementSchedule;

  /// Medication names. Off by default.
  final bool medicationNames;

  /// Medication dose and frequency as entered. Off by default.
  final bool medicationSchedule;

  /// Age bracket, sex, conditions, medication classes, allergies, goals,
  /// pregnancy and other profile flags. Off by default.
  final bool profile;

  /// PharmaGuide findings with severity, evidence level and sources.
  final bool findings;

  /// The same scope with dependent switches clamped to their parent.
  AiShareScope get normalized => AiShareScope(
    supplementNames: supplementNames,
    supplementAmounts: supplementNames && supplementAmounts,
    supplementSchedule: supplementNames && supplementSchedule,
    medicationNames: medicationNames,
    medicationSchedule: medicationNames && medicationSchedule,
    profile: profile,
    findings: findings,
  );

  bool get isEmpty =>
      !supplementNames && !medicationNames && !profile && !findings;

  AiShareScope copyWith({
    bool? supplementNames,
    bool? supplementAmounts,
    bool? supplementSchedule,
    bool? medicationNames,
    bool? medicationSchedule,
    bool? profile,
    bool? findings,
  }) {
    return AiShareScope(
      supplementNames: supplementNames ?? this.supplementNames,
      supplementAmounts: supplementAmounts ?? this.supplementAmounts,
      supplementSchedule: supplementSchedule ?? this.supplementSchedule,
      medicationNames: medicationNames ?? this.medicationNames,
      medicationSchedule: medicationSchedule ?? this.medicationSchedule,
      profile: profile ?? this.profile,
      findings: findings ?? this.findings,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiShareScope &&
      other.supplementNames == supplementNames &&
      other.supplementAmounts == supplementAmounts &&
      other.supplementSchedule == supplementSchedule &&
      other.medicationNames == medicationNames &&
      other.medicationSchedule == medicationSchedule &&
      other.profile == profile &&
      other.findings == findings;

  @override
  int get hashCode => Object.hash(
    supplementNames,
    supplementAmounts,
    supplementSchedule,
    medicationNames,
    medicationSchedule,
    profile,
    findings,
  );
}
