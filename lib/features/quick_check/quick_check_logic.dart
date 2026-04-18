// Pure helpers for the "Safe to Take Together?" quick-check feature.
//
// These live outside the widget so they can be unit-tested without a
// Flutter test harness. The widget (`quick_check_screen.dart`) is a thin
// stateful consumer on top of this logic + the interaction DB.

import 'dart:convert';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

/// Extract lowercase canonical ingredient IDs from a `ingredient_fingerprint`
/// JSON payload.
///
/// The pipeline emits two shapes:
///   - a map keyed by canonical id (values are metadata)
///   - a bare list of canonical ids
///
/// Returns an empty list for null, empty string, or malformed JSON.
List<String> extractCanonicalIds(String? fingerprint) {
  if (fingerprint == null || fingerprint.isEmpty) return const [];
  try {
    final decoded = jsonDecode(fingerprint);
    if (decoded is Map) {
      return decoded.keys.map((k) => k.toString().toLowerCase()).toList();
    }
    if (decoded is List) {
      return decoded
          .where((e) => e != null)
          .map((e) => e.toString().toLowerCase())
          .toList();
    }
  } on FormatException {
    // fall through
  }
  return const [];
}

/// Map a [Severity] enum to a [PGBannerTone] for the result card.
///
/// Policy: `contraindicated` and `avoid` → danger. `caution` → caution.
/// Everything else (monitor, safe) → info. Keep in sync with the severity
/// banner doc.
PGBannerTone toneForSeverity(Severity severity) {
  switch (severity) {
    case Severity.contraindicated:
    case Severity.avoid:
      return PGBannerTone.danger;
    case Severity.caution:
      return PGBannerTone.caution;
    case Severity.monitor:
    case Severity.informational:
    case Severity.safe:
      return PGBannerTone.info;
  }
}

/// Run a pair interaction check between two products.
///
/// Strategy: for each canonical id on product A, look up matching
/// interactions in [db] and keep the ones where the "other" side is in
/// product B's id set. Results are sorted severity-high-to-low.
///
/// Returns an empty list when either product is missing ingredient data.
Future<List<InteractionResult>> runPairCheck(
  ProductsCoreData a,
  ProductsCoreData b,
  InteractionDatabase db,
) async {
  final idsA = extractCanonicalIds(a.ingredientFingerprint);
  final idsB = extractCanonicalIds(b.ingredientFingerprint);
  if (idsA.isEmpty || idsB.isEmpty) return const [];

  final results = <InteractionResult>[];
  final seenIds = <String>{};

  for (final idA in idsA) {
    final rows = await db.lookupByCanonicalId(idA);
    for (final row in rows) {
      if (seenIds.contains(row.id)) continue;
      final otherId = (row.agent1CanonicalId == idA)
          ? row.agent2CanonicalId
          : row.agent1CanonicalId;
      if (otherId != null && idsB.contains(otherId.toLowerCase())) {
        seenIds.add(row.id);
        results.add(InteractionResult.fromRow(
          row,
          source: InteractionSource.pipeline,
          agent1NameOverride: a.productName,
          agent2NameOverride: b.productName,
        ));
      }
    }
  }

  results.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
  return results;
}
