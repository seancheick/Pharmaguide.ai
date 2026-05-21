import 'package:flutter/foundation.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/condition_thresholds.dart';

/// Conservative stack-level ingredient dose summer.
///
/// This is intentionally separate from [StackNutrientAggregator]. The nutrient
/// aggregator is for RDA/UL math keyed to nutrient reference rows; this service
/// is for profile-gate dose thresholds where the same active ingredient can
/// appear across multiple products. It only converts simple mass units
/// (`g`/`mg`/`mcg`). IU, RAE, DFE, NE, and form-dependent units are summed only
/// when the units match exactly.
class StackDoseSummer {
  const StackDoseSummer();

  Map<String, StackDoseTotal> sum(List<StackItemNutrients> stack) {
    final accum = <String, _MutableStackDoseTotal>{};

    for (final item in stack) {
      for (final row in item.ingredients) {
        if (!_isUsableDoseRow(row)) continue;

        final keys = _doseKeys(row);
        if (keys.isEmpty) continue;

        final amount = _readAmount(row);
        if (amount == null || amount <= 0) continue;

        final unit = _readUnit(row);
        final displayName = _readDisplayName(row) ?? keys.first;
        final exclusionReason = _exclusionReason(row, unit);

        for (final key in keys) {
          final total = accum.putIfAbsent(
            key,
            () => _MutableStackDoseTotal(
              canonicalId: key,
              displayName: displayName,
              unit: exclusionReason == null ? unit : '',
            ),
          );

          final contribution = StackDoseContribution(
            stackEntryId: item.stackEntryId,
            productName: item.productName,
            amount: amount,
            unit: unit,
          );

          if (exclusionReason != null) {
            total.excludedContributions.add(
              ExcludedStackDoseContribution(
                contribution: contribution,
                reason: exclusionReason,
              ),
            );
            continue;
          }

          if (total.unit.isEmpty) total.unit = unit;
          final converted = _amountInUnit(amount, from: unit, to: total.unit);
          if (converted == null) {
            total.excludedContributions.add(
              ExcludedStackDoseContribution(
                contribution: contribution,
                reason: StackDoseExclusionReason.unitConflict,
              ),
            );
            continue;
          }

          total.contributions.add(
            StackDoseContribution(
              stackEntryId: item.stackEntryId,
              productName: item.productName,
              amount: converted,
              unit: total.unit,
            ),
          );
          total.totalValue += converted;

          if (displayName.length > total.displayName.length) {
            total.displayName = displayName;
          }
        }
      }
    }

    return accum.map(
      (key, value) => MapEntry(
        key,
        StackDoseTotal(
          canonicalId: value.canonicalId,
          displayName: value.displayName,
          totalValue: value.totalValue,
          unit: value.unit,
          contributions: List.unmodifiable(value.contributions),
          excludedContributions: List.unmodifiable(value.excludedContributions),
        ),
      ),
    );
  }

  List<StackDoseThresholdAlert> thresholdAlerts({
    required Map<String, StackDoseTotal> totals,
    required Iterable<String> userConditions,
  }) {
    final alerts = <StackDoseThresholdAlert>[];
    final seen = <String>{};

    for (final rawCondition in userConditions) {
      final conditionId = rawCondition.trim().toLowerCase();
      if (conditionId.isEmpty) continue;

      final thresholds = conditionThresholds[conditionId];
      if (thresholds == null) continue;

      for (final entry in thresholds.entries) {
        final threshold = entry.value;
        if (threshold.directionality != NutrientDirectionality.neutral) {
          continue;
        }
        final thresholdValue = threshold.minDose;
        final thresholdUnit = threshold.doseUnit;
        if (thresholdValue == null || thresholdUnit == null) continue;

        final dose = _thresholdTotalFor(entry.key, totals);
        if (dose == null || dose.totalValue <= 0 || dose.unit.isEmpty) {
          continue;
        }

        final normalizedThresholdUnit = _normalizeUnit(thresholdUnit);
        final totalInThresholdUnit = _amountInUnit(
          dose.totalValue,
          from: dose.unit,
          to: normalizedThresholdUnit,
        );
        if (totalInThresholdUnit == null) continue;
        if (totalInThresholdUnit < thresholdValue) continue;

        final marker = '$conditionId:${dose.canonicalId}';
        if (!seen.add(marker)) continue;

        alerts.add(
          StackDoseThresholdAlert(
            conditionId: conditionId,
            canonicalId: dose.canonicalId,
            displayName: dose.displayName,
            totalValue: totalInThresholdUnit,
            unit: normalizedThresholdUnit,
            thresholdValue: thresholdValue,
            thresholdUnit: normalizedThresholdUnit,
            contributions: dose.contributions,
          ),
        );
      }
    }

    return alerts;
  }

