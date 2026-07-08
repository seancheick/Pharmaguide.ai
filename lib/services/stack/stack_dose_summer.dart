import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/units/dose_units.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

List<StackDoseThresholdRule> stackDoseThresholdRulesFromWarnings(
  Iterable<InteractionWarning> warnings,
) {
  final rules = <StackDoseThresholdRule>[];
  final seen = <String>{};

  for (final warning in warnings) {
    final ingredientName = warning.ingredientName?.trim();
    if (ingredientName == null || ingredientName.isEmpty) continue;
    final canonicalId = canonicalizeIngredientName(ingredientName);
    if (canonicalId.isEmpty) continue;

    final rawThresholds =
        warning.doseThresholdEvaluation?['thresholds_checked'];
    if (rawThresholds is! List) continue;

    for (final rawCondition in warning.conditionIds) {
      final conditionId = rawCondition.trim().toLowerCase();
      if (conditionId.isEmpty) continue;

      for (final rawThreshold in rawThresholds) {
        if (rawThreshold is! Map) continue;
        final thresholdValue = StackDoseSummer._asDouble(
          rawThreshold['threshold_value'],
        );
        final thresholdUnit = rawThreshold['threshold_unit']?.toString().trim();
        if (thresholdValue == null ||
            thresholdValue <= 0 ||
            thresholdUnit == null ||
            thresholdUnit.isEmpty) {
          continue;
        }

        final marker =
            '$conditionId|$canonicalId|$thresholdValue|${thresholdUnit.toLowerCase()}';
        if (!seen.add(marker)) continue;

        rules.add(
          StackDoseThresholdRule(
            conditionId: conditionId,
            canonicalId: canonicalId,
            displayName: ingredientName,
            thresholdValue: thresholdValue,
            thresholdUnit: thresholdUnit,
          ),
        );
      }
    }
  }

  return rules;
}

