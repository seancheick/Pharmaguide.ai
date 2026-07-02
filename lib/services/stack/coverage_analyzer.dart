// CoverageAnalyzer — Stack Gap Analysis ("is my stack working?").
//
// Pure, synchronous service that buckets the user's stack into:
//
//   1. SUPPORTED   — stated user goals that at least one stack product
//                    serves, via the pipeline's `products_core.goal_matches`
//                    column (offline, row-level — no detail blob needed).
//   2. UNDERDOSED  — nutrients present in the stack but below an adequate
//                    dose: RDA-tracked nutrients under 50% of RDA (from the
//                    M1 UL-checker statuses) plus medication-depletion
//                    nutrients at CoverageLevel.partial (present but below
//                    the authored adequacy threshold).
//   3. UNADDRESSED — (a) stated goals no stack product supports, and
//                    (b) medication-driven depletions no stack supplement
//                    replenishes (CoverageLevel.none).
//
// Copy contract (calm-advisory voice): the analyzer names nutrients and
// ingredient classes only — NEVER a specific product to buy. Product
// names appear only in the SUPPORTED bucket, describing what the user
// already takes. Nothing here is persisted; the report is recomputed
// from the live profile + stack every time (FitScore rule).
//
// No Riverpod, no I/O, no async — provider wiring lives in
// `lib/features/stack/providers/coverage_report_provider.dart` and tests
// drive this class directly with synthetic inputs.

import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

/// Minimal per-product input: what the analyzer needs from a hydrated
/// stack supplement. Built by the provider from `products_core` rows.
@immutable
class CoverageProductInput {
  const CoverageProductInput({
    required this.name,
    required this.goalMatches,
    this.goalMatchesUnderdosed = const {},
    this.productRole,
    this.prenatalCoverage = const [],
    this.adultMultiCoverage = const [],
  });

  /// Display name of the product (stack entry name).
  final String name;

  /// Decoded `products_core.goal_matches` — set of `GOAL_*` ids this
  /// product serves at a dose-adequate level per the pipeline contract.
  /// Empty when the column is null/unpopulated for this product.
  final Set<String> goalMatches;

  /// Decoded `products_core.goal_matches_underdosed` — `GOAL_*` ids this
  /// product matches on ingredient presence but BELOW the goal's effective
  /// dose. The pipeline guarantees this is disjoint from [goalMatches] (a
  /// goal is never both supported and underdosed for the same product).
  /// Empty when the column is null/unpopulated.
  final Set<String> goalMatchesUnderdosed;

  /// Pipeline-emitted product role from the detail blob. Null for old
  /// cached blobs; the analyzer treats that as "unknown", not as evidence.
  final String? productRole;

  /// Pipeline-emitted prenatal coverage anchors. Score-neutral, used only
  /// to say what a prenatal stack still appears to be missing.
  final List<PriorityCoverageAnchor> prenatalCoverage;

  /// Pipeline-emitted adult multivitamin coverage anchors. Score-neutral,
  /// used only to move missing adult-multi nutrients into stack coverage
  /// instead of treating them as product-quality defects.
  final List<PriorityCoverageAnchor> adultMultiCoverage;
}

/// One score-neutral nutrient anchor emitted by the pipeline coverage ledger.
@immutable
class PriorityCoverageAnchor {
  const PriorityCoverageAnchor({
    required this.nutrientId,
    required this.nutrientName,
    required this.status,
    required this.productName,
    this.amount,
    this.unit,
    this.target,
    this.targetUnit,
  });

  final String nutrientId;
  final String nutrientName;
  final String status;
  final String productName;
  final double? amount;
  final String? unit;
  final double? target;
  final String? targetUnit;
}

/// One SUPPORTED row: a user goal plus the stack products serving it.
@immutable
class SupportedGoal {
  const SupportedGoal({
    required this.goalId,
    required this.goalLabel,
    required this.productNames,
  });

  final String goalId;
  final String goalLabel;
  final List<String> productNames;
}

/// Where an UNDERDOSED signal came from.
enum UnderdosedSource {
  /// RDA-tracked nutrient totals below 50% of RDA (NutrientTier.underFifty).
  rda,

  /// Depletion-relevant nutrient present but below the authored
  /// adequacy threshold (CoverageLevel.partial).
  depletion,
}

