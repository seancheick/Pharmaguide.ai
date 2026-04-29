// Populations section (Section 8) — at-risk populations dedupe.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.9.
//
// Pipeline-side `populationWarnings` are free-form prose strings
// (e.g. "Children — immature gut barrier", "People with IBD — may
// aggravate inflammation", "Pregnancy"). Multiple
// [InteractionWarning] entries can each carry their own list, so the
// raw aggregate often contains duplicates.
//
// This section's job:
//   1. Dedupe the raw aggregate by string.
//   2. Filter out entries that match the user's profile (condition,
//      drug class, age bracket) — those are already surfaced in
//      Section 7's WithYourStackSection per-row treatment, so
//      repeating them here is redundant noise.
//   3. Render the remainder as "Extra caution for: A, B, C" with an
//      optional "(You are already covered for X, Y)" parenthetical
//      naming the user signals that DID match at least one
//      population (so the user knows we considered + handled them
//      elsewhere, didn't ignore them).
//
// Acceptance per spec: NO duplicate warning surfaces between
// Section 7 (Interactions) and Section 8 (Populations).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

/// Output of [splitPopulations] — a deterministic split of the raw
/// aggregate into "main list" entries (rendered as bullets) and
/// "already covered" labels (rendered as a quiet parenthetical).
typedef PopulationSplit = ({
  /// Population strings that DIDN'T match any user signal. Bullets
  /// in the main list. Order preserved from the input aggregate.
  List<String> mainList,

  /// Humanized user signal names that matched at least one
  /// population. E.g. ["Pregnancy", "Anticoagulants"]. Each appears
  /// at most once even if multiple populations matched it.
  List<String> alreadyCovered,
});

/// Match map — the keyword tokens we scan in population strings, and
/// the user-signal id each token maps to. Substring match,
/// lowercase, word-aware (we check that the keyword appears as a
/// whole word so "child" doesn't match "children" and vice versa
/// would be a hit, but "fishing" wouldn't match "fish").
///
/// Populated from observed pipeline `populationWarnings` strings —
/// add new entries when the pipeline starts shipping a population
/// the user could legitimately be in.
const Map<String, String> _populationKeywords = {
  // Conditions
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

  // Age
  'children': 'under_18',
  'pediatric': 'under_18',
  'minors': 'under_18',
  'older adults': 'over_65',
  'elderly': 'over_65',
  'geriatric': 'over_65',
};

/// Split the deduped population aggregate into main-list bullets +
/// already-covered labels based on user profile.
///
/// Pure function — no widget refs, no theme. Caller is responsible
/// for deduping the input list (this function preserves input order
/// and handles duplicates idempotently, but won't collapse them).
PopulationSplit splitPopulations({
  required List<String> populations,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  String? ageBracket,
}) {
  // Build the set of user-signal IDs we care about — we'll match
  // population strings against keywords that resolve to one of these.
  final userSignals = <String>{
    ...userConditions,
    ...userDrugClasses,
    if (ageBracket != null && ageBracket.isNotEmpty)
      _ageBracketToSignal(ageBracket),
  }..removeWhere((s) => s.isEmpty);

  if (userSignals.isEmpty) {
    // No profile to dedupe against — every population goes to main.
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

  // Humanize the covered signals for display. Sort alphabetically so
  // the "(already covered for X, Y)" line is deterministic.
  final coveredHumanized = coveredSignals.map(_humanize).toList()
    ..sort();

  return (mainList: main, alreadyCovered: coveredHumanized);
}

/// Aggregate populationWarnings across all warnings into a single
/// list. Caller passes the deduped list to [splitPopulations].
List<String> aggregatePopulations(List<InteractionWarning> warnings) {
  final out = <String>[];
  for (final w in warnings) {
    out.addAll(w.populationWarnings);
  }
  return out;
}

/// Try to match a population string against the user's signals.
/// Returns the matched signal ID or null. Word-boundary aware so
/// "diabetic" matches "diabetes" but "fishing" doesn't match "fish".
String? _matchSignal(String population, Set<String> userSignals) {
  final lower = population.toLowerCase();
  for (final entry in _populationKeywords.entries) {
    final keyword = entry.key;
    final signal = entry.value;
    if (!userSignals.contains(signal)) continue;
    // Word-boundary: keyword must be surrounded by non-letter chars
    // (or string start/end) on both sides. Prevents "fish" matching
    // inside "fishing" but allows "diabetes" matching inside
    // "Diabetic patients should…".
    final pattern = RegExp(
      r'\b' + RegExp.escape(keyword) + r'\b',
      caseSensitive: false,
    );
    if (pattern.hasMatch(lower)) return signal;
  }
  return null;
}

/// Map an age-bracket profile string to the canonical population
/// signal ID.
///
/// Production input comes from `profileProvider.ageBracket`, which
/// stores one of `SchemaIds.ageBrackets` verbatim:
///   ['14-18', '19-30', '31-50', '51-70', '71+']
///
/// Only `'14-18'` and `'71+'` map cleanly to the "Under 18" / "Over 65"
/// population signals. `'51-70'` deliberately stays unmapped — its
/// 51-64 majority would be miscategorised as "elderly" and silently
/// suppress legitimate warnings.
///
/// Also accepts canonical-looking inputs (`'under_18'`, `'over_65'`,
/// `'children'`, `'elderly'`, ...) for tests and any future caller
/// that already passes a normalised signal token.
String _ageBracketToSignal(String bracket) {
  final normalized = bracket.toLowerCase().trim();

  // Schema bracket strings (the real production input).
  if (normalized == '14-18') return 'under_18';
  if (normalized == '71+') return 'over_65';

  // Canonical / fuzzy fallback.
  if (normalized.startsWith('under') || normalized.contains('child')) {
    return 'under_18';
  }
  if (normalized.contains('65') || normalized.contains('over') ||
      normalized.contains('elderly') || normalized.contains('geriatric')) {
    return 'over_65';
  }
  return '';
}

/// snake_case → "Snake Case". Same humanizer used elsewhere in
/// for_you_section + with_your_stack_section.
String _humanize(String raw) {
  if (raw.isEmpty) return raw;
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Section 8 widget — renders the deduped populations + the already-
/// covered parenthetical. Hides entirely when there are no
/// populations to show OR when every population matched a user
/// signal (the dedupe cleaned the list to nothing).
class PopulationsSection extends StatelessWidget {
  final List<InteractionWarning> warnings;
  final Set<String> userConditions;
  final Set<String> userDrugClasses;
  final String? ageBracket;

  const PopulationsSection({
    super.key,
    required this.warnings,
    required this.userConditions,
    required this.userDrugClasses,
    this.ageBracket,
  });

  @override
  Widget build(BuildContext context) {
    final populations = aggregatePopulations(warnings);
    if (populations.isEmpty) return const SizedBox.shrink();

    final split = splitPopulations(
      populations: populations,
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
      ageBracket: ageBracket,
    );

    // If both sides are empty after dedupe, hide entirely.
    if (split.mainList.isEmpty && split.alreadyCovered.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'At-risk populations',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          if (split.mainList.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
            Text(
              'Extra caution for: ${split.mainList.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                height: 1.4,
              ),
            ),
          ],
          if (split.alreadyCovered.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space6),
            Text(
              '(You are already covered for ${split.alreadyCovered.join(', ')})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
