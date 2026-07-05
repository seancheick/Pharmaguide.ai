import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart'
    as gate;

@immutable
class MedicationProfileGateRule {
  const MedicationProfileGateRule({
    required this.id,
    required this.severity,
    required this.evidenceLevel,
    required this.headline,
    required this.body,
    required this.management,
    required this.sourceUrls,
    required this.profileGate,
  });

  final String id;
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String headline;
  final String body;
  final String management;
  final List<String> sourceUrls;
  final Map<String, dynamic> profileGate;

  factory MedicationProfileGateRule.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] ?? json['source_urls'];
    return MedicationProfileGateRule(
      id: json['id']?.toString() ?? '',
      severity: Severity.fromString(json['severity']?.toString() ?? 'caution'),
      evidenceLevel: EvidenceLevel.fromString(
        json['evidence_level']?.toString() ?? 'ungraded',
      ),
      headline: json['headline']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      management: json['management']?.toString() ?? '',
      sourceUrls: rawSources is List
          ? rawSources.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      profileGate: json['profile_gate'] is Map
          ? Map<String, dynamic>.from(json['profile_gate'] as Map)
          : const <String, dynamic>{},
    );
  }

  static List<MedicationProfileGateRule> listFromJson(
    Map<String, dynamic> json,
  ) {
    final raw = json['medication_profile_gate_rules'];
    if (raw is! List) return const <MedicationProfileGateRule>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => MedicationProfileGateRule.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        )
        .where((rule) => rule.id.isNotEmpty)
        .toList(growable: false);
  }
}

@immutable
class MedicationProfileWarning {
  const MedicationProfileWarning({
    required this.id,
    required this.ruleId,
    required this.medicationName,
    required this.severity,
    required this.evidenceLevel,
    required this.headline,
    required this.body,
    required this.management,
    required this.sourceUrls,
  });

  final String id;
  final String ruleId;
  final String medicationName;
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String headline;
  final String body;
  final String management;
  final List<String> sourceUrls;
}

class MedicationProfileGateEvaluator {
  const MedicationProfileGateEvaluator();

  List<MedicationProfileWarning> evaluate({
    required List<MedicationProfileGateRule> rules,
    required String medicationName,
    required Set<String> medicationProfileGateClassIds,
    required Set<String> userProfileFlags,
    Set<String> userConditions = const <String>{},
  }) {
    if (rules.isEmpty || medicationProfileGateClassIds.isEmpty) {
      return const <MedicationProfileWarning>[];
    }

    final profile = gate.UserProfile(
      conditions: userConditions,
      drugClasses: medicationProfileGateClassIds,
      profileFlags: userProfileFlags,
    );
    // Empty context is intentional: medication_profile_gate_rules are
    // gated only on conditions / drug classes / profile flags — none carry
    // a dose threshold or a product/nutrient-form exclude (verified: 0 of
    // the shipped rules use a dose block or *_forms_any). If a
    // dose-modified medication rule is ever added, a real ProductContext
    // (dose/form) must be threaded here or it will resolve to the weaker
    // `severity_if_not_met` branch.
    const context = gate.ProductContext();

    final out = <MedicationProfileWarning>[];
    for (final rule in rules) {
      final result = gate.evaluateProfileGate(
        rule.profileGate,
        profile,
        context,
        baseSeverity: rule.severity.name,
      );
      if (!result.fires) continue;
      final severity = Severity.fromString(
        result.severity ?? rule.severity.name,
      );
      out.add(
        MedicationProfileWarning(
          id: '${rule.id}:$medicationName',
          ruleId: rule.id,
          medicationName: medicationName,
          severity: severity,
          evidenceLevel: rule.evidenceLevel,
          headline: rule.headline,
          body: rule.body,
          management: rule.management,
          sourceUrls: rule.sourceUrls,
        ),
      );
    }
    return out;
  }
}
