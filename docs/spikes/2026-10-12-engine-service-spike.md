# Spike: can the on-device safety engine run server-side unchanged? (Phase 4, Lane F)

Date: 2026-10-12 · Branch: `worktree-agent-a3ac37572fd12204f` (base `d4c0b097`) · Status: spike, no `lib/` change

## Independent recheck — October 13, 2026

Owner: `tool/engine_spike/build.sh` and its `InteractionRow` shim. Evidence:
`rg` of the existing spike/test paths and the real `interactions_table.dart` schema.
Will NOT create: a second engine, a new clinical policy or replacement golden findings.

The initial recheck failed compilation because the spike row shim lacked the current nullable
`profileGateJson` and `medicationExceptionsJson` fields. The shim now passes through those JSON
columns when present; the frozen fixtures omit them and still read as null. No fixtures were
re-extracted, and no production engine source changed.

The harness also used to overwrite its golden and print parity/closure failures without reliably
failing its exit status. Five focused harness tests reproduced eight failing cases before the fix;
all five now pass. Verification requires Deno and Node, refuses missing outputs and failed compiles,
fails on any runtime difference, and compares against the reviewed golden without overwriting it.
The candidate VM golden is left under `.build/vm.golden.json` for inspection only.

After these bounded fixes, Dart 3.12.2 VM, native AOT, Deno 2.7.10 and Node 25.9.0 produced identical
findings for the same frozen fixture. Both full-closure compile probes passed. The existing real-app
golden and the added optional-field parser test passed (2 tests). Fixture, golden, bundled interaction
DB and depletion-reference hashes were unchanged. JS was 488,253 bytes (106,652 gzip); its local Deno
10-item warm mean was 0.965 ms, cold 3 ms and process RSS 89,849,856 bytes on the shared machine.

These are local portability measurements, not a deployed-runtime or clinical-completeness result.
The fixture still has no detail blobs and explicitly reports incomplete checks. The unverified paths
below remain unverified, and ADR-010 remains a proposal. Local receipts:
`/Users/seancheick/pg_quality/ai_connector_audit_20261013/engine-spike-*`.

## Answer

**Yes, for both targets, with no TypeScript and no change to `lib/`.** The unchanged engine sources
(all 29 files in `lib/services/{fit_score,warnings,stack}/` plus their transitive `core/` imports)
compile with `dart compile js -O2` and `dart compile exe` once four files and two Flutter libraries are
swapped at compile time. The pre-add check and depletion check produced byte-identical findings on the
Dart VM, AOT native, Deno 2.7.10 and Node 18. Those findings also equal what the real app path produces:
the Riverpod providers, Drift over the full 25 MB `interaction_db.sqlite`, and reference data loaded
through `rootBundle`.

Recommendation: run the engine as **dart2js inside the personal-MCP edge function**, and keep **AOT native
as the fallback**. To get there, first make the seams below real in `lib/`, so production needs no overlay.
The biggest piece of work is moving the orchestration out of the Riverpod providers.

## 1. Engine map: what blocks a server build

Method: transitive import closure of the engine entry files (`tool/engine_spike/bin/closure_probe.dart`
imports all 29). The closure is 71 files and about 16.8k lines. Riverpod appears **nowhere** in the engine
directories. It appears only in the orchestration providers.

| Blocker | Symbols actually used | Reached from |
|---|---|---|
| `package:flutter/foundation.dart` (pulls in `dart:ui`) | `@immutable` only | `stack/{coverage_analyzer,medication_profile_gate_evaluator,stack_dose_summer,stack_intelligence_engine,stack_nutrient_models,stack_safety_report}.dart`, `signals/clinical_signal_envelope.dart`, `medications/medication_class_bridge.dart` |
| `package:flutter/material.dart` | `Color` on the `StackTier` enum | `core/models/stack_intelligence.dart` ← `stack_intelligence_engine.dart` |
| `sentry_flutter`, `shared_preferences` | `CrashReportingService().recordError` (unknown-severity drift report) | `core/constants/severity.dart` → `services/crash_reporting_service.dart`. **14 of the 29 engine files import severity.dart**, so this single import blocks almost everything. |
| Drift + `drift/native` + `dart:io` (FFI) | generated row classes `InteractionRow`, `UserStacksLocalData`, `ProductsCoreData`, `ResearchPairRow`; concrete `InteractionDatabase` parameter | `stack_interaction_checker.dart`, `research_pair_lookup.dart`, `medications/medication_class_bridge.dart`, `medications/medication_identity_status.dart`, `core/models/interaction_result.dart` (`fromRow`), `core/utils/product_canonical_ids.dart` |
| `flutter/services` (`rootBundle`) | reference JSON loading | `data/repositories/reference_data_repository.dart` (outside the engine; it is a provider dependency) |

