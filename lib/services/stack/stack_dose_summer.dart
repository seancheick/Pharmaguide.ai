import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/units/dose_units.dart';
import 'package:pharmaguide/core/utils/num_parse.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';
import 'package:pharmaguide/services/ingredients/ingredient_row_fields.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

List<StackDoseThresholdRule> stackDoseThresholdRulesFromWarnings(
  Iterable<InteractionWarning> warnings, {
  String stackEntryId = '',
  String productName = '',
}) {
  final rules = <StackDoseThresholdRule>[];
  final seen = <String>{};

  for (final warning in warnings) {
    final ingredientName = warning.ingredientName?.trim();
    if (ingredientName == null || ingredientName.isEmpty) continue;
    final decision = warning.doseDecision;
    final emittedCanonicalId = warning.ingredientCanonicalId?.trim() ?? '';
    // New declarative rules must use the pipeline-owned identity. Name-based
    // canonicalization remains only for pre-contract cached blobs.
    final canonicalId = decision != null
        ? emittedCanonicalId
        : canonicalizeIngredientName(ingredientName);
    if (canonicalId.isEmpty) continue;
    final targets = <({String type, String id})>[
      for (final value in warning.conditionIds) (type: 'condition', id: value),
      for (final value in warning.drugClassIds) (type: 'drug_class', id: value),
    ];

    final decisionRule = decision?.decisionRule;
    final decisionThreshold = decisionRule?.threshold ?? decision?.threshold;
    final decisionUnit =
        decisionRule?.thresholdUnit?.trim() ?? decision?.thresholdUnit?.trim();
    final decisionComparator =
        decisionRule?.comparator?.trim() ?? decision?.comparator?.trim();
    if (decision != null &&
        decisionThreshold != null &&
        decisionThreshold > 0 &&
        decisionUnit != null &&
        decisionUnit.isNotEmpty &&
        decisionComparator != null &&
        decisionComparator.isNotEmpty) {
      for (final target in targets) {
        final targetId = target.id.trim().toLowerCase();
        if (targetId.isEmpty) continue;
        final marker =
            '${target.type}|$targetId|$canonicalId|$decisionThreshold|'
            '${decisionUnit.toLowerCase()}|$decisionComparator';
        if (!seen.add(marker)) continue;
        rules.add(
          StackDoseThresholdRule(
            conditionId: targetId,
            targetType: target.type,
            canonicalId: canonicalId,
            displayName: ingredientName,
            thresholdValue: decisionThreshold,
            thresholdUnit: decisionUnit,
            comparator: decisionComparator,
            clinicalSeverity:
                decision.clinicalSeverity ?? warning.severity.name,
            consumerDispositionIfMet:
                decisionRule?.consumerDispositionIfMet ?? 'review',
            consumerDispositionIfNotMet:
                decisionRule?.consumerDispositionIfNotMet ?? 'suppress',
            normalizedDailyAmount: decision.evaluatedDailyAmount,
            normalizedDailyUnit: decision.evaluatedUnit,
            sourceStackEntryId: stackEntryId,
            sourceProductName: productName,
          ),
        );
      }
      continue;
    }

    final rawThresholds =
        warning.doseThresholdEvaluation?['thresholds_checked'];
    if (rawThresholds is! List) continue;

    for (final target in targets) {
      final targetId = target.id.trim().toLowerCase();
      if (targetId.isEmpty) continue;

      for (final rawThreshold in rawThresholds) {
        if (rawThreshold is! Map) continue;
        final thresholdValue = asFiniteDouble(rawThreshold['threshold_value']);
        final thresholdUnit = rawThreshold['threshold_unit']?.toString().trim();
        if (thresholdValue == null ||
            thresholdValue <= 0 ||
            thresholdUnit == null ||
            thresholdUnit.isEmpty) {
          continue;
        }

        final marker =
            '${target.type}|$targetId|$canonicalId|$thresholdValue|${thresholdUnit.toLowerCase()}';
        if (!seen.add(marker)) continue;

        rules.add(
          StackDoseThresholdRule(
            conditionId: targetId,
            targetType: target.type,
            canonicalId: canonicalId,
            displayName: ingredientName,
            thresholdValue: thresholdValue,
            thresholdUnit: thresholdUnit,
            comparator: rawThreshold['comparator']?.toString().trim() ?? '>=',
            clinicalSeverity: warning.severity.name,
            sourceStackEntryId: stackEntryId,
            sourceProductName: productName,
          ),
        );
      }
    }
  }

  return rules;
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
        if (!isUsableDoseRow(row)) continue;

        final keys = readDoseNameKeys(row);
        if (keys.isEmpty) continue;

        final amount = readDoseAmount(row);
        if (amount == null || amount <= 0) continue;

        final unit = readDoseUnit(row);
        final displayName = readDisplayName(row) ?? keys.first;
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

  /// Evaluate cumulative exposure using only pipeline-normalized values.
  ///
  /// No unit conversion or clinical inference occurs here. Every product's
  /// warning contributes the daily exposure already converted by the pipeline
  /// into the rule's semantic threshold unit. Missing exposure is omitted; it
  /// never becomes an assumed maximum or an incomplete warning.
  List<StackDoseThresholdAlert> thresholdAlertsFromNormalizedRules({
    required Iterable<String> userConditions,
    Iterable<String> userDrugClasses = const <String>[],
    required Iterable<StackDoseThresholdRule> thresholdRules,
  }) {
    final activeConditions = userConditions
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final activeDrugClasses = userDrugClasses
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (activeConditions.isEmpty && activeDrugClasses.isEmpty) return const [];

    final grouped = <String, List<StackDoseThresholdRule>>{};
    for (final rule in thresholdRules) {
      final targetId = rule.conditionId.trim().toLowerCase();
      final targetIsActive = rule.targetType == 'drug_class'
          ? activeDrugClasses.contains(targetId)
          : activeConditions.contains(targetId);
      if (!targetIsActive) continue;
      final unit = normalizeDoseUnit(rule.thresholdUnit);
      final key =
          '${rule.targetType}|$targetId|${rule.canonicalId}|${rule.thresholdValue}|'
          '$unit|${rule.comparator}|${rule.consumerDispositionIfMet}';
      grouped.putIfAbsent(key, () => []).add(rule);
    }

    final alerts = <StackDoseThresholdAlert>[];
    for (final rules in grouped.values) {
      final representative = rules.first;
      final thresholdUnit = normalizeDoseUnit(representative.thresholdUnit);
      var total = 0.0;
      final contributions = <StackDoseContribution>[];
      for (final rule in rules) {
        final amount = rule.normalizedDailyAmount;
        final unit = normalizeDoseUnit(rule.normalizedDailyUnit ?? '');
        if (amount == null || amount <= 0 || unit != thresholdUnit) continue;
        total += amount;
        contributions.add(
          StackDoseContribution(
            stackEntryId: rule.sourceStackEntryId,
            productName: rule.sourceProductName,
            amount: amount,
            unit: thresholdUnit,
          ),
        );
      }
      if (contributions.isEmpty ||
          !_compareDose(
            total,
            representative.comparator,
            representative.thresholdValue,
          ) ||
          !const {
            'review',
            'block',
          }.contains(representative.consumerDispositionIfMet)) {
        continue;
      }
      alerts.add(
        StackDoseThresholdAlert(
          conditionId: representative.conditionId,
          targetType: representative.targetType,
          canonicalId: representative.canonicalId,
          displayName: representative.displayName ?? representative.canonicalId,
          totalValue: total,
          unit: thresholdUnit,
          thresholdValue: representative.thresholdValue,
          thresholdUnit: thresholdUnit,
          comparator: representative.comparator,
          contributions: List.unmodifiable(contributions),
          clinicalSeverity: representative.clinicalSeverity,
          consumerDisposition: representative.consumerDispositionIfMet,
        ),
      );
    }
    return alerts;
  }

  bool _compareDose(double amount, String comparator, double threshold) {
    return switch (comparator.trim()) {
      '>' => amount > threshold,
      '>=' => amount >= threshold,
      '<' => amount < threshold,
      '<=' => amount <= threshold,
      '==' => amount == threshold,
      _ => false,
    };
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
        final isIncomplete = dose.hasExcludedContributions;
        if (totalInThresholdUnit < rule.thresholdValue && !isIncomplete) {
          continue;
        }

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
            comparator: rule.comparator,
            contributions: dose.contributions,
            isIncomplete: isIncomplete,
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
    // Inherit source exclusions + record any whole source total dropped on a
    // unit mismatch, so this fresh alias total surfaces incompleteness the
    // same way the direct path does (compareThreshold must not suppress on an
    // undercount).
    final excluded = <ExcludedStackDoseContribution>[];

    for (final total in matchingTotals) {
      excluded.addAll(total.excludedContributions);
      final converted = amountInMass(
        total.totalValue,
        from: total.unit,
        to: anchor.unit,
      );
      if (converted == null) {
        excluded.add(
          ExcludedStackDoseContribution(
            contribution: StackDoseContribution(
              stackEntryId: '',
              productName: total.displayName,
              amount: total.totalValue,
              unit: total.unit,
            ),
            reason: StackDoseExclusionReason.unitConflict,
          ),
        );
        continue;
      }

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
      excludedContributions: List.unmodifiable(excluded),
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
      inheritedExclusions: _inheritedExclusions(totals, {
        ..._omega3EpaDhaAliases,
        ..._omega3TotalAliases,
        ..._omega3FishOilAliases,
      }),
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
    List<ExcludedStackDoseContribution> inheritedExclusions = const [],
  }) {
    if (contributions.isEmpty) return null;

    final unit = contributions.first.unit;
    if (unit.isEmpty) return null;

    var totalValue = 0.0;
    final convertedContributions = <StackDoseContribution>[];
    // This path builds a FRESH total, so it must surface incompleteness the
    // same way the direct `totals[key]` path does: compareThreshold refuses to
    // SUPPRESS a warning when the total carries excluded contributions (an
    // undercount must never justify suppression). Carry forward the source
    // totals' exclusions AND record any unit-mismatch we drop here.
    final excluded = <ExcludedStackDoseContribution>[...inheritedExclusions];
    for (final contribution in contributions) {
      final converted = amountInMass(
        contribution.amount,
        from: contribution.unit,
        to: unit,
      );
      if (converted == null) {
        excluded.add(
          ExcludedStackDoseContribution(
            contribution: contribution,
            reason: StackDoseExclusionReason.unitConflict,
          ),
        );
        continue;
      }
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
      excludedContributions: List.unmodifiable(excluded),
    );
  }

  /// Collect the excluded contributions from every source total present under
  /// [aliases]. A threshold total combined from these sources inherits their
  /// incompleteness so the downstream suppression gate fails open.
  List<ExcludedStackDoseContribution> _inheritedExclusions(
    Map<String, StackDoseTotal> totals,
    Set<String> aliases,
  ) {
    final excluded = <ExcludedStackDoseContribution>[];
    for (final alias in aliases) {
      final total = totals[alias];
      if (total != null) excluded.addAll(total.excludedContributions);
    }
    return excluded;
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

  static double? _amountInThresholdUnit({
    required String canonicalId,
    required double amount,
    required String from,
    required String to,
  }) {
    final normalizedFrom = normalizeDoseUnit(from);
    final normalizedTo = normalizeDoseUnit(to);
    final simple = amountInMass(amount, from: normalizedFrom, to: normalizedTo);
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
    this.targetType = 'condition',
    required this.canonicalId,
    this.displayName,
    required this.thresholdValue,
    required this.thresholdUnit,
    this.comparator = '>=',
    this.clinicalSeverity = 'caution',
    this.consumerDispositionIfMet = 'review',
    this.consumerDispositionIfNotMet = 'suppress',
    this.normalizedDailyAmount,
    this.normalizedDailyUnit,
    this.sourceStackEntryId = '',
    this.sourceProductName = '',
  });

  final String conditionId;

  /// `condition` or `drug_class`. [conditionId] is retained as the stable
  /// target-id field for compatibility with existing consumers.
  final String targetType;
  final String canonicalId;
  final String? displayName;
  final double thresholdValue;
  final String thresholdUnit;
  final String comparator;
  final String clinicalSeverity;
  final String consumerDispositionIfMet;
  final String consumerDispositionIfNotMet;
  final double? normalizedDailyAmount;
  final String? normalizedDailyUnit;
  final String sourceStackEntryId;
  final String sourceProductName;
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
    this.targetType = 'condition',
    required this.canonicalId,
    required this.displayName,
    required this.totalValue,
    required this.unit,
    required this.thresholdValue,
    required this.thresholdUnit,
    this.comparator = '>=',
    required this.contributions,
    this.isIncomplete = false,
    this.clinicalSeverity = 'caution',
    this.consumerDisposition = 'review',
  });

  final String conditionId;
  final String targetType;
  final String canonicalId;
  final String displayName;
  final double totalValue;
  final String unit;
  final double thresholdValue;
  final String thresholdUnit;
  final String comparator;
  final List<StackDoseContribution> contributions;

  /// True when the known comparable subtotal omitted at least one source row
  /// because its dose/unit could not be safely compared. The alert is still
  /// surfaced so the stack does not look cleared by an undercount, but callers
  /// should use hedge copy rather than claiming the threshold was proven.
  final bool isIncomplete;
  final String clinicalSeverity;
  final String consumerDisposition;
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