  StackDoseTotal? _thresholdTotalFor(
    String thresholdKey,
    Map<String, StackDoseTotal> totals,
  ) {
    final canonicalKey = canonicalizeIngredientName(thresholdKey);
    if (canonicalKey.isEmpty) return null;

    final aliases = _thresholdDoseAliases[canonicalKey];
    if (aliases == null) return totals[canonicalKey];

    final matchingTotals = <StackDoseTotal>[];
    for (final alias in aliases) {
      final total = totals[alias];
      if (total != null && total.totalValue > 0 && total.unit.isNotEmpty) {
        matchingTotals.add(total);
      }
    }
    if (matchingTotals.isEmpty) return null;

    final anchor = matchingTotals.first;
    var totalValue = 0.0;
    final contributions = <StackDoseContribution>[];

    for (final total in matchingTotals) {
      final converted = _amountInUnit(
        total.totalValue,
        from: total.unit,
        to: anchor.unit,
      );
      if (converted == null) continue;

      totalValue += converted;
      contributions.addAll(
        total.contributions.map(
          (contribution) => StackDoseContribution(
            stackEntryId: contribution.stackEntryId,
            productName: contribution.productName,
            amount:
                _amountInUnit(
                  contribution.amount,
                  from: contribution.unit,
                  to: anchor.unit,
                ) ??
                contribution.amount,
            unit: anchor.unit,
          ),
        ),
      );
    }

    if (totalValue <= 0) return null;
    final alertKey = _thresholdDoseCanonicalIds[canonicalKey] ?? canonicalKey;
    return StackDoseTotal(
      canonicalId: alertKey,
      displayName: _thresholdDoseDisplayNames[alertKey] ?? anchor.displayName,
      totalValue: totalValue,
      unit: anchor.unit,
      contributions: List.unmodifiable(contributions),
    );
  }

  bool _isUsableDoseRow(Map<String, dynamic> row) {
    final isActive = row['is_active'];
    if (isActive is bool && !isActive) return false;

    final isLabelDescriptor = row['is_label_descriptor'];
    if (isLabelDescriptor is bool && isLabelDescriptor) return false;

    final isBlend = row['is_proprietary_blend'];
    if (isBlend is bool && isBlend) return false;

    final isParentTotal = row['is_parent_total'];
    if (isParentTotal is bool && isParentTotal) return false;

    return true;
  }

  Set<String> _doseKeys(Map<String, dynamic> row) {
    final keys = <String>{};
    for (final field in const [
      'standard_name',
      'name',
      'ingredient',
      'mapped_name',
      'canonical_id',
      'normalized_key',
    ]) {
      final raw = row[field]?.toString();
      if (raw == null || raw.trim().isEmpty) continue;
      final key = canonicalizeIngredientName(raw);
      if (key.isNotEmpty) keys.add(key);
    }
    return keys;
  }

