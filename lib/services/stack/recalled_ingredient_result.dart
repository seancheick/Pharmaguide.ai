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
  final String recallStatus; // 'banned' or 'warning'
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
    return 'WARNING';
  }
}

/// Product in the user's stack that contains recalled ingredients.
class RecalledIngredientViolation {
  final String productDsldId;
  final String productName;
  final String brandName;
  final List<RecalledIngredientAlert> recalledIngredients;

  RecalledIngredientViolation({
    required this.productDsldId,
    required this.productName,
    required this.brandName,
    required this.recalledIngredients,
  });

  /// Highest severity from all recalled ingredients in this product
  Severity get worstSeverity {
    if (recalledIngredients.isEmpty) return Severity.safe;
    final severities = recalledIngredients.map((r) => r.displaySeverity).toList();
    // contraindicated > avoid > caution > monitor > safe
    if (severities.contains(Severity.contraindicated)) return Severity.contraindicated;
    if (severities.contains(Severity.avoid)) return Severity.avoid;
    return Severity.caution;
  }

  /// Human-readable alert for the banner
  String get bannerMessage {
    if (recalledIngredients.isEmpty) return '';
    final verb = _verbFor(recalledIngredients.first.banContext);
    if (recalledIngredients.length == 1) {
      final ing = recalledIngredients.first;
      final name = ing.commonNames.isNotEmpty ? ing.commonNames.first : ing.canonicalId;
      final oneLiner = ing.safetyWarningOneLiner.trim();
      final suffix = oneLiner.isEmpty ? '' : ' $oneLiner';
      return '${ing.statusLabel} — $productName $verb $name.$suffix';
    }
    return '${recalledIngredients.first.statusLabel} — $productName '
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

  bool get isEmpty => violations.isEmpty;

  RecalledIngredientsReport({
    required this.violations,
  });

  factory RecalledIngredientsReport.empty() {
    return RecalledIngredientsReport(
      violations: const [],
    );
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
    if (severities.contains(Severity.contraindicated)) return Severity.contraindicated;
    if (severities.contains(Severity.avoid)) return Severity.avoid;
    return Severity.caution;
  }
}