List<StackDoseThresholdRule> stackDoseThresholdRulesFromDetailBlob(
  Map<String, dynamic>? detailBlob,
) {
  if (detailBlob == null) return const [];

  final warnings = <InteractionWarning>[];
  for (final key in const ['warnings', 'warnings_profile_gated']) {
    final raw = detailBlob[key];
    if (raw is! List) continue;
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      try {
        warnings.add(InteractionWarning.fromJson(entry));
      } on Object {
        continue;
      }
    }
  }

  return stackDoseThresholdRulesFromWarnings(warnings);
}

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
          final converted = amountInMass(amount, from: unit, to: total.unit);
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
    required Iterable<StackDoseThresholdRule> thresholdRules,
  }) {
    final alerts = <StackDoseThresholdAlert>[];
    final seen = <String>{};
    final rulesByCondition = <String, List<StackDoseThresholdRule>>{};
    for (final rule in thresholdRules) {
      final conditionId = rule.conditionId.trim().toLowerCase();
      if (conditionId.isEmpty) continue;
      rulesByCondition.putIfAbsent(conditionId, () => []).add(rule);
    }

    for (final rawCondition in userConditions) {
      final conditionId = rawCondition.trim().toLowerCase();
      if (conditionId.isEmpty) continue;

      final rules = rulesByCondition[conditionId];
      if (rules == null) continue;

      for (final rule in rules) {
        final dose = _thresholdTotalFor(rule.canonicalId, totals);
        if (dose == null || dose.totalValue <= 0 || dose.unit.isEmpty) {
          continue;
        }

        final normalizedThresholdUnit = normalizeDoseUnit(rule.thresholdUnit);
        final totalInThresholdUnit = _amountInThresholdUnit(
          canonicalId: dose.canonicalId,
          amount: dose.totalValue,
          from: dose.unit,
          to: normalizedThresholdUnit,
        );
        if (totalInThresholdUnit == null) continue;
        if (totalInThresholdUnit < rule.thresholdValue) continue;

        final marker = '$conditionId:${dose.canonicalId}';
        if (!seen.add(marker)) continue;

        alerts.add(
          StackDoseThresholdAlert(
            conditionId: conditionId,
            canonicalId: dose.canonicalId,
            displayName:
                _thresholdDoseDisplayNames[dose.canonicalId] ??
                rule.displayName ??
                dose.displayName,
            totalValue: totalInThresholdUnit,
            unit: normalizedThresholdUnit,
            thresholdValue: rule.thresholdValue,
            thresholdUnit: normalizedThresholdUnit,
            contributions: dose.contributions,
          ),
        );
      }
    }

    return alerts;
  }

  StackDoseThresholdComparison compareThreshold({
    required Map<String, StackDoseTotal> totals,
    required String canonicalId,
    required double thresholdValue,
    required String thresholdUnit,
  }) {
    if (thresholdValue <= 0) return StackDoseThresholdComparison.unavailable;

    final dose = _thresholdTotalFor(canonicalId, totals);
    if (dose == null || dose.totalValue <= 0 || dose.unit.isEmpty) {
      return StackDoseThresholdComparison.unavailable;
    }
    // Fail OPEN when the total dropped a mismatched-unit contribution. This
    // total is used to SUPPRESS a warning below a floor; an undercount (e.g. a
    // stack holding vitamin E in both mg and IU, where the non-anchor unit is
    // excluded) must never justify suppression — the true combined dose could
    // be above the floor. Suppression requires a COMPLETE, comparable total.
    if (dose.hasExcludedContributions) {
      return StackDoseThresholdComparison.unavailable;
    }

    final normalizedThresholdUnit = normalizeDoseUnit(thresholdUnit);
    final totalInThresholdUnit = _amountInThresholdUnit(
      canonicalId: dose.canonicalId,
      amount: dose.totalValue,
      from: dose.unit,
      to: normalizedThresholdUnit,
    );
    if (totalInThresholdUnit == null) {
      return StackDoseThresholdComparison.unavailable;
    }

    return totalInThresholdUnit < thresholdValue
        ? StackDoseThresholdComparison.below
        : StackDoseThresholdComparison.atOrAbove;
  }

  StackDoseTotal? _thresholdTotalFor(
    String thresholdKey,
    Map<String, StackDoseTotal> totals,
  ) {
    final canonicalKey = canonicalizeIngredientName(thresholdKey);
    if (canonicalKey.isEmpty) return null;

    if (_omega3ThresholdKeys.contains(canonicalKey)) {
      return _omega3ThresholdTotal(totals);
    }

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
      final converted = amountInMass(
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
                amountInMass(
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

  StackDoseTotal? _omega3ThresholdTotal(Map<String, StackDoseTotal> totals) {
    final epaDha = _contributionsByProduct(totals, _omega3EpaDhaAliases);
    final totalOmega3 = _contributionsByProduct(totals, _omega3TotalAliases);
    final fishOil = _contributionsByProduct(totals, _omega3FishOilAliases);

    final productKeys = <String>{
      ...epaDha.keys,
      ...totalOmega3.keys,
      ...fishOil.keys,
    };
    final selected = <StackDoseContribution>[];

    for (final productKey in productKeys) {
      final epaDhaRows = epaDha[productKey];
      if (epaDhaRows != null && epaDhaRows.isNotEmpty) {
        selected.addAll(epaDhaRows);
        continue;
      }

      final totalRows = totalOmega3[productKey];
      if (totalRows != null && totalRows.isNotEmpty) {
        selected.addAll(totalRows);
        continue;
      }

      final fishOilRows = fishOil[productKey];
      if (fishOilRows != null && fishOilRows.isNotEmpty) {
        selected.addAll(fishOilRows);
      }
    }

    return _combinedThresholdTotal(
      canonicalId: 'omega_3',
      displayName: _thresholdDoseDisplayNames['omega_3'] ?? 'Omega-3',
      contributions: selected,
    );
  }

  Map<String, List<StackDoseContribution>> _contributionsByProduct(
    Map<String, StackDoseTotal> totals,
    Set<String> aliases,
  ) {
    final byProduct = <String, List<StackDoseContribution>>{};
    for (final alias in aliases) {
      final total = totals[alias];
      if (total == null || total.totalValue <= 0 || total.unit.isEmpty) {
        continue;
      }
      for (final contribution in total.contributions) {
        final key = contribution.stackEntryId.isNotEmpty
            ? contribution.stackEntryId
            : contribution.productName;
        if (key.isEmpty) continue;
        byProduct.putIfAbsent(key, () => []).add(contribution);
      }
    }
    return byProduct;
  }

  StackDoseTotal? _combinedThresholdTotal({
    required String canonicalId,
    required String displayName,
    required List<StackDoseContribution> contributions,
  }) {
    if (contributions.isEmpty) return null;

    final unit = contributions.first.unit;
    if (unit.isEmpty) return null;

    var totalValue = 0.0;
    final convertedContributions = <StackDoseContribution>[];
    for (final contribution in contributions) {
      final converted = amountInMass(
        contribution.amount,
        from: contribution.unit,
        to: unit,
      );
      if (converted == null) continue;
      totalValue += converted;
      convertedContributions.add(
        StackDoseContribution(
          stackEntryId: contribution.stackEntryId,
          productName: contribution.productName,
          amount: converted,
          unit: unit,
        ),
      );
    }

    if (totalValue <= 0) return null;
    return StackDoseTotal(
      canonicalId: canonicalId,
      displayName: displayName,
      totalValue: totalValue,
      unit: unit,
      contributions: List.unmodifiable(convertedContributions),
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
        return normalizeDoseUnit(candidate);
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

  static double? _amountInThresholdUnit({
    required String canonicalId,
    required double amount,
    required String from,
    required String to,
  }) {
    final normalizedFrom = normalizeDoseUnit(from);
    final normalizedTo = normalizeDoseUnit(to);
    final simple = amountInMass(
      amount,
      from: normalizedFrom,
      to: normalizedTo,
    );
    if (simple != null) return simple;

    if (canonicalId == 'vitamin_e') {
      return _vitaminEUpperBoundConversion(
        amount,
        from: normalizedFrom,
        to: normalizedTo,
      );
    }

    return null;
  }

  static double? _vitaminEUpperBoundConversion(
    double amount, {
    required String from,
    required String to,
  }) {
    if (from == 'mg' && to == 'iu') {
      // Conservative upper bound for unknown vitamin E form:
      // synthetic alpha-tocopherol can be 2.22 IU per mg.
      return amount * 2.22;
    }
    if (from == 'iu' && to == 'mg') {
      // Conservative upper bound for unknown vitamin E form:
      // natural alpha-tocopherol can be 0.67 mg per IU.
      return amount * 0.67;
    }
    return null;
  }

  static const Set<String> _omega3ThresholdKeys = {'omega_3', 'fish_oil'};
  static const Set<String> _omega3EpaDhaAliases = {'epa', 'dha'};
  static const Set<String> _omega3TotalAliases = {
    'omega_3',
    'omega_3_fatty_acids',
  };
  static const Set<String> _omega3FishOilAliases = {'fish_oil'};

  static const Map<String, Set<String>> _thresholdDoseAliases = {};

  static const Map<String, String> _thresholdDoseDisplayNames = {
    'omega_3': 'Omega-3 (EPA/DHA)',
  };

  static const Map<String, String> _thresholdDoseCanonicalIds = {
    'fish_oil': 'omega_3',
  };
}

@immutable
class StackDoseThresholdRule {
  const StackDoseThresholdRule({
    required this.conditionId,
    required this.canonicalId,
    this.displayName,
    required this.thresholdValue,
    required this.thresholdUnit,
  });

  final String conditionId;
  final String canonicalId;
  final String? displayName;
  final double thresholdValue;
  final String thresholdUnit;
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

enum StackDoseThresholdComparison { below, atOrAbove, unavailable }

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
