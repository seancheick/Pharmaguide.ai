import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';

/// App-wide reference-data repository.
///
/// The repository lazy-caches bundled JSON assets such as RDA/UL tables,
/// timing rules, taxonomy mappings, recalls, and depletion references.
/// Keeping this in the data layer gives stack health, FitScore, and product
/// detail one override point in tests and one cache for the app lifetime.
final referenceDataRepositoryProvider = Provider<ReferenceDataRepository>((
  ref,
) {
  return ReferenceDataRepository();
});

/// Active bundled RDA/UL artifact. Product-detail surfaces use its versioned
/// semantic fingerprint to reject UL verdicts computed from stale catalog data.
final rdaOptimalUlsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repository = ref.watch(referenceDataRepositoryProvider);
  return repository.loadRdaOptimalUls();
});