/// One UNDERDOSED row: a nutrient that is present but below adequate.
@immutable
class UnderdosedNutrient {
  const UnderdosedNutrient({
    required this.nutrientName,
    required this.detail,
    required this.source,
  });

  final String nutrientName;

  /// Calm one-liner, e.g. "About 42% of the typical daily target across
  /// your stack." Never an imperative, never a product recommendation.
  final String detail;

  final UnderdosedSource source;
}

/// One PRIORITY GAP row: a goal-specific nutrient not confirmed at target.
@immutable
class PriorityNutrientGap {
  const PriorityNutrientGap({
    required this.nutrientId,
    required this.nutrientName,
    required this.detail,
    this.hedged = false,
  });

  final String nutrientId;
  final String nutrientName;
  final String detail;
  final bool hedged;
}

/// One UNADDRESSED goal row.
@immutable
class UnaddressedGoal {
  const UnaddressedGoal({
    required this.goalId,
    required this.goalLabel,
    this.hedged = false,
  });

  final String goalId;
  final String goalLabel;

  /// True when coverage data is incomplete (a stack product had
  /// null/empty `goal_matches` — unpopulated, not "supports no goals" —
  /// or label mapping fell below the trust floor). The copy must then
  /// soften from a confident absence claim to "couldn't confirm".
  final bool hedged;

  /// Calm-advisory copy. Names the goal only — never a product.
  String get message => hedged
      ? "We couldn't confirm anything in your stack supports your "
            '${goalLabel.toLowerCase()} goal.'
      : 'Nothing in your stack currently supports your '
            '${goalLabel.toLowerCase()} goal.';
}

/// One UNADDRESSED depletion row: a medication-driven depletion with no
/// replenishing supplement in the stack.
@immutable
class UnreplenishedDepletion {
  const UnreplenishedDepletion({
    required this.drugDisplayName,
    required this.nutrientName,
  });

  final String drugDisplayName;
  final String nutrientName;

  /// Calm-advisory copy — names the nutrient class, never a product,
  /// and closes with the conversation-with-your-doctor pattern.
  String get message =>
      '$drugDisplayName may lower $nutrientName over time — nothing in '
      'your stack provides $nutrientName. Worth a conversation with '
      'your doctor.';
}

/// Output of [CoverageAnalyzer.analyze] — the three buckets plus the
/// flags the card needs for hedging and empty states.
@immutable
class CoverageReport {
  const CoverageReport({
    this.supported = const [],
    this.partiallySupported = const [],
    this.priorityGaps = const [],
    this.underdosed = const [],
    this.unaddressedGoals = const [],
    this.unreplenishedDepletions = const [],
    this.hasGoals = false,
    this.goalsOptedOut = false,
    this.hasStack = false,
    this.coverageIncomplete = false,
  });

  final List<SupportedGoal> supported;

  /// Goals matched only by present-but-underdosed ingredients (pipeline
  /// `goal_matches_underdosed`). The honest middle state between Supported
  /// and Unaddressed: the right ingredient is in the stack, just below its
  /// effective dose for this goal. Reuses [SupportedGoal] (goal + the
  /// products carrying the underdosed ingredient).
  final List<SupportedGoal> partiallySupported;
  final List<PriorityNutrientGap> priorityGaps;
  final List<UnderdosedNutrient> underdosed;
  final List<UnaddressedGoal> unaddressedGoals;
  final List<UnreplenishedDepletion> unreplenishedDepletions;

  /// True when the user has at least one real (non-sentinel) goal.
  final bool hasGoals;

  /// True when the user explicitly opted out of goals (GOAL_NONE
  /// sentinel). The card must not nag "Add goals" for these users.
  final bool goalsOptedOut;

  /// True when the stack contains at least one supplement.
  final bool hasStack;

  /// True when at least one stack product's label mapping coverage is
  /// below the 0.3 trust floor (or hydration failed) — the card must
  /// hedge rather than imply the analysis is complete.
  final bool coverageIncomplete;

  int get unaddressedCount =>
      unaddressedGoals.length + unreplenishedDepletions.length;

  /// True when there is nothing at all to render (empty stack — the
  /// card hides entirely).
  bool get isEmpty => !hasStack;
}

class CoverageAnalyzer {
  const CoverageAnalyzer();