Files with no blocker of their own, blocked only through `severity.dart`: all of `fit_score/*`, `warnings/*`,
and `stack/{depletion_checker,depletion_watch,recalled_ingredient_result,stack_nutrient_aggregator,stack_reminder_scheduler,stack_safety_scorer,stack_ul_checker,synergy_result,timing_evaluation_service,timing_guidance_builder}.dart`.

### Entry points (where the findings are assembled)

The engine has no single entry point. The orchestration lives inside Riverpod providers in
`lib/features/stack/providers/stack_safety_providers.dart`:

- `safetyCheckForAddProvider(dsldId)` ("check this product against my stack") runs
  `StackInteractionChecker.checkSupplementPairInteractions`, then `_normalizeMedicationRowsForSafety`
  (`MedicationClassBridge.resolve` + `MedicationIdentitySnapshot.fromStackRow`), then
  `checkMedicationInteractions`, then `checkSafety` (fingerprint heuristics). It dedupes by id and tracks
  `checksIncomplete`.
- `stackSafetyReportProvider` runs the same checks with every supplement pivoted as "new", plus
  `checkMedicationFoodAdvisories`, `checkMedicationPairInteractions`, `MedicationProfileGateEvaluator`,
  `TimingEvaluationService.evaluateStack` and `StackSafetyReport(...)`.
- `depletionReportProvider` runs `activateMedicationDepletionsArtifact` and then `DepletionChecker.check`.
- `_pairwiseDoseTotalsFor` turns the detail blob into `ProductHealthFacts` and then
  `StackDoseSummer.sum` (dose-dependent suppression).
- `StackInteractionChecker.checkMedicationInteractions` keys on medication rxcui, generic rxcui,
  ingredient rxcuis and class ids, then looks up `db.lookupByCanonicalId(newId)`, prefers drug rules over
  class rules, and maps through `InteractionResult.fromRow`.

The pure helpers that the providers use, `canonicalIdsForProduct` and `parseFingerprint` in
`stack_provider_helpers.dart`, import no Riverpod code. The spike imports them directly.

## 2. Minimal server-side data-access interface

These are all the methods the engine closure calls on `InteractionDatabase`. Each one reproduces the
existing SQL predicate, as `tool/engine_spike/shims/overlay/data/database/interaction_database.dart` does:

```dart
abstract interface class InteractionRuleSource {
  // retired_at IS NULL AND (lower(agent1_canonical_id)=? OR lower(agent2_canonical_id)=?)
  Future<List<InteractionRow>> lookupByCanonicalId(String canonicalId);
  Future<List<InteractionRow>> lookupByRxcui(String rxcui);           // agent_type='drug'
  Future<List<InteractionRow>> lookupByDrugClass(String classId);     // class-as-agent OR class tag
  Future<List<InteractionRow>> lookupPair(String a1Id, String a1Type, String a2Id, String a2Type);
  Future<List<String>> rxcuisForDrugClass(String classId);            // drug_class_map
  Future<List<String>> drugClassesForRxcui(String rxcui);             // full drug_class_map scan, sorted
  Future<bool> isDrugClassExcluded(String classId, Iterable<String> rxcuis);
  // Tier-2 research evidence only (research_pair_lookup.dart), never safety:
  Future<List<ResearchPairRow>> lookupResearchPairsByCanonicalId(String id, {int limit = 20});
  Future<List<ResearchPairRow>> lookupResearchPairsByRxcui(String rxcui, {int limit = 20});
}
```

