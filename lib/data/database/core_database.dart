import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pharmaguide/data/database/tables/products_core_table.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

part 'core_database.g.dart';

sealed class UpcResolution {
  const UpcResolution();
}

final class UpcNotFound extends UpcResolution {
  const UpcNotFound();
}

final class UpcUnique extends UpcResolution {
  const UpcUnique(this.product);

  final ProductsCoreData product;
}

final class UpcAmbiguous extends UpcResolution {
  UpcAmbiguous(List<ProductsCoreData> candidates)
    : candidates = List.unmodifiable(candidates);

  final List<ProductsCoreData> candidates;
}

/// READ-ONLY database backed by the pre-built `pharmaguide_core.db` file
/// downloaded from Supabase (or the bundled asset on first launch).
///
/// v4-only reader. The current catalog contract is export schema 2.4.0:
/// `quality_score_v4_100` is the shipped /100 score and
/// `quality_score_status` controls score eligibility. Catalog safety and
/// quality assessment completion are independent nullable fields so older
/// v2.x snapshots remain readable.
@DriftDatabase(tables: [ProductsCore])
class CoreDatabase extends _$CoreDatabase {
  CoreDatabase(File dbFile)
    : super(NativeDatabase(dbFile, logStatements: false));

  CoreDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

  /// SQL for the v4 /100 quality score. `quality_score_v4_100` is NULL for
  /// safety-suppressed rows, so those rows sort last and never outrank a real
  /// score.
  static const String effectiveScoreSql = 'quality_score_v4_100';

