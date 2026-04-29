import 'package:drift/drift.dart';

/// Caches product image URLs resolved from Open Food Facts (OFF) API.
///
/// Positive results (real image URL) are cached for 30 days.
/// Negative results (stored as "no_image") are cached for 7 days to avoid
/// hammering the OFF API for products we know don't have images.
class ProductImageCache extends Table {
  TextColumn get dsldId => text().named('dsld_id')();
  TextColumn get imageUrl =>
      text().named('image_url')(); // URL or "no_image" marker
  DateTimeColumn get cachedAt =>
      dateTime().named('cached_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {dsldId};

  @override
  String get tableName => 'product_image_cache';
}