  /// Build a [CoverageReport] from already-loaded inputs.
  ///
  /// [goals] — sentinel-stripped user goal ids (`goalsForEvaluator`).
  /// [products] — hydrated stack supplements with their offline
  ///   `goal_matches` sets.
  /// [depletions] — output of [DepletionChecker] for the current stack.
  /// [nutrientStatuses] — M1 RDA/UL statuses; pass an empty list when
  ///   detail blobs aren't cached (the feature degrades gracefully:
  ///   the RDA-underdosed bucket is simply empty).
  /// [coverageIncomplete] — low label-mapping trust flag, mirrored
  ///   from the stack safety hydration pass (also forced true here when
  ///   any product carries an empty `goal_matches` set — unpopulated
  ///   column, not "supports no goals").
  /// [goalsOptedOut] — user explicitly chose GOAL_NONE; passed through
  ///   so the card skips the "Add goals" invitation.
  /// [hasStackOverride] — pass true when the stack has supplements but
  ///   every one failed hydration ([products] is empty); keeps the card
  ///   alive so depletion gaps still render alongside the hedge.
  CoverageReport analyze({
    required List<String> goals,
    required List<CoverageProductInput> products,
    List<DepletionMatch> depletions = const [],
    List<NutrientStatus> nutrientStatuses = const [],
    bool coverageIncomplete = false,
    bool goalsOptedOut = false,
    bool? hasStackOverride,
  }) {
    final hasStack = hasStackOverride ?? products.isNotEmpty;
    final hasGoals = goals.isNotEmpty;

    // 3,560/9,270 legacy products ship with null/empty goal_matches — that
    // column can be UNPOPULATED, not evidence the product supports no goals
    // (see e2a_goal_calculator.dart). With the v2.x partial-support column,
    // a product can legitimately have no dose-adequate goals but still carry
    // goal_matches_underdosed. Treat that as populated coverage data; otherwise
    // partial-only products would trigger a false "coverage incomplete" hedge.
    final anyUnpopulatedGoalMatches = products.any(
      (p) => p.goalMatches.isEmpty && p.goalMatchesUnderdosed.isEmpty,
    );
    final effectiveIncomplete = coverageIncomplete || anyUnpopulatedGoalMatches;

    // -------------------------------------------------------------------
    // SUPPORTED / UNADDRESSED goals — offline goal_matches pass.
    // -------------------------------------------------------------------
    final supported = <SupportedGoal>[];
    final partiallySupported = <SupportedGoal>[];
    final unaddressedGoals = <UnaddressedGoal>[];
    if (hasGoals && hasStack) {
      for (final goalId in goals) {
        final label = SchemaIds.goalLabels[goalId] ?? goalId;
        final serving = products
            .where((p) => p.goalMatches.contains(goalId))
            .map((p) => p.name)
            .toList(growable: false);
        if (serving.isNotEmpty) {
          // Dose-adequate support wins outright (a goal is never both
          // supported and partially supported).
          supported.add(
            SupportedGoal(
              goalId: goalId,
              goalLabel: label,
              productNames: serving,
            ),
          );
          continue;
        }
        // Not fully supported — is the goal carried by a present-but-
        // underdosed ingredient? If so it is partially supported, not
        // "Unaddressed".
        final partial = products
            .where((p) => p.goalMatchesUnderdosed.contains(goalId))
            .map((p) => p.name)
            .toList(growable: false);
        if (partial.isNotEmpty) {
          partiallySupported.add(
            SupportedGoal(
              goalId: goalId,
              goalLabel: label,
              productNames: partial,
            ),
          );
        } else {
          unaddressedGoals.add(
            UnaddressedGoal(
              goalId: goalId,
              goalLabel: label,
              hedged: effectiveIncomplete,
            ),
          );
        }
      }
    }

    // -------------------------------------------------------------------
    // PRIORITY GAPS — score-neutral, goal-specific stack coverage.
    // Prenatal base products are not "bad products" for omitting DHA or
    // choline; those gaps belong here, where separate companion products
    // can satisfy them.
    // -------------------------------------------------------------------
    final priorityGaps = _priorityGapsForGoals(
      goals: goals,
      products: products,
      coverageIncomplete: effectiveIncomplete,
    );

    // -------------------------------------------------------------------
    // UNDERDOSED — RDA-tracked nutrients below 50% of RDA, plus
    // depletion-relevant nutrients at partial coverage. Dedupe by
    // (lowercased) nutrient name; the depletion framing wins because it
    // carries the medication context.
    // -------------------------------------------------------------------
    final underdosedByName = <String, UnderdosedNutrient>{};
    for (final status in nutrientStatuses) {
      if (status.tier != NutrientTier.underFifty) continue;
      final name = status.total.displayName;
      // The percentage can be false when unit-conflicting or excluded
      // contributions were dropped from the sum — fall back to the
      // qualitative line rather than display a wrong number.
      final totalUnreliable =
          status.total.hasUnitConflict || status.total.hasExcludedContributions;
      final pct = totalUnreliable ? null : status.pctOfRda;
      // Inside the under-50 bucket, clamp display to 1..49 so rounding
      // never produces "About 0%" or "About 50%".
      final displayPct = pct?.round().clamp(1, 49);
      final detail = displayPct == null
          ? 'Present in your stack, but below the typical daily target.'
          : 'About $displayPct% of the typical daily target across '
                'your stack.';
      underdosedByName[name.toLowerCase()] = UnderdosedNutrient(
        nutrientName: name,
        detail: detail,
        source: UnderdosedSource.rda,
      );
    }
    for (final dep in depletions) {
      if (!_isCoverageRelevant(dep)) continue;
      if (dep.coverageLevel != CoverageLevel.partial) continue;
      final name = dep.nutrientName;
      if (name.isEmpty) continue;
      underdosedByName[name.toLowerCase()] = UnderdosedNutrient(
        nutrientName: name,
        detail:
            'Present in your stack, but below the level typically used '
            'alongside ${dep.drugDisplayName}.',
        source: UnderdosedSource.depletion,
      );
    }

    // -------------------------------------------------------------------
    // UNADDRESSED depletions — coverage-relevant rows where nothing in
    // the stack provides the nutrient at all. Dedupe by
    // (drug, nutrient) so duplicate authored rows surface once.
    // -------------------------------------------------------------------
    final unreplenished = <UnreplenishedDepletion>[];
    final seenDepletions = <String>{};
    for (final dep in depletions) {
      if (!_isCoverageRelevant(dep)) continue;
      if (dep.coverageLevel != CoverageLevel.none) continue;
      if (dep.nutrientName.isEmpty || dep.drugDisplayName.isEmpty) continue;
      final key =
          '${dep.drugDisplayName.toLowerCase()}|'
          '${dep.nutrientName.toLowerCase()}';
      if (!seenDepletions.add(key)) continue;
      unreplenished.add(
        UnreplenishedDepletion(
          drugDisplayName: dep.drugDisplayName,
          nutrientName: dep.nutrientName,
        ),
      );
    }

    return CoverageReport(
      supported: supported,
      partiallySupported: partiallySupported,
      priorityGaps: priorityGaps,
      underdosed: underdosedByName.values.toList(growable: false),
      unaddressedGoals: unaddressedGoals,
      unreplenishedDepletions: unreplenished,
      hasGoals: hasGoals,
      goalsOptedOut: goalsOptedOut,
      hasStack: hasStack,
      coverageIncomplete: effectiveIncomplete,
    );
  }

