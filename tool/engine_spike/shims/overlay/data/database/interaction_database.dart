// SPIKE OVERLAY for lib/data/database/interaction_database.dart.
//
// This file IS the server-side data-access interface the engine needs from the
// interaction DB. Every method below is one the engine closure calls; each
// reproduces the SQL/Drift predicate of the real InteractionDatabase method of
// the same name, over rows held in memory (pipeline-exported JSON, here the
// sqlite3 -json fixture). No dart:io, no FFI: compiles to JS and native.
import 'dart:convert';

/// Plain mirror of the Drift-generated `InteractionRow` (same fields/types).
class InteractionRow {
  const InteractionRow({
    required this.id,
    required this.agent1Type,
    required this.agent1Name,
    required this.agent1Id,
    this.agent1CanonicalId,
    this.agent1DrugClass,
    required this.agent2Type,
    required this.agent2Name,
    required this.agent2Id,
    this.agent2CanonicalId,
    this.agent2DrugClass,
    required this.severity,
    this.effectType,
    required this.mechanism,
    required this.management,
    this.evidenceLevel,
    required this.sourceUrlsJson,
    required this.sourcePmidsJson,
    required this.bidirectional,
    required this.doseDependent,
    this.doseThresholdText,
    this.direction,
    this.materiality,
    this.doseThresholdJson,
    required this.typeAuthored,
    required this.source,
    required this.provenance,
    required this.versionAdded,
    required this.versionLastModified,
    this.retiredAt,
    this.retiredReason,
    required this.lastUpdated,
    this.alertStyle,
    this.noteBody,
    this.practicalGuidance,
  });

  factory InteractionRow.fromSqlJson(Map<String, dynamic> j) => InteractionRow(
    id: j['id'] as String,
    agent1Type: j['agent1_type'] as String,
    agent1Name: j['agent1_name'] as String,
    agent1Id: j['agent1_id'].toString(),
    agent1CanonicalId: j['agent1_canonical_id'] as String?,
    agent1DrugClass: j['agent1_drug_class'] as String?,
    agent2Type: j['agent2_type'] as String,
    agent2Name: j['agent2_name'] as String,
    agent2Id: j['agent2_id'].toString(),
    agent2CanonicalId: j['agent2_canonical_id'] as String?,
    agent2DrugClass: j['agent2_drug_class'] as String?,
    severity: j['severity'] as String,
    effectType: j['effect_type'] as String?,
    mechanism: j['mechanism'] as String,
    management: j['management'] as String,
    evidenceLevel: j['evidence_level'] as String?,
    sourceUrlsJson: j['source_urls_json'] as String,
    sourcePmidsJson: j['source_pmids_json'] as String,
    bidirectional: (j['bidirectional'] as int?) ?? 1,
    doseDependent: (j['dose_dependent'] as int?) ?? 0,
    doseThresholdText: j['dose_threshold_text'] as String?,
    direction: j['direction'] as String?,
    materiality: j['materiality'] as String?,
    doseThresholdJson: j['dose_threshold_json'] as String?,
    typeAuthored: j['type_authored'] as String,
    source: j['source'] as String,
    provenance: j['provenance'] as String,
    versionAdded: j['version_added'] as String,
    versionLastModified: j['version_last_modified'] as String,
    retiredAt: j['retired_at'] as String?,
    retiredReason: j['retired_reason'] as String?,
    lastUpdated: j['last_updated'] as String,
    alertStyle: j['alert_style'] as String?,
    noteBody: j['note_body'] as String?,
    practicalGuidance: j['practical_guidance'] as String?,
  );

  final String id;
  final String agent1Type;
  final String agent1Name;
  final String agent1Id;
  final String? agent1CanonicalId;
  final String? agent1DrugClass;
  final String agent2Type;
  final String agent2Name;
  final String agent2Id;
  final String? agent2CanonicalId;
  final String? agent2DrugClass;
  final String severity;
  final String? effectType;
  final String mechanism;
  final String management;
  final String? evidenceLevel;
  final String sourceUrlsJson;
  final String sourcePmidsJson;
  final int bidirectional;
  final int doseDependent;
  final String? doseThresholdText;
  final String? direction;
  final String? materiality;
  final String? doseThresholdJson;
  final String typeAuthored;
  final String source;
  final String provenance;
  final String versionAdded;
  final String versionLastModified;
  final String? retiredAt;
  final String? retiredReason;
  final String lastUpdated;
  final String? alertStyle;
  final String? noteBody;
  final String? practicalGuidance;
}

