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

  @override
  int get schemaVersion => 1;

  /// Open a pre-built database file (downloaded from Supabase).
  static CoreDatabase open(String dbPath) {
    return CoreDatabase(File(dbPath));
  }

  // ---------------------------------------------------------------------------
  // Query methods
  // ---------------------------------------------------------------------------

  /// Barcode lookup with deterministic ordering:
  ///   1. Active products first
  ///   2. Highest score wins ties
  Future<ProductsCoreData?> findByUpc(String upc) {
    return (select(productsCore)
          ..where((t) => t.upcSku.equals(upc))
          ..orderBy([
            (t) => OrderingTerm(
                  expression:
                      t.productStatus.equals('active').cast<int>(),
                  mode: OrderingMode.desc,
                ),
            (t) => OrderingTerm(
                  expression: t.scoreQuality80,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Find a single product by its DSLD ID (primary key).
  Future<ProductsCoreData?> findById(String dsldId) {
    return (select(productsCore)
          ..where((t) => t.dsldId.equals(dsldId)))
        .getSingleOrNull();
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
