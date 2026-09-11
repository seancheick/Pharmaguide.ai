import 'package:supabase_flutter/supabase_flutter.dart';

/// Contribution points live in an append-only server ledger, written only
/// when a submission is promoted into the catalog
/// (`mark_product_submission_promoted`). The app adds them up for display and
/// never decides what anything is worth: a formula on the phone could
/// re-price history the moment its inputs or its code changed.
int sumLedgerPoints(Iterable<Map<String, Object?>> rows) {
  var total = 0;
  for (final row in rows) {
    final points = row['points'];
    if (points is int && points > 0) total += points;
  }
  return total;
}

/// The signed-in user's own ledger rows; row-level security scopes the read.
Future<int> readOwnContributionPoints(SupabaseClient client) async {
  final rows = await client
      .from('product_contribution_ledger')
      .select('points');
  return sumLedgerPoints([for (final row in rows) Map.from(row)]);
}
