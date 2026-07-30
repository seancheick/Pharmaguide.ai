import 'package:pharmaguide/core/models/timing_optimization.dart';

int _hoursBetween(DailySlot a, DailySlot b) =>
    (a.anchorHour - b.anchorHour).abs();

/// A constraint the resolver could not satisfy, carried out rather than
/// dropped. An unsatisfiable set is a legitimate outcome — the honest answer is
/// "these two cannot both be honoured", never a silently invented compromise.
class UnsatisfiedTimingConstraint {
  const UnsatisfiedTimingConstraint({
    required this.ruleId,
    required this.advice,
    required this.reason,
  });

  final String ruleId;

  /// The pipeline's own words. The resolver never rewrites advice.
  final String advice;

  /// Why it could not be placed, in scheduling terms only.
  final String reason;
}

/// One item placed in the daily plan.
class PlannedItem {
  const PlannedItem({required this.name, required this.slot});

  final String name;
  final DailySlot slot;
}

/// The resolved daily plan.
class TimingSequencePlan {
  const TimingSequencePlan({
    required this.itemsBySlot,
    required this.unsatisfied,
  });

  final Map<DailySlot, List<String>> itemsBySlot;
  final List<UnsatisfiedTimingConstraint> unsatisfied;

  bool get isEmpty => itemsBySlot.values.every((items) => items.isEmpty);
  bool get isFullySatisfied => unsatisfied.isEmpty;

  List<PlannedItem> get orderedItems => [
    for (final slot in DailySlot.values)
      for (final name in itemsBySlot[slot] ?? const <String>[])
        PlannedItem(name: name, slot: slot),
  ];
}

/// Resolves pairwise timing advice into one daily plan.
///
/// This sits ABOVE [TimingEvaluationService] and never modifies it. The engine
/// remains the only thing that decides which rules apply; this layer only
/// arranges the constraints it emits into buckets, and reports whatever it
/// could not arrange.
///
/// Determinism is a hard requirement: the same constraint set must always
/// produce the same plan regardless of input order, because a plan that
/// reshuffles between openings reads as advice changing.
class TimingSequenceResolver {
  const TimingSequenceResolver();

  TimingSequencePlan resolve(List<TimingOptimization> optimizations) {
    // Sort by rule id so input order can never change the outcome.
    final constraints =
        optimizations
            .where((optimization) => optimization.dailyPlanEligible)
            .toList()
          ..sort((a, b) => a.ruleId.compareTo(b.ruleId));

    // Unary constraints narrow an item's allowed slots. Binary constraints
    // relate two items. `food`/`sleep` pseudo-ingredients on the second side of
    // a unary rule are context, not stack items, so they are never placed.
    final domains = <String, Set<DailySlot>>{};
    final binary = <TimingOptimization>[];
    final unaryByItem = <String, List<TimingOptimization>>{};
    final authoredUnaryFailures = <UnsatisfiedTimingConstraint>[];

    void ensure(String name) {
      domains.putIfAbsent(name, () => DailySlot.values.toSet());
    }

    void rememberUnary(String name, TimingOptimization constraint) {
      unaryByItem.putIfAbsent(name, () => []).add(constraint);
    }

    for (final c in constraints) {
      final item1 = _itemName(c.product1Name, c.ingredient1);
      final item2 = _itemName(c.product2Name, c.ingredient2);
      switch (c.ruleType) {
        case TimingRuleType.takeWithFood:
          ensure(item1);
          rememberUnary(item1, c);
          domains[item1] = domains[item1]!.where((s) => s.isWithFood).toSet();
        case TimingRuleType.takeOnEmptyStomach:
          ensure(item1);
          rememberUnary(item1, c);
          domains[item1] = domains[item1]!.where((s) => !s.isWithFood).toSet();
        case TimingRuleType.timeOfDay:
          ensure(item1);
          rememberUnary(item1, c);
          if (c.allowedDailySlots.isEmpty) {
            domains[item1] = <DailySlot>{};
            authoredUnaryFailures.add(
              UnsatisfiedTimingConstraint(
                ruleId: c.ruleId,
                advice: c.advice,
                reason:
                    'This time-of-day guidance has no reviewed structured '
                    'daily slot.',
              ),
            );
          } else {
            domains[item1] = domains[item1]!
                .where(c.allowedDailySlots.contains)
                .toSet();
          }
        case TimingRuleType.separate:
        case TimingRuleType.takeTogether:
          if ((c.product2Name == null || c.product2Name!.trim().isEmpty) &&
              _isNonPhysicalContext(c.ingredient2)) {
            authoredUnaryFailures.add(
              UnsatisfiedTimingConstraint(
                ruleId: c.ruleId,
                advice: c.advice,
                reason:
                    'This rule does not identify a second physical stack '
                    'item that can be scheduled safely.',
              ),
            );
            continue;
          }
          ensure(item1);
          ensure(item2);
          binary.add(c);
      }
    }

    if (domains.isEmpty) {
      return TimingSequencePlan(
        itemsBySlot: const {},
        unsatisfied: authoredUnaryFailures,
      );
    }

    final unplaceable =
        domains.entries
            .where((entry) => entry.value.isEmpty)
            .map((entry) => entry.key)
            .toList()
          ..sort();
    final unplaceableSet = unplaceable.toSet();
    final blockedBinary = <TimingOptimization>[];
    final schedulableBinary = <TimingOptimization>[];
    for (final constraint in binary) {
      final first = _itemName(constraint.product1Name, constraint.ingredient1);
      final second = _itemName(constraint.product2Name, constraint.ingredient2);
      if (unplaceableSet.contains(first) || unplaceableSet.contains(second)) {
        blockedBinary.add(constraint);
      } else {
        schedulableBinary.add(constraint);
      }
    }

    // Relax the least-impactful constraints first when the set is
    // over-constrained, so what survives is what the pipeline weighted highest.
    final relaxable = [...schedulableBinary]
      ..sort((a, b) {
        final byImpact = a.scoreImpact.abs().compareTo(b.scoreImpact.abs());
        return byImpact != 0 ? byImpact : a.ruleId.compareTo(b.ruleId);
      });

    final dropped = <TimingOptimization>[];
    Map<String, DailySlot>? solution;
    final active = [...relaxable];
    while (true) {
      solution = _solve(domains, active);
      if (solution != null) break;
      if (active.isEmpty) break;
      dropped.add(active.removeAt(0));
    }

    final unsatisfied = <UnsatisfiedTimingConstraint>[
      ...authoredUnaryFailures,
      for (final name in unplaceable)
        for (final constraint
            in unaryByItem[name] ?? const <TimingOptimization>[])
          if (!authoredUnaryFailures.any(
            (failure) => failure.ruleId == constraint.ruleId,
          ))
            UnsatisfiedTimingConstraint(
              ruleId: constraint.ruleId,
              advice: constraint.advice,
              reason:
                  'This guidance conflicts with other timing guidance for '
                  'the same stack item.',
            ),
      for (final constraint in blockedBinary)
        UnsatisfiedTimingConstraint(
          ruleId: constraint.ruleId,
          advice: constraint.advice,
          reason:
              'A stack item in this rule has other timing guidance that '
              'cannot be placed.',
        ),
      for (final c in dropped)
        UnsatisfiedTimingConstraint(
          ruleId: c.ruleId,
          advice: c.advice,
          reason: c.ruleType == TimingRuleType.separate
              ? 'This needs more separation than a single day of slots allows '
                    'alongside your other items.'
              : 'This could not be placed alongside your other timing items.',
        ),
    ];

    final itemsBySlot = <DailySlot, List<String>>{
      for (final slot in DailySlot.values) slot: <String>[],
    };
    if (solution != null) {
      final names = solution.keys.toList()..sort();
      for (final name in names) {
        itemsBySlot[solution[name]!]!.add(name);
      }
    }

    return TimingSequencePlan(
      itemsBySlot: itemsBySlot,
      unsatisfied: unsatisfied,
    );
  }

