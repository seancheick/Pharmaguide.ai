import 'package:pharmaguide/core/constants/severity.dart';

/// A single recalled ingredient found in a product in the user's stack.
///
/// The `warningMessage` field was removed in Sprint 27.6 after the
/// derived strings in the bundled asset were found to be medically
/// incorrect for ~30-40 of 139 entries (pre-baked sentences inverted
/// the safety signal for pharmaceutical adulterants like metformin).
/// Replacement: the pipeline now ships authored `safety_warning` +
/// `safety_warning_one_liner` + `ban_context`, and Flutter passes them
/// through verbatim. No Flutter-side derivation from `reason`.
class RecalledIngredientAlert {
  final String canonicalId;
  final List<String> commonNames;
  final String recallStatus; // 'banned', 'recalled', or advisory status
  final String regulatoryBasis;
  final String reason;
  final String effectiveDate;
  final String severity; // 'critical' or 'major'
  final String safetyWarning;
  final String safetyWarningOneLiner;
  final String banContext;

  RecalledIngredientAlert({
    required this.canonicalId,
    required this.commonNames,
    required this.recallStatus,
    required this.regulatoryBasis,
    required this.reason,
    required this.effectiveDate,
    required this.severity,
    required this.safetyWarning,
    required this.safetyWarningOneLiner,
    required this.banContext,
  });

  /// Convert to Severity enum for consistent UI rendering
  Severity get displaySeverity {
    switch (severity) {
      case 'critical':
        return Severity.contraindicated;
      case 'major':
        return Severity.avoid;
      default:
        return Severity.caution;
    }
  }

  /// Human-readable status label
  String get statusLabel {
    if (recallStatus == 'banned') return 'BANNED';
    if (recallStatus == 'recalled') return 'RECALLED';
    return 'WARNING';
  }
}

/// Product in the user's stack that contains recalled ingredients.
class RecalledIngredientViolation {
  final String productDsldId;
  final String productName;
  final String brandName;
  final List<RecalledIngredientAlert> recalledIngredients;
  final bool pipelineBannedSubstance;
  final bool pipelineRecalledProduct;

  RecalledIngredientViolation({
    required this.productDsldId,
    required this.productName,
    required this.brandName,
    required this.recalledIngredients,
    this.pipelineBannedSubstance = false,
    this.pipelineRecalledProduct = false,
  });

  bool get isBannedSubstance =>
      pipelineBannedSubstance ||
      recalledIngredients.any((alert) => alert.recallStatus == 'banned');

  bool get isRecalledProduct =>
      pipelineRecalledProduct ||
      recalledIngredients.any((alert) => alert.recallStatus == 'recalled');

  /// Highest severity from all recalled ingredients in this product.
  ///
  /// A violation only exists because the pipeline flagged this product, so an
  /// empty ingredient list means "we could not name the substance", never
  /// "nothing is wrong". Returning `safe` there would let the one product we
  /// are certain about rank below every ordinary caution.
  Severity get worstSeverity {
    if (recalledIngredients.isEmpty) return Severity.avoid;
    final severities = recalledIngredients
        .map((r) => r.displaySeverity)
        .toList();
    // contraindicated > avoid > caution > monitor > safe
    if (severities.contains(Severity.contraindicated)) {
      return Severity.contraindicated;
    }
    // Floored at `avoid`, never lower. A violation exists only because the
    // pipeline flagged the product, so an authored record with a softer
    // severity may sharpen this verdict but must never soften it below the
    // hard tier — otherwise one `minor` record could rank a blocked product
    // alongside an ordinary caution.
    return Severity.avoid;
  }

  /// Human-readable alert for the banner.
  ///
  /// The unnamed case is real: the pipeline flags the product, but no authored
  /// record matches its ingredient ids, so we can state the finding without
  /// naming the substance. Returning an empty string here would silently blank
  /// the banner on a product we know is flagged.
  String get bannerMessage {
    if (recalledIngredients.isEmpty) {
      if (isBannedSubstance) {
        return 'BANNED — $productName contains a substance not permitted in '
            'supplements.';
      }
      return 'RECALLED — $productName is flagged by the product catalog. '
          'Check the product lot and recall notice before using it.';
    }
    final verb = _verbFor(recalledIngredients.first.banContext);
    final status = isBannedSubstance
        ? 'BANNED'
        : isRecalledProduct
        ? 'RECALLED'
        : recalledIngredients.first.statusLabel;
    if (recalledIngredients.length == 1) {
      final ing = recalledIngredients.first;
      final name = ing.commonNames.isNotEmpty
          ? ing.commonNames.first
          : ing.canonicalId;
      final oneLiner = ing.safetyWarningOneLiner.trim();
      final suffix = oneLiner.isEmpty ? '' : ' $oneLiner';
      return '$status — $productName $verb $name.$suffix';
    }
    return '$status — $productName '
        '$verb ${recalledIngredients.length} flagged ingredient(s)';
  }

  String _verbFor(String banContext) {
    switch (banContext) {
      case 'adulterant_in_supplements':
        return 'may contain undeclared';
      case 'substance':
        return 'contains banned';
      case 'watchlist':
        return 'contains watchlisted';
      case 'export_restricted':
        return 'contains export-restricted';
      case 'contamination_recall':
        return 'is subject to a recall involving';
      default:
        return 'contains flagged';
    }
  }
}

/// Aggregated recall status for a user's stack.
class RecalledIngredientsReport {
  final List<RecalledIngredientViolation> violations;
  final bool incomplete;

  bool get isEmpty => violations.isEmpty;

  const RecalledIngredientsReport({
    required this.violations,
    this.incomplete = false,
  });

  factory RecalledIngredientsReport.empty({bool incomplete = false}) {
    return RecalledIngredientsReport(
      violations: const [],
      incomplete: incomplete,
    );
  }

  /// Consumer summary for the stack-level product-safety banner.
  ///
  /// A partial scan stays explicitly partial even when it found one or more
  /// violations. Showing only the known findings would imply that the list is
  /// exhaustive, which is another form of false all-clear.
  String get bannerMessage {
    final ordered = orderedViolations;
    if (ordered.isEmpty) return '';

    final primary = ordered.first;
    final names = ordered
        .map((violation) => violation.productName)
        .toList(growable: false);
    final finding = ordered.length == 1
        ? primary.bannerMessage
        : '${ordered.length} products need review. '
              '${primary.bannerMessage} Plus ${ordered.length - 1} '
              'more: ${names.skip(1).join(", ")}.';
    if (!incomplete) return finding;
    return '$finding Some products could not be checked, so additional '
        'safety alerts may be missing.';
  }

  /// All violations sorted by severity (contraindicated first)
  List<RecalledIngredientViolation> get orderedViolations {
    final sorted = [...violations];
    sorted.sort((a, b) {
      final severityOrder = {
        Severity.contraindicated: 0,
        Severity.avoid: 1,
        Severity.caution: 2,
        Severity.monitor: 3,
        Severity.safe: 4,
      };
      final aSev = severityOrder[a.worstSeverity] ?? 99;
      final bSev = severityOrder[b.worstSeverity] ?? 99;
      return aSev.compareTo(bSev);
    });
    return sorted;
  }

  /// Highest severity across all violations
  Severity get overallSeverity {
    if (isEmpty) return Severity.safe;
    final severities = violations.map((v) => v.worstSeverity).toList();
    if (severities.contains(Severity.contraindicated)) {
      return Severity.contraindicated;
    }
    if (severities.contains(Severity.avoid)) return Severity.avoid;
    return Severity.caution;
  }
}
