// Compare feature providers.
//
// Reuses the existing machinery end to end — no second brains:
//   • product rows via [coreDatabaseProvider].findById (same lookup the
//     product detail screen does)
//   • pillar data via the shared [detailBlobProvider] (same blob /
//     `quality_pillars_v4` path the score breakdown reads)
//   • picker candidates from [activeStackProvider] + the user DB's
//     `getRecentScans` (same source the home carousel joins)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';

/// One side of the comparison: the local catalog row plus its detail
/// blob. [blobFailed] is true when the blob fetch errored (offline /
/// network) — the screen then shows hero scores with a calm hedge
/// instead of pillar rows. A null [blob] with [blobFailed] false means
/// the product genuinely has no detail blob.
class CompareEntry {
  final ProductsCoreData? product;
  final Map<String, dynamic>? blob;
  final bool blobFailed;

  const CompareEntry({
    required this.product,
    required this.blob,
    required this.blobFailed,
  });

  Map<String, dynamic>? get qualityPillarsV4 {
    final raw = blob?['quality_pillars_v4'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }
}

/// Loads one comparison side by dsldId. Blob errors are absorbed into
/// [CompareEntry.blobFailed] so one offline blob never takes down the
/// whole compare screen.
final compareEntryProvider = FutureProvider.autoDispose
    .family<CompareEntry, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      final product = await coreDb.findById(dsldId);

      Map<String, dynamic>? blob;
      var blobFailed = false;
      if (product != null) {
        try {
          blob = await ref.watch(detailBlobProvider(dsldId).future);
          // `on Object` (not Exception): a thrown Error (TypeError from a
          // malformed blob, StateError from a disposed provider) must be
          // absorbed into blobFailed too — otherwise it kills the whole
          // compare entry and the screen falsely reports a catalog miss.
        } on Object {
          blobFailed = true;
        }
      }
      return CompareEntry(product: product, blob: blob, blobFailed: blobFailed);
    });

/// One row in the second-product picker sheet.
class CompareCandidate {
  final String dsldId;
  final String name;
  final String brand;
  const CompareCandidate({
    required this.dsldId,
    required this.name,
    required this.brand,
  });
}

/// Picker candidates: stack supplements + recent scans.
class CompareCandidates {
  final List<CompareCandidate> stack;
  final List<CompareCandidate> recentScans;
  const CompareCandidates({required this.stack, required this.recentScans});

  bool get isEmpty => stack.isEmpty && recentScans.isEmpty;
}

/// Candidates for comparing against [currentDsldId] (always excluded).
/// Stack section: active supplements that carry a dsldId. Recent scans:
/// `user_scan_history` joined against the core catalog, minus anything
/// already shown in the stack section.
final compareCandidatesProvider = FutureProvider.autoDispose
    .family<CompareCandidates, String>((ref, currentDsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      final userDb = ref.watch(userDatabaseProvider);

      final stackEntries = await ref.watch(activeStackProvider.future);
      final stack = <CompareCandidate>[];
      final seen = <String>{currentDsldId};
      for (final entry in stackEntries) {
        final dsldId = entry.dsldId;
        if (entry.type != 'supplement' || dsldId == null) continue;
        if (!seen.add(dsldId)) continue;
        final product = await coreDb.findById(dsldId);
        if (product == null) continue;
        stack.add(
          CompareCandidate(
            dsldId: dsldId,
            name: product.productName,
            brand: product.brandName ?? '',
          ),
        );
      }

      final history = await userDb.getRecentScans(limit: 10);
      final recents = <CompareCandidate>[];
      for (final scan in history) {
        if (!seen.add(scan.dsldId)) continue;
        final product = await coreDb.findById(scan.dsldId);
        if (product == null) continue;
        recents.add(
          CompareCandidate(
            dsldId: scan.dsldId,
            name: product.productName,
            brand: product.brandName ?? '',
          ),
        );
      }

      return CompareCandidates(stack: stack, recentScans: recents);
    });
