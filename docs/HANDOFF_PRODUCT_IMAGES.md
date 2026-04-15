# Handoff: Product Image System — Open Food Facts + Branded Placeholder

**Date:** 2026-04-15
**From:** Sprint 26 session
**Status:** Ready to implement — all prerequisite work is done

---

## Goal

Every product in the app should display a visual image. Two-tier system:
1. **Primary:** Real product photo from Open Food Facts (OFF) API, matched by UPC barcode
2. **Fallback:** Branded placeholder card generated in Flutter using DB data

No pipeline changes needed. No Supabase storage needed. Pure Flutter.

---

## Context & Prior Work

### What exists today
- `products_core.upc_sku` — 2,244 of 2,492 products have UPC barcodes
- `products_core.image_url` — all 2,492 have DSLD label PDFs (not usable as product photos)
- `products_core.image_thumbnail_url` — column exists in Drift schema (added this session), currently null for all products
- "View Supplement Label" button on product detail opens the PDF in external browser
- No product image widget exists anywhere in the app

### OFF API test results (done this session)
- Tested 15 supplement UPCs against `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`
- **~10% hit rate** for supplements (OFF is primarily food)
- Consumer grocery-store brands (OLLY) found; specialty brands (Thorne, Pure Encapsulations, Nature Made) mostly missing
- API returns `product.image_front_url` when available — direct CDN link, no auth needed
- Rate limit: respect `User-Agent` header, ~1 req/sec recommended

### What was decided
- OFF is worth trying (free, real photos when available, coverage will grow)
- Branded placeholder fills the 90% gap with a polished generated card
- User-contributed photos added to sprint tracker as post-launch feature

---

## Implementation Plan

### File 1: `lib/services/product_image_resolver.dart` (new)

Service that resolves the best available image for a product.

```dart
class ProductImageResolver {
  /// Returns the best image URL for a product, or null for placeholder.
  ///
  /// Priority:
  /// 1. Local cache (user_data.db product_image_cache table)
  /// 2. OFF API lookup by UPC
  /// 3. null → caller renders BrandedPlaceholder
  Future<String?> resolve(String dsldId, String? upc) async { ... }
}
```

**Logic:**
```
resolve(dsldId, upc):
  1. Check cache: SELECT image_url FROM product_image_cache WHERE dsld_id = ?
     → if found and < 7 days old, return cached URL
     → if found and "no_image" marker, return null (don't re-query OFF)

  2. If upc is null or empty → cache "no_image", return null

  3. Try OFF API:
     GET https://world.openfoodfacts.org/api/v2/product/{upc}.json
       ?fields=code,product_name,image_front_url,image_front_small_url
     Headers: User-Agent: PharmaGuide/1.0 (supplement-safety-app)

     → status == 1 && image_front_url not empty:
         Cache the URL, return it
     → status == 0 or no image:
         Cache "no_image" marker, return null
     → Network error / timeout:
         Return null (don't cache — retry next time)

  4. Return null → caller shows placeholder
```

**Cache table** — add to `user_database.dart` tables:
```dart
class ProductImageCache extends Table {
  TextColumn get dsldId => text().named('dsld_id')();
  TextColumn get imageUrl => text().named('image_url')(); // or "no_image"
  DateTimeColumn get cachedAt => dateTime().named('cached_at')
      .withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {dsldId};
  @override
  String get tableName => 'product_image_cache';
}
```

**Important constraints:**
- Catch ALL exceptions from HTTP call — never crash the app for a missing image
- Respect OFF rate limits: use a simple Completer-based throttle (max 2 concurrent)
- Cache "no_image" results for 7 days to avoid hammering OFF with known misses
- Cache positive results for 30 days (OFF images are stable URLs)

### File 2: `lib/core/widgets/branded_placeholder.dart` (new)

A generated product card widget — no network, no images, 100% coverage.

```dart
class BrandedPlaceholder extends StatelessWidget {
  final String productName;
  final String brandName;
  final String? formFactor;
  final double? score;

  const BrandedPlaceholder({ ... });
}
```

**Design:**
```
┌──────────────────────────────┐
│                              │
│        ┌──────────┐         │  ← Rounded square with brand color
│        │          │         │     (derived from brand name hash)
│        │    T     │         │  ← Large initial letter, white
│        │          │         │
│        └──────────┘         │
│                              │
│   Vitamin D3 2000 IU        │  ← Product name, centered, 2 lines max
│   Thorne Research            │  ← Brand name, muted
│                              │
│   ● Softgel    ████░░ 85    │  ← Form icon + mini score bar
│                              │
└──────────────────────────────┘
```

