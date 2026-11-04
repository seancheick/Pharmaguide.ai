import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/constants/consumer_disposition.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/units/dose_units.dart';
import 'package:pharmaguide/core/utils/num_parse.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';
import 'package:pharmaguide/services/ingredients/ingredient_row_fields.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';

List<StackDoseThresholdRule> stackDoseThresholdRulesFromWarnings(
  Iterable<InteractionWarning> warnings, {
  String stackEntryId = '',
  String productName = '',
}) {
  final rules = <StackDoseThresholdRule>[];
  final seen = <String>{};
  final decisionRuleAt = <String, int>{};

  for (final warning in warnings) {
    final ingredientName = warning.ingredientName?.trim();
    if (ingredientName == null || ingredientName.isEmpty) continue;
    final decision = warning.doseDecision;
    if (decision != null &&
        (decision.formExcluded || warning.unreadBetaCaroteneAddsNothing)) {
      continue;
    }
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
        final rule = StackDoseThresholdRule(
          conditionId: targetId,
          targetType: target.type,
          canonicalId: canonicalId,
          displayName: ingredientName,
          thresholdValue: decisionThreshold,
          thresholdUnit: decisionUnit,
          comparator: decisionComparator,
          clinicalSeverity: Severity.fromString(
            decision.clinicalSeverity ?? warning.severity.name,
          ),
          consumerDispositionIfMet: consumerDispositionFromWire(
            decisionRule?.consumerDispositionIfMet,
          ),
          // The exported amount can be an exclusive lower bound. At the
          // exact boundary, retain the pipeline's proven strict comparison;
          // do not replace it with an invented point amount.
          normalizedAmountIsStrictLowerBound:
              decision.evaluationStatus == 'above_threshold' &&
              const {
                'block',
                'review',
                'good_to_know',
              }.contains(decision.consumerDisposition) &&
              decisionComparator == '>' &&
              decision.evaluatedDailyAmount == decisionThreshold &&
              normalizeDoseUnit(decision.evaluatedUnit ?? '') ==
                  normalizeDoseUnit(decisionUnit) &&
              decision.threshold == decisionThreshold &&
              normalizeDoseUnit(decision.thresholdUnit ?? '') ==
                  normalizeDoseUnit(decisionUnit) &&
              decision.comparator == decisionComparator,
          normalizedDailyAmount: decision.evaluatedDailyAmount,
          normalizedDailyUnit: decision.evaluatedUnit,
          sourceStackEntryId: stackEntryId,
          sourceProductName: productName,
          amountUnresolved: decision.amountUnread,
        );
        final at = decisionRuleAt[marker];
        if (at == null) {
          decisionRuleAt[marker] = rules.length;
          rules.add(rule);
        } else {
          rules[at] = rules[at]._mergedWith(rule);
        }
      }
      continue;
    }
    if (decision != null && decision.amountUnread) continue;

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
            clinicalSeverity: warning.severity,
            sourceStackEntryId: stackEntryId,
            sourceProductName: productName,
          ),
        );
      }
    }
  }

  return rules;
}

/// Approved wording, shown verbatim. Its "20 mg" is true only of the
/// 10,000 mcg RAE tier, so the card reads that tier and no other.
const String kBetaCaroteneStackCardBody =
    'Your stack supplies 20 mg or more of beta-carotene a day. At similar '
    'doses it raised lung cancer risk in smokers, former smokers and '
    'asbestos-exposed workers. Ask your doctor if any apply to you.';
