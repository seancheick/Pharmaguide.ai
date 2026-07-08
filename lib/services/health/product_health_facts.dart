import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/health/dose_safety.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Typed, side-effect-free view of the health-relevant fields in a pipeline
/// detail blob.
///
/// This is the boundary between pipeline JSON and Flutter health logic. The
/// goal is for FitScore, product detail, stack health, allergens, and timing
/// surfaces to consume the same parsed facts instead of each re-reading blob
/// fields with subtly different fallbacks.
class ProductHealthFacts {
  const ProductHealthFacts({
    required this.activeIngredients,
    required this.inactiveIngredients,
    required this.ulAnalysis,
    required this.ingredientContextRows,
    required this.nutrients,
    required this.ulSafetyFlags,
    required this.interactionSummary,
    required this.warnings,
    required this.allergens,
    required this.productClusters,
    required this.productForm,
    required this.ingredientDoses,
    required this.ingredientNames,
  });

  /// Scorable nutrient rows. Preferred source is
  /// `rda_ul_data.analyzed_ingredients` because those rows carry pipeline
  /// conversion and `skip_ul_check` provenance.
  final List<Map<String, dynamic>> nutrients;

  /// Raw active-ingredient rows from `detail_blob.ingredients`, used for
  /// label-style product detail rendering. Kept separate from [nutrients]
  /// because [nutrients] intentionally prefers converted RDA/UL rows.
  final List<Map<String, dynamic>> activeIngredients;

  /// Raw inactive/excipient rows from `detail_blob.inactive_ingredients`.
  final List<Map<String, dynamic>> inactiveIngredients;

  /// Pipeline per-ingredient RDA/UL analysis rows.
  final List<Map<String, dynamic>> ulAnalysis;

  /// Pipeline-level RDA/UL flags such as `rda_ul_data.safety_flags`.
  /// These are already evaluated at source and may use a different shape
  /// than [ulAnalysis], so keep them explicit instead of making UI sections
  /// parse raw `rda_ul_data` independently.
  final List<Map<String, dynamic>> ulSafetyFlags;

  /// Candidate rows for ingredient-specific profile-gate context such as
  /// nutrient form and dose. Includes active rows, RDA/UL rows, and
  /// ingredient-quality rows so warning filtering does not need to reparse
  /// raw blob keys.
  final List<Map<String, dynamic>> ingredientContextRows;

  final Map<String, dynamic> interactionSummary;
  final List<InteractionWarning> warnings;
  final List<Map<String, dynamic>> allergens;
  final List<String> productClusters;
  final String? productForm;
  final Map<String, IngredientDose> ingredientDoses;
  final List<String> ingredientNames;

  factory ProductHealthFacts.fromDetailBlob(Map<String, dynamic> blob) {
    final nutrients = _extractNutrients(blob);
    final ulAnalysis = _extractUlAnalysis(blob);
    final ingredientContextRows = _extractIngredientContextRows(blob);
    return ProductHealthFacts(
      activeIngredients: _extractMapList(blob['ingredients']),
      inactiveIngredients: _extractMapList(blob['inactive_ingredients']),
      ulAnalysis: ulAnalysis,
      ulSafetyFlags: _extractUlSafetyFlags(blob),
      ingredientContextRows: ingredientContextRows,
      nutrients: nutrients,
      interactionSummary: _extractMap(blob['interaction_summary']),
      warnings: _extractWarnings(blob),
      allergens: _extractAllergens(blob['allergens']),
      productClusters: _extractProductClusters(blob),
      productForm: _stringValue(blob['product_form']),
      ingredientDoses: extractIngredientDoses(blob),
      ingredientNames: _extractIngredientNames(ingredientContextRows),
    );
  }

  /// Dose rows for pairwise stack-threshold checks (fed to
  /// [StackDoseSummer]). Prefers the parsed [ingredientDoses] as
  /// `{standard_name, quantity, unit}` rows; falls back to the raw active
  /// ingredient rows, then nutrients, when no doses parsed. Shared by the
  /// product-detail personalized-warnings provider and the stack-safety
  /// provider so both feed the summer the SAME row shape (was a byte-identical
  /// private copy in each).
  List<Map<String, dynamic>> get doseRowsForThresholds {
    if (ingredientDoses.isNotEmpty) {
      return [
        for (final entry in ingredientDoses.entries)
          {
            'standard_name': entry.key,
            'quantity': entry.value.value,
            'unit': entry.value.unit,
          },
      ];
    }
    if (activeIngredients.isNotEmpty) return activeIngredients;
    return nutrients;
  }

  static List<Map<String, dynamic>> _extractUlAnalysis(
    Map<String, dynamic> blob,
  ) {
    final rdaUlData = blob['rda_ul_data'];
    if (rdaUlData is! Map) return const [];
    return _extractMapList(rdaUlData['analyzed_ingredients']);
  }

  static List<Map<String, dynamic>> _extractUlSafetyFlags(
    Map<String, dynamic> blob,
  ) {
    final rdaUlData = blob['rda_ul_data'];
    if (rdaUlData is! Map) return const [];
    return _extractMapList(rdaUlData['safety_flags']);
  }

