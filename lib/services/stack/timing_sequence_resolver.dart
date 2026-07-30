import 'package:pharmaguide/core/models/timing_optimization.dart';

/// Four organizational buckets a daily routine anchors to.
///
/// These are scheduling buckets, NOT clinical advice. Their anchor hours exist
/// only to decide whether two buckets are far enough apart to satisfy a
/// pipeline-authored separation; the app never tells the user to take anything
/// at a specific clock time it invented. Every word of advice shown to a user
/// still comes from the rule's own `advice` text.
enum DailySlot {
  morningEmpty('Morning, before food', 7),
  withBreakfast('With breakfast', 8),
  withDinner('With dinner', 18),
  bedtime('Before bed', 22);

  const DailySlot(this.label, this.anchorHour);

  final String label;
  final int anchorHour;

  bool get isWithFood => this == withBreakfast || this == withDinner;
}

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
    final constraints = [...optimizations]
      ..sort((a, b) => a.ruleId.compareTo(b.ruleId));

    // Unary constraints narrow an item's allowed slots. Binary constraints
    // relate two items. `food`/`sleep` pseudo-ingredients on the second side of
    // a unary rule are context, not stack items, so they are never placed.
    final domains = <String, Set<DailySlot>>{};
    final binary = <TimingOptimization>[];

    void ensure(String name) {
      domains.putIfAbsent(name, () => DailySlot.values.toSet());
    }

    for (final c in constraints) {
      switch (c.ruleType) {
        case TimingRuleType.takeWithFood:
          ensure(c.ingredient1);
          domains[c.ingredient1] = domains[c.ingredient1]!
              .where((s) => s.isWithFood)
              .toSet();
        case TimingRuleType.takeOnEmptyStomach:
          ensure(c.ingredient1);
          domains[c.ingredient1] = domains[c.ingredient1]!
              .where((s) => !s.isWithFood)
              .toSet();
        case TimingRuleType.timeOfDay:
          ensure(c.ingredient1);
          // The only authored time-of-day rules are evening/wind-down ones.
          // Anything else keeps its full domain rather than being guessed at.
          if (_isEveningAdvice(c.advice)) {
            domains[c.ingredient1] = domains[c.ingredient1]!
                .where((s) => s == DailySlot.bedtime || s == DailySlot.withDinner)
                .toSet();
          }
        case TimingRuleType.separate:
        case TimingRuleType.takeTogether:
          ensure(c.ingredient1);
          ensure(c.ingredient2);
          binary.add(c);
      }
    }

    if (domains.isEmpty) {
      return const TimingSequencePlan(itemsBySlot: {}, unsatisfied: []);
    }

    // Relax the least-impactful constraints first when the set is
    // over-constrained, so what survives is what the pipeline weighted highest.
    final relaxable = [...binary]
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

    // An item whose unary constraints emptied its domain cannot be placed at
    // all; surface that instead of dropping the item silently.
    final unplaceable = domains.entries
        .where((e) => e.value.isEmpty)
        .map((e) => e.key)
        .toList()
      ..sort();
    for (final name in unplaceable) {
      unsatisfied.add(
        UnsatisfiedTimingConstraint(
          ruleId: 'unplaceable:$name',
          advice: '$name has timing advice that cannot all apply at once.',
          reason:
              'Its guidance asks for both with-food and without-food timing.',
        ),
      );
    }

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

  static bool _isEveningAdvice(String advice) {
    final lower = advice.toLowerCase();
    return lower.contains('evening') ||
        lower.contains('night') ||
        lower.contains('bed');
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
      final a = assigned[c.ingredient1];
      final b = assigned[c.ingredient2];
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
