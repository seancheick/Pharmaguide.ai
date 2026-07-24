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
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
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
    String? productRole;
    var prenatalCoverage = const <PriorityCoverageAnchor>[];
    var adultMultiCoverage = const <PriorityCoverageAnchor>[];
    try {
      final blob = await ref.watch(detailBlobProvider(dsldId).future);
      productRole = _readProductRole(blob);
      prenatalCoverage = _readCoverageAnchors(
        blob,
        entry.name,
        'prenatal_coverage',
      );
      adultMultiCoverage = _readCoverageAnchors(
        blob,
        entry.name,
        'adult_multi_coverage',
      );
    } on Object {
      // Detail blobs are best-effort here. Goal coverage still works from
      // products_core; priority gaps simply stay absent when the blob is not
      // cached/fetchable.
    }
    products.add(
      CoverageProductInput(
        name: entry.name,
        goalMatches: decodeGoalMatches(product.goalMatches),
        goalMatchesUnderdosed: decodeGoalMatches(product.goalMatchesUnderdosed),
        productRole: productRole,
        prenatalCoverage: prenatalCoverage,
        adultMultiCoverage: adultMultiCoverage,
      ),
    );
  }
  // NOTE: even when every supplement failed hydration (products empty)
  // we keep going — depletion gaps are goal-independent and must not be
  // silently dropped. The analyzer is told the stack exists via
  // hasStackOverride so the card renders with the hedge.

  // Depletion matches — reuse the existing checker output. Best-effort:
  // a depletion failure must not take the whole card down. But an `unavailable`
  // status (or a thrown failure) with empty matches is NOT "no depletions" —
  // per the MedNutrientReport contract, mark coverage incomplete so the card
  // hedges instead of implying a false all-clear.
  List<DepletionMatch> depletions;
  try {
    final depReport = await ref.watch(depletionReportProvider.future);
    depletions = depReport.matches;
    if (depReport.status == MedNutrientLoadStatus.unavailable) {
      coverageIncomplete = true;
    }
  } on Object {
    depletions = const <DepletionMatch>[];
    coverageIncomplete = true;
  }

  // RDA/UL nutrient statuses — needs cached detail blobs; degrade to
  // an empty UNDERDOSED (RDA) bucket when unavailable, and hedge (a failure
  // here likewise must not read as "no underdosed nutrients").
  List<NutrientStatus> nutrientStatuses;
  try {
    nutrientStatuses = await ref.watch(stackNutrientStatusesProvider.future);
  } on Object {
    nutrientStatuses = const <NutrientStatus>[];
    coverageIncomplete = true;
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

String? _readProductRole(Map<String, dynamic>? blob) {
  final raw = blob?['product_role'];
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

List<PriorityCoverageAnchor> _readCoverageAnchors(
  Map<String, dynamic>? blob,
  String productName,
  String field,
) {
  final coverage = blob?[field];
  if (coverage is! Map) return const [];
  final anchors = coverage['anchors'];
  if (anchors is! List) return const [];
  final out = <PriorityCoverageAnchor>[];
  for (final row in anchors) {
    if (row is! Map) continue;
    final id = row['nutrient_id']?.toString().trim() ?? '';
    final label = row['label']?.toString().trim() ?? id;
    final status = row['status']?.toString().trim() ?? '';
    if (id.isEmpty || label.isEmpty || status.isEmpty) continue;
    out.add(
      PriorityCoverageAnchor(
        nutrientId: id,
        nutrientName: label,
        status: status,
        productName: productName,
        amount: _readDouble(row['amount']),
        unit: row['unit']?.toString(),
        target: _readDouble(row['target']),
        targetUnit: row['target_unit']?.toString(),
      ),
    );
  }
  return out;
}

double? _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
