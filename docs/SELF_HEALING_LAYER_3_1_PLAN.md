# Layer 3.1 plan — Sentry instrumentation upgrade

**Status:** Planned, not built. Pick up when production volume justifies
it — likely after the first wider beta or once a real bug slips
through invisibly because Sentry didn't catch it.

**Goal:** Close the gap between "what Sentry CAN catch" and "what
PharmaGuide actually reports". The Layer 3 routine is only as good as
its input — and right now most user-impacting errors never reach
Sentry. This PR adds the wiring so the routine has signal to act on.

**Risk:** Increases Sentry event volume from previously-silent code
paths. Current monthly volume (~700 events, 99% dev noise) is well
under the 5,000/month free tier ceiling, but instrumentation could
2-3x the production share. Worth re-checking after a week of data.

## Concrete changes

### 1. Add SentryNavigatorObserver to GoRouter

GoRouter has a built-in observers slot. Adding the Sentry observer
gives every event a `route` tag + a navigation breadcrumb trail
showing the last N screens the user visited. Without this, the agent
investigating a crash sees a stack trace but no user journey.

- File: `lib/main.dart` (or wherever GoRouter is configured)
- Add: `observers: [SentryNavigatorObserver()]`
- Result: every Sentry event now carries `route:/scan`, `route:/product/:id`, etc.

### 2. Wrap HTTP clients with SentryHttpClient

Two clients in the app currently bypass Sentry's network breadcrumb
tracking:

- `lib/services/product_image_resolver.dart:28` — `http.Client()` for OFF API
- `lib/services/medications/rxnorm_api_service.dart:91` — `HttpClient` for RxNorm

Wrap each with `SentryHttpClient` (or use the SDK's
`captureFailedRequests: true` option). Result: every HTTP failure
becomes a Sentry-visible breadcrumb with status code, URL, latency.

### 3. Add `recordError()` to silent catches

Seven files currently catch + swallow errors without informing Sentry.
Each silent catch hides a class of user-impacting bugs from the
autofix loop. The fix is one `CrashReportingService().recordError(e, stackTrace, fatal: false)` call per catch.

| File | Lines | What it hides |
|---|---|---|
| `lib/services/catalog_swap.dart` | 92-128 (5 catches) | OTA DB swap failures — users see "catalog unavailable" |
| `lib/services/catalog_updater_service.dart` | 98-139 | Download / staging failures |
| `lib/services/auth/pg_auth_service.dart` | 76-184 | Apple, Google, magic-link auth errors |
| `lib/features/product_detail/widgets/pg_stack_action_buttons.dart` | 114, 156, 191, 217 | Stack mutation failures (add/remove/restore) |
| `lib/features/profile/profile_provider.dart` | 161, 443, 462 | Profile fetch/save corruption |
| `lib/features/scanner/scanner_screen.dart` | 134 | `catch (_)` on the DB lookup path |

Rule of thumb: a `catch` that swallows an error and shows the user a
generic "something went wrong" message should also report to Sentry
with `fatal: false`. Don't add Sentry hits to expected control flow
(e.g. `AuthException` on a wrong password — that's a user-input
problem, not a code bug).

### 4. Custom tags

Add the following tags via `Sentry.configureScope` in the right
lifecycle hooks:

- `screen` — set on every `GoRouter.routerDelegate` change. Already
  semi-redundant if Layer 3.1.1 (SentryNavigatorObserver) is in,
  but explicit `setTag` is more durable.
- `scan_result` — set to `found` / `not_found` / `error` on each
  scan completion (already has the call site at
  `scanner_screen.dart:_lookUpProduct`).
- `auth_state` — set to `guest` / `signed_in` on auth state change.
- `release_channel` — set to `dev` / `testflight` / `production` from
  the existing `SENTRY_ENVIRONMENT` value. Redundant with the
  built-in `environment` tag, but easier to query consistently.

These let the routine filter by `tags[screen]:/scan` or
`tags[scan_result]:not_found` — turning the search from
"all unresolved errors" into "all unresolved errors that happened
during a scan attempt", which is what triage actually needs.

### 5. Tighten the scrubber

Current scrubber uses substring match:
```dart
if (key.toLowerCase().contains(sensitiveKey)) { ... }
```

This false-positive scrubs `email_verified` (contains `email`),
`condition_id_class` (contains `condition`), etc. A whole-word match
would be tighter:

```dart
final keyLower = key.toLowerCase();
if (sensitiveKey == keyLower ||
    keyLower.startsWith('${sensitiveKey}_') ||
    keyLower.endsWith('_$sensitiveKey') ||
    keyLower.contains('_${sensitiveKey}_')) { ... }
```

Worth verifying against the existing tests in
`test/services/crash_reporting_service_test.dart` (if any) before
shipping — substring scrubbing might be intentionally aggressive.

### 6. Framework hooks not yet wired

- `runZonedGuarded` — wrap `runApp` in `lib/main.dart` so synchronous
  errors from the root zone get captured.
- `Isolate.current.addErrorListener` — already partially handled by
  `PlatformDispatcher.instance.onError`, but the explicit
  isolate listener catches background isolate errors that may
  otherwise vanish.

## Estimated scope

- ~7 files touched
- ~50 lines of code (mostly one-line `recordError` adds)
- 1 new test file: `test/services/crash_reporting_service_scrubber_test.dart`
  to verify the tightened scrubber doesn't false-positive on legit
  keys like `email_verified`.

## Verification

After landing:

1. Trigger each error path manually in dev (kill catalog swap, force
   auth failure, etc.). Verify each appears in Sentry as a separate
   issue.
2. Check that breadcrumbs now include navigation events: scan a
   product, navigate to detail, navigate back — the stack should
   show three `navigation` crumbs.
3. Run the autofix routine. Confirm it uses the new tags (e.g. the
   triage step now also filters by `screen` and `scan_result`).
4. After 7 days, re-check Sentry monthly volume to confirm the free
   tier isn't being approached.

## Open questions

- Do we want a `feature_flag` tag once Growthbook (or equivalent) is
  wired? Probably yes, but defer until Growthbook ships.
- Should we send `sentry_user_segment` (signed-in vs guest) as a tag
  even though we don't send the Supabase UUID? Yes — it lets the
  routine triage "guest-only bugs" separately from "signed-in-only
  bugs" without exposing identity.
- The `setUserId` method is defined but never called. Should it stay
  for future use, or be deleted to remove the temptation to misuse
  it? Decision: keep, with the privacy comment added in this branch.
