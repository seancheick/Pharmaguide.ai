// Coverage report provider — async glue for the Stack Gap Analysis
// ("Coverage") card. Composes existing providers; all bucket logic
// lives in the pure [CoverageAnalyzer].
//
// Offline contract: SUPPORTED / UNADDRESSED-goal buckets run entirely
// off the bundled core DB (`products_core.goal_matches`) — no detail
// blob, no network. The UNDERDOSED (RDA) bucket and the depletion
// buckets reuse providers that read cached detail blobs; when blobs
// aren't cached those inputs degrade to empty lists and the card simply
// shows fewer rows. Nothing here is persisted (FitScore rule: goal
// coverage is recomputed from the live profile + stack every build).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart'
    show depletionReportProvider;
import 'package:pharmaguide/services/stack/coverage_analyzer.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

/// Builds the [CoverageReport] for the current stack + profile.
///
/// Empty stack → `CoverageReport(isEmpty: true)` and the card hides.
/// No goals → `hasGoals == false` and the card renders the calm
/// profile-completion invitation instead of fake analysis.
final coverageReportProvider = FutureProvider.autoDispose<CoverageReport>((
  ref,
) async {
  // Active stack — mutation invalidates us.
  final stack = await ref.watch(activeStackProvider.future);
  final supplements = stack
      .where((e) => e.type == 'supplement')
      .toList(growable: false);
  if (supplements.isEmpty) return const CoverageReport();

  // Sentinel-stripped goals from the persisted profile.
  final profile = await ref.watch(loadedProfileProvider.future);
  final goals = profile.goalsForEvaluator;

  // Hydrate each supplement's offline goal_matches from the core DB.
  // Track the same low label-mapping trust floor the safety report
  // uses (mapped_coverage < 0.3 → hedge, never imply completeness).
  final coreDb = ref.watch(coreDatabaseProvider);
  var coverageIncomplete = false;
  final products = <CoverageProductInput>[];
  for (final entry in supplements) {
    final dsldId = entry.dsldId;
    if (dsldId == null || dsldId.isEmpty) {
      coverageIncomplete = true;
      continue;
    }
    ProductsCoreData? product;
    try {
      product = await coreDb.findById(dsldId);
    } on Object {
      coverageIncomplete = true;
      continue;
    }
    if (product == null) {
      coverageIncomplete = true;
      continue;
    }
    if (isLowCoverage(product.mappedCoverage)) coverageIncomplete = true;
    products.add(
      CoverageProductInput(
        name: entry.name,
        goalMatches: decodeGoalMatches(product.goalMatches),
        goalMatchesUnderdosed: decodeGoalMatches(product.goalMatchesUnderdosed),
      ),
    );
  }
  // NOTE: even when every supplement failed hydration (products empty)
  // we keep going — depletion gaps are goal-independent and must not be
  // silently dropped. The analyzer is told the stack exists via
  // hasStackOverride so the card renders with the hedge.

  // Depletion matches — reuse the existing checker output. Best-effort:
  // a depletion failure must not take the whole card down.
  List<DepletionMatch> depletions;
  try {
    depletions = await ref.watch(depletionReportProvider.future);
  } on Object {
    depletions = const <DepletionMatch>[];
  }

  // RDA/UL nutrient statuses — needs cached detail blobs; degrade to
  // an empty UNDERDOSED (RDA) bucket when unavailable.
  List<NutrientStatus> nutrientStatuses;
  try {
    nutrientStatuses = await ref.watch(stackNutrientStatusesProvider.future);
  } on Object {
    nutrientStatuses = const <NutrientStatus>[];
  }

  return const CoverageAnalyzer().analyze(
    goals: goals,
    products: products,
    depletions: depletions,
    nutrientStatuses: nutrientStatuses,
    coverageIncomplete: coverageIncomplete,
    goalsOptedOut: profile.hasGoalNone,
    hasStackOverride: supplements.isNotEmpty,
  );
});

/// Decode the `products_core.goal_matches` JSON list into a set of
/// `GOAL_*` ids. Null / empty / malformed → empty set (defensive — all
/// JSON parsing must survive missing fields).
Set<String> decodeGoalMatches(String? raw) {
  final out = <String>{};
  if (raw == null || raw.isEmpty) return out;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      for (final v in decoded) {
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
  } on FormatException {
    // Defensive — malformed column never crashes the card.
  }
  return out;
}
