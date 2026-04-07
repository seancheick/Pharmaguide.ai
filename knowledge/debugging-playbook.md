# Debugging Playbook

> Common issues and step-by-step fixes.  
> **Rule:** When you fix a non-trivial bug, add an entry here so the next person doesn't waste time rediscovering it.  
> **Format:** Symptom -> Root Cause -> Fix -> Prevention

---

## Database Issues

### Symptom: "no such table: products_core" on app launch

**Root Cause:** Drift database was not loaded from the bundled asset. Either `db_asset_loader.dart` failed silently, or the asset path in `pubspec.yaml` is wrong.

**Fix:**
1. Verify `pubspec.yaml` has `assets/db/pharmaguide_core.db` listed under `flutter: assets:`
2. Verify the file exists at that path: `ls -la assets/db/pharmaguide_core.db`
3. Check `db_asset_loader.dart` -- it must copy from asset to app documents directory on first launch
4. Run `flutter clean && flutter pub get` to rebuild asset bundle

**Prevention:** Add a startup test that queries `SELECT count(*) FROM products_core` and fails fast with a clear error message if the table doesn't exist.

---

### Symptom: OTA DB swap loses user data

**Root Cause:** OTA swap replaced `user_data.db` instead of only `pharmaguide_core.db`.

**Fix:** This is a critical bug. Verify that `db_swap_service.dart` only touches `pharmaguide_core.db`. The swap flow must be:
1. Download new DB to staging path
2. Verify checksum
3. Run integrity check (`PRAGMA integrity_check`)
4. Close reference DB connection
5. Rename current to `.bak`
6. Rename staging to production
7. Reopen reference DB
8. Delete `.bak` on success, restore `.bak` on failure

**Prevention:** Test: after OTA swap, query `user_data.db` for a known user profile row and assert it still exists. Add this as an automated test.

---

## JSON Parsing Issues

### Symptom: `type 'Null' is not a subtype of type 'String'` on product detail

**Root Cause:** Raw `as String` cast on a nullable JSON field. The pipeline may export `null` for optional fields.

**Fix:** Replace raw casts with SafeJson extensions:
```dart
// Bad:
final name = json['product_name'] as String;
// Good:
final name = json.safeString('product_name', 'Unknown Product');
```

**Prevention:** Never use raw `as Type` casts on JSON. Always use SafeJson extensions. Add a lint rule or code review checklist item.

---

### Symptom: Score displays as "NaN/100" or "Infinity"

**Root Cause:** `score_quality_80` is null (NOT_SCORED product) and the display formatter divides by zero or operates on null.

**Fix:** Always null-check `score_quality_80` before computing `score_100_equivalent`:
```dart
if (product.scoreQuality80 == null) {
  return 'Not Scored';
}
final score100 = (product.scoreQuality80! / 80.0) * 100.0;
```

**Prevention:** Use the pipeline's pre-formatted `score_display_100_equivalent` string when available. Only compute locally if you need the numeric value.

---

## Search Issues

### Symptom: Search returns stale results (wrong product for current query)

**Root Cause:** Previous async query completed after a newer query, overwriting results. Missing latest-query-wins pattern.

**Fix:** Implement query cancellation:
```dart
// Track the latest query ID
// In the provider, compare query ID before updating state
// If a newer query was issued, discard the older result
```

**Prevention:** Use the latest-query-wins pattern from the start. Never return async search results without checking they match the current query.

---

### Symptom: FTS search crashes on special characters

**Root Cause:** SQLite FTS5 has special syntax characters (`*`, `"`, `NEAR`, `AND`, `OR`, `NOT`). User input with these characters causes a query syntax error.

**Fix:** Escape or strip FTS special characters from user input before querying:
```dart
String sanitizeFtsQuery(String input) {
  // Remove FTS5 special operators
  return input.replaceAll(RegExp(r'["\*]'), '').trim();
}
```

**Prevention:** Always sanitize FTS input. Add test cases for: `vitamin "d"`, `omega*`, `NOT available`, `fish AND oil`.

---

## Performance Issues

### Symptom: App jank when scrolling product list

**Root Cause:** Loading full product data (all 88 columns) for list items. Most columns are unused in list view.

**Fix:** Use `customSelect` with only the columns needed for list display:
```sql
SELECT dsld_id, product_name, brand_name, score_display_100_equivalent,
       verdict, grade, image_url, image_is_pdf
FROM products_core
WHERE ...
LIMIT 50
```

**Prevention:** Never `SELECT *` from `products_core`. Always specify the exact columns needed for the UI context.

---

### Symptom: Memory usage grows continuously during repeated scan/detail/back cycles

**Root Cause:** Detail blob JSON objects retained in memory by provider cache. Riverpod providers keep references to all previously loaded detail blobs.

**Fix:** Configure provider auto-dispose and/or manually invalidate detail blob providers when navigating away from detail screen.

**Prevention:** Use `@riverpod` with `keepAlive: false` for detail-level providers. Profile memory with DevTools during development.

---

## Auth Issues

### Symptom: Guest scan count not preserved after sign-in

**Root Cause:** Guest scan count stored in Hive with a guest key. After sign-in, the app looks for the signed-in user's key, finds no count, and resets to 0.

**Fix:** During guest-to-auth migration, copy the guest's Hive scan count to the signed-in user's record. Then delete the guest record.

**Prevention:** Document the guest-to-auth migration flow. Test it explicitly: scan 5 times as guest, sign in, verify count shows 5.

---

## Build Issues

### Symptom: Drift code generation fails with "unresolved reference"

**Root Cause:** Missing `build_runner` dependency or stale generated files.

**Fix:**
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

**Prevention:** Add `build_runner` and `drift_dev` to `dev_dependencies`. Run code generation after any Drift schema change.

---

### Symptom: iOS build fails with "No signing certificate"

**Root Cause:** Xcode signing configuration not set up for the team.

**Fix:**
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select Runner target -> Signing & Capabilities
3. Select your team and enable automatic signing
4. Verify bundle identifier matches App Store Connect

**Prevention:** Document the signing setup in onboarding. Keep the team ID in a shared (but not committed) config.

---

## Template for New Entries

```
### Symptom: [What the developer sees]

**Root Cause:** [Why it happens]

**Fix:**
[Step-by-step instructions]

**Prevention:** [How to avoid this in the future]
```