  /// Only true drug-induced depletions and condition-related nutrient
  /// issues are supplement-coverage-relevant — mirrors
  /// [DepletionChecker]'s `_isSupplementCoverageRelevant`. Other
  /// taxonomy buckets (functional antagonism, monitoring notes,
  /// supplement interactions) are not "gaps" a nutrient can fill.
  static bool _isCoverageRelevant(DepletionMatch dep) =>
      dep.depletionType == 'depletion' ||
      dep.depletionType == 'condition_related';

  static const _prenatalGoalId = 'GOAL_PRENATAL_PREGNANCY';

  static const _prenatalPriorityOrder = [
    'dha',
    'choline',
    'folate',
    'iron',
    'iodine',
    'vitamin_d',
    'vitamin_b12',
    'vitamin_a',
  ];

  static const _adultMultiPriorityOrder = [
    'vitamin_d',
    'folate',
    'vitamin_b12',
    'iodine',
    'zinc',
    'selenium',
    'copper',
    'vitamin_a',
    'vitamin_c',
    'vitamin_e',
    'vitamin_k',
  ];

  static List<PriorityNutrientGap> _priorityGapsForGoals({
    required List<String> goals,
    required List<CoverageProductInput> products,
    required bool coverageIncomplete,
  }) {
    final gaps = <PriorityNutrientGap>[];

    gaps.addAll(
      _prenatalPriorityGapsForGoals(
        goals: goals,
        products: products,
        coverageIncomplete: coverageIncomplete,
      ),
    );
    gaps.addAll(
      _adultMultiPriorityGaps(
        products: products,
        coverageIncomplete: coverageIncomplete,
      ),
    );

    return gaps;
  }

