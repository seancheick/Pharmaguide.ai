import 'dart:convert';

import 'package:pharmaguide/core/models/research_pair_evidence.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';

class ResearchPairLookup {
  const ResearchPairLookup(this._db);

  final InteractionDatabase _db;

  Future<List<ResearchPairEvidence>> lookupForProduct({
    required List<String> canonicalIds,
    List<UserStacksLocalData> stack = const <UserStacksLocalData>[],
    int limit = 6,
  }) async {
    if (limit <= 0) return const <ResearchPairEvidence>[];

    final canonicalSet = _normalizeSet(canonicalIds);
    if (canonicalSet.isEmpty) return const <ResearchPairEvidence>[];

    final medicationRxcuis = _rxcuisFromStack(stack);
    final rowsById = <String, ResearchPairRow>{};

    for (final canonicalId in canonicalSet) {
      final rows = await _db.lookupResearchPairsByCanonicalId(
        canonicalId,
        limit: limit * 4,
      );
      for (final row in rows) {
        rowsById[row.pairId] = row;
      }
    }

    for (final rxcui in medicationRxcuis) {
      final rows = await _db.lookupResearchPairsByRxcui(
        rxcui,
        limit: limit * 4,
      );
      for (final row in rows) {
        if (_rowMatchesAnyCanonical(row, canonicalSet)) {
          rowsById[row.pairId] = row;
        }
      }
    }

    final evidence = rowsById.values
        .map(ResearchPairEvidence.fromRow)
        .where(
          (row) =>
              canonicalSet.any(row.involvesCanonicalId) &&
              _hasDisplayableEvidence(row),
        )
        .toList(growable: false);

    final contextual = evidence
        .where((row) => medicationRxcuis.any(row.involvesRxcui))
        .toList(growable: false);
    final broad = evidence
        .where((row) => !medicationRxcuis.any(row.involvesRxcui))
        .toList(growable: false);

    contextual.sort(_compareEvidence);
    broad.sort(_compareEvidence);

    return <ResearchPairEvidence>[
      ...contextual,
      ...broad,
    ].take(limit).toList(growable: false);
  }

  static Set<String> _normalizeSet(Iterable<String> values) {
    return values
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  static bool _rowMatchesAnyCanonical(
    ResearchPairRow row,
    Set<String> canonicalIds,
  ) {
    return canonicalIds.contains(row.canonicalIdA?.toLowerCase()) ||
        canonicalIds.contains(row.canonicalIdB?.toLowerCase());
  }

  static bool _hasDisplayableEvidence(ResearchPairEvidence row) {
    return row.paperCount > 0 &&
        (row.topSentences.isNotEmpty || row.topPmids.isNotEmpty);
  }

  static int _compareEvidence(ResearchPairEvidence a, ResearchPairEvidence b) {
    final paper = b.paperCount.compareTo(a.paperCount);
    if (paper != 0) return paper;
    final clinical = b.clinicalStudyCount.compareTo(a.clinicalStudyCount);
    if (clinical != 0) return clinical;
    final human = b.humanStudyCount.compareTo(a.humanStudyCount);
    if (human != 0) return human;
    final year = (b.latestPaperYear ?? 0).compareTo(a.latestPaperYear ?? 0);
    if (year != 0) return year;
    return a.pairId.compareTo(b.pairId);
  }

  static Set<String> _rxcuisFromStack(List<UserStacksLocalData> stack) {
    final out = <String>{};
    for (final entry in stack) {
      if (entry.type != 'medication') continue;
      _addTrimmed(out, entry.rxcui);
      _addTrimmed(out, entry.genericRxcui);
      for (final rxcui in _decodeStringList(entry.ingredientRxcuisCol)) {
        _addTrimmed(out, rxcui);
      }
    }
    return out;
  }

  static void _addTrimmed(Set<String> out, String? value) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) out.add(trimmed);
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const <String>[];
    }
  }
}
