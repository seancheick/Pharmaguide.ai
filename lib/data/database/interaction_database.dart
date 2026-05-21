import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pharmaguide/data/database/tables/drug_class_map_table.dart';
import 'package:pharmaguide/data/database/tables/interaction_db_metadata_table.dart';
import 'package:pharmaguide/data/database/tables/interactions_table.dart';
import 'package:pharmaguide/data/database/tables/research_pairs_table.dart';

part 'interaction_database.g.dart';

/// Strongly-typed view of the embedded `interaction_db_metadata` key/value
/// table. The pipeline writes a fixed set of keys (M2 / spec §6.3 step 8);
/// hydrating them into a single immutable struct keeps callers from juggling
/// raw string lookups and lets the test suite assert against named fields.
///
/// `sha256` is **intentionally absent** — see the table file docstring and
/// the T7 fix in `release_interaction_artifact.py`. The manifest is the sole
/// source of truth for the file checksum.
class InteractionDbMetadata {
  const InteractionDbMetadata({
    required this.schemaVersion,
    required this.builtAt,
    required this.sourceDraftsCount,
    required this.sourceSuppaiCount,
    required this.totalInteractions,
    required this.overrideCount,
    required this.resolvedConflictCount,
    required this.interactionDbVersion,
    required this.pipelineVersion,
    required this.minAppVersion,
  });

  /// Schema version of the SQLite layout (e.g. `"1.0.0"`).
  final String schemaVersion;

  /// ISO 8601 UTC timestamp the pipeline finished building the file.
  final String builtAt;

  /// Curated draft rows that survived `verify_interactions.py` gates.
  final int sourceDraftsCount;

  /// supp.ai research pairs that survived the ≥2-paper / ≥1-human-study
  /// filter applied by `ingest_suppai.py`.
  final int sourceSuppaiCount;

  /// Final row count in the `interactions` table after dedup, conflict
  /// resolution, and override application.
  final int totalInteractions;

  /// Number of manual `curated_overrides/*.json` rows applied during build.
  final int overrideCount;

  /// Number of severity conflicts the pipeline auto-resolved while merging
  /// curated drafts and supp.ai-derived rows.
  final int resolvedConflictCount;

  /// Human-readable release tag for the interaction DB bundle
  /// (e.g. `"2026.04.11.001"`).
  final String interactionDbVersion;

  /// Pipeline build version that produced the bundle.
  final String pipelineVersion;

  /// Minimum Flutter app `version` (semver) that can read this DB. The app
  /// must refuse to open a bundle that requires a newer version than itself.
  final String minAppVersion;
}

/// READ-ONLY Drift wrapper around the bundled `interaction_db.sqlite` asset.
///
/// The DB is built deterministically by the pipeline's
/// `release_interaction_artifact.py` (M2) and shipped as a Flutter asset
/// (`assets/db/interaction_db.sqlite`). The app copies it to the documents
/// directory on first launch via [ensureInteractionDatabaseAvailable] in
/// `database_providers.dart`, then opens it through this wrapper.
///
/// **Read-only contract.** Every row is verified by the pipeline; the app
/// must never INSERT/UPDATE/DELETE here. Tombstoned rows are kept in the
/// table for audit but filtered out of every public lookup via
/// `WHERE retired_at IS NULL`.
///
/// **No migrations.** The bundle is replaced wholesale on every release;
/// `schemaVersion` is pinned to `1` (matching the pipeline's
/// `PRAGMA user_version=1`) so Drift never attempts to alter the schema at
/// open time. The pipeline's manifest carries the human-readable
/// `schema_version` ("1.0.0") for compatibility checks.
@DriftDatabase(
  tables: [
    Interactions,
    DrugClassMap,
    ResearchPairs,
    InteractionDbMetadataTable,
  ],
)
class InteractionDatabase extends _$InteractionDatabase {
  InteractionDatabase(File dbFile)
    : super(NativeDatabase(dbFile, logStatements: false));