**Brand color derivation:**
```dart
Color _brandColor(String brand) {
  final hash = brand.toLowerCase().hashCode;
  // Use HSL with fixed saturation/lightness for consistent premium feel
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.35, 0.45).toColor();
}
```

**Form factor icons:**
- Capsule → `Icons.medication_outlined`
- Softgel → `Icons.circle_outlined`
- Tablet → `Icons.crop_square_rounded`
- Gummy → `Icons.favorite_outline`
- Powder → `Icons.grain`
- Liquid → `Icons.water_drop_outlined`
- Default → `Icons.medication_outlined`

### File 3: `lib/core/widgets/product_image.dart` (new)

Orchestrating widget that tries the real image first, falls back to placeholder.

```dart
class ProductImage extends ConsumerWidget {
  final String dsldId;
  final String? upc;
  final String productName;
  final String brandName;
  final String? formFactor;
  final double? score;
  final double size; // width & height

  const ProductImage({ ... });
}
```

**Build logic:**
```dart
Widget build(context, ref) {
  final imageAsync = ref.watch(productImageProvider(dsldId));

  return imageAsync.when(
    loading: () => BrandedPlaceholder(...), // Show placeholder while loading
    error: (_, __) => BrandedPlaceholder(...),
    data: (imageUrl) {
      if (imageUrl == null) return BrandedPlaceholder(...);
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => BrandedPlaceholder(...),
          errorWidget: (_, __, ___) => BrandedPlaceholder(...),
        ),
      );
    },
  );
}
```

**Provider:**
```dart
final productImageProvider = FutureProvider.family
    .autoDispose<String?, String>((ref, dsldId) async {
  final coreDb = ref.read(coreDatabaseProvider);
  final product = await coreDb.findById(dsldId);
  if (product == null) return null;
  final resolver = ref.read(productImageResolverProvider);
  return resolver.resolve(dsldId, product.upcSku);
});
```

### File 4: Wiring into existing widgets

Add `ProductImage` to these existing widgets:

**`lib/core/widgets/product_list_item.dart`** — Add image left of the score ring:
```dart
Row(
  children: [
    ProductImage(
      dsldId: product.dsldId,
      upc: product.upcSku,
      productName: product.productName,
      brandName: product.brandName ?? '',
      formFactor: product.formFactor,
      score: product.score100Equivalent,
      size: 52,
    ),
    const SizedBox(width: 12),
    PGScoreRing(...),
    // ... rest of row
  ],
)
```

**`lib/features/home/home_screen.dart` → `_RecentScanCard`** — Add image above score ring:
```dart
Column(
  children: [
    ProductImage(..., size: 48),
    const SizedBox(height: 8),
    PGScoreRing(...),
    // ...
  ],
)
```

**`lib/features/product_detail/product_detail_screen.dart` → `_HeaderSection`** — Optional, could add small image next to product name.

### Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  cached_network_image: ^3.3.1
  http: ^1.2.1  # if not already present
```

---

## Testing Checklist

- [ ] OFF API returns image → displayed, cached
- [ ] OFF API returns 404 → branded placeholder shown, "no_image" cached
- [ ] OFF API timeout → branded placeholder shown, NOT cached (retry next time)
- [ ] Product with no UPC → branded placeholder immediately (no API call)
- [ ] Cache hit within TTL → no API call
- [ ] Cache expired → re-queries OFF
- [ ] Branded placeholder colors are consistent for same brand across sessions
- [ ] Images display correctly in: product list, grid view, carousel card, product detail
- [ ] Offline mode → cached images still display, uncached show placeholder
- [ ] No crashes on malformed OFF responses

---

## What NOT to do

- Do NOT use the DSLD PDF URLs as images — they're label scans, not product photos
- Do NOT call OFF API during pipeline build — it's a runtime Flutter decision
- Do NOT store OFF images in Supabase — OFF serves from their CDN, just cache the URL
- Do NOT block product display on image loading — always show placeholder immediately, swap in real image when ready
- Do NOT hit OFF more than 2 concurrent requests — they rate limit

---

## Files to read first

| File | Why |
|------|-----|
| `lib/core/widgets/product_list_item.dart` | Where images will be inserted |
| `lib/features/home/home_screen.dart` → `_RecentScanCard` | Carousel card that needs images |
| `lib/data/database/user_database.dart` | Where to add the cache table |
| `lib/data/providers/database_providers.dart` | Provider patterns to follow |
| `lib/data/supabase/supabase_contract.dart` | Example of centralized constants |
| `CLAUDE.md` | Project safety rules and conventions |

---

## Sprint tracker entry (already added)

In `SPRINT_TRACKER.md` under "Pending (next sprint)":
- `[ ] Build branded placeholder card widget`
- `[ ] User-contributed photos (post-launch data moat)`
