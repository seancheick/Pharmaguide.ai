# Flutter Patterns & Conventions

> Patterns and conventions specific to the PharmaGuide Flutter app.  
> Follow these consistently. When establishing a new pattern, document it here.

---

## State Management: Riverpod 3.x

- Use `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator` for code generation.
- All async data providers use `@riverpod` annotation.
- Tune auto-retry and off-screen provider pausing explicitly -- do not rely on defaults for scan/search flows.
- Provider files live in `lib/providers/` or co-located with their feature in `lib/features/<feature>/providers/`.

```dart
@riverpod
Future<ProductCore> productByUpc(Ref ref, String upc) async {
  final db = ref.watch(referenceDatabaseProvider);
  return db.productDao.findByUpc(upc);
}
```

---

## Navigation: GoRouter

- Single router defined in `lib/router/app_router.dart`.
- Five-tab shell using `ShellRoute` with `StatefulShellRoute.indexedStack` for state preservation.
- Deep links handled in `lib/router/deep_link_handler.dart`.
- Invalid routes redirect to home with a toast, never crash.

---

## Database: Drift

- Two databases, never mixed:
  - `ReferenceDatabase` (`pharmaguide_core.db`) -- read-only, bundled + OTA
  - `UserDatabase` (`user_data.db`) -- read/write, user-owned, never replaced by OTA
- Use `customSelect` for hot paths (UPC lookup, FTS search) with narrow column lists.
- Always `LIMIT` queries. Never fetch all 180K products.
- WAL mode enabled. Consider `NativeDatabase.createInBackground` for read pool on heavy queries.
- Cross-DB joins: not supported by Drift. Join at the application level via `dsld_id`.

---

## JSON Parsing: SafeJson Extensions

**CRITICAL: Never use raw `as Map<String, dynamic>` casts anywhere.**

All JSON parsing goes through SafeJson extensions that handle null, wrong types, and missing keys gracefully:

```dart
extension SafeJson on Map<String, dynamic> {
  String safeString(String key, [String fallback = '']) =>
      this[key] is String ? this[key] as String : fallback;

  int safeInt(String key, [int fallback = 0]) =>
      this[key] is int ? this[key] as int : fallback;

  double safeDouble(String key, [double fallback = 0.0]) {
    final v = this[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return fallback;
  }

  List<String> safeStringList(String key) {
    final v = this[key];
    if (v is List) return v.whereType<String>().toList();
    return [];
  }

  Map<String, dynamic> safeMap(String key) {
    final v = this[key];
    if (v is Map<String, dynamic>) return v;
    return {};
  }
}
```

---

## FitScore: Always Computed, Never Persisted

- `ScoreFitCalculator` is a pure function: `(ProductCore, HealthProfile) -> FitScore`.
- FitScore is **never** written to any database.
- Recomputed fresh every time the product is displayed or profile changes.
- This ensures profile updates are instantly reflected without cache invalidation.

---

## File Organization: Feature-First

```
lib/features/
  home/
    screens/
    widgets/
    providers/
  scan/
    screens/
    widgets/
    providers/
  stack/
  chat/
  profile/
  search/
  product_detail/
    screens/
    widgets/
      pillar_cards/
    providers/
```

Shared widgets go in `lib/shared/widgets/`. Cross-feature services go in `lib/services/`.

---

## Image Handling: PDF Guard

Many products in the DSLD database have `image_url` pointing to a PDF, not an image. Always check `image_is_pdf` before loading:

```dart
Widget productImage(ProductCore product) {
  if (product.imageIsPdf || product.imageUrl == null) {
    return const PlaceholderImage();
  }
  return CachedNetworkImage(
    imageUrl: product.imageUrl!,
    placeholder: (_, __) => const PlaceholderImage(),
    errorWidget: (_, __, ___) => const PlaceholderImage(),
  );
}
```

---

## Error Handling Pattern

Errors follow a typed hierarchy. Never show raw exceptions to users:

```dart
sealed class AppException {
  String get userMessage;
  String get debugMessage;
}

class NetworkException extends AppException { ... }
class DatabaseException extends AppException { ... }
class ParseException extends AppException { ... }
class AuthException extends AppException { ... }
```

Error display follows the error matrix (spec section 11):
- Transient network errors -> toast with retry
- Parse errors -> log to Crashlytics, show graceful fallback UI
- Auth errors -> bottom sheet with sign-in prompt
- Safety data errors -> never swallow, always surface to user

---

## Warning Types: Sealed Hierarchy

Warning types from the pipeline map to a sealed Dart class. Switch statements must be exhaustive (no default case):

```dart
sealed class Warning {
  final String severity;
  final String ingredient;
}

class BannedIngredientWarning extends Warning { ... }
class RecalledIngredientWarning extends Warning { ... }
class HarmfulAdditiveWarning extends Warning { ... }
class AllergenWarning extends Warning { ... }
class DoseExceededWarning extends Warning { ... }
class InteractionWarning extends Warning { ... }
```

---

## Search Pattern: Latest-Query-Wins

Search uses 300ms debounce with stale query cancellation:

```dart
// In provider:
// 1. Debounce 300ms
// 2. Cancel previous query if new one arrives
// 3. LIMIT 50 always
// 4. Return empty list on empty query (don't search for "")
```

---

## Accessibility Requirements

- All icons use Lucide (never emojis as structural UI).
- Score rings and verdict banners have semantic labels.
- Animations respect `MediaQuery.disableAnimations` (reduced motion).
- Dynamic Type: test at 200% -- no text truncation or overflow.
- B0 gate screen must be fully navigable by VoiceOver/TalkBack.

---

## Naming Conventions

- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables/functions: `camelCase`
- Constants: `camelCase` (Dart convention, not SCREAMING_SNAKE)
- Test files: `<source_file>_test.dart` in mirror directory structure under `test/`
- Score field names are **FROZEN**: use `score_quality_80`, `score_display_100_equivalent` exactly as pipeline exports them. Never rename.
