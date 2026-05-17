// Phase 11.7d.4 — Populations section adapter.
//
// V2 mirror of production's `PopulationsSection`. Composes the v2 PGPopulationsSection
// from aggregated population warnings.
//
// Production data path (verbatim port):
//   aggregatePopulations(guardedWarnings) → List<String>
//   splitPopulations(populations, userConditions, userDrugClasses, ageBracket)
//     → (mainList, alreadyCovered)
//   render: bullet list of mainList (alreadyCovered dropped 2026-05-05
//   per Sean — silence in ReviewBeforeUseCard is sufficient signal)
//
// Each population string follows the pattern "Group — explanation":
//   "Children — immature gut barrier"
//   "People with IBD — may aggravate inflammation"
// We split at the first em-dash / en-dash / " - " into label + body.
//
// Sean's rules (2026-05-15):
//   • Preserve production gates: section hides when mainList empty.
//   • Use production's aggregatePopulations + splitPopulations helpers
//     verbatim (publicly exposed).
//   • Drop the "already covered" parenthetical (matches production's
//     2026-05-05 behavior — Sean's call).
//   • No invented copy — every label/body string comes from the pipeline.
//   • Privacy-aware: user signals are filtered OUT of the main list
//     (matches via splitPopulations); they're already personalized
//     surfaces upstream.
//
// Deferred to S8.next-iteration:
//   • Per-population icon mapping (pregnancy → pregnant_woman, kidney →
//     bloodtype, etc.). Production renders plain bullets without icons;
//     v2 PGPopulationCallout requires an icon. We default to
//     Icons.groups_outlined for every callout (matches production's
//     section header icon). Population-aware icon resolution would
//     surface a richer visual without changing semantics.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_populations_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/populations_section.dart'
    show aggregatePopulations, splitPopulations;

/// Build the Populations section.
///
/// Returns `SizedBox.shrink()` when:
///   - aggregatePopulations returns an empty list, OR
///   - splitPopulations.mainList is empty after dedupe against user signals.
///
/// Matches production's `if (split.mainList.isEmpty) return SizedBox.shrink()`.
Widget buildPopulationsSection({
  required List<InteractionWarning> warnings,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  String? ageBracket,
}) {
  final populations = aggregatePopulations(warnings);
  if (populations.isEmpty) return const SizedBox.shrink();

  final split = splitPopulations(
    populations: populations,
    userConditions: userConditions,
    userDrugClasses: userDrugClasses,
    ageBracket: ageBracket,
  );

  if (split.mainList.isEmpty) return const SizedBox.shrink();

  final callouts = split.mainList
      .map(_toCallout)
      .toList(growable: false);

  return PGPopulationsSection(
    callouts: callouts,
    // Production header copy: "Extra caution if you are…" — verbatim port.
    title: 'Extra caution if you are…',
  );
}

/// Split a raw population string at the first em-dash / en-dash / " - "
/// into a label (group name) + body (caution reason). Falls through to
/// label-only when no separator is found.
PGPopulationCallout _toCallout(String raw) {
  final (head, tail) = _splitAtDash(raw.trim());
  return PGPopulationCallout(
    label: head,
    body: tail,
    // Default icon — production renders plain bullets without per-population
    // icons. Population-aware icon mapping is queued as S8.next-iteration.
    icon: Icons.groups_outlined,
  );
}

/// Verbatim port of production's `_splitAtDash` (private in
/// populations_section.dart). Looks for `—`, `–`, or ` - ` (in that order)
/// and splits at the first match. Returns (raw, '') when none found.
(String, String) _splitAtDash(String raw) {
  for (final sep in const ['—', '–', ' - ']) {
    final idx = raw.indexOf(sep);
    if (idx > 0) {
      final head = raw.substring(0, idx).trim();
      final tail = raw.substring(idx + sep.length).trim();
      if (head.isNotEmpty) return (head, tail);
    }
  }
  return (raw, '');
}
