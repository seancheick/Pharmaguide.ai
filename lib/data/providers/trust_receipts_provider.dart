import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

/// Live data-source counts for the Trust Receipts ("Why trust this?") sheet.
///
/// Every field is nullable BY DESIGN: a count that can't be read at runtime
/// (missing manifest row, malformed bundle) is simply omitted from the sheet
/// rather than replaced with an invented number. Never hardcode fallbacks
/// here — a missing number is honest; a stale one is not.
@immutable
class TrustReceiptsData {
  /// Product rows in the bundled catalog (`products_core` COUNT).
  final int? productCount;

  /// Catalog build timestamp (`generated_at` from the embedded
  /// export_manifest). Doubles as the recall-sync freshness date — recalls
  /// are folded in by the pipeline on every catalog build, so there is no
  /// separate FDA sync date to show.
  final DateTime? catalogGeneratedAt;

  /// Live (non-tombstoned), hand-reviewed interaction rows in the
  /// bundled interaction DB (source ∈ {'curated','override'}). The
  /// sheet labels this count "Hand-reviewed, evidence-graded", so
  /// machine-extracted source='suppai' rows are excluded by design.
  final int? interactionCount;

  /// supp.ai PubMed co-occurrence research pairs in the bundled
  /// interaction DB.
  final int? researchPairCount;

  const TrustReceiptsData({
    this.productCount,
    this.catalogGeneratedAt,
    this.interactionCount,
    this.researchPairCount,
  });

  @override
  bool operator ==(Object other) {
    return other is TrustReceiptsData &&
        other.productCount == productCount &&
        other.catalogGeneratedAt == catalogGeneratedAt &&
        other.interactionCount == interactionCount &&
        other.researchPairCount == researchPairCount;
  }

  @override
  int get hashCode => Object.hash(
    productCount,
    catalogGeneratedAt,
    interactionCount,
    researchPairCount,
  );
}

/// Gathers live counts for the Trust Receipts sheet from the bundled
/// databases. Each read is independently guarded — one failed lookup nulls
/// only its own field, never the whole sheet.
///
/// NOT in this provider (and intentionally so):
///   • Curated clinical study cluster count — not exposed at runtime by the
///     current bundle, so the sheet shows the static line without a number.
///   • FDA recall sync date — recalls ship inside each catalog build; the
///     catalog `generated_at` IS the freshness date (see field doc above).
final trustReceiptsProvider = FutureProvider.autoDispose<TrustReceiptsData>((
  ref,
) async {
  final coreDb = ref.watch(coreDatabaseProvider);
  final interactionDb = ref.watch(interactionDatabaseProvider);

  Future<T?> guard<T>(Future<T> Function() read, String label) async {
    try {
      return await read();
    } on Object catch (e) {
      // A missing count is rendered as "no number", never a fake one.
      debugPrint('[trust-receipts] $label unavailable: ${e.runtimeType}');
      return null;
    }
  }

  final productCount = await guard(coreDb.countProducts, 'product count');
  final generatedAtRaw = await guard(
    () => coreDb.readManifestValue('generated_at'),
    'catalog generated_at',
  );
  final interactionCount = await guard(
    interactionDb.countCuratedInteractions,
    'interaction count',
  );
  final researchPairCount = await guard(
    interactionDb.countResearchPairs,
    'research pair count',
  );

  DateTime? generatedAt;
  if (generatedAtRaw != null && generatedAtRaw.isNotEmpty) {
    generatedAt = DateTime.tryParse(generatedAtRaw);
  }

  return TrustReceiptsData(
    productCount: productCount,
    catalogGeneratedAt: generatedAt,
    interactionCount: interactionCount,
    researchPairCount: researchPairCount,
  );
});