const double _betaCaroteneCardThresholdMcgRae = 10000;
const String _betaCaroteneCardUnit = 'mcg rae';

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

  Map<String, StackDoseTotal> sum(
    List<StackItemNutrients> stack, {
    bool formFactsComplete = true,
  }) {
    final accum = <String, _MutableStackDoseTotal>{};
    final incompleteFormKeys = <String>{};

    for (final item in stack) {
      for (final row in item.ingredients) {
        if (!isUsableDoseRow(row)) continue;

        final keys = readDoseNameKeys(row);
        if (keys.isEmpty) continue;

        final amount = readDoseAmount(row);
        if (amount == null || amount <= 0) {
          incompleteFormKeys.addAll(keys);
          continue;
        }

        final unit = readDoseUnit(row);
        final displayName = readDisplayName(row) ?? keys.first;
        final exclusionReason = _exclusionReason(row, unit, item.ingredients);

        for (final key in keys) {
          final total = accum.putIfAbsent(
            key,
            () => _MutableStackDoseTotal(
              canonicalId: key,
              displayName: displayName,
              unit: exclusionReason == null ? unit : '',
            ),
          );

          final forms = readMatchedForms(row);
          if (forms == null || forms.length != 1 || exclusionReason != null) {
            total.formsComplete = false;
          }

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
          if (forms != null && forms.length == 1) {
            total.formTotals.update(
              forms.single,
              (v) => v + converted,
              ifAbsent: () => converted,
            );
          }

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
          formTotals:
              formFactsComplete &&
                  value.formsComplete &&
                  !incompleteFormKeys.contains(key)
              ? Map.unmodifiable(value.formTotals)
              : null,
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
          '$unit|${rule.comparator}';
      grouped.putIfAbsent(key, () => []).add(rule);
    }

    final alerts = <StackDoseThresholdAlert>[];
    for (final rules in grouped.values) {
      final representative = rules.first;
      final clinicalSeverity = rules.fold<Severity>(
        representative.clinicalSeverity,
        (current, rule) => rule.clinicalSeverity.weight > current.weight
            ? rule.clinicalSeverity
            : current,
      );
      final consumerDisposition = rules.fold<ConsumerDisposition>(
        representative.consumerDispositionIfMet,
        (current, rule) => rule.consumerDispositionIfMet.rank > current.rank
            ? rule.consumerDispositionIfMet
            : current,
      );
      final thresholdUnit = normalizeDoseUnit(representative.thresholdUnit);
      var total = 0.0;
      var totalIsStrictLowerBound = false;
      final contributions = <StackDoseContribution>[];
      for (final rule in rules) {
        final amount = rule.normalizedDailyAmount;
        final unit = normalizeDoseUnit(rule.normalizedDailyUnit ?? '');
        if (amount == null || amount <= 0 || unit != thresholdUnit) continue;
        total += amount;
        totalIsStrictLowerBound |= rule.normalizedAmountIsStrictLowerBound;
        contributions.add(
          StackDoseContribution(
            stackEntryId: rule.sourceStackEntryId,
            productName: rule.sourceProductName,
            amount: amount,
            unit: thresholdUnit,
          ),
        );
      }
      final comparatorKnown = _isKnownComparator(representative.comparator);
      final thresholdMet =
          _compareDose(
            total,
            representative.comparator,
            representative.thresholdValue,
          ) ||
          (representative.comparator.trim() == '>' &&
              total == representative.thresholdValue &&
              totalIsStrictLowerBound);
      if (contributions.isEmpty ||
          (comparatorKnown && !thresholdMet) ||
          !consumerDisposition.isVisible) {
        continue;
      }
      // A label above the higher line ships its row at that line only, but the
      // alert states what the whole stack supplies.
      if (representative.canonicalId == 'beta_carotene') {
        final byEntry = <String, StackDoseContribution>{};
        final strictByEntry = <String, bool>{};
        for (final rule in thresholdRules) {
          final amount = rule.normalizedDailyAmount;
          if (rule.canonicalId != representative.canonicalId ||
              rule.targetType != representative.targetType ||
              rule.conditionId.trim().toLowerCase() !=
                  representative.conditionId.trim().toLowerCase() ||
              amount == null ||
              amount <= 0 ||
              normalizeDoseUnit(rule.normalizedDailyUnit ?? '') !=
                  thresholdUnit) {
            continue;
          }
          final held = byEntry[rule.sourceStackEntryId];
          if (held == null || amount > held.amount) {
            strictByEntry[rule.sourceStackEntryId] =
                rule.normalizedAmountIsStrictLowerBound;
            byEntry[rule.sourceStackEntryId] = StackDoseContribution(
              stackEntryId: rule.sourceStackEntryId,
              productName: rule.sourceProductName,
              amount: amount,
              unit: thresholdUnit,
            );
          } else if (amount == held.amount) {
            strictByEntry[rule.sourceStackEntryId] =
                strictByEntry[rule.sourceStackEntryId]! ||
                rule.normalizedAmountIsStrictLowerBound;
          }
        }
        final whole = byEntry.values.fold(0.0, (sum, c) => sum + c.amount);
        if (whole > total) {
          total = whole;
          totalIsStrictLowerBound = strictByEntry.values.any((value) => value);
          contributions
            ..clear()
            ..addAll(byEntry.values);
        }
      }
      alerts.add(
        StackDoseThresholdAlert(
          conditionId: representative.conditionId,
          targetType: representative.targetType,
          canonicalId: representative.canonicalId,
          displayName: representative.displayName ?? representative.canonicalId,
          totalValue: total,
          totalIsStrictLowerBound: totalIsStrictLowerBound,
          unit: thresholdUnit,
          thresholdValue: representative.thresholdValue,
          thresholdUnit: thresholdUnit,
          comparator: representative.comparator,
          contributions: List.unmodifiable(contributions),
          isIncomplete:
              !comparatorKnown || rules.any((rule) => rule.amountUnresolved),
          clinicalSeverity: clinicalSeverity,
          consumerDisposition: consumerDisposition,
        ),
      );
    }
    return alerts;
  }

  /// The 20 mg beta-carotene card for a stack with no risk-factor id present.
  ///
  /// The tier is the every-viewer `/ dose` card the pipeline ships, and a
  /// person with one of its risk factors gets that tier as a condition alert
  /// instead. Each product counts once: its two lung-cancer rules describe one
  /// exposure, so their cards are not added together.
  StackDoseThresholdAlert? betaCaroteneStackCardAlert({
    required Iterable<String> userConditions,
    required Iterable<
      ({
        String stackEntryId,
        String productName,
        Iterable<InteractionWarning> warnings,
      })
    >
    products,
  }) {
    final activeConditions = userConditions
        .map((value) => value.trim().toLowerCase())
        .toSet();
    final contributions = <StackDoseContribution>[];
    var total = 0.0;
    var hasUnread = false;
    var severity = Severity.safe;
    var disposition = ConsumerDisposition.suppress;
    String? comparator;

    for (final product in products) {
      double? productAmount;
      for (final warning in product.warnings) {
        final decision = warning.doseDecision;
        final rule = decision?.decisionRule;
        final threshold = rule?.threshold ?? decision?.threshold;
        final unit = rule?.thresholdUnit ?? decision?.thresholdUnit;
        if (decision == null ||
            warning.ingredientCanonicalId?.trim() != 'beta_carotene' ||
            // A card naming no risk factors can't tell who has one.
            warning.conditionIds.isEmpty ||
            warning.profileGate?['gate_type'] != 'dose' ||
            profileGateRequiresProfile(warning.profileGate) ||
            threshold != _betaCaroteneCardThresholdMcgRae ||
            unit == null ||
            normalizeDoseUnit(unit) != _betaCaroteneCardUnit) {
          continue;
        }
        if (warning.conditionIds.any(
          (id) => activeConditions.contains(id.trim().toLowerCase()),
        )) {
          return null;
        }

        comparator ??= (rule?.comparator ?? decision.comparator)?.trim();
        final gateDose = warning.profileGate?['dose'];
        final severityIfMet = Severity.fromString(
          (gateDose is Map ? gateDose['severity_if_met']?.toString() : null) ??
              '',
        );
        if (severityIfMet.weight > severity.weight) severity = severityIfMet;
        final dispositionIfMet = consumerDispositionFromWire(
          rule?.consumerDispositionIfMet,
        );
        if (dispositionIfMet.rank > disposition.rank) {
          disposition = dispositionIfMet;
        }

        final amount = decision.evaluatedDailyAmount;
        final amountUnit = normalizeDoseUnit(decision.evaluatedUnit ?? '');
        if (amount == null ||
            amount < 0 ||
            amountUnit != _betaCaroteneCardUnit) {
          hasUnread = hasUnread || !warning.unreadBetaCaroteneAddsNothing;
        } else if (amount > 0 &&
            (productAmount == null || amount > productAmount)) {
          productAmount = amount;
        }
      }
      if (productAmount == null) continue;
      total += productAmount;
      contributions.add(
        StackDoseContribution(
          stackEntryId: product.stackEntryId,
          productName: product.productName,
          amount: productAmount,
          unit: _betaCaroteneCardUnit,
        ),
      );
    }

    final readComparator = comparator ?? '';
    final comparatorKnown = _isKnownComparator(readComparator);
    if (contributions.isEmpty ||
        !disposition.isVisible ||
        (comparatorKnown &&
            !_compareDose(
              total,
              readComparator,
              _betaCaroteneCardThresholdMcgRae,
            ))) {
      return null;
    }
    return StackDoseThresholdAlert(
      conditionId: 'unknown',
      targetType: 'risk_status',
      canonicalId: 'beta_carotene',
      displayName: 'Beta-carotene',
      totalValue: total,
      unit: _betaCaroteneCardUnit,
      thresholdValue: _betaCaroteneCardThresholdMcgRae,
      thresholdUnit: _betaCaroteneCardUnit,
      comparator: readComparator,
      contributions: List.unmodifiable(contributions),
      isIncomplete: hasUnread || !comparatorKnown,
      clinicalSeverity: severity,
      consumerDisposition: disposition,
      consumerBody: comparatorKnown ? kBetaCaroteneStackCardBody : null,
    );
  }

  /// Whether the most a stack's beta-carotene mixtures could hold reaches a tier
  /// for this person that its confirmed amounts don't.
  ///
  /// The two stay apart: an amount on a decision is confirmed and can cross a
  /// tier, and a mixture row's `safety_exposure` high is only the maximum, so it
  /// can leave the check unresolved but never make an alert or a card. The
  /// pipeline owns the conversion, and a mcg RAE row with no mass has a high of 0.
  bool betaCaroteneMaximumUnresolved({
    required Iterable<String> userConditions,
    required Iterable<
      ({
        Iterable<InteractionWarning> warnings,
        Iterable<Map<String, dynamic>> rows,
      })
    >
    products,
  }) {
    final activeConditions = userConditions
        .map((value) => value.trim().toLowerCase())
        .toSet();
    var maximum = 0.0;
    final tiers = <({double threshold, String comparator})>{};
    final confirmedByProduct =
        <Map<({double threshold, String comparator}), double>>[];

    for (final product in products) {
      for (final row in product.rows) {
        // Not readCanonicalId: it answers vitamin_a, the row's nutrient group.
        if (row['canonical_id'] != 'beta_carotene' ||
            readUlDoseUnit(row) != _betaCaroteneCardUnit) {
          continue;
        }
        maximum += readUlDoseRange(row)?.high ?? 0;
      }
      final confirmed = <({double threshold, String comparator}), double>{};
      for (final warning in product.warnings) {
        final decision = warning.doseDecision;
        final rule = decision?.decisionRule;
        final threshold = rule?.threshold ?? decision?.threshold;
        final unit = rule?.thresholdUnit ?? decision?.thresholdUnit;
        final comparator = (rule?.comparator ?? decision?.comparator)?.trim();
        if (decision == null ||
            warning.ingredientCanonicalId?.trim() != 'beta_carotene' ||
            !warning.conditionIds.any(
              (id) => activeConditions.contains(id.trim().toLowerCase()),
            ) ||
            threshold == null ||
            comparator == null ||
            !_isKnownComparator(comparator) ||
            normalizeDoseUnit(unit ?? '') != _betaCaroteneCardUnit) {
          continue;
        }
        final tier = (threshold: threshold, comparator: comparator);
        tiers.add(tier);
        final amount = decision.evaluatedDailyAmount;
        if (amount != null &&
            amount > (confirmed[tier] ?? 0) &&
            normalizeDoseUnit(decision.evaluatedUnit ?? '') ==
                _betaCaroteneCardUnit) {
          confirmed[tier] = amount;
        }
      }
      confirmedByProduct.add(confirmed);
    }

    if (maximum <= 0) return false;
    return tiers.any((tier) {
      final confirmed = confirmedByProduct.fold<double>(
        0,
        (total, product) => total + (product[tier] ?? 0),
      );
      return !_compareDose(confirmed, tier.comparator, tier.threshold) &&
          _compareDose(confirmed + maximum, tier.comparator, tier.threshold);
    });
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

  bool _isKnownComparator(String comparator) =>
      const {'>', '>=', '<', '<=', '=='}.contains(comparator.trim());

  List<StackDoseThresholdAlert> thresholdAlerts({
    required Map<String, StackDoseTotal> totals,
    required Iterable<String> userConditions,
    Iterable<String> userDrugClasses = const <String>[],
    required Iterable<StackDoseThresholdRule> thresholdRules,
  }) {
    final alerts = <StackDoseThresholdAlert>[];
    final seen = <String>{};
    final activeConditions = userConditions
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final activeDrugClasses = userDrugClasses
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();

    for (final rule in thresholdRules) {
      final targetId = rule.conditionId.trim().toLowerCase();
      if (targetId.isEmpty) continue;
      final targetIsActive = rule.targetType == 'drug_class'
          ? activeDrugClasses.contains(targetId)
          : activeConditions.contains(targetId);
      if (!targetIsActive || !rule.consumerDispositionIfMet.isVisible) continue;

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
      final isIncomplete =
          dose.hasExcludedContributions || !_isKnownComparator(rule.comparator);
      if (!isIncomplete &&
          !_compareDose(
            totalInThresholdUnit,
            rule.comparator,
            rule.thresholdValue,
          )) {
        continue;
      }

      final marker = '${rule.targetType}:$targetId:${dose.canonicalId}';
      if (!seen.add(marker)) continue;

      alerts.add(
        StackDoseThresholdAlert(
          conditionId: targetId,
          targetType: rule.targetType,
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
          clinicalSeverity: rule.clinicalSeverity,
          consumerDisposition: rule.consumerDispositionIfMet,
        ),
      );
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
    List<Map<String, dynamic>> labelRows,
  ) {
    if (pipelineBlocksDoseReadOnLabel(row, labelRows)) {
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
    this.clinicalSeverity = Severity.caution,
    this.consumerDispositionIfMet = ConsumerDisposition.review,
    this.normalizedDailyAmount,
    this.normalizedAmountIsStrictLowerBound = false,
    this.normalizedDailyUnit,
    this.sourceStackEntryId = '',
    this.sourceProductName = '',
    this.amountUnresolved = false,
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
  final Severity clinicalSeverity;
  final ConsumerDisposition consumerDispositionIfMet;
  final double? normalizedDailyAmount;

  /// Internal arithmetic metadata carried from the authored dose decision.
  final bool normalizedAmountIsStrictLowerBound;
  final String? normalizedDailyUnit;
  final String sourceStackEntryId;
  final String sourceProductName;

  /// The pipeline could not read this product's amount for this rule, on this
  /// card or another for the same rule, so [normalizedDailyAmount] may not be
  /// its whole exposure. Its label rows are no substitute for that amount.
  final bool amountUnresolved;

  bool get _hasAmount =>
      (normalizedDailyAmount ?? -1) >= 0 &&
      normalizedDailyUnit?.trim().isNotEmpty == true;

  /// One product's two cards for one rule describe one exposure: the larger
  /// amount stands, in place of adding them or keeping whichever came first.
  StackDoseThresholdRule _mergedWith(StackDoseThresholdRule other) {
    final sameUnit =
        normalizeDoseUnit(normalizedDailyUnit ?? '') ==
        normalizeDoseUnit(other.normalizedDailyUnit ?? '');
    final amountFrom = !_hasAmount
        ? other
        : other._hasAmount &&
              sameUnit &&
              other.normalizedDailyAmount! > normalizedDailyAmount!
        ? other
        : this;
    return StackDoseThresholdRule(
      conditionId: conditionId,
      targetType: targetType,
      canonicalId: canonicalId,
      displayName: displayName,
      thresholdValue: thresholdValue,
      thresholdUnit: thresholdUnit,
      comparator: comparator,
      clinicalSeverity: other.clinicalSeverity.weight > clinicalSeverity.weight
          ? other.clinicalSeverity
          : clinicalSeverity,
      consumerDispositionIfMet:
          other.consumerDispositionIfMet.rank > consumerDispositionIfMet.rank
          ? other.consumerDispositionIfMet
          : consumerDispositionIfMet,
      normalizedDailyAmount: amountFrom.normalizedDailyAmount,
      normalizedAmountIsStrictLowerBound:
          amountFrom.normalizedAmountIsStrictLowerBound ||
          (sameUnit &&
              normalizedDailyAmount == other.normalizedDailyAmount &&
              (normalizedAmountIsStrictLowerBound ||
                  other.normalizedAmountIsStrictLowerBound)),
      normalizedDailyUnit: amountFrom.normalizedDailyUnit,
      sourceStackEntryId: sourceStackEntryId,
      sourceProductName: sourceProductName,
      amountUnresolved:
          amountUnresolved ||
          other.amountUnresolved ||
          !_hasAmount ||
          !other._hasAmount,
    );
  }
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
    this.formTotals,
    this.isDailyExposureConfirmed = false,
  });

  final String canonicalId;
  final String displayName;
  final double totalValue;
  final String unit;
  final List<StackDoseContribution> contributions;
  final List<ExcludedStackDoseContribution> excludedContributions;
  final Map<String, double>? formTotals;

  /// Label serving amounts are not proof of the current total daily intake.
  final bool isDailyExposureConfirmed;

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
    this.totalIsStrictLowerBound = false,
    required this.unit,
    required this.thresholdValue,
    required this.thresholdUnit,
    this.comparator = '>=',
    required this.contributions,
    this.isIncomplete = false,
    this.clinicalSeverity = Severity.caution,
    this.consumerDisposition = ConsumerDisposition.review,
    this.consumerBody,
  });

  final String conditionId;
  final String targetType;
  final String canonicalId;
  final String displayName;
  final double totalValue;

  /// The actual total is strictly greater than the recorded lower bound.
  final bool totalIsStrictLowerBound;
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
  final Severity clinicalSeverity;
  final ConsumerDisposition consumerDisposition;

  /// Approved wording shown as written, in place of the generic threshold text.
  final String? consumerBody;
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
  bool formsComplete = true;
  final Map<String, double> formTotals = {};
  final List<StackDoseContribution> contributions = [];
  final List<ExcludedStackDoseContribution> excludedContributions = [];
}