  /// In-memory variant for tests that build a fixture DB on the fly.
  InteractionDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // The bundle ships fully built; we never create from scratch in
      // production. Tests using [InteractionDatabase.memory] do hit
      // this path, so let Drift create the schema from the table
      // definitions for them.
      await m.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      // Pre-built DB — no versioned migrations.
    },
  );

  /// Open a pre-built database file (the bundled asset, copied to the
  /// app documents directory by [ensureInteractionDatabaseAvailable]).
  static InteractionDatabase open(String dbPath) {
    return InteractionDatabase(File(dbPath));
  }

  // ---------------------------------------------------------------------------
  // Lookup methods (spec §7.3)
  //
  // All lookups filter `retired_at IS NULL` so M3 callers never see
  // tombstoned rows. The DB-level filter is the single source of truth —
  // do NOT re-implement it in callers, and do NOT remove it here without
  // updating M4/M5 to apply their own filter.
  // ---------------------------------------------------------------------------

  /// All live interactions involving the supplement identified by
  /// [canonicalId] (e.g. `"dsld:warfarin"`, `"umls:C0042890"`).
  ///
  /// Direction-agnostic: matches whether the supplement appears as
  /// `agent1` or `agent2`. Tombstoned rows are excluded.
  Future<List<InteractionRow>> lookupByCanonicalId(String canonicalId) {
    final normalized = canonicalId.trim().toLowerCase();
    if (normalized.isEmpty) return Future.value(const <InteractionRow>[]);

    return customSelect(
      '''
      SELECT *
      FROM interactions
      WHERE retired_at IS NULL
        AND (
          lower(agent1_canonical_id) = ?
          OR lower(agent2_canonical_id) = ?
        )
      ''',
      variables: [
        Variable.withString(normalized),
        Variable.withString(normalized),
      ],
      readsFrom: {interactions},
    ).map((row) => interactions.map(row.data)).get();
  }

  /// All live interactions involving the drug identified by [rxcui].
  ///
  /// Matches `agent_type = 'drug' AND agent_id = rxcui` on either side.
  /// We tighten the type filter to `'drug'` so a supplement that happens
  /// to share a numeric id (theoretically possible if a non-drug agent
  /// were stored with a numeric id) cannot collide.
  Future<List<InteractionRow>> lookupByRxcui(String rxcui) {
    return (select(interactions)..where(
          (t) =>
              ((t.agent1Type.equals('drug') & t.agent1Id.equals(rxcui)) |
                  (t.agent2Type.equals('drug') & t.agent2Id.equals(rxcui))) &
              t.retiredAt.isNull(),
        ))
        .get();
  }

  /// All live interactions that name [classId] (e.g. `"class:statins"`)
  /// anywhere on the row.
  ///
  /// In the M2 build the class id can appear in two shapes:
  ///
  ///   1. **Class-as-agent** — the row's agent is the class itself, with
  ///      `agent1_type='drug_class' AND agent1_id='class:statins'` (and the
  ///      `agent1_drug_class` column is null on those rows).
  ///   2. **Class-tag-on-a-drug** — the row's agent is a specific drug
  ///      and the `agent1_drug_class` column carries `class:statins` as a
  ///      cross-reference so the same row also matches sibling lookups.
  ///
  /// We OR all four positions so callers don't have to know which shape
  /// the pipeline emitted. To enumerate the member RXCUIs of a class so
  /// callers can branch into per-drug lookups, use [rxcuisForDrugClass].
  Future<List<InteractionRow>> lookupByDrugClass(String classId) {
    return (select(interactions)..where((t) {
          final agentMatch =
              (t.agent1Type.equals('drug_class') & t.agent1Id.equals(classId)) |
              (t.agent2Type.equals('drug_class') & t.agent2Id.equals(classId));
          final tagMatch =
              t.agent1DrugClass.equals(classId) |
              t.agent2DrugClass.equals(classId);
          return (agentMatch | tagMatch) & t.retiredAt.isNull();
        }))
        .get();
  }

  /// Symmetric pair lookup: find live rows where one side matches
  /// (`a1Id`, `a1Type`) and the other matches (`a2Id`, `a2Type`),
  /// regardless of which slot the pipeline placed them in.
  ///
  /// This is the workhorse for stack/medication interaction checks
  /// (M4-M5): given two known agents, "do we have a curated row about
  /// this exact pair?".
  Future<List<InteractionRow>> lookupPair(
    String a1Id,
    String a1Type,
    String a2Id,
    String a2Type,
  ) {
    return (select(interactions)..where((t) {
          final forward =
              t.agent1Id.equals(a1Id) &
              t.agent1Type.equals(a1Type) &
              t.agent2Id.equals(a2Id) &
              t.agent2Type.equals(a2Type);
          final reverse =
              t.agent1Id.equals(a2Id) &
              t.agent1Type.equals(a2Type) &
              t.agent2Id.equals(a1Id) &
              t.agent2Type.equals(a1Type);
          return (forward | reverse) & t.retiredAt.isNull();
        }))
        .get();
  }

  /// Tier-2 supp.ai research rows involving [canonicalId].
  ///
  /// These rows are deliberately separate from [lookupByCanonicalId]:
  /// they are literature co-occurrence evidence, not curated safety
  /// warnings. Callers must render them in a neutral evidence surface and
  /// must never convert them to [InteractionRow] or score penalties.
  Future<List<ResearchPairRow>> lookupResearchPairsByCanonicalId(
    String canonicalId, {
    int limit = 20,
  }) {
    final normalized = canonicalId.trim().toLowerCase();
    if (normalized.isEmpty || limit <= 0) {
      return Future.value(const <ResearchPairRow>[]);
    }

    return customSelect(
      '''
      SELECT *
      FROM research_pairs
      WHERE lower(canonical_id_a) = ?
         OR lower(canonical_id_b) = ?
      ORDER BY paper_count DESC,
               clinical_study_count DESC,
               human_study_count DESC,
               latest_paper_year DESC NULLS LAST,
               pair_id ASC
      LIMIT ?
      ''',
      variables: [
        Variable.withString(normalized),
        Variable.withString(normalized),
        Variable.withInt(limit),
      ],
      readsFrom: {researchPairs},
    ).map((row) => researchPairs.map(row.data)).get();
  }

  /// Tier-2 supp.ai research rows involving [rxcui].
  ///
  /// RxCUI matching is exact and direction-agnostic. The pipeline only
  /// populates these columns when a supp.ai drug CUI has an unambiguous
  /// local RxNorm bridge.
  Future<List<ResearchPairRow>> lookupResearchPairsByRxcui(
    String rxcui, {
    int limit = 20,
  }) {
    final normalized = rxcui.trim();
    if (normalized.isEmpty || limit <= 0) {
      return Future.value(const <ResearchPairRow>[]);
    }

    return customSelect(
      '''
      SELECT *
      FROM research_pairs
      WHERE rxcui_a = ?
         OR rxcui_b = ?
      ORDER BY paper_count DESC,
               clinical_study_count DESC,
               human_study_count DESC,
               latest_paper_year DESC NULLS LAST,
               pair_id ASC
      LIMIT ?
      ''',
      variables: [
        Variable.withString(normalized),
        Variable.withString(normalized),
        Variable.withInt(limit),
      ],
      readsFrom: {researchPairs},
    ).map((row) => researchPairs.map(row.data)).get();
  }

  /// Resolve a drug class id to its member RXCUI list.
  ///
  /// Used by M4 medication entry — when a user types a brand or generic
  /// name, the app fetches its drug classes from RxNorm, then walks each
  /// class through this method to know which sibling drugs share the
  /// same interaction profile.
  ///
  /// The pipeline stores the membership as a JSON array in
  /// `drug_rxcuis_json`; we decode it here so callers receive a typed
  /// `List<String>`. Returns an empty list if the class id is unknown
  /// or the JSON cannot be parsed (rather than throwing — a missing
  /// class should degrade gracefully into "no sibling drugs found").
  Future<List<String>> rxcuisForDrugClass(String classId) async {
    final row = await (select(
      drugClassMap,
    )..where((t) => t.classId.equals(classId))).getSingleOrNull();
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

  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------

  /// Hydrate the embedded `interaction_db_metadata` key/value table into
  /// a typed [InteractionDbMetadata] struct.
  ///
  /// All keys listed in the table file docstring are required; if any are
  /// missing the bundle is malformed and we throw [StateError] so the
  /// import gate (`scripts/import_catalog_artifact.sh`) catches it before
  /// the user ever opens the app.
  Future<InteractionDbMetadata> getMetadata() async {
    final rows = await select(interactionDbMetadataTable).get();
    final kv = <String, String>{for (final r in rows) r.key: r.value};

    String require(String key) {
      final v = kv[key];
      if (v == null || v.isEmpty) {
        throw StateError(
          'interaction_db_metadata is missing required key "$key" — '
          'the bundle is malformed. Re-run release_interaction_artifact.py.',
        );
      }
      return v;
    }

    int requireInt(String key) {
      final raw = require(key);
      final parsed = int.tryParse(raw);
      if (parsed == null) {
        throw StateError(
          'interaction_db_metadata key "$key" is not an integer: "$raw"',
        );
      }
      return parsed;
    }

    return InteractionDbMetadata(
      schemaVersion: require('schema_version'),
      builtAt: require('built_at'),
      sourceDraftsCount: requireInt('source_drafts_count'),
      sourceSuppaiCount: requireInt('source_suppai_count'),
      totalInteractions: requireInt('total_interactions'),
      overrideCount: requireInt('override_count'),
      resolvedConflictCount: requireInt('resolved_conflict_count'),
      interactionDbVersion: require('interaction_db_version'),
      pipelineVersion: require('pipeline_version'),
      minAppVersion: require('min_app_version'),
    );
  }

  /// Total live (non-tombstoned) interaction rows. Used by health checks
  /// and the import gate to confirm the bundle isn't empty.
  Future<int> countLiveInteractions() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS count FROM interactions WHERE retired_at IS NULL',
      readsFrom: {interactions},
    ).getSingle();
    return row.read<int>('count');
  }
}
