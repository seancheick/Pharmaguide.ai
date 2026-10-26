---
name: verify-pharmaguide
description: Verify PharmaGuide's native iOS behavior and trace a reported product discrepancy through installed catalog, detail blob and rendered screen. Use for old wording, incorrect displayed amounts, missing warnings, or verification of a delivered app fix. Does not establish scientific approval or authorize publication.
---

# Verify the actual PharmaGuide app

Read AGENTS.md and the current handoff. Reuse pipeline data-fix, pg-scoring-change,
verify-data and catalog-release for their respective owners. The app renders their
results. Never fix a stale installed catalog by changing the scorer again.

## Establish the instance first

Use `xcrun simctl list devices -j` and choose an explicit UUID. Own one isolated
simulator for the run; never use `booted` when more than one exists or take over
another agent's/user's device. Record whether you created it. Do not erase user data.

From the app repository, run the read-only doctor before diagnosing an existing install:

```sh
python3 scripts/verify_native_app.py --device UUID --product 295048 --output /absolute/durable/new-directory
```

`UUID` and output directory must be actual values discovered for this run. The
check reads the installed Info.plist, executable hash, SQLite embedded manifest,
exact product row and detail hash; it also inspects the installed bundled catalog.
It does not infer the running source revision from the current checkout. Its
historical journey receipt is evidence only after its source, catalog and action
log are matched to the present run. No receipt means runtime mode is unverified.
`identity_captured` proves identity inspection only, never UI or release success.
`--expected-catalog VERSION` fails if the installed version differs.

Run `make verify-supabase` for the existing service-access check. Its success does
not establish evidence readiness or publication compatibility. A pending
`assets/db/.catalog-import-transaction` must be recovered by the existing importer
before these assets may be treated as a coherent bundle. Do not import or publish
a catalog simply to make verification pass; use authorized release procedures.

## Launch and drive the ordinary app

The existing `make run-ios IOS_DEVICE=UUID` launches the normal app. Complete
onboarding through its real controls first and verify Home navigation using the
computer-control tool. The iOS26 integration binding cannot reliably operate the
UIKit tab bar; that is a harness limitation, not proof of a product failure. Stop
only your normal launch process, preserving the isolated app data. For repeatable
startup/search/detail verification on this normally initialized device use:

```sh
make verify-native VERIFY_DEVICE=UUID VERIFY_OWNED_DEVICE=1 VERIFY_PRODUCT_ID=295048 VERIFY_EVIDENCE_DIR=/absolute/durable/new-run
```

This uses the normal `main`, real database/providers and actual service. It drives
onboarding if needed, Home search, the exact label tile, and Testing & Brand.
It does not seed user state or override providers. It refuses `SCREENSHOT_MODE`,
`SCREENSHOT_ROUTE` and `DEV_ROUTE`. Marketing `make screenshots` is not an ordinary
app delivery test. The integration test's `source_revision_at_launch` identifies
the checkout used to build it; retain `git diff` and its hash if the checkout is dirty.

For a delivery assertion add `VERIFY_CATALOG_VERSION=...` and
`VERIFY_EXPLANATION='the exact source-approved explanation'`. These expected values
must come from the reviewed candidate, not be copied from whatever screen appeared.
Without those arguments the journey proves installed-data rendering parity only.
Do not call a matching old explanation proof that a new correction was delivered.

Controls: Home `Search supplements`, search `TextField`, exact
`ValueKey('search-product-<dsld_id>')`, then the visible `Testing & Brand` row.
On iOS26 the tab bar is native UIKit. A run printing `NATIVE_CONTROL_REQUIRED`
has reached the known harness boundary: return to ordinary app launch/onboarding
and report this attempt as unverified. Do not inject a route or override the bar.
Dismiss any first-use keyboard tip through normal UI. This is assisted native
verification, not unattended fresh-device automation. Device Hub may host the simulator on newer Xcode installations.
Use normal taps/text/scrolls. Read-only provider inspection may capture what the app
loaded; it must not substitute for navigation or inject a different result.

## Preserve evidence and diagnose failures

The host driver writes `native_journey.json` and numbered screenshots to
`VERIFY_EVIDENCE_DIR`, including assertion-failure evidence. Device copies are
secondary because test cleanup may uninstall the app. An interrupted runner may
leave incomplete evidence: only a successful runner exit plus the assertions and
reviewed screenshots establish the journey pass. `journey_assertions_passed` alone
does not establish runner success. Run the doctor while the app is installed. Retain
launch log, exact source diff/commit, app build, installed catalog version, product
ID, detail hash, action sequence, observed explanation and unmet expectations.
Never include credentials, account snapshots or unrelated user data in public commits.

If a run fails: distinguish startup/harness failure, unavailable data, wrong catalog,
wrong export, provider error and rendering error. Trace the earliest divergent layer.
For missing details use existing unavailable-state tests; never replace them with
an all-clear fixture. Map each claimed result to [the feature map](features/journeys.md).
Only mark journeys actually exercised. UI parity does not grant scientific approval.

## Cleanup and maintenance

Copy evidence before shutting down a simulator you created. Shut down only that UUID;
never kill processes by name. Keep the evidence and completed candidate. Do not delete
existing devices or reset user storage. Re-run this skill when its launch/control
instructions change. A failed control must be repaired or reported, never hidden by
loosening a clinical expectation. Use existing owner tests for negative cases and
retain the original reproduction for every claimed fix.
