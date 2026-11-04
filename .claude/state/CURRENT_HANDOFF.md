# Safety state and search follow-up — November 3, 2026

Goal: confirm and repair the reported medication-dose, incomplete pre-add, catalog recovery and search races; user authorizes commits/push, not merge/release. Branch codex/safety-state-followup, baseline origin/main7fa991ca (submission195 integrated). Existing Claude worktrees/replay untouched. Source qualification only, no device proof.

Owner: active_stack_provider.dart::StackActions.updateTracking; stack_safety_providers.dart::safetyCheckForAddProvider; app.dart::_buildRouter/PharmaGuideApp; medication_entry_v2_screen.dart query/clear handlers; search_v2_screen.dart query handlers; photo_panel_hints.dart::_directions. Evidence: call-site searches, fail-first tests and final diff review. Will NOT create new clinical rules, thresholds, persisted fields, severity meanings or duplicate safety engines.

Implemented:
- Changed/cleared medication dosage revokes only old confirmed dailyDoseMg, retaining route/use context. Existing aspirin kidney rule returns; unchanged-dose/non-dose control retains valid confirmation.
- Candidate/stack low or unknown mapping, absent canonical ingredients or catalog identities produce incomplete pre-add checks. Preserve known interaction hits and distinct empty-stack copy; reuse existing coverage threshold.
- Catalog routes observe current availability/reason/retry through a private inherited scope, preserving the same router. Recover and withhold again without restart.
- Medication/product query edits invalidate in-flight work immediately. Actual medication Clear cancels debounce, invalidates old response and clears searching; offline fallback is also guarded.
- Separate low-priority photo hint recognizes Shake well before dosing instructions. This is not a health warning and does not qualify clinical evidence; it is not a release blocker.

Validation:
- RED:2aspirin stale-context cases;6mapping cases;catalog recovery retained unavailable route;medication/product old-response races;actual Clear pending timer and in-flight result;Shake well dosing prefix missed.
- GREEN:58combined safety owner/consumer tests, then27pre-add/sheet tests after additional controls;98photo/submission tests;36app/search/medication tests. These runs overlap; do not sum as unique tests.
- Scoped analysis clean; formatting and git diff --check passed. Independent review found actual Clear bypass, repaired with two failing-first button regressions; final review has no remaining actionable finding.
- Initial SQLite native-library errors were concurrent Flutter invocation contention; serialized tests pass. New router test initially left the global router on search and polluted7later tests; restored home at teardown without weakening assertions; final36pass.
- Full local make check intentionally not launched alongside the active corpus replay. Hosted full app CI remains required on pushed candidate. No merge/device/deployment acceptance claimed.

Durable local receipts: /Users/seancheick/pg_quality/codex_takeover_20261103/{SAFETY_STATE_FOLLOWUP_GREEN,PREADD_MAPPING_RED,PREADD_MAPPING_GREEN,SHAKE_DIRECTIONS_TEST,RECOVERY_SEARCH_FOCUSED,MEDICATION_CLEAR_RED}.log. Next: push qualification PR, inspect CI, fix actual failures; authorized integrator owns merge and final device/catalog acceptance.