The engine also needs these inputs, which are not on this interface:

- **Product lookup by `dsld_id`.** Columns read: `product_name`, `key_ingredient_tags`,
  `ingredient_fingerprint`, `contains_{stimulants,sedatives,blood_thinners}`, `mapped_coverage`.
- **Detail blob by `dsld_id`.** Only needed for dose totals and UL checks (`ProductHealthFacts.fromDetailBlob`).
- **Stack rows.** Fields: `type`, `name`, `dsld_id`, `ingredient_keys`, `rxcui`, `generic_rxcui`,
  `ingredient_rxcuis`, `drug_classes`.
- **Reference JSON** from `assets/reference_data/`: `medication_depletions` (via
  `activateMedicationDepletionsArtifact`), `medication_profile_gate_rules`, `timing_rules`,
  `rda_optimal_uls`, `synergy_cluster`, `banned_recalled_ingredients`, `user_goals_to_clusters`,
  `clinical_risk_taxonomy`.
- **`profile_warning_rules`.** Read by providers through `lookupProfileWarningRules`, not by the engine closure.

**Data size.** The 25 MB SQLite file is almost entirely `research_pairs` (about 19.5 MB plus about 3 MB of
indexes, 31,768 rows), which the safety checks never read. The whole live safety ruleset is small:

- `interactions`: 132 live rows, 200 KB as JSON
- `drug_class_map`: 40 rows, 16 KB
- `profile_warning_rules`: 152 rows, about 1 MB
- reference JSON: 856 KB

That is about 2.1 MB in total, which fits the 20 MB edge bundle many times over. Research pairs should be
a server-side indexed query, not part of the bundle.

## 3. The spike (`tool/engine_spike/`)

The spike adds a compile-time overlay. Production code is not edited. `make_overlay.py` builds a
symlink farm of `lib/` in which only the following files are replaced:

- `data/database/{interaction,user,core}_database.dart`: plain row classes with the same fields and types
  as the Drift-generated classes, and a JSON-backed `InteractionDatabase` that implements the
  interface above
- `services/crash_reporting_service.dart`: collects drift reports instead of dropping them

It also writes a `package_config.json` that maps `flutter` to `shims/flutter`. That shim provides
`foundation.dart`, which re-exports `meta`, and `material.dart`, which provides `Color`. Every other
file compiled is the app's own source, through the symlinks.

Files in the spike:

- **`extract_fixtures.sh`**: uses `sqlite3 -json` to extract only the rows the fixture needs, in rowid
  order: 11 interaction rows, 40 `drug_class_map` rows and 3 `products_core` rows. It also extracts all
  132 live interaction rules for the benchmark. Medication depletions are read whole from
  `assets/reference_data/` (not copied).
- **`fixtures/stack.json`**: candidate Ginkgo Biloba (15699); stack Fish Oil 1,000 mg (12043), Odorless
  Garlic (12009) and warfarin (rxcui 11289, classes left empty so `MedicationClassBridge` resolves them);
  a minimal profile. The products are real catalog rows; there is no user data.
- **`lib/spike_runner.dart`**: line-for-line mirrors of `safetyCheckForAddProvider`,
  `_normalizeMedicationRowsForSafety` and `depletionReportProvider`, calling the real engine classes. It
  also runs a 10-item benchmark (7 supplements and 3 medications over all 132 live rules: the pre-add
  check, the O(n²) stack pivot, food advisories and depletion).
- **`bin/engine_spike.dart`**: entry point. Line 1 of its output is the canonical findings JSON from
  `lib/findings_codec.dart`; line 2 is `TIMING`.
- **`bin/closure_probe.dart`**: a compile-only probe that imports all 29 engine files.
- **`test/golden_parity_test.dart`**: the app-side golden check.
- **`build.sh`**: builds the overlay, runs the VM, compiles and runs exe and JS (Deno and Node), compiles
  the probe and checks parity.