class DrugClassMapRow {
  const DrugClassMapRow({
    required this.classId,
    required this.drugRxcuisJson,
    required this.excludedDrugRxcuisJson,
  });

  factory DrugClassMapRow.fromSqlJson(Map<String, dynamic> j) =>
      DrugClassMapRow(
        classId: j['class_id'] as String,
        drugRxcuisJson: j['drug_rxcuis_json'] as String,
        excludedDrugRxcuisJson: j['excluded_drug_rxcuis_json'] as String,
      );

  final String classId;
  final String drugRxcuisJson;
  final String excludedDrugRxcuisJson;
}

/// Plain mirror of the Drift-generated `ResearchPairRow`. Research pairs
/// (31,768 rows, the bulk of the 25 MB file) feed only the Tier-2 research
/// evidence lane (lib/services/stack/research_pair_lookup.dart), never the
/// safety checks. Server-side they would be a remote indexed query, not bundled.
class ResearchPairRow {
  const ResearchPairRow({
    required this.pairId,
    required this.cuiA,
    required this.cuiB,
    required this.entityAName,
    required this.entityBName,
    required this.entityAType,
    required this.entityBType,
    this.canonicalIdA,
    this.canonicalIdB,
    this.rxcuiA,
    this.rxcuiB,
    required this.paperCount,
    required this.humanStudyCount,
    required this.clinicalStudyCount,
    required this.topSentencesJson,
    required this.topPmidsJson,
    this.latestPaperYear,
    required this.source,
    required this.lastUpdated,
  });

  final String pairId;
  final String cuiA;
  final String cuiB;
  final String entityAName;
  final String entityBName;
  final String entityAType;
  final String entityBType;
  final String? canonicalIdA;
  final String? canonicalIdB;
  final String? rxcuiA;
  final String? rxcuiB;
  final int paperCount;
  final int humanStudyCount;
  final int clinicalStudyCount;
  final String topSentencesJson;
  final String topPmidsJson;
  final int? latestPaperYear;
  final String source;
  final String lastUpdated;
}

/// Fixture/JSON-backed stand-in for the Drift `InteractionDatabase`.
class InteractionDatabase {
  InteractionDatabase.fromRows({
    required List<InteractionRow> interactions,
    required List<DrugClassMapRow> drugClassMap,
    List<ResearchPairRow> researchPairs = const [],
  }) : _interactions = interactions,
       _drugClassMap = drugClassMap,
       _researchPairs = researchPairs;

  final List<ResearchPairRow> _researchPairs;

  // ORDER BY paper_count DESC, clinical_study_count DESC, human_study_count
  // DESC, latest_paper_year DESC NULLS LAST, pair_id ASC LIMIT ?
  List<ResearchPairRow> _rankedPairs(
    bool Function(ResearchPairRow) where,
    int limit,
  ) {
    if (limit <= 0) return const <ResearchPairRow>[];
    final rows = _researchPairs.where(where).toList()
      ..sort((a, b) {
        var c = b.paperCount.compareTo(a.paperCount);
        if (c != 0) return c;
        c = b.clinicalStudyCount.compareTo(a.clinicalStudyCount);
        if (c != 0) return c;
        c = b.humanStudyCount.compareTo(a.humanStudyCount);
        if (c != 0) return c;
        final ay = a.latestPaperYear, by = b.latestPaperYear;
        if (ay != by) {
          if (ay == null) return 1;
          if (by == null) return -1;
          return by.compareTo(ay);
        }
        return a.pairId.compareTo(b.pairId);
      });
    return rows.take(limit).toList();
  }

  Future<List<ResearchPairRow>> lookupResearchPairsByCanonicalId(
    String canonicalId, {
    int limit = 20,
  }) async {
    final n = canonicalId.trim().toLowerCase();
    if (n.isEmpty) return const <ResearchPairRow>[];
    return _rankedPairs(
      (r) =>
          r.canonicalIdA?.toLowerCase() == n ||
          r.canonicalIdB?.toLowerCase() == n,
      limit,
    );
  }