  static String _itemName(String? productName, String ingredientName) {
    final normalizedProduct = productName?.trim();
    return normalizedProduct == null || normalizedProduct.isEmpty
        ? ingredientName
        : normalizedProduct;
  }

  static bool _isNonPhysicalContext(String value) {
    return const {
      'food',
      'dietary fat',
      'sleep',
      'melatonin production',
      'medications',
    }.contains(value.trim().toLowerCase());
  }

  /// Deterministic backtracking over a 4-value domain. Items are visited in
  /// sorted order and slots in declaration order, so the first solution found
  /// is always the same solution.
  Map<String, DailySlot>? _solve(
    Map<String, Set<DailySlot>> domains,
    List<TimingOptimization> binary,
  ) {
    final names = domains.keys.toList()..sort();
    if (names.any((n) => domains[n]!.isEmpty)) {
      // Unplaceable items are reported separately; solve around them.
      final solvable = names.where((n) => domains[n]!.isNotEmpty).toList();
      if (solvable.isEmpty) return <String, DailySlot>{};
      return _backtrack(solvable, domains, binary, {}, 0);
    }
    return _backtrack(names, domains, binary, {}, 0);
  }

  Map<String, DailySlot>? _backtrack(
    List<String> names,
    Map<String, Set<DailySlot>> domains,
    List<TimingOptimization> binary,
    Map<String, DailySlot> assigned,
    int index,
  ) {
    if (index == names.length) return Map.of(assigned);
    final name = names[index];
    for (final slot in DailySlot.values) {
      if (!domains[name]!.contains(slot)) continue;
      assigned[name] = slot;
      if (_consistent(assigned, binary)) {
        final result = _backtrack(names, domains, binary, assigned, index + 1);
        if (result != null) return result;
      }
      assigned.remove(name);
    }
    return null;
  }

  bool _consistent(
    Map<String, DailySlot> assigned,
    List<TimingOptimization> binary,
  ) {
    for (final c in binary) {
      final a = assigned[_itemName(c.product1Name, c.ingredient1)];
      final b = assigned[_itemName(c.product2Name, c.ingredient2)];
      if (a == null || b == null) continue;
      switch (c.ruleType) {
        case TimingRuleType.takeTogether:
          if (a != b) return false;
        case TimingRuleType.separate:
          final required = c.separationHours ?? 0;
          if (_hoursBetween(a, b) < required) return false;
        case TimingRuleType.takeWithFood:
        case TimingRuleType.takeOnEmptyStomach:
        case TimingRuleType.timeOfDay:
          break;
      }
    }
    return true;
  }
}