  double? _readAmount(Map<String, dynamic> row) {
    final candidates = <Object?>[
      row['per_day_max'],
      row['daily_amount'],
      row['quantity'],
      row['dose_amount'],
      row['converted_quantity'],
      row['amount'],
      row['normalized_amount'],
      row['normalizedAmount'],
      row['dosage'],
    ];
    for (final candidate in candidates) {
      final parsed = _asDouble(candidate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _readUnit(Map<String, dynamic> row) {
    final candidates = <Object?>[
      row['daily_amount_unit'],
      row['unit'],
      row['dose_unit'],
      row['converted_unit'],
      row['normalized_unit'],
      row['normalizedUnit'],
      row['dosage_unit'],
    ];
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return _normalizeUnit(candidate);
      }
    }
    return '';
  }

  String? _readDisplayName(Map<String, dynamic> row) {
    for (final field in const [
      'display_name',
      'display_label',
      'name',
      'standard_name',
      'standardName',
      'ingredient',
    ]) {
      final raw = row[field]?.toString().trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return null;
  }

  StackDoseExclusionReason? _exclusionReason(
    Map<String, dynamic> row,
    String unit,
  ) {
    if (row['skip_ul_check'] == true) {
      return StackDoseExclusionReason.skippedByPipeline;
    }
    if (unit.isEmpty) return StackDoseExclusionReason.missingUnit;
    if (unit == 'np' || unit == 'n/p' || unit == 'not provided') {
      return StackDoseExclusionReason.notProvidedUnit;
    }
    if (unit == 'unspecified' || unit == 'unknown') {
      return StackDoseExclusionReason.unsupportedUnit;
    }
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is double && value.isFinite) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }

  static double? _amountInUnit(
    double amount, {
    required String from,
    required String to,
  }) {
    if (from.isEmpty || to.isEmpty) return null;
    if (from == to) return amount;

    final fromGrams = _simpleMassGramsFactor(from);
    final toGrams = _simpleMassGramsFactor(to);
    if (fromGrams == null || toGrams == null) return null;
    return amount * fromGrams / toGrams;
  }

  static double? _simpleMassGramsFactor(String unit) {
    return switch (unit) {
      'g' || 'gram' || 'grams' || 'gram(s)' => 1.0,
      'mg' => 0.001,
      'mcg' || 'microgram' || 'micrograms' => 0.000001,
      _ => null,
    };
  }

  static String _normalizeUnit(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll('µg', 'mcg')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static const Map<String, Set<String>> _thresholdDoseAliases = {
    // Condition thresholds for omega-3/fish oil are written against
    // combined EPA + DHA intake. Labels often split those fatty acids into
    // separate rows, so the threshold evaluator must sum them together.
    'omega_3': {'omega_3', 'omega_3_fatty_acids', 'fish_oil', 'epa', 'dha'},
    'fish_oil': {'omega_3', 'omega_3_fatty_acids', 'fish_oil', 'epa', 'dha'},
  };

  static const Map<String, String> _thresholdDoseDisplayNames = {
    'omega_3': 'Omega-3 (EPA/DHA)',
  };

  static const Map<String, String> _thresholdDoseCanonicalIds = {
    'fish_oil': 'omega_3',
  };
}

@immutable
class StackDoseContribution {
  const StackDoseContribution({
    required this.stackEntryId,
    required this.productName,
    required this.amount,
    required this.unit,
  });

  final String stackEntryId;
  final String productName;
  final double amount;
  final String unit;
}

enum StackDoseExclusionReason {
  missingUnit,
  notProvidedUnit,
  unsupportedUnit,
  unitConflict,
  skippedByPipeline,
}

@immutable
class ExcludedStackDoseContribution {
  const ExcludedStackDoseContribution({
    required this.contribution,
    required this.reason,
  });

  final StackDoseContribution contribution;
  final StackDoseExclusionReason reason;
}

@immutable
class StackDoseTotal {
  const StackDoseTotal({
    required this.canonicalId,
    required this.displayName,
    required this.totalValue,
    required this.unit,
    required this.contributions,
    this.excludedContributions = const [],
  });

  final String canonicalId;
  final String displayName;
  final double totalValue;
  final String unit;
  final List<StackDoseContribution> contributions;
  final List<ExcludedStackDoseContribution> excludedContributions;

  bool get hasExcludedContributions => excludedContributions.isNotEmpty;
}

@immutable
class StackDoseThresholdAlert {
  const StackDoseThresholdAlert({
    required this.conditionId,
    required this.canonicalId,
    required this.displayName,
    required this.totalValue,
    required this.unit,
    required this.thresholdValue,
    required this.thresholdUnit,
    required this.contributions,
  });

  final String conditionId;
  final String canonicalId;
  final String displayName;
  final double totalValue;
  final String unit;
  final double thresholdValue;
  final String thresholdUnit;
  final List<StackDoseContribution> contributions;
}

class _MutableStackDoseTotal {
  _MutableStackDoseTotal({
    required this.canonicalId,
    required this.displayName,
    required this.unit,
  });

  final String canonicalId;
  String displayName;
  String unit;
  double totalValue = 0;
  final List<StackDoseContribution> contributions = [];
  final List<ExcludedStackDoseContribution> excludedContributions = [];
}
