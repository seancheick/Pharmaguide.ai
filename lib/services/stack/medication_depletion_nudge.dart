// Medication-added gentle nudge — Phase 4 of the depletion UX plan.
//
// When a user adds a medication to their stack and we know it can
// gradually lower a nutrient (from medication_depletions.json), show a
// one-time, dismissible suggestion. Uses SharedPreferences to ensure
// the nudge fires only once per (medication-id, depleted-nutrient)
// pair — not on every stack view.
//
// Tone is deliberately calm: "Since you take metformin, long-term users
// often supplement vitamin B12 — want to add it to your stack?" No
// alarm. Users who dismiss are not asked again for the same pair.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

/// A one-time nudge suggestion surfaced after a medication is added.
class PendingDepletionNudge {
  /// The stack-entry id of the medication the user just added.
  final String stackEntryId;

  /// Depletions (already filtered to non-critical, unseen, significant/
  /// moderate severity) ready to surface. The widget renders one
  /// suggestion per entry — typically 1-2 per medication.
  final List<DepletionMatch> depletions;

  const PendingDepletionNudge({
    required this.stackEntryId,
    required this.depletions,
  });

  bool get isEmpty => depletions.isEmpty;
}

class MedicationDepletionNudgeService {
  /// Severity levels allowed to nudge. "mild" depletions are too soft a
  /// signal to pop a suggestion for; "significant" and "moderate" are
  /// the sweet spot. (No depletion entries carry "critical" severity.)
  static const _allowedSeverities = {'significant', 'moderate'};

  final Future<SharedPreferences> Function() _prefsFactory;

  MedicationDepletionNudgeService({
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  /// Compute the pending nudge for a newly-added medication.
  ///
  /// Returns null when there's nothing to surface — empty depletion
  /// data, all depletions already dismissed, or user's stack already
  /// covers every eligible depletion.
  ///
  /// [stackEntryId] — id of the stack row for the medication; used as
  ///   the nudge key so returning users don't see the same suggestion
  ///   on app restart.
  /// [medicationName] / [drugClassIds] — same shape the existing
  ///   [DepletionChecker] already matches on.
  /// [depletionsData] — the parsed `medication_depletions.json`.
  /// [stackCanonicalIds] / [stackDoses] — stack coverage data used to
  ///   suppress nudges for already-covered nutrients.
  Future<PendingDepletionNudge?> computePendingNudge({
    required String stackEntryId,
    required String medicationName,
    required List<String> drugClassIds,
    required Map<String, dynamic> depletionsData,
    Set<String> stackCanonicalIds = const {},
    List<StackSupplementDose> stackDoses = const [],
  }) async {
    final meds = drugClassIds.isEmpty
        ? [(name: medicationName, drugClassId: null as String?)]
        : drugClassIds
              .map((c) => (name: medicationName, drugClassId: c as String?))
              .toList(growable: false);

    final matches = DepletionChecker().check(
      medications: meds,
      depletionsData: depletionsData,
      stackCanonicalIds: stackCanonicalIds,
      stackDoses: stackDoses,
    );

    final prefs = await _prefsFactory();
    final eligible = <DepletionMatch>[];
    for (final m in matches) {
      // Gate 1: severity tier.
      if (!_allowedSeverities.contains(m.severity.toLowerCase())) continue;
      // Gate 2: user's stack already covers this nutrient adequately.
      if (m.coverageLevel == CoverageLevel.adequate) continue;
      // Gate 3: user already dismissed this nudge.
      if (prefs.getBool(_key(stackEntryId, m.depletionId)) == true) continue;
      eligible.add(m);
    }

    if (eligible.isEmpty) return null;

    // Cap at 2 depletions per nudge — one suggestion is ideal, two is
    // the maximum before the sheet feels like a checklist.
    return PendingDepletionNudge(
      stackEntryId: stackEntryId,
      depletions: eligible.take(2).toList(growable: false),
    );
  }

  /// Mark a specific (medication, depletion) nudge as dismissed so it
  /// won't fire again for the same stack entry.
  Future<void> markSeen({
    required String stackEntryId,
    required String depletionId,
  }) async {
    final prefs = await _prefsFactory();
    await prefs.setBool(_key(stackEntryId, depletionId), true);
  }

  /// Mark every depletion in the nudge as dismissed — used by the
  /// "Maybe later" / dismiss button so the whole suggestion doesn't
  /// reappear.
  Future<void> markAllSeen(PendingDepletionNudge nudge) async {
    final prefs = await _prefsFactory();
    for (final m in nudge.depletions) {
      await prefs.setBool(_key(nudge.stackEntryId, m.depletionId), true);
    }
  }

  static String _key(String stackEntryId, String depletionId) {
    return 'depletion_nudge_seen::$stackEntryId::$depletionId';
  }
}