  static List<Map<String, dynamic>> _extractNutrients(
    Map<String, dynamic> blob,
  ) {
    final rdaUlData = blob['rda_ul_data'];
    if (rdaUlData is Map) {
      final rows = _extractMapList(rdaUlData['analyzed_ingredients']);
      if (rows.isNotEmpty) return rows;
    }

    final direct = _extractMapList(blob['ingredients']);
    if (direct.isNotEmpty) return direct;

    final iqd = blob['ingredient_quality_data'];
    if (iqd is Map) {
      final nested = _extractIngredientQualityRows(iqd);
      if (nested.isNotEmpty) return nested;
    }

    return const [];
  }

  static List<InteractionWarning> _extractWarnings(Map<String, dynamic> blob) {
    final rows = <Map<String, dynamic>>[];
    final hasStructuredProductStatus = blob['product_status'] is Map;

    for (final key in const ['warnings', 'warnings_profile_gated']) {
      rows.addAll(
        _extractMapList(blob[key]).where(
          (warning) => !_isLegacyProductStatusWarning(
            warning,
            hasStructuredProductStatus: hasStructuredProductStatus,
          ),
        ),
      );
    }

    return InteractionWarning.dedupe([
      ...rows.map(InteractionWarning.fromJson),
      ..._extractUlWarnings(blob),
    ]);
  }

  static List<InteractionWarning> _extractUlWarnings(
    Map<String, dynamic> blob,
  ) {
    return extractUlExceedances(_extractNutrients(blob))
        .map(
          (exceedance) => InteractionWarning(
            severity: Severity.avoid,
            evidenceLevel: EvidenceLevel.established,
            title: 'Exceeds upper limit: ${exceedance.standardName}',
            mechanism: exceedance.warning,
            management: 'Reduce dose or consult a healthcare provider.',
            displayModeDefault: 'critical',
          ),
        )
        .toList(growable: false);
  }

  static List<String> _extractProductClusters(Map<String, dynamic> blob) {
    final raw = blob['product_clusters'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
    }

    final synergyDetail = blob['synergy_detail'];
    if (synergyDetail is Map) {
      final clusters = synergyDetail['clusters'];
      if (clusters is List) {
        return clusters
            .whereType<Map<Object?, Object?>>()
            .map((cluster) => cluster['cluster_id']?.toString().trim() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);
      }
    }

    final formulationData = blob['formulation_data'];
    if (formulationData is Map) {
      final clusters = formulationData['synergy_clusters'];
      if (clusters is List) {
        return clusters
            .whereType<Map<Object?, Object?>>()
            .map((cluster) => cluster['cluster_id']?.toString().trim() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);
      }
    }

    return const [];
  }

  static List<String> _extractIngredientNames(List<Map<String, dynamic>> rows) {
    final names = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      final name =
          _stringValue(row['display_label']) ??
          _stringValue(row['standard_name']) ??
          _stringValue(row['name']) ??
          _stringValue(row['ingredient']) ??
          _stringValue(row['mapped_name']);
      if (name == null) continue;
      final key = name.trim().toLowerCase();
      if (seen.add(key)) names.add(name);
    }
    return names;
  }

  static List<Map<String, dynamic>> _extractIngredientContextRows(
    Map<String, dynamic> blob,
  ) {
    final rows = <Map<String, dynamic>>[];

    final rdaUlData = blob['rda_ul_data'];
    if (rdaUlData is Map) {
      rows.addAll(_extractMapList(rdaUlData['analyzed_ingredients']));
    }

    rows.addAll(_extractMapList(blob['ingredients']));

    final iqd = blob['ingredient_quality_data'];
    if (iqd is Map) {
      rows.addAll(_extractIngredientQualityRows(iqd));
    }

    return rows;
  }

  static List<Map<String, dynamic>> _extractIngredientQualityRows(
    Map<Object?, Object?> iqd,
  ) {
    final rows = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final key in const ['ingredients', 'ingredients_scorable']) {
      for (final row in _extractMapList(iqd[key])) {
        final marker = row.toString();
        if (seen.add(marker)) rows.add(row);
      }
    }
    return rows;
  }

  static List<Map<String, dynamic>> _extractAllergens(Object? raw) {
    final rows = _extractMapList(raw);
    if (rows.isEmpty) return const [];
    return rows
        .map((row) {
          final normalized = Map<String, dynamic>.from(row);
          final id =
              _stringValue(normalized['allergen_id']) ??
              _stringValue(normalized['id']);
          if (id != null) {
            normalized['allergen_id'] = id;
            normalized['id'] = _stringValue(normalized['id']) ?? id;
          }
          return normalized;
        })
        .toList(growable: false);
  }

  static Map<String, dynamic> _extractMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  static List<Map<String, dynamic>> _extractMapList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  static String? _stringValue(Object? raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static bool _isLegacyProductStatusWarning(
    Map<String, dynamic> warning, {
    required bool hasStructuredProductStatus,
  }) {
    if (!hasStructuredProductStatus) return false;
    final tokens = [
      warning['type'],
      warning['source'],
      warning['category'],
      warning['warning_type'],
    ].map((value) => value?.toString().trim().toLowerCase() ?? '');
    return tokens.contains('status') || tokens.contains('product_status');
  }
}
