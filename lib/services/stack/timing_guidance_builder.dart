// Builds per-product timing guidance. Replaces the former
// TimingSequenceResolver, which solved a 4-slot constraint problem and reported
// the first feasible assignment as a recommendation.
//
// There is no solver here and no schedule. The app does not know when the user
// wakes, eats, fasts, or sleeps, and it must never restate when a prescribed
// medication is taken. What it does know is which bottles are in the stack and
// which reviewed rules apply to them — so that is all it says.

import 'package:pharmaguide/core/models/timing_optimization.dart';

/// Something the evaluator could not turn into guidance, carried out rather
/// than dropped.
///
/// Typed rather than a single catch-all, because the causes need different user
/// copy and produce different beta telemetry: an unresolved medication identity
/// is a data problem, while conflicting product guidance is a rule-scope
/// problem.
sealed class TimingEvaluationIssue {
  const TimingEvaluationIssue();
}

/// One physical product carries applicable rules that cannot all be followed.
///
/// After `applies_to: standalone` scoping this should be rare: it means two
/// rules genuinely disagree about the same bottle, not that a trace ingredient
/// dragged a standalone rule into a combination product.
final class ConflictingProductGuidance extends TimingEvaluationIssue {
  const ConflictingProductGuidance({
    required this.stackEntryId,
    required this.productName,
    required this.ruleIds,
  });

  final String stackEntryId;
  final String productName;
  final List<String> ruleIds;
}

/// A rule applies, but the product's formulation is not known well enough to
/// say whether it applies to *this* bottle.
final class FormulationUnknown extends TimingEvaluationIssue {
  const FormulationUnknown({
    required this.stackEntryId,
    required this.productName,
    required this.ruleId,
  });

  final String stackEntryId;
  final String productName;
  final String ruleId;
}

/// A rule matched, but no physical stack row could be resolved for it.
///
/// Guidance is never rendered under a bare ingredient name — users take
/// bottles, not nutrients — so this is reported rather than displayed.
final class IdentityUnresolved extends TimingEvaluationIssue {
  const IdentityUnresolved({required this.ruleId, required this.ingredient});

  final String ruleId;
  final String ingredient;
}

/// The timing check did not run. Never render this as "nothing found".
final class AnalysisUnavailable extends TimingEvaluationIssue {
  const AnalysisUnavailable({required this.reason});

  final String reason;
}

/// Guidance for one physical bottle in the stack.
class ProductTimingGuidance {
  const ProductTimingGuidance({
    required this.stackEntryId,
    required this.productName,
    this.importantSeparation = const [],
    this.howToTake = const [],
    this.optional = const [],
  });

  final String stackEntryId;
  final String productName;
  final List<TimingOptimization> importantSeparation;
  final List<TimingOptimization> howToTake;
  final List<TimingOptimization> optional;

  bool get isEmpty =>
      importantSeparation.isEmpty && howToTake.isEmpty && optional.isEmpty;

  /// Highest category present, for ordering products against each other.
  int get displayPriority => [
    ...importantSeparation,
    ...howToTake,
    ...optional,
  ].fold(0, (max, o) => o.displayPriority > max ? o.displayPriority : max);
}

/// The complete timing guidance for a stack.
class TimingGuidance {
  const TimingGuidance({this.products = const [], this.issues = const []});

  final List<ProductTimingGuidance> products;
  final List<TimingEvaluationIssue> issues;

  bool get isEmpty => products.every((p) => p.isEmpty);

  /// Whether the check completed well enough to say "nothing found".
  ///
  /// An [AnalysisUnavailable] or [IdentityUnresolved] issue means the app did
  /// not finish looking — reporting a clean result then would be a false
  /// all-clear, which is the one thing this surface must never do.
  bool get canAssertNoFindings => !issues.any(
    (issue) => issue is AnalysisUnavailable || issue is IdentityUnresolved,
  );
}

/// Groups reviewed timing optimizations into per-bottle guidance.
///
/// Deterministic: products are ordered by priority then stack row id, and rules
/// within a product by priority then rule id, so the same stack always produces
/// the same output.
class TimingGuidanceBuilder {
  const TimingGuidanceBuilder();

