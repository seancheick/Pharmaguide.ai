import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pharmaguide/data/database/tables/products_core_table.dart';

part 'core_database.g.dart';

/// READ-ONLY database backed by the pre-built `pharmaguide_core.db` file
/// downloaded from Supabase. Contains 180K+ product rows across 88 columns.
@DriftDatabase(tables: [ProductsCore])
class CoreDatabase extends _$CoreDatabase {
  CoreDatabase(File dbFile)
      : super(NativeDatabase(dbFile, logStatements: false));

  CoreDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          // Not used — pre-built DB, no versioned migrations.
        },
        beforeOpen: (details) async {
          // The pre-built DB from the pipeline may lack v1.3.0 columns.
          // Add any missing columns so Drift queries don't crash.
          await _ensureV130Columns();
        },
      );

  /// Add v1.3.0 columns if they don't exist in the pre-built DB.
  /// Safe to call multiple times — uses IF NOT EXISTS pattern.
  Future<void> _ensureV130Columns() async {
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
      'contains_omega3 INTEGER',
      'contains_probiotics INTEGER',
      'contains_collagen INTEGER',
      'contains_adaptogens INTEGER',
      'contains_nootropics INTEGER',
      'key_ingredient_tags TEXT',
      'goal_matches TEXT',
      'goal_match_confidence REAL',
      'dosing_summary TEXT',
      'servings_per_container INTEGER',
      'allergen_summary TEXT',
      'image_thumbnail_url TEXT',
      'calories_per_serving REAL',
      'net_contents_quantity REAL',
      'net_contents_unit TEXT',
    ];

    for (final col in columns) {
      try {
        await customStatement(
            'ALTER TABLE products_core ADD COLUMN $col');
      } on Exception {
        // Column already exists — safe to ignore. Drift wraps the
        // underlying SqliteException in a generic Exception for this path.
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
  /// Ordering when multiple products share a UPC (private-label duplicates):
  ///   1. Active products first
  ///   2. Highest `score_quality_80` wins ties
  Future<ProductsCoreData?> findByUpc(String upc) async {
    final digits = upc.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    // Build candidate list — dedup to avoid running the query twice
    // for a 12-digit UPC that doesn't need adjustment.
    final candidates = <String>{digits};
    if (digits.length == 13 && digits.startsWith('0')) {
      candidates.add(digits.substring(1)); // UPC-A fallback
    }
    if (digits.length == 12) {
      candidates.add('0$digits'); // EAN-13 variant
    }

    for (final candidate in candidates) {
      final row = await customSelect(
        "SELECT * FROM products_core "
        "WHERE REPLACE(upc_sku, ' ', '') = ? "
        "ORDER BY (product_status = 'active') DESC, "
        "         COALESCE(score_quality_80, 0) DESC "
        "LIMIT 1",
        variables: [Variable.withString(candidate)],
        readsFrom: {productsCore},
      ).getSingleOrNull();
      if (row != null) {
        return productsCore.map(row.data);
      }
    }
    return null;
  }

  /// Find a single product by its DSLD ID (primary key).
  Future<ProductsCoreData?> findById(String dsldId) {
    return (select(productsCore)
          ..where((t) => t.dsldId.equals(dsldId)))
        .getSingleOrNull();
  }

  /// Text search using FTS5 full-text index (porter stemming, ranked).
  ///
  /// The pipeline builds a `products_fts` virtual table over product_name
  /// and brand_name. This gives instant ranked results and eliminates
  /// duplicate UPC rows that LIKE would return. Falls back to LIKE if the
  /// FTS table is missing (older catalog snapshots).
  Future<List<ProductsCoreData>> searchProducts(
    String query, {
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // Try FTS5 first — dramatically faster and dedup-aware.
    try {
      // FTS5 query: append * for prefix matching ("vita" → "vitamin").
      // Escape double-quotes in user input to prevent FTS5 syntax errors.
      final ftsQuery = trimmed.replaceAll('"', '""');
      final rows = await customSelect(
        'SELECT p.* FROM products_fts f '
        'JOIN products_core p ON p.rowid = f.rowid '
        'WHERE products_fts MATCH ? '
        'ORDER BY rank, COALESCE(p.score_quality_80, 0) DESC '
        'LIMIT ?',
        variables: [
          Variable.withString('"$ftsQuery"*'),
          Variable.withInt(limit),
        ],
        readsFrom: {productsCore},
      ).get();

      return rows.map((row) => productsCore.map(row.data)).toList();
    } on Exception {
      // FTS table missing or query syntax error — fall back to LIKE.
      final pattern = '%$trimmed%';
      return (select(productsCore)
            ..where((t) =>
                t.productName.like(pattern) | t.brandName.like(pattern))
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.scoreQuality80,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(limit))
          .get();
    }
  }

  /// Find products with higher scores in the same category. Used for
  /// "Better Alternatives" on the product detail screen.
  Future<List<ProductsCoreData>> findAlternatives(
    String category,
    double minScore, {
    String? excludeDsldId,
    int limit = 5,
  }) {
    return (select(productsCore)
          ..where((t) {
            var expr = t.primaryCategory.equals(category) &
                t.scoreQuality80.isBiggerOrEqualValue(minScore);
            if (excludeDsldId != null) {
              expr = expr & t.dsldId.equals(excludeDsldId).not();
            }
            return expr;
          })
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.scoreQuality80,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .get();
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
              expression: t.scoreQuality80,
              mode: OrderingMode.desc,
            ),
      ]);
    } else if (sortBy == 'name') {
      query.orderBy([(t) => OrderingTerm(expression: t.productName)]);
    } else if (sortBy == 'percentile') {
      query.orderBy([
        (t) => OrderingTerm(expression: t.percentileTopPct),
      ]);
    }

    return query.get();
  }
}
