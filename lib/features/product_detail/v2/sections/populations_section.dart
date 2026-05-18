// Phase 11.7d.4 — Populations section adapter.
//
// Composes the v2 PGPopulationsSection from aggregated population
// warnings, while preserving the production dedupe/profile-filter logic.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_populations_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

/// Output of [splitPopulations] — a deterministic split of the raw
/// aggregate into "main list" entries and "already covered" labels.
typedef PopulationSplit = ({
  List<String> mainList,
  List<String> alreadyCovered,
});

const Map<String, String> _populationKeywords = {
  'pregnancy': 'pregnancy',
  'pregnant': 'pregnancy',
  'lactation': 'lactation',
  'breastfeed': 'lactation',
  'breastfeeding': 'lactation',
  'kidney disease': 'kidney_disease',
  'renal impairment': 'kidney_disease',
  'liver disease': 'liver_disease',
  'hepatic impairment': 'liver_disease',
  'diabetes': 'diabetes',
  'diabetic': 'diabetes',
  'hypertension': 'hypertension',
  'high blood pressure': 'hypertension',
  'thyroid': 'thyroid_disorder',
  'ibd': 'inflammatory_bowel_disease',
  'inflammatory bowel': 'inflammatory_bowel_disease',
  'autoimmune': 'autoimmune',
  'children': 'under_18',
  'pediatric': 'under_18',
  'minors': 'under_18',
  'older adults': 'over_65',
  'elderly': 'over_65',
  'geriatric': 'over_65',
};

/// Split population warnings into rendered rows and profile-covered labels.
PopulationSplit splitPopulations({
  required List<String> populations,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  String? ageBracket,
}) {
  final userSignals = <String>{
    ...userConditions,
    ...userDrugClasses,
    if (ageBracket != null && ageBracket.isNotEmpty)
      _ageBracketToSignal(ageBracket),
  }..removeWhere((s) => s.isEmpty);

  if (userSignals.isEmpty) {
    final dedupedMain = <String>[];
    final seen = <String>{};
    for (final p in populations) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) dedupedMain.add(trimmed);
    }
    return (mainList: dedupedMain, alreadyCovered: const <String>[]);
  }

  final main = <String>[];
  final coveredSignals = <String>{};
  final seen = <String>{};

  for (final p in populations) {
    final trimmed = p.trim();
    if (trimmed.isEmpty) continue;
    final dedupeKey = trimmed.toLowerCase();
    if (!seen.add(dedupeKey)) continue;

    final matchedSignal = _matchSignal(trimmed, userSignals);
    if (matchedSignal != null) {
      coveredSignals.add(matchedSignal);
    } else {
      main.add(trimmed);
    }
  }

  final coveredHumanized = coveredSignals.map(_humanize).toList()..sort();
  return (mainList: main, alreadyCovered: coveredHumanized);
}

/// Aggregate populationWarnings across all warnings into a single list.
List<String> aggregatePopulations(List<InteractionWarning> warnings) {
  final out = <String>[];
  for (final w in warnings) {
    out.addAll(w.populationWarnings);
  }
  return out;
}

/// Build the Populations section.
///
/// Returns `SizedBox.shrink()` when there are no population warnings or
/// the main list is empty after dedupe against user signals.
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

  final callouts = split.mainList.map(_toCallout).toList(growable: false);

  return PGPopulationsSection(
    callouts: callouts,
    title: 'Extra caution if you are…',
  );
}

PGPopulationCallout _toCallout(String raw) {
  final (head, tail) = _splitAtDash(raw.trim());
  return PGPopulationCallout(
    label: head,
    body: tail,
    icon: Icons.groups_outlined,
  );
}

String? _matchSignal(String population, Set<String> userSignals) {
  final lower = population.toLowerCase();
  for (final entry in _populationKeywords.entries) {
    final keyword = entry.key;
    final signal = entry.value;
    if (!userSignals.contains(signal)) continue;
    final pattern = RegExp(
      r'\b' + RegExp.escape(keyword) + r'\b',
      caseSensitive: false,
    );
    if (pattern.hasMatch(lower)) return signal;
  }
  return null;
}

String _ageBracketToSignal(String bracket) {
  final normalized = bracket.toLowerCase().trim();
  if (normalized == '14-18') return 'under_18';
  if (normalized == '71+') return 'over_65';
  if (normalized.startsWith('under') || normalized.contains('child')) {
    return 'under_18';
  }
  if (normalized.contains('65') ||
      normalized.contains('over') ||
      normalized.contains('elderly') ||
      normalized.contains('geriatric')) {
    return 'over_65';
  }
  return '';
}

String _humanize(String raw) {
  if (raw.isEmpty) return raw;
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

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
