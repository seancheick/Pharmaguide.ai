import 'package:drift/drift.dart';

// Failed-scan queue: each row is one UPC that the local catalog couldn't
// resolve, with a count of how many times the user has tried and the
// first/last timestamps.
//
// **Privacy contract (enforced by test/safety_invariants/
// failed_scans_no_pii_test.dart):** this table carries only the UPC and
// aggregate counts. NO user_id, device_id, session_id, location, profile
// reference, or any other identifier. A "missing UPC" is a public
// product identifier (the same string printed on every bottle of that
// product worldwide) — it is not health data and is not tied to the
// person who scanned it.
//
// The table feeds the Layer 4 missing-UPC triage flow. It is not synced
// to Supabase in v1; the user dumps it locally and pastes it into the
// `/triage-missing-upcs` slash command when they want a triage report.
// Future versions may add an opt-in anonymous aggregate sync, but that
// requires its own privacy review.
class FailedScans extends Table {
  TextColumn get upc => text()();
  IntColumn get attemptCount =>
      integer().named('attempt_count').withDefault(const Constant(1))();
  DateTimeColumn get firstSeen =>
      dateTime().named('first_seen').withDefault(currentDateAndTime)();
  DateTimeColumn get lastSeen =>
      dateTime().named('last_seen').withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {upc};

  @override
  String get tableName => 'user_failed_scans';
}