  Future<List<ResearchPairRow>> lookupResearchPairsByRxcui(
    String rxcui, {
    int limit = 20,
  }) async {
    final n = rxcui.trim();
    if (n.isEmpty) return const <ResearchPairRow>[];
    return _rankedPairs((r) => r.rxcuiA == n || r.rxcuiB == n, limit);
  }

  factory InteractionDatabase.fromSqlJson({
    required String interactionsJson,
    required String drugClassMapJson,
  }) => InteractionDatabase.fromRows(
    interactions: [
      for (final r in jsonDecode(interactionsJson) as List)
        InteractionRow.fromSqlJson(r as Map<String, dynamic>),
    ],
    drugClassMap: [
      for (final r in jsonDecode(drugClassMapJson) as List)
        DrugClassMapRow.fromSqlJson(r as Map<String, dynamic>),
    ],
  );

  final List<InteractionRow> _interactions;
  final List<DrugClassMapRow> _drugClassMap;

  Iterable<InteractionRow> get _live =>
      _interactions.where((r) => r.retiredAt == null);

  // SQL: retired_at IS NULL AND (lower(agent1_canonical_id) = ? OR lower(agent2_canonical_id) = ?)
  Future<List<InteractionRow>> lookupByCanonicalId(String canonicalId) async {
    final normalized = canonicalId.trim().toLowerCase();
    if (normalized.isEmpty) return const <InteractionRow>[];
    return _live
        .where(
          (r) =>
              r.agent1CanonicalId?.toLowerCase() == normalized ||
              r.agent2CanonicalId?.toLowerCase() == normalized,
        )
        .toList();
  }

  Future<List<InteractionRow>> lookupByRxcui(String rxcui) async => _live
      .where(
        (t) =>
            (t.agent1Type == 'drug' && t.agent1Id == rxcui) ||
            (t.agent2Type == 'drug' && t.agent2Id == rxcui),
      )
      .toList();

  Future<List<InteractionRow>> lookupByDrugClass(String classId) async =>
      _live.where((t) {
        final agentMatch =
            (t.agent1Type == 'drug_class' && t.agent1Id == classId) ||
            (t.agent2Type == 'drug_class' && t.agent2Id == classId);
        final tagMatch =
            t.agent1DrugClass == classId || t.agent2DrugClass == classId;
        return agentMatch || tagMatch;
      }).toList();

  Future<List<InteractionRow>> lookupPair(
    String a1Id,
    String a1Type,
    String a2Id,
    String a2Type,
  ) async => _live.where((t) {
    final forward =
        t.agent1Id == a1Id &&
        t.agent1Type == a1Type &&
        t.agent2Id == a2Id &&
        t.agent2Type == a2Type;
    final reverse =
        t.agent1Id == a2Id &&
        t.agent1Type == a2Type &&
        t.agent2Id == a1Id &&
        t.agent2Type == a1Type;
    return forward || reverse;
  }).toList();

  Future<List<String>> rxcuisForDrugClass(String classId) async {
    final row = _drugClassMap.where((r) => r.classId == classId).firstOrNull;
    if (row == null) return const <String>[];
    try {
      final decoded = jsonDecode(row.drugRxcuisJson);
      if (decoded is! List) return const <String>[];
      return decoded
          .where((e) => e != null)
          .map((e) => e.toString())
          .toList(growable: false);
    } on FormatException {
      return const <String>[];
    }
  }

  Future<List<String>> drugClassesForRxcui(String rxcui) async {
    final normalized = rxcui.trim();
    if (normalized.isEmpty) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final row in _drugClassMap) {
      try {
        final decoded = jsonDecode(row.drugRxcuisJson);
        if (decoded is! List) continue;
        final contains = decoded.any((e) => e?.toString().trim() == normalized);
        if (contains && seen.add(row.classId)) out.add(row.classId);
      } on FormatException {
        continue;
      }
    }
    out.sort();
    return out;
  }

  Future<bool> isDrugClassExcluded(
    String classId,
    Iterable<String> rxcuis,
  ) async {
    final row = _drugClassMap.where((r) => r.classId == classId).firstOrNull;
    if (row == null) return false;
    try {
      final decoded = jsonDecode(row.excludedDrugRxcuisJson);
      if (decoded is! List) return false;
      final identities = rxcuis.map((id) => id.trim()).toSet();
      return decoded.any(
        (id) => id != null && identities.contains(id.toString().trim()),
      );
    } on FormatException {
      return false;
    }
  }
}