  /// SQL expression that normalizes a stored UPC to digits-only form.
  ///
  /// IMPORTANT: this exact string is used BOTH in the expression index
  /// created by [_ensureAppIndexes] AND in the [findAllByUpc] WHERE clause.
  /// SQLite only uses an expression index when the query expression matches
  /// the index expression character-for-character — keep them identical.
  static const String upcNormalizeSql =
      "REPLACE(REPLACE(REPLACE(REPLACE(upc_sku, ' ', ''), '-', ''), '.', ''), '/', '')";

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      throw StateError(
        'Core database schema changed from $from to $to. '
        'This database is a pre-built artifact and must be replaced, '
        'not migrated in place.',
      );
    },
    beforeOpen: (details) async {
      // The pre-built DB from the pipeline may lack additive columns the
      // current app build expects. Add safe nullable columns so older local
      // snapshots don't crash during app startup.
      await _ensureCompatColumns();
      await _ensureAppIndexes();
    },
  );

  /// App-side performance indexes created at open time.
  ///
  /// The local copy of `pharmaguide_core.db` lives in the app documents
  /// directory and IS writable (it's OTA-replaced wholesale), so creating
  /// indexes here is legitimate. `IF NOT EXISTS` makes this a no-op after
  /// the first open of any given snapshot; after an OTA swap the new file
  /// gets re-indexed on its first open.
  ///
  /// LONG-TERM FIX: these indexes should be built pipeline-side in
  /// `build_final_db.py` so the app never pays the one-time index build
  /// cost (matters as the catalog grows 9K → 250K rows). Keep the app-side
  /// `IF NOT EXISTS` as a safety net even after the pipeline ships them.
  ///
  /// Failures are logged (non-fatal) and swallowed — a missing index only
  /// degrades performance, it must never block catalog open.
  Future<void> _ensureAppIndexes() async {
    const statements = [
      // findAllByUpc: the REPLACE(...) normalization wrapper defeats the
      // plain idx_core_upc index (verified SCAN via EXPLAIN QUERY PLAN).
      // This expression index restores SEARCH — the expression matches
      // [upcNormalizeSql] exactly.
      'CREATE INDEX IF NOT EXISTS idx_core_upc_normalized '
          'ON products_core ($upcNormalizeSql)',
      // fetchBetterAlternativesPool: partial composite index matching the
      // query's quality_score_status = 'scored' predicate, so the
      // category branch of the intent OR resolves via SEARCH with the
      // score range folded into the same index (verified via EXPLAIN
      // QUERY PLAN: SEARCH ... idx_core_cat_score
      // (primary_category=? AND quality_score_v4_100>?)).
      "CREATE INDEX IF NOT EXISTS idx_core_cat_score "
          "ON products_core (primary_category, quality_score_v4_100 DESC) "
          "WHERE quality_score_status = 'scored'",
    ];
    for (final ddl in statements) {
      try {
        await customStatement(ddl);
      } on Exception catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'core_db:app_index_create_failed',
        );
      }
    }
  }

  /// Add additive nullable columns missing from the pre-built DB. Safe to call
  /// multiple times — each ALTER is wrapped so an already-present column is
  /// ignored.
  Future<void> _ensureCompatColumns() async {
    const columns = [
      'image_is_pdf INTEGER',
      'detail_blob_sha256 TEXT',
      'interaction_summary_hint TEXT',
      'decision_highlights TEXT',
      'ingredient_fingerprint TEXT',
      'key_nutrients_summary TEXT',
      'contains_stimulants INTEGER',
      'contains_sedatives INTEGER',
      'contains_blood_thinners INTEGER',
      'share_title TEXT',
      'share_description TEXT',
      'share_highlights TEXT',
      'share_og_image_url TEXT',
      'primary_category TEXT',
      'secondary_categories TEXT',
      // Phase 11.7L.G (2026-05-16): `supplement_type` is required by
      // `fetchBetterAlternativesPool` + `rankAlternatives` tier
      // classifier (tiers 0/1 keyed on this column). Older bundled
      // catalogs predate the v92 schema where the column was added —
      // without this defensive backfill, `supplement_type` is NULL on
      // every row, collapsing tiers 0/1/2 to reject and forcing every
      // candidate into tier 3 (primary_category only). That was the
      // KSM-66 Ashwagandha → Magnesium Glycinate failure mode.
      'supplement_type TEXT',
      'contains_omega3 INTEGER',
      'contains_probiotics INTEGER',
      'contains_collagen INTEGER',
      'contains_adaptogens INTEGER',
      'contains_nootropics INTEGER',
      'key_ingredient_tags TEXT',
      'goal_matches TEXT',
      'goal_match_confidence REAL',
      // v2.x: Coverage "Partially supported" — goals present but underdosed.
      'goal_matches_underdosed TEXT',
      'dosing_summary TEXT',
      'servings_per_container INTEGER',
      'allergen_summary TEXT',
      'image_thumbnail_url TEXT',
      'calories_per_serving REAL',
      'net_contents_quantity REAL',
      'net_contents_unit TEXT',
      // v1.6.x (2026-05-12): searchable ingredient text — defensive
      // backfill for older bundled catalogs that predate the v92 schema.
      // A fresh-built v1.6.x DB ships this column already; this is here
      // only for in-place upgrades where the user is on an old snapshot.
      'ingredients_text TEXT',
      // v2.0.0 (2026-06): v4 /100 scoring contract.
      'quality_score_v4_100 INTEGER',
      'quality_score_status TEXT',
      // v2.3.0: independent safety/quality states plus typed dose-safety detail.
      'product_safety_status TEXT',
      'quality_assessment_status TEXT',
      'quality_tier TEXT',
      'quality_score_suppressed_reason TEXT',
      'v4_module TEXT',
      // 2.4 canonical split: score confidence is never a gate state; route
      // confidence and score-unavailable reason have their own columns.
      'quality_score_confidence TEXT',
      'score_unavailable_reason TEXT',
      'route_confidence TEXT',
      'score_model_version TEXT',
    ];

    for (final col in columns) {
      try {
        await customStatement('ALTER TABLE products_core ADD COLUMN $col');
      } on Exception catch (e, st) {
        // The expected (and overwhelmingly common) failure is the column
        // already existing — that is safe to ignore. Anything else
        // (read-only file, disk full, malformed DB) used to be silently
        // swallowed here, which hid real catalog problems until a query
        // failed downstream. Log those non-fatally and continue: a
        // missing compat column degrades a feature, it must not block
        // catalog open.
        final message = e.toString().toLowerCase();
        if (message.contains('duplicate column name')) {
          continue;
        }
        CrashReportingService().recordError(
          e,
          st,
          hint: 'core_db:compat_column_failed',
        );
      }
    }

    // Schema 2.3 stored score confidence in v4_confidence, including one
    // invalid gate-state value. Copy only the three score-confidence bands;
    // blocked/unavailable state is represented by score_unavailable_reason.
    try {
      await customStatement(
        'UPDATE products_core '
        'SET quality_score_confidence = LOWER(TRIM(v4_confidence)) '
        'WHERE quality_score_confidence IS NULL '
        "AND LOWER(TRIM(v4_confidence)) IN ('high', 'moderate', 'low')",
      );
      await customStatement(
        'UPDATE products_core '
        "SET score_unavailable_reason = 'blocked_by_safety_gate' "
        'WHERE score_unavailable_reason IS NULL '
        "AND LOWER(TRIM(v4_confidence)) = 'blocked_by_safety_gate'",
      );
    } on Exception catch (e, st) {
      final message = e.toString().toLowerCase();
      if (!message.contains('no such column')) {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'core_db:confidence_alias_backfill_failed',
        );
      }
    }
  }

  /// Open a pre-built database file (downloaded from Supabase).
  static CoreDatabase open(String dbPath) {
    return CoreDatabase(File(dbPath));
  }

  /// Returns the export schema version (e.g. "1.3.2") embedded on every
  /// `products_core` row.
  ///
  /// This is the SCHEMA version — it tells the app which column set to
  /// expect. For catalog freshness comparisons against remote manifests,
  /// use [readDbVersion] instead.
  Future<String?> readExportVersion() async {
    // NOTE: SQLite uses single quotes for string literals. Double quotes are
    // interpreted as identifiers (column names), which is why the previous
    // `!= ""` form raised `no such column: ""` at runtime.
    final row = await customSelect(
      "SELECT export_version FROM products_core "
      "WHERE export_version IS NOT NULL AND export_version != '' "
      "LIMIT 1",
      readsFrom: {productsCore},
    ).getSingleOrNull();

    return row?.data['export_version'] as String?;
  }

  /// Returns the catalog build version (e.g. "2026.04.10.222555") from the
  /// in-SQLite `export_manifest` key-value table written by the pipeline's
  /// `build_final_db.py`.
  ///
  /// This is the BUILD version — it tells the app whether the catalog is
  /// fresh relative to a remote manifest. Compare this against
  /// `SyncService.fetchCurrentDbVersion()` when deciding whether to pull
  /// an OTA update.
  ///
  /// Returns null if the embedded table is missing (e.g. the DB was not
  /// produced by the pipeline).
  Future<String?> readDbVersion() async {
    final row = await customSelect(
      "SELECT value FROM export_manifest WHERE key = 'db_version' LIMIT 1",
    ).getSingleOrNull();

    return row?.data['value'] as String?;
  }

  /// Returns a manifest value by key from the embedded export_manifest table.
  Future<String?> readManifestValue(String key) async {
    final row = await customSelect(
      "SELECT value FROM export_manifest WHERE key = ? LIMIT 1",
      variables: [Variable.withString(key)],
    ).getSingleOrNull();
    return row?.data['value'] as String?;
  }

  /// Returns the number of products currently available in the catalog.
  Future<int> countProducts() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS count FROM products_core',
      readsFrom: {productsCore},
    ).getSingle();

    return row.read<int>('count');
  }

  /// Ensures the opened catalog snapshot is structurally usable by the app.
  ///
  /// Returns the BUILD version (`db_version` from the embedded export_manifest
  /// table) when it is present, falling back to the SCHEMA version
  /// (`export_version` from products_core) so older DBs built before v1.3.2
  /// still validate. The returned value is what callers should compare
  /// against the remote manifest's `db_version` for freshness checks.
  Future<String> validateCatalogSnapshot() async {
    final productCount = await countProducts();
    if (productCount <= 0) {
      throw StateError('Catalog snapshot is empty');
    }

    final exportVersion = await readExportVersion();
    if (exportVersion == null || exportVersion.isEmpty) {
      throw StateError('Catalog snapshot is missing export_version');
    }

    final dbVersion = await readDbVersion();
    if (dbVersion != null && dbVersion.isNotEmpty) {
      return dbVersion;
    }

    // Older catalogs without the embedded export_manifest table still pass
    // validation via the schema version — they just can't participate in
    // freshness comparisons against remote manifests.
    return exportVersion;
  }

  // ---------------------------------------------------------------------------
  // Query methods
  // ---------------------------------------------------------------------------

  /// Barcode lookup that tolerates real-world UPC formatting variance.
  ///
  /// The bundled catalog stores UPCs with human-readable spaces
  /// (`0 50428 38139 7`), while mobile scanners return pure digits
  /// (`050428381397`). Additionally, a product labelled UPC-A (12 digits)
  /// may be reported as EAN-13 (13 digits with a leading zero) depending
  /// on the symbology the scanner detected.
  ///
  /// This method normalizes both sides:
  ///   1. Strips the scanner input to digits only.
  ///   2. Tries the raw digits, with a leading zero, and without.
  ///   3. Uses `REPLACE(upc_sku, ' ', '')` in SQL so the stored spaces
  ///      don't prevent the match.
  ///
  /// Returns every matching catalog identity. A score, verdict, or warning is
  /// never used to decide which physical bottle the user scanned.
  Future<List<ProductsCoreData>> findAllByUpc(String upc) async {
    final digits = upc.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const [];

    // Build candidate list — dedup to avoid running the query twice
    // for a 12-digit UPC that doesn't need adjustment.
    //
    // The catalog stores GTINs VERBATIM in {8,12,13,14} digit widths
    // (normalize_upc, build_final_db.py); GS1 zero-padding equivalence is
    // the reader's job, so every valid zero-padded/stripped representation
    // of the scanned code becomes a candidate. EAN-8 is its own GS1
    // numbering — never a stripped form of a longer code — so an 8-digit
    // scan only ever pads, and longer codes never strip below 12.
    final candidates = <String>{digits};
    if (digits.length == 8) {
      candidates.add('000000$digits'); // EAN-8 stored as GTIN-14
    }
    if (digits.length == 12) {
      candidates.add('0$digits'); // EAN-13 variant
      candidates.add('00$digits'); // GTIN-14 variant
    }
    if (digits.length == 13 && digits.startsWith('0')) {
      candidates.add(digits.substring(1)); // UPC-A fallback
    }
    if (digits.length == 13) {
      candidates.add('0$digits'); // GTIN-14 variant
    }
    if (digits.length == 14) {
      if (digits.startsWith('0')) {
        candidates.add(digits.substring(1)); // EAN-13 form
      }
      if (digits.startsWith('00')) {
        candidates.add(digits.substring(2)); // UPC-A form
      }
      if (digits.startsWith('000000')) {
        candidates.add(digits.substring(6)); // EAN-8 form
      }
    }

    final matches = <String, ProductsCoreData>{};
    for (final candidate in candidates) {
      // Uses [upcNormalizeSql] so the WHERE expression matches the
      // idx_core_upc_normalized expression index exactly (SEARCH, not SCAN).
      final rows = await customSelect(
        'SELECT * FROM products_core '
        'WHERE $upcNormalizeSql = ? '
        'ORDER BY dsld_id',
        variables: [Variable.withString(candidate)],
        readsFrom: {productsCore},
      ).get();
      for (final row in rows) {
        final product = productsCore.map(row.data);
        matches[product.dsldId] = product;
      }
    }
    return List.unmodifiable(matches.values);
  }

  Future<UpcResolution> resolveByUpc(String upc) async {
    final candidates = await findAllByUpc(upc);
    if (candidates.isEmpty) return const UpcNotFound();
    if (candidates.length == 1) return UpcUnique(candidates.single);
    return UpcAmbiguous(candidates);
  }

  /// Find a single product by its DSLD ID (primary key).
  Future<ProductsCoreData?> findById(String dsldId) {
    return (select(
      productsCore,
    )..where((t) => t.dsldId.equals(dsldId))).getSingleOrNull();
  }

  /// Text search using FTS5 full-text index (porter stemming, ranked).
  ///
  /// The pipeline builds a `products_fts` virtual table over product_name,
  /// brand_name, and (v1.6.x onward) ingredients_text. This gives instant
  /// ranked results, eliminates duplicate UPC rows that LIKE would return,
  /// AND lets users find products by ingredient name (e.g. "Capsimax"
  /// matches Capsiplex / Phen-Phenom products that list it as an active
  /// even when the product name doesn't). Falls back to LIKE if the FTS
  /// table is missing (older catalog snapshots).
  Future<List<ProductsCoreData>> searchProducts(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final safeOffset = offset < 0 ? 0 : offset;

    // Try FTS5 first — dramatically faster and dedup-aware.
    try {
      // FLTR-SEARCH — tokenize the query and AND each token with
      // prefix match. Previously we wrapped the full string as one
      // phrase ("thorne vitamin a"*), which forced the literal
      // phrase to appear in a single indexed column. Since brand
      // ("Thorne Research") and product_name ("Vitamin A") sit in
      // different columns, multi-word cross-column queries returned
      // zero. Splitting into tokens — each prefix-matched and AND'd —
      // lets FTS5 match "thorne" against brand and "vitamin" / "a"
      // against product_name simultaneously.
      final tokens = trimmed
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .map((t) => t.replaceAll('"', '""'))
          .map((t) => '"$t"*')
          .toList();
      if (tokens.isEmpty) return [];
      final ftsQuery = tokens.join(' AND ');
      final rows = await customSelect(
        'SELECT p.* FROM products_fts f '
        'JOIN products_core p ON p.rowid = f.rowid '
        'WHERE products_fts MATCH ? '
        'ORDER BY rank, '
        '         COALESCE(p.quality_score_v4_100, 0) DESC '
        'LIMIT ? OFFSET ?',
        variables: [
          Variable.withString(ftsQuery),
          Variable.withInt(limit),
          Variable.withInt(safeOffset),
        ],
        readsFrom: {productsCore},
      ).get();

      return rows.map((row) => productsCore.map(row.data)).toList();
    } on Exception {
      // FTS table missing or query syntax error — fall back to LIKE.
      // The fallback firing at all means the snapshot is missing its FTS
      // index (older catalog or broken build) — breadcrumb it so Sentry
      // shows the degraded-search context if anything fails downstream.
      CrashReportingService().log(
        'core_db: FTS search unavailable — LIKE fallback fired',
      );
      // Prefix-only LIKE ('query%') so idx_core_name / idx_core_brand stay
      // usable; a leading-wildcard '%query%' forces a full table scan,
      // which is unacceptable at 250K rows. The trade-off (no mid-string
      // match) is acceptable for a degraded fallback path.
      final pattern = '$trimmed%';
      // v1.6.x: ingredients_text is included so by-ingredient search still
      // works when FTS is absent — but the column itself is a compat
      // column that _ensureCompatColumns may have failed to add, so a
      // missing column degrades to name/brand-only instead of throwing.
      // Raw SQL keeps the fallback independent of `.g.dart` codegen.
      try {
        return await _likeFallback(
          'product_name LIKE ? OR brand_name LIKE ? OR ingredients_text LIKE ?',
          [pattern, pattern, pattern],
          limit,
          safeOffset,
        );
      } on Exception {
        return _likeFallback(
          'product_name LIKE ? OR brand_name LIKE ?',
          [pattern, pattern],
          limit,
          safeOffset,
        );
      }
    }
  }

  Future<List<ProductsCoreData>> _likeFallback(
    String whereClause,
    List<String> patterns,
    int limit,
    int offset,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM products_core '
      'WHERE $whereClause '
      'ORDER BY COALESCE(quality_score_v4_100, 0) DESC '
      'LIMIT ? OFFSET ?',
      variables: [
        for (final p in patterns) Variable.withString(p),
        Variable.withInt(limit),
        Variable.withInt(offset),
      ],
      readsFrom: {productsCore},
    ).get();
    return rows.map((row) => productsCore.map(row.data)).toList();
  }

  /// Find products with higher scores in the same category. Used for
  /// "Better Alternatives" on the product detail screen.
  ///
  /// **Deprecated 2026-05-16 (Phase 11.7L.F).** This query has the
  /// failure modes documented in `knowledge/better-alternatives-audit.md`
  /// — it ignores on-market status, allows score ties, and treats
  /// `primary_category` as the only intent signal. New call sites
  /// should use `fetchBetterAlternativesPool` + the pure ranker in
  /// `lib/services/recommendations/better_alternatives_ranker.dart`.
  /// The legacy entrypoint is kept on the class for backward
  /// compatibility with widget tests that seed a custom in-memory
  /// catalog.
  @Deprecated(
    'Use fetchBetterAlternativesPool + BetterAlternativesRanker. '
    'See knowledge/better-alternatives-audit.md for context.',
  )
  Future<List<ProductsCoreData>> findAlternatives(
    String category,
    double minScore, {
    String? excludeDsldId,
    int limit = 5,
  }) {
    return (select(productsCore)
          ..where((t) {
            var expr =
                t.primaryCategory.equals(category) &
                t.qualityScoreV4100.isBiggerOrEqualValue(minScore);
            if (excludeDsldId != null) {
              expr = expr & t.dsldId.equals(excludeDsldId).not();
            }
            return expr;
          })
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.qualityScoreV4100,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit))
        .get();
  }

  /// Phase 11.7L.F — relevance-first candidate pool for the Better
  /// Alternatives ranker. Applies the SQL-side hard filters (on-market,
  /// scored, strictly higher, no banned/recalled, not-self), then admits
  /// candidates that share supplement type, primary category, OR at least
  /// one canonical `key_ingredient_tags` value.
  ///
  /// Type/category and ingredient-family matches are selected as two
  /// independent channels (up to [poolSize] each) before they are merged.
  /// That prevents either a broad bucket's highest scores or a common
  /// ingredient tag from truncating the other signal before Dart can rank.
  ///
  /// Returns `[]` when no candidate clears the SQL hard filters.
  /// Caller is then expected to hand the pool to
  /// `BetterAlternativesRanker.rankAlternatives(current, pool, …)`
  /// for the final tier + tiebreaker pass.
  Future<List<ProductsCoreData>> fetchBetterAlternativesPool(
    ProductsCoreData current, {
    int poolSize = 50,
  }) async {
    if (poolSize <= 0) return const [];

    final currentCategory = current.primaryCategory?.trim().toLowerCase() ?? '';
    final currentType = current.supplementType?.trim().toLowerCase() ?? '';
    final currentTags = current.keyIngredientTags?.trim() ?? '[]';
    final currentScore = current.qualityScoreV4100 ?? 0;
    if (currentCategory.isEmpty && currentType.isEmpty && currentTags == '[]') {
      // No intent signal to match on — return nothing rather than
      // dump the top-N by raw score.
      return const [];
    }

    final rows = await customSelect(
      '''
      WITH current_context(type, category, tags, score, dsld_id, pool_size) AS (
        VALUES (?, ?, ?, ?, ?, ?)
      ),
      current_tags(value) AS (
        SELECT lower(trim(CAST(value AS TEXT)))
        FROM current_context,
             json_each(
               CASE WHEN json_valid(tags) THEN tags ELSE '[]' END
             )
        WHERE trim(CAST(value AS TEXT)) <> ''
      ),
      eligible AS (
        SELECT
          p.*,
          CASE
            WHEN lower(trim(COALESCE(p.supplement_type, ''))) = c.type
                 AND c.type <> '' THEN 1 ELSE 0
          END AS same_type,
          CASE
            WHEN lower(trim(COALESCE(p.primary_category, ''))) = c.category
                 AND c.category <> '' THEN 1 ELSE 0
          END AS same_category,
          CASE WHEN EXISTS (
            SELECT 1
            FROM json_each(
                   CASE
                     WHEN json_valid(p.key_ingredient_tags)
                       THEN p.key_ingredient_tags
                     ELSE '[]'
                   END
                 ) AS product_tag
            JOIN current_tags AS current_tag
              ON lower(trim(CAST(product_tag.value AS TEXT))) = current_tag.value
          ) THEN 1 ELSE 0 END AS family_overlap
        FROM products_core AS p, current_context AS c
        WHERE p.dsld_id <> c.dsld_id
          AND p.quality_score_status = 'scored'
          AND p.$effectiveScoreSql > c.score
          AND trim(COALESCE(p.discontinued_date, '')) = ''
          AND COALESCE(p.has_banned_substance, 0) = 0
          AND COALESCE(p.has_recalled_ingredient, 0) = 0
      ),
      family_candidates AS (
        SELECT *
        FROM eligible
        WHERE family_overlap = 1
        ORDER BY same_type DESC, $effectiveScoreSql DESC, dsld_id ASC
        LIMIT (SELECT pool_size FROM current_context)
      ),
      intent_candidates AS (
        SELECT *
        FROM eligible
        WHERE same_type = 1 OR same_category = 1
        ORDER BY same_type DESC, $effectiveScoreSql DESC, dsld_id ASC
        LIMIT (SELECT pool_size FROM current_context)
      ),
      candidate_ids AS (
        SELECT dsld_id FROM family_candidates
        UNION
        SELECT dsld_id FROM intent_candidates
      )
      SELECT eligible.*
      FROM eligible
      JOIN candidate_ids USING (dsld_id)
      ORDER BY
        CASE
          WHEN same_type = 1 AND family_overlap = 1 THEN 0
          WHEN same_type = 1 THEN 1
          WHEN family_overlap = 1 THEN 2
          ELSE 3
        END,
        $effectiveScoreSql DESC,
        dsld_id ASC
      ''',
      variables: [
        Variable.withString(currentType),
        Variable.withString(currentCategory),
        Variable.withString(currentTags),
        Variable.withReal(currentScore),
        Variable.withString(current.dsldId),
        Variable.withInt(poolSize),
      ],
      readsFrom: {productsCore},
    ).get();

    return rows
        .map((row) => productsCore.map(row.data))
        .toList(growable: false);
  }

  /// Category / attribute filter query. All parameters are optional.
  Future<List<ProductsCoreData>> filterProducts({
    String? category,
    bool? omega3,
    bool? probiotics,
    bool? collagen,
    bool? adaptogens,
    bool? nootropics,
    bool? vegan,
    bool? glutenFree,
    bool? organic,
    bool? diabetesFriendly,
    bool? hypertensionFriendly,
    String? sortBy,
    int limit = 50,
  }) {
    final query = select(productsCore)..limit(limit);

    query.where((t) {
      Expression<bool> expr = const Constant(true);
      if (category != null) {
        expr = expr & t.primaryCategory.equals(category);
      }
      if (omega3 == true) expr = expr & t.containsOmega3.equals(1);
      if (probiotics == true) {
        expr = expr & t.containsProbiotics.equals(1);
      }
      if (collagen == true) expr = expr & t.containsCollagen.equals(1);
      if (adaptogens == true) {
        expr = expr & t.containsAdaptogens.equals(1);
      }
      if (nootropics == true) {
        expr = expr & t.containsNootropics.equals(1);
      }
      if (vegan == true) expr = expr & t.isVegan.equals(1);
      if (glutenFree == true) expr = expr & t.isGlutenFree.equals(1);
      if (organic == true) expr = expr & t.isOrganic.equals(1);
      if (diabetesFriendly == true) {
        expr = expr & t.diabetesFriendly.equals(1);
      }
      if (hypertensionFriendly == true) {
        expr = expr & t.hypertensionFriendly.equals(1);
      }
      return expr;
    });

    if (sortBy == 'score') {
      query.orderBy([
        (t) => OrderingTerm(
          expression: const CustomExpression<double>(effectiveScoreSql),
          mode: OrderingMode.desc,
        ),
      ]);
    } else if (sortBy == 'name') {
      query.orderBy([(t) => OrderingTerm(expression: t.productName)]);
    } else if (sortBy == 'percentile') {
      query.orderBy([(t) => OrderingTerm(expression: t.percentileTopPct)]);
    }

    return query.get();
  }
}
