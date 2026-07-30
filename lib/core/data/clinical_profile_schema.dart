import 'package:flutter/foundation.dart';

enum ProfileCaptureMode { derivedFromCondition, userSelectable, reserved }

@immutable
class ClinicalProfileOption {
  final String id;
  final String label;
  final String description;
  final int displayPriority;

  const ClinicalProfileOption({
    required this.id,
    required this.label,
    required this.description,
    required this.displayPriority,
  });
}

@immutable
class ClinicalProfileFlag {
  final String id;
  final String label;
  final String description;
  final ProfileCaptureMode captureMode;
  final String? sourceConditionId;

  const ClinicalProfileFlag({
    required this.id,
    required this.label,
    required this.description,
    required this.captureMode,
    this.sourceConditionId,
  });
}

/// Typed app boundary for the pipeline-owned clinical profile taxonomy.
///
/// The JSON owns IDs, labels, order, and capture behavior. UI surfaces consume
/// this model instead of maintaining Dart mirrors.
@immutable
class ClinicalProfileSchema {
  final List<ClinicalProfileOption> selectableConditions;
  final List<ClinicalProfileFlag> userSelectableFlags;
  final Map<String, String> derivedFlagByCondition;

  const ClinicalProfileSchema({
    required this.selectableConditions,
    required this.userSelectableFlags,
    required this.derivedFlagByCondition,
  });

  factory ClinicalProfileSchema.fromJson(Map<String, dynamic> json) {
    final rawConditions = json['conditions'];
    final rawFlags = json['profile_flags'];
    if (rawConditions is! List || rawFlags is! List) {
      throw const FormatException(
        'Clinical profile taxonomy requires conditions and profile_flags lists',
      );
    }

    final conditionIds = <String>{};
    final conditions = <ClinicalProfileOption>[];
    for (final raw in rawConditions) {
      if (raw is! Map) {
        throw const FormatException('Clinical condition must be an object');
      }
      final entry = Map<String, dynamic>.from(raw);
      final id = _requiredString(entry, 'id', section: 'condition');
      if (!conditionIds.add(id)) {
        throw FormatException('Duplicate clinical condition id: $id');
      }
      if (entry['user_selectable'] != true) continue;
      final priority = entry['display_priority'];
      if (priority is! num) {
        throw FormatException('$id: display_priority must be numeric');
      }
      conditions.add(
        ClinicalProfileOption(
          id: id,
          label: _requiredString(entry, 'label', section: id),
          description: _requiredString(entry, 'description', section: id),
          displayPriority: priority.round(),
        ),
      );
    }
    conditions.sort(
      (left, right) => left.displayPriority.compareTo(right.displayPriority),
    );
    if (conditions.isEmpty) {
      throw const FormatException(
        'Clinical profile taxonomy has no selectable conditions',
      );
    }

    final flagIds = <String>{};
    final selectableFlags = <ClinicalProfileFlag>[];
    final derivedByCondition = <String, String>{};
    for (final raw in rawFlags) {
      if (raw is! Map) {
        throw const FormatException('Clinical profile flag must be an object');
      }
      final entry = Map<String, dynamic>.from(raw);
      final id = _requiredString(entry, 'id', section: 'profile flag');
      if (!flagIds.add(id)) {
        throw FormatException('Duplicate clinical profile flag id: $id');
      }
      final mode = _parseCaptureMode(entry['capture_mode'], flagId: id);
      final sourceConditionId = entry['source_condition_id']?.toString().trim();
      final flag = ClinicalProfileFlag(
        id: id,
        label: _requiredString(entry, 'label', section: id),
        description: _requiredString(entry, 'description', section: id),
        captureMode: mode,
        sourceConditionId: sourceConditionId?.isEmpty == true
            ? null
            : sourceConditionId,
      );

      switch (mode) {
        case ProfileCaptureMode.derivedFromCondition:
          final source = flag.sourceConditionId;
          if (source == null || !conditionIds.contains(source)) {
            throw FormatException(
              '$id: derived profile flag needs a known source_condition_id',
            );
          }
          if (derivedByCondition.putIfAbsent(source, () => id) != id) {
            throw FormatException(
              '$source derives more than one clinical profile flag',
            );
          }
        case ProfileCaptureMode.userSelectable:
          if (flag.sourceConditionId != null) {
            throw FormatException(
              '$id: user-selectable flag cannot declare source_condition_id',
            );
          }
          selectableFlags.add(flag);
        case ProfileCaptureMode.reserved:
          if (flag.sourceConditionId != null) {
            throw FormatException(
              '$id: reserved flag cannot declare source_condition_id',
            );
          }
      }
    }

    return ClinicalProfileSchema(
      selectableConditions: List.unmodifiable(conditions),
      userSelectableFlags: List.unmodifiable(selectableFlags),
      derivedFlagByCondition: Map.unmodifiable(derivedByCondition),
    );
  }

  String? conditionLabel(String id) {
    for (final condition in selectableConditions) {
      if (condition.id == id) return condition.label;
    }
    return null;
  }

  String? profileFlagLabel(String id) {
    for (final flag in userSelectableFlags) {
      if (flag.id == id) return flag.label;
    }
    return null;
  }

  Set<String> evaluatorFlags({
    required Iterable<String> conditions,
    required Iterable<String> explicitFlags,
  }) {
    final result = <String>{...explicitFlags};
    for (final condition in conditions) {
      final derived = derivedFlagByCondition[condition];
      if (derived != null) result.add(derived);
    }
    return result;
  }
}

String _requiredString(
  Map<String, dynamic> entry,
  String key, {
  required String section,
}) {
  final value = entry[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('$section: $key must be a non-empty string');
  }
  return value;
}

ProfileCaptureMode _parseCaptureMode(dynamic value, {required String flagId}) {
  return switch (value) {
    'derived_from_condition' => ProfileCaptureMode.derivedFromCondition,
    'user_selectable' => ProfileCaptureMode.userSelectable,
    'reserved' => ProfileCaptureMode.reserved,
    _ => throw FormatException('$flagId: unknown capture_mode $value'),
  };
}