**Findings on the fixture** (same on every runtime):

- Pre-add check, `checks_incomplete: true` (no detail blobs, so dose checks could not run):
  - `DSI_FISHOIL_GINKGO`: caution/probable
  - `DSI_WAR_GINKGO`: avoid/probable; the medication classes were resolved by the bridge to
    `class:anticoagulants` and `class:vitamin_k_antagonists`
  - `STACK_BT_1`: blood-thinner heuristic, avoid/established
- Depletion (status `loaded`): `DEP_ANTICOAGULANTS_VITAMINK`, vitamin K, significant/established.

## 4. Golden check

`flutter test tool/engine_spike/test/golden_parity_test.dart` runs the real `safetyCheckForAddProvider`
and `depletionReportProvider`. It uses a real Drift `InteractionDatabase` over a temporary copy of the
**full** bundled DB (not the fixture subset), the real reference repository, and the detail blob
overridden to null on both sides. It asserts deep equality with `golden/spike_findings.json`. **Result:
pass.** I also changed one value in the golden to check that the test fails on a mismatch: it does
("Some tests failed"), and the golden was restored afterwards. `build.sh` asserts that the exe, Deno and
Node outputs are byte-identical to the VM output, which is the golden.

**Not verified:**

- **Dose-dependent paths.** `StackDoseSummer` pairwise suppression, the UL and RDA checks and dose totals
  for depletion need detail blobs, and both sides ran with blob = null.
- **Code that compiled but never ran or was compared:** `FitScoreService`, `StackIntelligenceEngine`,
  `MedicationProfileGateEvaluator`, the profile gates, `TimingEvaluationService` and the stack-wide report
  assembly.
- **Fixture coverage.** There is only one fixture. Phase 4 asks for a fixed set of stacks and products.
- **dart2js numerics.** On JS, `1.0 is int` is true and `jsonEncode(1.0)` gives `1`. These did not affect
  this fixture, but they could affect dose and unit code. Blob-backed goldens must cover this before
  launch.
- **Supabase Edge Runtime.** Nothing was deployed. The JS was measured under the local Deno CLI and Node,
  not under the Supabase Edge Runtime.

## 5. Measurements (Apple Silicon, shared machine; ranges over two `build.sh` runs)

| Target | Artifact | Fixture run (cold) | 10-item stack, cold | 10-item stack, warm avg (200×) | Process CPU (user) | Max RSS |
|---|---|---|---|---|---|---|
| Dart VM (JIT) | — | 18–28 ms | 5.1–5.7 ms | 0.84–0.89 ms | — | — |
| AOT `dart compile exe` | 6.65 MB exe | 0.4–0.7 ms | 0.65–0.72 ms | 0.53–0.58 ms | 0.11 s | 26 MB |
| dart2js -O2 in **Deno 2.7.10** | 480 KB JS (104 KB gzip), of which ~338 KB is embedded fixture JSON | 9–17 ms | 3–7 ms | 0.9–1.25 ms | 0.31–0.37 s | 90 MB |
| dart2js -O2 in Node 18 | same | 9–22 ms | 7–25 ms | 1.2–2.0 ms | 0.47–0.62 s | 73–76 MB |

Fixture parse time (JSON decode of the rules and the 103 KB depletion file) was 4–9 ms in Deno and about
1–2 ms in AOT. In Deno, `performance.now()` is coarsened to 1 ms, so the sub-millisecond figures are
averages.

**Is the 2 s CPU cap credible?** Yes, by two to three orders of magnitude. The whole Deno process,
including runtime start-up and about 400 engine runs, used 0.31–0.37 s of CPU. One 10-item check is a
few milliseconds cold and about 1 ms warm. Parsing the full ~2.1 MB safety ruleset per isolate should
take tens of milliseconds; the spike measured only the 0.34 MB fixture subset. That estimate is an
assumption until it is measured on the real ruleset. Memory is well under the 256 MB limit.

## 6. Refactor needed so production builds without the overlay (estimate)