  static List<PriorityNutrientGap> _prenatalPriorityGapsForGoals({
    required List<String> goals,
    required List<CoverageProductInput> products,
    required bool coverageIncomplete,
  }) {
    if (!goals.contains(_prenatalGoalId)) return const [];
    final hasPrenatalRole = products.any(
      (p) => (p.productRole ?? '').startsWith('prenatal_'),
    );
    if (!hasPrenatalRole) return const [];

    final anchorsById = <String, List<PriorityCoverageAnchor>>{};
    for (final product in products) {
      for (final anchor in product.prenatalCoverage) {
        if (anchor.nutrientId.isEmpty) continue;
        anchorsById.putIfAbsent(anchor.nutrientId, () => []).add(anchor);
      }
    }
    if (anchorsById.isEmpty) return const [];

    return _priorityGapsFromAnchors(
      anchorsById: anchorsById,
      priorityOrder: _prenatalPriorityOrder,
      belowTargetDetail:
          'Present in your stack, but below the usual prenatal target.',
      missingDetail: 'Not confirmed in your stack for prenatal coverage.',
      coverageIncomplete: coverageIncomplete,
    );
  }

  static List<PriorityNutrientGap> _adultMultiPriorityGaps({
    required List<CoverageProductInput> products,
    required bool coverageIncomplete,
  }) {
    final hasAdultMultiRole = products.any(
      (p) => (p.productRole ?? '').startsWith('adult_multi_'),
    );
    if (!hasAdultMultiRole) return const [];

    final anchorsById = <String, List<PriorityCoverageAnchor>>{};
    for (final product in products) {
      for (final anchor in product.adultMultiCoverage) {
        if (anchor.nutrientId.isEmpty) continue;
        anchorsById.putIfAbsent(anchor.nutrientId, () => []).add(anchor);
      }
    }
    if (anchorsById.isEmpty) return const [];

    return _priorityGapsFromAnchors(
      anchorsById: anchorsById,
      priorityOrder: _adultMultiPriorityOrder,
      belowTargetDetail:
          'Present in your stack, but below the usual adult multivitamin target.',
      missingDetail:
          'Not confirmed in your stack for adult multivitamin coverage.',
      coverageIncomplete: coverageIncomplete,
    );
  }

  static List<PriorityNutrientGap> _priorityGapsFromAnchors({
    required Map<String, List<PriorityCoverageAnchor>> anchorsById,
    required List<String> priorityOrder,
    required String belowTargetDetail,
    required String missingDetail,
    required bool coverageIncomplete,
  }) {
    final gaps = <PriorityNutrientGap>[];
    for (final id in priorityOrder) {
      final anchors = anchorsById[id];
      if (anchors == null || anchors.isEmpty) continue;
      final label = anchors.first.nutrientName;
      final target = anchors
          .map((a) => a.target)
          .whereType<double>()
          .where((v) => v > 0)
          .fold<double?>(null, (max, v) => max == null || v > max ? v : max);
      final units = anchors
          .map((a) => (a.targetUnit ?? a.unit ?? '').trim())
          .where((u) => u.isNotEmpty)
          .toSet();
      final comparable = target != null && units.length <= 1;
      final amount = anchors
          .where((a) => a.amount != null && a.amount! > 0)
          .fold<double>(0, (sum, a) => sum + a.amount!);
      final anyCovered = anchors.any(
        (a) => const {'covered', 'near_ul', 'above_ul'}.contains(a.status),
      );
      if (anyCovered || (comparable && amount >= target)) continue;

      gaps.add(
        PriorityNutrientGap(
          nutrientId: id,
          nutrientName: label,
          detail: amount > 0 ? belowTargetDetail : missingDetail,
          hedged: coverageIncomplete,
        ),
      );
    }
    return gaps;
  }
}
