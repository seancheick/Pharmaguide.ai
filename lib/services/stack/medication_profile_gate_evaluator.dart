import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart'
    as gate;

/// Device-local, explicitly confirmed facts; absent values remain unknown.
@immutable
class MedicationUseContext {
  const MedicationUseContext({
    this.dailyDoseMg,
    this.route,
    this.useContext,
    this.isCurrentCheck = false,
  });
  // Transient confirmation: never persisted or restored from stored context.
  final bool isCurrentCheck;
  final double? dailyDoseMg;
  final String? route;
  final String? useContext;
  Map<String, dynamic> toJson() => {
    if (dailyDoseMg != null && dailyDoseMg!.isFinite && dailyDoseMg! > 0)
      'daily_dose_mg': dailyDoseMg,
    if (route != null) 'route': route,
    if (useContext != null) 'use_context': useContext,
  };
  static MedicationUseContext fromStored(String? value) {
    try {
      final json = jsonDecode(value ?? '{}');
      if (json is! Map) return const MedicationUseContext();
      final dose = json['daily_dose_mg'];
      return MedicationUseContext(
        dailyDoseMg: dose is num && dose.isFinite && dose > 0
            ? dose.toDouble()
            : null,
        route: json['route'] is String ? json['route'] as String : null,
        useContext: json['use_context'] is String
            ? json['use_context'] as String
            : null,
      );
    } on FormatException {
      return const MedicationUseContext();
    }
  }
}

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
    this.medicationIngredientRxcuis = const [],
    this.medicationExceptions = const [],
  });

  final String id;
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String headline;
  final String body;
  final String management;
  final List<String> sourceUrls;
  final Map<String, dynamic> profileGate;
  final List<String> medicationIngredientRxcuis;
  final List<Map<String, dynamic>> medicationExceptions;

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
      medicationIngredientRxcuis:
          (json['medication_ingredient_rxcuis'] is List
                  ? json['medication_ingredient_rxcuis'] as List<dynamic>
                  : const <dynamic>[])
              .whereType<String>()
              .toList(),
      medicationExceptions:
          (json['medication_exceptions'] is List
                  ? json['medication_exceptions'] as List<dynamic>
                  : const <dynamic>[])
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
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
    Set<String> medicationIngredientRxcuis = const <String>{},
    MedicationUseContext medicationContext = const MedicationUseContext(),
  }) {
    if (rules.isEmpty) {
      return const <MedicationProfileWarning>[];
    }

    final profile = gate.UserProfile(
      conditions: userConditions,
      drugClasses: medicationProfileGateClassIds,
      profileFlags: userProfileFlags,
    );
    const context = gate.ProductContext();

    final out = <MedicationProfileWarning>[];
    for (final rule in rules) {
      if (rule.medicationExceptions.any(
        (e) => matchesMedicationException(
          e,
          medicationIngredientRxcuis,
          medicationContext,
        ),
      )) {
        continue;
      }
      final subjectMatches = rule.medicationIngredientRxcuis.any(
        medicationIngredientRxcuis.contains,
      );
      // Authored ingredient subjects (aspirin) extend this rule's class scope;
      // they do not alter medication class membership or another warning.
      final ruleProfile = subjectMatches
          ? gate.UserProfile(
              conditions: userConditions,
              drugClasses: {
                ...medicationProfileGateClassIds,
                ...((rule.profileGate['requires'] is Map
                            ? rule.profileGate['requires']['drug_classes_any']
                            : null)
                        is List
                    ? (rule.profileGate['requires']['drug_classes_any'] as List)
                          .whereType<String>()
                    : const <String>[]),
              },
              profileFlags: userProfileFlags,
            )
          : profile;
      final result = gate.evaluateProfileGate(
        rule.profileGate,
        ruleProfile,
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

  bool matchesMedicationException(
    Map<String, dynamic> exception,
    Set<String> ingredients,
    MedicationUseContext context,
  ) {
    if (exception.isEmpty ||
        exception.keys.every((k) => k == 'notes') ||
        exception.keys.any(
          (k) => !const {
            'ingredient_rxcuis',
            'dose_mg_exact',
            'dose_mg_range_inclusive',
            'route',
            'use_context',
            'notes',
          }.contains(k),
        )) {
      return false;
    }
    if (context.dailyDoseMg != null &&
        (!context.dailyDoseMg!.isFinite || context.dailyDoseMg! <= 0)) {
      return false;
    }
    if (exception.values.any((value) => value == null)) {
      return false;
    }
    final ids = exception['ingredient_rxcuis'];
    if (ids != null &&
        (ids is! List ||
            ids.isEmpty ||
            ids.any((id) => id is! String || id.isEmpty) ||
            ingredients.isEmpty ||
            !ingredients.every(ids.whereType<String>().contains))) {
      return false;
    }
    if (exception.containsKey('route') &&
        (exception['route'] is! String ||
            (exception['route'] as String).isEmpty ||
            context.route == null ||
            context.route != exception['route'])) {
      return false;
    }
    if (exception.containsKey('use_context') &&
        (exception['use_context'] is! String ||
            (exception['use_context'] as String).isEmpty ||
            context.useContext == null ||
            context.useContext != exception['use_context'])) {
      return false;
    }
    final exact = exception['dose_mg_exact'];
    final range = exception['dose_mg_range_inclusive'];
    if (exact != null &&
        (exact is! num ||
            !exact.isFinite ||
            exact <= 0 ||
            context.dailyDoseMg == null ||
            context.dailyDoseMg != exact)) {
      return false;
    }
    if (range != null &&
        (range is! List ||
            range.length != 2 ||
            range[0] is! num ||
            range[1] is! num ||
            !(range[0] as num).isFinite ||
            !(range[1] as num).isFinite ||
            (range[0] as num) <= 0 ||
            (range[0] as num) > (range[1] as num) ||
            context.dailyDoseMg == null ||
            context.dailyDoseMg! < (range[0] as num) ||
            context.dailyDoseMg! > (range[1] as num))) {
      return false;
    }
    return true;
  }
}