1. **`severity.dart`**: replace the direct `CrashReportingService` call with an injectable hook (for
   example a static `onUnknownSeverity` callback wired up in `main.dart`). 1 file plus the bootstrap.
   This unblocks 14 engine files.
2. **`@immutable`**: import it from `package:meta` instead of `flutter/foundation`. 8 files, mechanical.
3. **`StackTier.color`**: move the tier-to-`Color` mapping into the widget layer
   (`core/utils/stack_intelligence_helpers.dart` and the home and stack v2 screens use it). About 4 files.
4. **Data interface**: add `InteractionRuleSource` (section 2), have `InteractionDatabase` implement it,
   and retype the parameter in `StackInteractionChecker`, `MedicationClassBridge` and
   `ResearchPairLookup`. 1 new file and 4 edits.
5. **Row types.** The engine consumes Drift-generated row classes, whose libraries import
   `drift/native` and `dart:io`. There are two ways to fix this:
   - **(a) Cheaper.** Move each database's `NativeDatabase(File)` constructor into a native-only factory
     file, so the three database libraries become platform-neutral and the generated rows are reusable
     server-side. It touches 3 DB files and the constructor call sites; `InteractionDatabase` is used in
     9 lib and 25 test files, mostly `.memory()`. Drift core's dart2js size is unmeasured.
   - **(b) Cleaner.** Use plain engine value types with mappers at the app boundary. `ProductsCoreData`
     appears in 35 lib and 19 test files, and `UserStacksLocalData` in 13 lib and 11 test files.
   - Recommendation: do (a) now and (b) only if the bundle or coupling demands it.
6. **Extract the orchestration (largest piece, and the "one brain" piece).** Move the bodies of
   `safetyCheckForAddProvider`, `stackSafetyReportProvider`, `depletionReportProvider`,
   `_pairwiseDoseTotalsFor` and `_normalizeMedicationRowsForSafety` (about 600 lines of
   `stack_safety_providers.dart`) into pure functions in a new `lib/services/engine/` module. They should
   take the rule source, product lookup, blob lookup and reference data as inputs. The providers become
   thin adapters. Until this is done, a server would have to copy the provider logic, as the spike's
   `spike_runner.dart` does, and that copy is exactly the drift we must not ship.
7. **Reference data.** Split `ReferenceDataRepository` into pure parsers and a loader interface
   (`rootBundle` on the device; bundled JSON or Storage on the server).
8. **Pipeline export.** Publish the live safety ruleset (interactions, `drug_class_map`,
   `profile_warning_rules`) and the reference JSON as one versioned JSON artifact next to the catalog
   manifest. `research_pairs` stays a server-side query.

**Size:** roughly 20–25 `lib/` files touched, 2 new modules, one ~600-line move out of a provider file,
and constructor churn in tests. This is a rough estimate of 3–5 focused dev-days including golden
fixtures. It has not been validated.

## 7. Recommendation: edge-function JS vs native Dart service

| | dart2js in the Supabase edge function | AOT native service (container) |
|---|---|---|
| Fits the limits | yes: ~0.5 MB JS + ~2.1 MB rules ≪ 20 MB; ms-scale CPU ≪ 2 s; ~90 MB ≪ 256 MB | n/a (no edge limits) |
| Deployables | one (the MCP function already exists in the plan) | a second service: auth hop, cold starts, ops, cost |
| Research pairs (19.5 MB) | cannot bundle; needs a Postgres query or is left out | can open the full SQLite file with real Drift |
| Numerics | JS number semantics (int and double merge); needs blob-backed goldens | identical to the device VM |
| Measured | Deno CLI and Node only; not the Supabase Edge Runtime | exe measured locally; no container measured |

**Recommend dart2js in the personal-MCP edge function**, with these conditions:

- TypeScript is only transport: auth, MCP tool schema, and JSON in and out.
- The engine is exposed through a `dart:js_interop` export, for example `globalThis.pgCheck(json)`.
  The spike runs `main()` only and did not build this.
- Golden fixtures run on the VM and on JS in CI.

