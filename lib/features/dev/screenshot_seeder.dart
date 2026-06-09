// Dev-only seeder that populates the local stack with a curated set of
// supplements + a medication so marketing screenshots are reproducible.
//
// Activation:
//   flutter run --dart-define=SCREENSHOT_MODE=true
//
// Double-gated by [kDebugMode] AND the dart-define flag so a release
// build can never trigger this code path — `kDebugMode` is a
// compile-time constant that constant-folds the body out of release.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';

const bool _screenshotMode = bool.fromEnvironment(
  'SCREENSHOT_MODE',
  defaultValue: false,
);

/// Populates [userDb] with a curated demo stack pulled from [coreDb] so
/// the 4 marketing screenshots (scan, product, interaction, my-stack)
/// always tell the same story.
///
/// No-op outside debug builds, no-op when SCREENSHOT_MODE is false, and
/// idempotent within a debug build (skips items already in the stack).
class ScreenshotSeeder {
  ScreenshotSeeder._();

  /// Curated lookups. Each entry resolves to a real product at runtime
  /// via a search of [coreDb], so the seed survives catalog rebuilds
  /// where dsldIds may shift.
  static const _supplements = <_SupplementSeed>[
    _SupplementSeed(
      label: 'hero-vitamin-d3',
      query: 'vitamin d3',
      // The product detail screenshot points at the hero — we want the
      // highest-scoring match so the FitScore ring looks impressive.
      preferHighestScore: true,
    ),
    _SupplementSeed(
      label: 'interaction-st-johns-wort',
      query: "st. john's wort",
      // For the interaction shot we just need a real St. John's Wort
      // product paired with the SSRI medication below — the curated
      // interaction row in interaction_db.sqlite is what surfaces the
      // contraindicated banner.
      preferHighestScore: true,
    ),
    _SupplementSeed(
      label: 'stack-magnesium',
      query: 'magnesium glycinate',
      preferHighestScore: true,
    ),
  ];

  /// Sertraline (Zoloft generic) — stable RxNorm concept id. We also
  /// stamp the `antidepressants_ssri_snri` class so the curated
  /// interaction lookup matches even if the bundled interaction_db
  /// indexes by class rather than rxcui.
  static const _sertraline = _MedicationSeed(
    name: 'Sertraline',
    rxcui: '36437',
    drugClasses: ['antidepressants_ssri_snri'],
  );

  /// Entry point called from the app bootstrap after the core DB is
  /// open. Safe to call unconditionally — exits early if the flag is
  /// off.
  static Future<void> maybeRun({
    required CoreDatabase coreDb,
    required UserDatabase userDb,
  }) async {
    if (!kDebugMode || !_screenshotMode) return;

    try {
      final existing = await userDb.getActiveStack();
      final existingDsldIds = existing
          .map((e) => e.dsldId)
          .whereType<String>()
          .toSet();
      final existingRxcuis = existing
          .map((e) => e.rxcui)
          .whereType<String>()
          .toSet();

      for (final seed in _supplements) {
        final product = await _resolveProduct(coreDb, seed);
        if (product == null) {
          debugPrint(
            '[screenshot-seeder] no product found for "${seed.query}" — '
            'skipping',
          );
          continue;
        }
        if (existingDsldIds.contains(product.dsldId)) {
          debugPrint(
            '[screenshot-seeder] ${seed.label} already in stack — skip',
          );
          continue;
        }
        await userDb.addToStack(
          UserStacksLocalCompanion(
            id: Value('${seed.label}_${DateTime.now().microsecondsSinceEpoch}'),
            type: const Value('supplement'),
            name: Value(product.productName),
            dsldId: Value(product.dsldId),
            ingredientKeys: Value(product.ingredientFingerprint),
          ),
        );
        // Format: leading dsldId= so the capture script's regex is
        // unambiguous even when product names contain parentheses.
        debugPrint(
          '[screenshot-seeder] seeded ${seed.label}: '
          'dsldId=${product.dsldId} name="${product.productName}"',
        );
      }

      if (!existingRxcuis.contains(_sertraline.rxcui)) {
        await userDb.addToStack(
          UserStacksLocalCompanion(
            id: Value(
              'screenshot-med-sertraline_'
              '${DateTime.now().microsecondsSinceEpoch}',
            ),
            type: const Value('medication'),
            name: Value(_sertraline.name),
            rxcui: Value(_sertraline.rxcui),
            drugClassesCol: Value(jsonEncode(_sertraline.drugClasses)),
          ),
        );
        debugPrint(
          '[screenshot-seeder] seeded medication: ${_sertraline.name}',
        );
      }
    } on Object catch (e, st) {
      // Never fail app launch over the seeder — it's marketing scaffolding,
      // not a product feature.
      debugPrint('[screenshot-seeder] failed (non-fatal): $e\n$st');
    }
  }

  static Future<ProductsCoreData?> _resolveProduct(
    CoreDatabase coreDb,
    _SupplementSeed seed,
  ) async {
    final results = await coreDb.searchProducts(seed.query, limit: 10);
    if (results.isEmpty) return null;

    // searchProducts already orders by rank then score, so the first
    // result is the best name match. preferHighestScore re-sorts within
    // the top 10 by raw quality score so the hero shot doesn't pick a
    // ranked-but-unimpressive product.
    if (!seed.preferHighestScore) return results.first;
    final sorted = [
      ...results,
    ]..sort((a, b) => (b.qualityScoreV4100 ?? 0).compareTo(a.qualityScoreV4100 ?? 0));
    return sorted.first;
  }
}

class _SupplementSeed {
  final String label;
  final String query;
  final bool preferHighestScore;
  const _SupplementSeed({
    required this.label,
    required this.query,
    this.preferHighestScore = false,
  });
}

class _MedicationSeed {
  final String name;
  final String rxcui;
  final List<String> drugClasses;
  const _MedicationSeed({
    required this.name,
    required this.rxcui,
    required this.drugClasses,
  });
}
