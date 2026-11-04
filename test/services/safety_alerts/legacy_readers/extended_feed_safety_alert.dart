// FROZEN COPY of lib/services/safety_alerts/safety_alert.dart at 7fa991ca. Do not edit: it stands
// in for a build already on phones, so tests run the real old parser against
// the current feed format.
// ignore_for_file: type=lint
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';

/// Strict, authored regulatory-event feed model.
///
/// The app never reconstructs an alert from the long-lived banned-ingredient
/// reference data. It consumes only the human-approved, checksum-verified
/// fast-lane record and matches exact IDs locally.
enum SafetyAlertEventType { ingredientBan, productRecall, interactionRule }

enum SafetyAlertDisposition { block, review }

/// What this device knows about the person, for matching rules on the phone.
/// None of it is ever sent anywhere.
final class DeviceSafetyProfile {
  const DeviceSafetyProfile({
    this.medicationIds = const {},
    this.conditions = const {},
    this.profileFlags = const {},
    this.isComplete = true,
  });

  /// `class:*`, RxCUI and profile drug-class ids.
  final Set<String> medicationIds;
  final Set<String> conditions;
  final Set<String> profileFlags;

  /// False when part of this couldn't be read, so a missing match proves nothing.
  final bool isComplete;

  bool get isEmpty =>
      medicationIds.isEmpty && conditions.isEmpty && profileFlags.isEmpty;
}

/// What an `interaction_rule` alert adds: who it is for and how serious it is.
/// The reason and management are the alert's own `body` and `action`.
final class SafetyAlertInteraction {
  const SafetyAlertInteraction({
    required this.ruleId,
    required this.ingredientName,
    this.medicationName,
    this.medicationIds = const {},
    this.profileGate,
    this.profileContext,
    required this.severity,
    required this.evidenceLevel,
  });

  final String ruleId;
  final String ingredientName;
  final String? medicationName;

  /// Exact ids in the rule's own vocabulary: `class:*`, RxCUI or profile
  /// drug-class id. Compared only on the device, never sent anywhere.
  final Set<String> medicationIds;

  /// A rule for pregnancy, lactation or a condition targets this gate instead
  /// of medications, evaluated on the device from the profile alone.
  final Map<String, dynamic>? profileGate;

  /// Who [profileGate] is for, as the user reads it.
  final String? profileContext;
  final Severity severity;
  final EvidenceLevel evidenceLevel;

  bool matches(DeviceSafetyProfile device) {
    final gate = profileGate;
    if (gate == null) return medicationIds.any(device.medicationIds.contains);
    return evaluateProfileGate(
      gate,
      UserProfile(
        conditions: device.conditions,
        drugClasses: device.medicationIds,
        profileFlags: device.profileFlags,
      ),
      const ProductContext(),
    ).fires;
  }

  /// Malformed or newer blocks skip this one alert rather than rejecting the
  /// feed: a bad interaction block must not cost anyone the bans in the same
  /// release. An unknown evidence value only loses its grade.
  factory SafetyAlertInteraction.fromJson(Object? json) {
    if (json is! Map) throw const UnsupportedSafetyAlert('interaction');
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw const UnsupportedSafetyAlert('interaction');
      }
      return value.trim();
    }

    final targetsMedication =
        json.containsKey('medication_ids') ||
        json.containsKey('medication_name');
    final targetsProfile =
        json.containsKey('profile_gate') || json.containsKey('profile_context');
    if (targetsMedication == targetsProfile) {
      throw const UnsupportedSafetyAlert('interaction');
    }
    final severity = switch (json['severity']) {
      'contraindicated' => Severity.contraindicated,
      'avoid' => Severity.avoid,
      'caution' => Severity.caution,
      'monitor' => Severity.monitor,
      _ => throw const UnsupportedSafetyAlert('interaction severity'),
    };
    final evidence = json['evidence_level'];
    return SafetyAlertInteraction(
      ruleId: text('rule_id'),
      ingredientName: text('ingredient_name'),
      medicationName: targetsMedication ? text('medication_name') : null,
      medicationIds: targetsMedication
          ? Set.unmodifiable(_medicationIds(json['medication_ids']))
          : const {},
      profileGate: targetsProfile ? _deviceGate(json['profile_gate']) : null,
      profileContext: targetsProfile ? text('profile_context') : null,
      severity: severity,
      evidenceLevel: EvidenceLevel.fromString(
        evidence is String ? evidence : '',
      ),
    );
  }

  static Set<String> _medicationIds(Object? ids) {
    if (ids is! List || ids.isEmpty) {
      throw const UnsupportedSafetyAlert('interaction');
    }
    return {
      for (final id in ids)
        if (id is String && id.trim().isNotEmpty)
          id.trim()
        else
          throw const UnsupportedSafetyAlert('interaction'),
    };
  }

  /// A gate the profile alone can answer, narrowed to someone. A gate with no
  /// requirement fires for everyone, a dose or a form needs a product in hand,
  /// and a key this build doesn't know would be ignored, widening the rule.
  static Map<String, dynamic> _deviceGate(Object? raw) {
    const unsupported = UnsupportedSafetyAlert('interaction profile_gate');
    if (raw is! Map) throw unsupported;
    final gate = Map<String, dynamic>.from(raw);
    if (validateProfileGate(gate).isNotEmpty || gate['dose'] != null) {
      throw unsupported;
    }
    const profileKeys = {
      'conditions_any',
      'drug_classes_any',
      'profile_flags_any',
    };
    final requires = gate['requires'];
    final excludes = gate['excludes'];
    if (requires is! Map || excludes is! Map) throw unsupported;
    bool populated(Object? value) => value is List && value.isNotEmpty;
    if (!profileKeys.any((key) => populated(requires[key])) ||
        requires.keys.any(
          (key) => !profileKeys.contains(key) && populated(requires[key]),
        ) ||
        excludes.keys.any(
          (key) => !profileKeys.contains(key) && populated(excludes[key]),
        )) {
      throw unsupported;
    }
    return gate;
  }
}