**Fall back to the AOT service** if the Supabase Edge Runtime mishandles the dart2js output, or if the
assistant must serve research-pair evidence from the full SQLite file.

## 8. Draft ADR-010 (for the integrator; not appended to `knowledge/architecture-decisions.md`)

> **ADR-010: One engine, server-side via dart2js in the edge function (native Dart as fallback)**
>
> **Status:** Proposed (spike evidence 2026-10-12, `docs/spikes/2026-10-12-engine-service-spike.md`).
>
> **Context:** Phase 4 ("check against my stack" for AI assistants) needs the same findings the app
> shows: interactions with their evidence levels, depletions, duplication and dose context. A
> TypeScript re-implementation would create a second safety brain. The spike showed that the unchanged
> Dart engine compiles to JS and to AOT. On a real-catalog fixture, the JS, AOT and VM outputs and the
> app's own provider path (over the full interaction DB) produced identical findings, at millisecond-scale
> CPU and a ~0.5 MB bundle. The 25 MB interaction DB is about 90% `research_pairs`. The safety ruleset is
> about 2.1 MB.
>
> **Decision:**
> 1. The engine stays in Dart in this repository. There are no TypeScript rules, ever.
> 2. Before any server use, `lib/` exposes a pure engine API:
>    - an `InteractionRuleSource` interface
>    - plain or platform-neutral row types
>    - orchestration extracted from the Riverpod providers into `lib/services/engine/`
>    - an injectable severity drift hook in place of the Sentry import
>    - `meta` in place of `flutter/foundation`
>
>    The app providers become thin adapters over that API.
> 3. The server build is `dart compile js` of that API, called from the personal-MCP edge function
>    through a `dart:js_interop` export. TypeScript handles only auth, MCP transport and JSON.
> 4. The pipeline publishes the live safety ruleset (interactions, `drug_class_map`,
>    `profile_warning_rules`) and the reference JSON as one versioned artifact. `research_pairs` is
>    served by an indexed server query or left out of assistant answers.
> 5. Release gate: golden fixtures covering a fixed set of stacks and products, including blob-backed
>    dose and UL cases, must produce identical findings on the VM and on JS in CI.
> 6. Fallback: if the edge runtime cannot run the JS within limits, the same API is built with
>    `dart compile exe` as a container service called by the MCP function. Its decision rules are the
>    same.
>
> **Consequences:** a one-time refactor (about 20–25 files) that also simplifies testing the app. JS
> numeric semantics become a tested surface. Rule and reference updates ship with the catalog version,
> not with function deploys. Completeness flags (`checks_incomplete`, unresolved identity, missing
> blobs) cross the API unchanged, so "no known concerns" is only emitted under the Phase 4 completeness
> rule.

## 9. Open questions

1. Does the Supabase Edge Runtime, as opposed to the Deno CLI, accept the dart2js output unchanged?
   What is its cold-start time with about 2.1 MB of rules?
2. Should research-pair evidence be part of assistant answers at all? If it should, does that mean a
   Postgres table plus a query, or the native fallback?
3. Where do detail blobs come from server-side? The dose and UL checks need them; the edge function can
   read the same Supabase blobs the app reads.
4. Seam 5: option (a), platform-neutral Drift libraries, or option (b), plain value types? The answer
   depends on how big Drift core is under dart2js, which was not measured.

## Reproduce

```bash
cp "/Users/seancheick/PharmaGuide ai/assets/db/interaction_db.sqlite" assets/db/   # gitignored
flutter pub get && make gen
python3 tool/engine_spike/test/build_harness_test.py
bash tool/engine_spike/build.sh
flutter test tool/engine_spike/test/golden_parity_test.dart
```

`analysis_options.yaml` excludes `tool/engine_spike/**`. The spike compiles against its own overlay
package config, so the app analyzer would otherwise report its overlay-only symbols.
Do not run `extract_fixtures.sh` during a parity recheck. Refreshing fixtures or accepting a new golden
is a separate reviewed data change; a passing build never updates the reviewed golden automatically.
