// SPIKE OVERLAY for lib/data/database/core_database.dart.
//
// The engine only touches the Drift-generated `ProductsCoreData` row class
// (via lib/core/utils/product_canonical_ids.dart). This plain class carries the
// columns the engine reads; names/types match the generated class.
class ProductsCoreData {
  const ProductsCoreData({
    required this.dsldId,
    required this.productName,
    this.mappedCoverage,
    this.ingredientFingerprint,
    this.containsStimulants,
    this.containsSedatives,
    this.containsBloodThinners,
    this.keyIngredientTags,
  });

  factory ProductsCoreData.fromSqlJson(Map<String, dynamic> j) =>
      ProductsCoreData(
        dsldId: j['dsld_id'].toString(),
        productName: j['product_name'] as String,
        mappedCoverage: (j['mapped_coverage'] as num?)?.toDouble(),
        ingredientFingerprint: j['ingredient_fingerprint'] as String?,
        containsStimulants: j['contains_stimulants'] as int?,
        containsSedatives: j['contains_sedatives'] as int?,
        containsBloodThinners: j['contains_blood_thinners'] as int?,
        keyIngredientTags: j['key_ingredient_tags'] as String?,
      );

  final String dsldId;
  final String productName;
  final double? mappedCoverage;
  final String? ingredientFingerprint;
  final int? containsStimulants;
  final int? containsSedatives;
  final int? containsBloodThinners;
  final String? keyIngredientTags;
}