  TimingGuidance build(List<TimingOptimization> optimizations) {
    final issues = <TimingEvaluationIssue>[];
    final byRow = <String, List<TimingOptimization>>{};
    final nameByRow = <String, String>{};

    for (final optimization in optimizations) {
      final anchor = _guidanceAnchor(optimization);
      if (anchor == null) {
        // No physical row: the rule matched an ingredient we cannot tie to a
        // bottle. Report it, never render it under the nutrient's name.
        issues.add(
          IdentityUnresolved(
            ruleId: optimization.ruleId,
            ingredient: optimization.ingredient1,
          ),
        );
        continue;
      }
      byRow.putIfAbsent(anchor.stackEntryId, () => []).add(optimization);
      nameByRow.putIfAbsent(anchor.stackEntryId, () => anchor.displayName);
    }

    final products = <ProductTimingGuidance>[];
    final rowIds = byRow.keys.toList()..sort();

    for (final rowId in rowIds) {
      final forRow = byRow[rowId]!
        ..sort((a, b) {
          final byPriority = b.displayPriority.compareTo(a.displayPriority);
          return byPriority != 0 ? byPriority : a.ruleId.compareTo(b.ruleId);
        });
      final productName = nameByRow[rowId]!;

      // Two rules that disagree about how this bottle is taken cannot both be
      // followed. Showing either would be arbitrary and showing both would be
      // contradictory, so the product drops out and the conflict is reported.
      final conflicting = _conflictingRuleIds(forRow);
      if (conflicting.isNotEmpty) {
        issues.add(
          ConflictingProductGuidance(
            stackEntryId: rowId,
            productName: productName,
            ruleIds: conflicting,
          ),
        );
        continue;
      }

      products.add(
        ProductTimingGuidance(
          stackEntryId: rowId,
          productName: productName,
          importantSeparation: forRow
              .where((o) => o.category == TimingCategory.importantSeparation)
              .toList(growable: false),
          howToTake: forRow
              .where((o) => o.category == TimingCategory.howToTake)
              .toList(growable: false),
          optional: forRow
              .where((o) => o.category == TimingCategory.optional)
              .toList(growable: false),
        ),
      );
    }

    products.sort((a, b) {
      final byPriority = b.displayPriority.compareTo(a.displayPriority);
      return byPriority != 0
          ? byPriority
          : a.stackEntryId.compareTo(b.stackEntryId);
    });

    return TimingGuidance(
      products: products.where((p) => !p.isEmpty).toList(growable: false),
      issues: issues,
    );
  }

  /// The stack row guidance attaches to.
  ///
  /// For a rule involving a medication, that is always the *supplement* side:
  /// the app constrains the supplement around the prescription, and never the
  /// prescription around the supplement.
  static ({String stackEntryId, String displayName})? _guidanceAnchor(
    TimingOptimization optimization,
  ) {
    if (optimization.involvesMedication && optimization.medicationIsProduct1) {
      final id = optimization.product2StackEntryId?.trim();
      final name = optimization.product2Name?.trim();
      if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
      return (stackEntryId: id, displayName: name);
    }
    final id = optimization.product1StackEntryId?.trim();
    final name = optimization.product1Name?.trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    return (stackEntryId: id, displayName: name);
  }

  /// Rule ids whose relations cannot hold simultaneously for one bottle.
  static List<String> _conflictingRuleIds(List<TimingOptimization> forRow) {
    final withFood = forRow
        .where((o) => o.relation.type == TimingRelationType.withFood)
        .toList(growable: false);
    final emptyStomach = forRow
        .where((o) => o.relation.type == TimingRelationType.emptyStomach)
        .toList(growable: false);
    if (withFood.isEmpty || emptyStomach.isEmpty) return const [];
    return [
      ...withFood.map((o) => o.ruleId),
      ...emptyStomach.map((o) => o.ruleId),
    ]..sort();
  }
}
