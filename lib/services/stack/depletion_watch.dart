import 'package:pharmaguide/services/stack/depletion_checker.dart';

/// One medication in the user's stack, paired with the stack row id that the
/// health event log records lifecycle events against.
typedef WatchedMedication = ({
  String stackEntryId,
  DepletionMedicationIdentity identity,
});

/// A curated watch threshold evaluated against how long the user has actually
/// been tracking the medication.
///
/// [isDue] is the only thing the UI should branch on. Both the threshold and
/// the [basis] originate in reviewed curated data; this class performs date
/// arithmetic over them and nothing else.
class DepletionWatchStatus {
  const DepletionWatchStatus({
    required this.depletionId,
    required this.thresholdDays,
    required this.basis,
    required this.trackedFor,
  });

  final String depletionId;
  final int thresholdDays;
  final String basis;

  /// Continuous tracked duration, clamped at zero. A device clock moved
  /// backwards must read as "just started", never as a negative span.
  final Duration trackedFor;

  bool get isDue => trackedFor.inDays >= thresholdDays;

  /// Whole months tracked, for the "tracked here for N months" device-fact
  /// line. Uses the same 30-day month the threshold vocabulary implies; this
  /// is a display rounding, never an input to [isDue].
  int get trackedMonths => trackedFor.inDays ~/ 30;
}

/// Evaluates curated watch thresholds against the append-only tracking log.
///
/// **Why this reuses [DepletionChecker.check] rather than re-implementing
/// matching:** `check` flattens every medication identity into shared lookup
/// sets, so a returned [DepletionMatch] carries no link back to the stack row
/// that produced it. Rather than thread ids through that safety-critical
/// matcher, this resolver replays the same pure function one medication at a
/// time. The checker stays the single matching authority, so a watch can never
/// disagree with the card it annotates.
///
/// The resolver invents nothing. An entry with no reviewer-authored threshold
/// produces no status, which is what keeps the feature inert until curated
/// data enables it.
class DepletionWatchResolver {
  DepletionWatchResolver({DepletionChecker? checker})
    : _checker = checker ?? DepletionChecker();

  final DepletionChecker _checker;

  /// Returns a status per depletion entry that has BOTH a curated threshold and
  /// at least one contributing medication with a known tracking start.
  ///
  /// [trackedSinceByStackEntry] comes from
  /// `HealthEventRepository.getStackTrackedSince()`, falling back to the stack
  /// row's own `added_at` for rows predating the v10 event log. Entries absent
  /// from that map are skipped rather than treated as newly started.
  Map<String, DepletionWatchStatus> evaluate({
    required List<WatchedMedication> medications,
    required Map<String, dynamic> depletionsData,
    required Map<String, DateTime> trackedSinceByStackEntry,
    required DateTime now,
  }) {
    final nowUtc = now.toUtc();
    final earliestByDepletion = <String, DateTime>{};
    final thresholds = <String, DepletionMatch>{};

    for (final medication in medications) {
      final trackedSince = trackedSinceByStackEntry[medication.stackEntryId];
      if (trackedSince == null) continue;

      // Coverage inputs are deliberately omitted: they set `coverageLevel` and
      // never change which entries match, so the matched id set is identical.
      final matches = _checker.check(
        medications: const [],
        medicationIdentities: [medication.identity],
        depletionsData: depletionsData,
      );

      for (final match in matches) {
        if (match.watchThresholdDays == null || match.watchBasis == null) {
          continue;
        }
        thresholds[match.depletionId] = match;
        final startedAt = trackedSince.toUtc();
        final existing = earliestByDepletion[match.depletionId];
        // Earliest start across contributing medications: when two drugs in
        // the same class drive one relationship, the exposure is as old as the
        // longer-standing of them.
        if (existing == null || startedAt.isBefore(existing)) {
          earliestByDepletion[match.depletionId] = startedAt;
        }
      }
    }

    final statuses = <String, DepletionWatchStatus>{};
    for (final entry in earliestByDepletion.entries) {
      final match = thresholds[entry.key]!;
      var tracked = nowUtc.difference(entry.value);
      if (tracked.isNegative) tracked = Duration.zero;
      statuses[entry.key] = DepletionWatchStatus(
        depletionId: entry.key,
        thresholdDays: match.watchThresholdDays!,
        basis: match.watchBasis!,
        trackedFor: tracked,
      );
    }
    return statuses;
  }
}
