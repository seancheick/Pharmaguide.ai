import 'package:drift/drift.dart';

/// Scan history — records each barcode scan with timestamp.
class ScanHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dsldId => text().named('dsld_id')();
  TextColumn get upcSku => text().named('upc_sku').nullable()();
  TextColumn get productName => text().named('product_name').nullable()();
  TextColumn get formulaFingerprint =>
      text().named('formula_fingerprint').nullable()();
  TextColumn get catalogSourceVersion =>
      text().named('catalog_source_version').nullable()();
  DateTimeColumn get scannedAt =>
      dateTime().named('scanned_at').withDefault(currentDateAndTime)();

  @override
  String get tableName => 'user_scan_history';
}
