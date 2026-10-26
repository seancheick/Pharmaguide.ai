# Native feature map

This map describes reachable behaviors and their evidence, not independent medical
rules. Expected values come from reviewed canonical outputs. Coverage is per run.

| Journey | Normal route and control | Proof and reset | Existing owner/tests |
|---|---|---|---|
| Exact product and explanation | Home → Search supplements → exact `search-product-ID` tile → Testing & Brand | Native journey receipt + home/search/detail screenshots; exact catalog/ID/hash/reason. Leave product via Back. | `integration_test/native_catalog_journey_test.dart`; `detail_blob_provider.dart`, `v4_pillars.dart` |
| Profile-specific warning | Profile → edit relevant test profile → reopen exact product | Record before/after profile action and source-authored warning; negative control from reviewed fixture. Restore only the profile created for this test. Never edit the operator's profile. | `ProductHealthFacts`, existing profile/warning widget and engine tests; not automated by the first native journey |
| Stack changes | Product → Add to my stack → Stack → remove newly added item | Observe updated existing engine result and counts, then restore added test state. Record any amount prompt; never infer a dose. | stack providers and existing interaction tests; separate native execution required |
| Missing/offline detail | Open an uncached declared detail while connectivity is unavailable | Must show unavailable/limited assessment, not no-known-concerns inferred from absence. Offline harness tests are boundary evidence, not native offline proof. | `test/data/supabase/detail_blob_offline_test.dart`, detail blob provider/service |
| Catalog delivery | Run authorized existing import/update → relaunch → search exact ID again | Compare pre/post installed version and detail hash, correct explanation and preserved user state. Publication requires pipeline release gates; doctor does not install data. | catalog swap/updater tests, `scripts/import_catalog_artifact.sh`, `make verify-bundle` |
| Submission history | Profile → contribution history → exact submission | Correct existing review state and identity, no fabricated approval. Do not send a live submission solely for a smoke test. | `integration_test/contribution_history_test.dart` uses fixture providers and is explicitly narrower than ordinary app delivery |

A marketing screenshot, fixture widget or direct route launch cannot close the
ordinary startup/navigation journey. A blocked release can still have tested UI
components; record staged/installed/live evidence separately.