/// A well-formed alert written for a newer app: its event type or disposition
/// isn't one this build knows. Skipped rather than treated as damage, so
/// publishing a new alert kind can't cost older builds the alerts they can read.
class UnsupportedSafetyAlert extends FormatException {
  const UnsupportedSafetyAlert(String field)
    : super('Safety alert $field is unsupported.');
}

final class SafetyAlert {
  const SafetyAlert({
    required this.alertId,
    required this.revision,
    required this.eventType,
    required this.sourceUrl,
    required this.headline,
    required this.body,
    required this.action,
    required this.disposition,
    required this.resolvedDsldIds,
    required this.ingredientCanonicalIds,
    this.interaction,
  });

  final String alertId;
  final int revision;
  final SafetyAlertEventType eventType;
  final Uri sourceUrl;
  final String headline;
  final String body;
  final String action;
  final SafetyAlertDisposition disposition;
  final Set<String> resolvedDsldIds;
  final Set<String> ingredientCanonicalIds;

  /// Present only on an `interaction_rule`.
  final SafetyAlertInteraction? interaction;

  /// Ingredient, medication, reason, what to do and evidence grade, for any
  /// surface showing this as a notice. Null unless this is an interaction rule.
  String? get interactionNotice {
    final rule = interaction;
    if (rule == null) return null;
    final target = rule.medicationName != null
        ? 'Medication: ${rule.medicationName}'
        : 'Applies to: ${rule.profileContext}';
    return 'Ingredient: ${rule.ingredientName}\n'
        '$target\n\n'
        '$body\n\n'
        '$action\n\n'
        '${rule.evidenceLevel.label}';
  }

  /// A damaged ban or recall rejects the feed, so the last good copy stays. A
  /// damaged interaction rule skips itself instead: this type must not cost
  /// anyone the bans in the same release, which is what older builds do with it.
  factory SafetyAlert.fromJson(Map<String, Object?> json) {
    try {
      return SafetyAlert._parse(json);
    } on FormatException {
      final id = json['alert_id'];
      if (json['event_type'] == 'interaction_rule' &&
          id is String &&
          id.trim().isNotEmpty) {
        throw const UnsupportedSafetyAlert('interaction_rule');
      }
      rethrow;
    }
  }

  factory SafetyAlert._parse(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Safety alert $key is required.');
      }
      return value.trim();
    }

    final id = requiredString('alert_id');
    if (!RegExp(r'^SA_[0-9]{4}_[0-9]{4}$').hasMatch(id)) {
      throw const FormatException('Safety alert id is malformed.');
    }
    final revision = json['revision'];
    if (revision is! int || revision < 1) {
      throw const FormatException('Safety alert revision is malformed.');
    }
    final eventType = switch (requiredString('event_type')) {
      'ingredient_ban' => SafetyAlertEventType.ingredientBan,
      'product_recall' => SafetyAlertEventType.productRecall,
      'interaction_rule' => SafetyAlertEventType.interactionRule,
      _ => throw const UnsupportedSafetyAlert('event type'),
    };
    final disposition = switch (requiredString('consumer_disposition')) {
      'block' => SafetyAlertDisposition.block,
      'review' => SafetyAlertDisposition.review,
      _ => throw const UnsupportedSafetyAlert('disposition'),
    };
    final sourceUrl = Uri.tryParse(requiredString('source_url'));
    if (sourceUrl == null ||
        sourceUrl.scheme != 'https' ||
        sourceUrl.host.isEmpty) {
      throw const FormatException('Safety alert source is not an HTTPS URL.');
    }
    final resolved = _stringSet(json['resolved_dsld_ids'], 'resolved_dsld_ids');
    final scope = json['scope'];
    if (scope is! Map) {
      throw const FormatException('Safety alert scope is malformed.');
    }
    final ingredients = _stringSet(
      scope['ingredient_canonical_ids'],
      'scope.ingredient_canonical_ids',
    );
    return SafetyAlert(
      alertId: id,
      revision: revision,
      eventType: eventType,
      sourceUrl: sourceUrl,
      headline: requiredString('headline'),
      body: requiredString('body'),
      action: requiredString('action'),
      disposition: disposition,
      resolvedDsldIds: resolved,
      ingredientCanonicalIds: ingredients,
      interaction: eventType == SafetyAlertEventType.interactionRule
          ? SafetyAlertInteraction.fromJson(json['interaction'])
          : null,
    );
  }

  /// [device] stays on the device. An interaction rule never applies without
  /// a match on it, so nobody else is told about it; it plays no part in the
  /// other event types.
  bool appliesTo({
    required String dsldId,
    required Iterable<String> ingredientCanonicalIds,
    required DeviceSafetyProfile device,
  }) {
    final rule = interaction;
    if (rule != null && !rule.matches(device)) return false;
    if (resolvedDsldIds.contains(dsldId)) return true;
    return ingredientCanonicalIds.any(this.ingredientCanonicalIds.contains);
  }

  static Set<String> _stringSet(Object? value, String field) {
    if (value is! List) {
      throw FormatException('Safety alert $field is malformed.');
    }
    final result = <String>{};
    for (final item in value) {
      if (item is! String || item.trim().isEmpty) {
        throw FormatException('Safety alert $field has an invalid value.');
      }
      result.add(item.trim());
    }
    return Set.unmodifiable(result);
  }
}
