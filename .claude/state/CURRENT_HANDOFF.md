# Interaction audit — Stage 1 baseline done (2026-11-11)

Lane: branch `claude/interaction-baseline` in both repos (worktrees /Users/seancheick/worktrees/dsld-interaction-baseline
and /Users/seancheick/worktrees/app-interaction-baseline). Plan: /Users/seancheick/.claude/plans/i-recieved-this-feedback-sparkling-boot.md (approved).
Class: tests only + dated audit; no production behaviour change.

Pipeline 4ed305a08: `scripts/audits/interaction_audit_20261111/` (FINDINGS.md evidence ledger, baseline.py,
baseline.json pins, sample_ids.json) and `scripts/tests/test_interaction_baseline_reproductions.py`
(1 pass, 8 strict xfail; each xfail checked with --runxfail to fail on its own assertion).
App 5fef332b: `test/interaction_baseline/interaction_baseline_reproductions_test.dart` (5 reproductions seen RED,
then `skip`; controls pass; analyze clean).

Corrections to the audit: 79 unreachable sub-rules, not 81 (two SSRI sub-rules carry an authored `ssris` alias,
and the app matches `drug_classes_any`). New: SNRIs (venlafaxine 39786, duloxetine 72625) are in no class, so the
St. John's wort contraindication never reaches them and no curated pair covers them.
Not done: the ginkgo + warfarin conflict reproduction and the regenerated 18-pair conflict list (moved to Stage 3); no simulator run.

Owner Check: drug_classes.json / ingredient_interaction_rules.json / timing_rules.json / curated_interactions (data);
medication_class_bridge.dart::profileGateIdsForClasses, stack_safety_providers.dart::stackSafetyReportProvider and
_normalizeMedicationRowsForSafety (app). Will NOT create: severity, registry, status, second engine.
Next: Stage 2 (crosswalk exported from drug_classes.json, memberships with exclusions, Stack class-only delivery,
truthful completeness). Membership and hypoglycemic tiers need PharmD sign-off on the prepared content.

---

# Evidence V1 — current implementation and qualification

Sean approved ingredient-first, claim-independent, preparation-aware research within the existing scan/product page, six pillars and 20-point Evidence owner. Latest clarification expressly excludes a new discovery or sexual-wellness feature.

App branch `codex/evidence-v1-research-explanations`, PR222. Base current main82380682, commits99211ae9 and a692cd60. Only existing Evidence adapter and its test changed. Reads optional pipeline evidence_data.ingredient_research (ingredient, summary, studied_uses outcome/summary, applicability_note, references_structured). Authored research and citations render even without product clinical credit, never calculate score/Dose/safety. Authored research suppresses contradictory legacy ingredient strength subtitle; canonical pillar owns numeric presentation.

Validation: full make check on rebased main passed5560 tests/2skips before final 3-line subtitle correction;76 focused Evidence tests and final make analyze passed after that correction. Independent review retained. Native light/dark component harness on NEW owned simulator9E7E218C-27B8-406B-9824-E29030DA92EE verifies layout using real frozen candidate18343 blob, NOT ordinary startup/search or installed-catalog delivery. Earlier frames exposed contradictory legacy strong/4-studies attribution; final exact-blob four native frames now show canonical Limited10.4/20, two qualified studies, stress/sleep research and explicit limitations in light/dark. Runner exited0, root inspected light_research/dark_limitations; all strings readable with ordinary scrolling. This is component visual qualification only. The integration runner removed its temporary app; subsequent doctor reported no installed app, so no installed-catalog identity/delivery assertion is made. Temporary harness preserved privately, removed from app tree after use. Preserve other simulators/user data.

Pipeline branch `codex/evidence-v1-ashwagandha` in warning-contract-fixes/dsld_clean, PR433 candidatebdb7417c6. Owns generic ashwagandha V1 class inference, preparation conjunction/raw-note proof, qualified citation projection and consumer research. Historical signed brand decisions preserved, no new physician signature. GLN numerical HOLD, Dose, Formulation and safety unchanged. Fresh26 raw Clean/Enrich/Score/Blob comparison passed; five non-Evidence pillars and inspected safety/identity/amount/role structures unchanged. Only GNC18343 and Solgar201708 Evidence0->10.4, actual Core display61->72/61->71. Owner1498passed/1declaredartifactskip; local564passed/24declaredskips with strictguardgreen. Corrected production Blob-hash Core proof and performance review retained; controlled pipeline scorer median-sum+10.3%, memory+.2%, explained additional qualification work. Hosted exact-head checks pending before merge. Other scientific thread owns taurine/carnitine/rice/grape + finite-source review; will integrate ours and perform ONE combined nonpublishing census. Do not start a competing corpus/catalog rebuild.

Evidence /Users/seancheick/pg_quality/evidence-v1-20261110. Source qualification, code integration, installed-data parity, publication and observed scan delivery remain distinct. No release/publication performed.

## Previous completed Sentry and warning history

# Verified Sentry fixes integrated — November 8, 2026

User authorized pushing verified fixes to main and continuing four native hangs, verifying each before closure. App PR219 merged at e3fafa33; exact candidate ba0aa194 and merged main have identical Git tree b1281cbf. Hosted CI42558725508 passed analysis, tests, formatting and Merge readiness. Final local make check: analysis clean,5556 passed/2skipped; changed Dart formatting clean. No release, app distribution, catalog rebuild/import or publication.

Pipeline PR416 merged at48dd5d5b after all8whole-fast shards and Merge readiness passed; combined exporter owner261passed. Main already contained the approved dose_dependent->caution source correction through the concurrent warning-contract integration; PR416 retains direct regressions for caution, authored severity and non-US informational behavior. Unrelated original untracked product submissions untouched.

Main integration used managed worktrees because another session switched the shared primary checkouts and advanced main mid-turn. App merge conflict only in this handoff: retained current warning-reader qualification and Sentry records. Pipeline conflicts retained both new test groups. Earlier toast/FitScore/scanner and export severity source guards were already on current main. Read-only review found no blockers in the final source batches.

Review follow-up ba0aa194: real widget regression RED reproduced a reminder tap discarded while account teardown removed the router. Existing LaunchLinkBuffer now reattaches before teardown and during recovery; bootstrap drains only after current account DB and mounted router are ready. Initial unavailable-data state retains its pending location; no replay after delivery. Owner lib/main.dart::_releaseAccountConsumers/_onAccountChanged/_handoffLaunchLinks, existing startup buffer; no new persisted/synced state, provider, router or clinical logic.161focused bootstrap/router/notification/account tests pass; final full gate5556/2skipped. Review thread PRRT_kwDOR9b7S861H0pX resolved after verified fix.

Sentry current unresolved ONLY PHARMAGUIDE-2B,2D,2J,2W. No closures in this continuation. Full pagination independently reviewed43events (2B38,2D2,2J1,2W2): ALL iOS simulators1.0.0+23, no physical-phone events. User reports no current freeze. Current text profile exercises paragraph/glyph paths (root layout~157ms, paint~18ms, frame~230ms) without reproducing historical2-second hang. Matched system-binary UUIDs enable deeper Apple symbolication: representative2B CAtransaction/IOSurface attachment deserialize with raster idle; other2B tops vary.2W main Swift bridge/refresh-rate work concurrent with raster MTLSimDriver/MetalSerializer setup; unknown shared tail PCs remain unattributed. Low memory is a hypothesis, not proven cause/lock cycle.2D cold glyph bounds/FontParser scratch setup and2J Impeller Typeface first paint remain unverified causes.

Exact old artifact reproduction unavailable: temporary QA bundles are partial (no Info.plist/executable); retained old_build23.app has Sentry UUID591c57f3, mismatching original2D15c700c5 and2J623562e1. No old build launched with copied actual data. Next useful probe is repeated all-thread native samples plus loaded-image UUID/address maps during actual current-build recurrence, with host/simulator memory pressure and fresh-vs-long-lived comparison. Do not bulk-close, weaken hang capture or speculate an SDK/clinical fix.

Original PHARMAGUIDE-2X/2Z closures retained:2X was plain-SQLite build over encrypted iPhone data, recovered before this task with user confirmation and merged PR179 encryption support; today's real SQLCipher/account tests and isolated encrypted reopen validated it.2Z objective_c9.4.1 debug class enumeration reproduced by CPU profile; supported9.6.3 update removes it (directory lookup967->2samples, enumeration963->0), with code_assets2.2.0/native_toolchain_c0.19.6; sqlite3 remains3.8.0. No monitoring filter/assertion disabling/threshold change.

Final-source native check COMPLETE after user unlocked Mac: ordinary make run-ios rebuilt/started1.0.1/build23 on owned0CFED67B with normal defines and source identical to qualified ba0aa194 (merged main differs only in handoff docs). Normal UI changed only the isolated synthetic supplement reminder to11:47PM, then returned to Home. Explicitly terminated app; launch service absent, including immediately before notification tap. Actual system local reminder delivered11:47PM. CUA activated the notification primary button; observed cold launch directly to My stack with native Stack selected. Reviewed Home-before-termination, delivered-reminder and final Stack screenshots. Identity/catalog receipts, action record and launch log: /Users/seancheick/pg_quality/reminder-final-20261108. No provider/route override, original user-data change, physical-phone install or release. Shut down only owned simulator after evidence capture. Earlier Mac-lock blocker is cleared. This verifies reminder cold navigation; it does not verify causes of the four historical native hangs.

Evidence: /Users/seancheick/pg_quality/sentry-main-20261108 (remaining-event-audit.json, full events, remaining-investigation.md, Apple/all-thread symbolication, fail-first/handoff owner/full/hosted logs, PR merge and native identity receipts). Earlier evidence: sentry-six-20261108 and reminder-navigation-20261108. Historical sections below may describe superseded status; this section is current.

---

# Reminder notification tap — native verification complete

User unlocked Mac and authorized continuation. Normal app source a47e57ae verified on owned iOS 26.5 simulator 0CFED67B-8AB4-454F-B7F7-9E139A2EBF16, app 1.0.1/build 23. Ordinary UI added an isolated test item, saved daily reminder at 9:43 PM, enabled notifications via app settings. Actual generic reminder delivered to Notification Center; app explicitly terminated before tapping it. Native notification tap cold-launched directly to My stack with Stack selected. Reviewed screenshot: /Users/seancheick/pg_quality/reminder-navigation-20261108/native-cold-tap-stack.png. Native identity, launch log and action record in same directory. No provider override, route injection, physical-phone install, upload or deployment. Warm/app-running path and Android path covered by prior plugin/router tests; 5550 tests and analysis remain green, source unchanged. Mac-lock blocker resolved. Test fixture exists only in this owned signed-out simulator; preserve actual user data. Shut down only owned device after evidence capture.

---

# Pill-reminder tap routing — November 8, 2026

User reports tapping a take-a-pill reminder opens Home instead of Stack. Reported phone build not identified; source defect reproduced via real plugin MethodChannel response (expected /stack, actual null). Source a47e57ae fixes foreground/background response handling plus notification-launched startup. Existing queued payload stack-reminder unchanged; no rescheduling or user-data change needed. No deployment/publication.

Owner: LaunchLinkBuffer::attach/detach/openLocation, rootNavigatorKey, Routes.stack; existing three plugin initializers in stack_reminder_providers.dart, local_health_reminder_service.dart, notification_authorization_service.dart. Evidence rg onDidReceiveNotificationResponse/getNotificationAppLaunchDetails/payload/Routes.stack in lib: payload existed, all three initializers had no callback and no cold-launch reader. No existing notification navigation owner; new local_notification_navigation.dart registers one shared handler/settings, reusing the existing route buffer/router. Will NOT create another route queue/router, reminder store, persisted/synced field, clinical logic or payload containing health details. Existing authorization settings moved to the shared owner; no permission prompt added at boot.

Verification: fail-first reminder-navigation-red.log; 6 new iOS/Android tests cover warm route, startup buffering, terminated-app launch, subsequent initializer preservation (all three clients), no launch replay, unknown/null/non-reminder/action payloads. Focused six-file owner sweep 65 passed. Final named analysis clean. Full make check passed: analysis clean, 5550 passed / 2 skipped. Logs under /Users/seancheick/pg_quality/reminder-navigation-20261108 (red initial log also under sentry-20261108/reminder-navigation-red.log). Normal iOS source built on owned simulator 0CFED67B-8AB4-454F-B7F7-9E139A2EBF16, then hot restarted with the fix. Native notification tap verification blocked because Mac locked; user asked asynchronously to unlock. Do not claim actual OS tap/native acceptance until unlocked and tested. Runner stopped with q and only the owned simulator was shut down, preserving its data. Resume with make run-ios on that UUID after unlock. No new package, native-platform code or catalog changes.

Prior Sentry task still has 6 unresolved incidents; do not bulk-close them. History preserved below.

---

# Remaining Sentry fixes and verification — November 8, 2026

User requested all remaining 15 fixed and individually verified. Closed 10 after reproduction/native verification: 29 (missing PKCE verifier recovery; fb593c4d), 2K/2M/2P/2R (debug diagnostic Eval parser; ee9c6648 preserves original recorded stacks), 2N/2Q/2S (proven invalid VM-injected input incidents; normal native/standard driver verified), 2C (normal native startup/Home/search/detail journey), 2G (ordinary bootstrap provides real rules: schema 4.0.0 / 131 curated rows). Test additions cf2124ba protect real corrupt-file containment and 96edf709 checks native paired-rules provision. No clinical/score/catalog/sync changes, no publication or deployment. No monitoring disabled.

Verification: 230 focused owner tests pass; make check analysis clean, 5544 passed / 2 skipped. Standard and paired-rules native journeys pass with exit 0 and reviewed screenshots; targeted native-test analysis clean. Full source/dirty-test-only receipts and logs: /Users/seancheick/pg_quality/sentry-20261108/remaining-verification.md. Owner: app.dart::authStreamErrorResponse/_AuthEventListenerState; crash_reporting_service.dart::initialize/bootstrap; native_catalog_journey_test.dart::main. Evidence rg authStreamErrorResponse/_isExpiredOrUsedLink/demangleStackTrace/Eval/interactionDatabaseProvider in existing owners. Will NOT create a parallel auth/scoring owner, persist/sync fields, rewrite invalid inputs, erase corrupt data or suppress real hang reports.

Still open: 2X corrupt user DB (real unreadable-file test proves withholding and byte preservation, not restoration); 2B/2D/2J/2W native hangs (matched engine symbolication retained, root fix unverified). Newly observed 2Z startup hang on the fresh simulator also remains open. Uploaded matching Flutter engine and Runner native symbols to Sentry. Final count expected 6 unresolved including new 2Z. User asked for current reproduction/device asynchronously; no answer yet. Need a reproducible/native sampled workload and original affected-data context before safe repair/closure. No hang-causing dependency or upstream bug established; do not speculate or bulk-close.

Owned fresh simulator 0CFED67B-8AB4-454F-B7F7-9E139A2EBF16; historical inspection clone C7D48265-4FE7-4E51-80AE-3A8818E6EB61. Originals never launched/modified. Clone remains shutdown; contains copied stack data, so the old unsanitized app was not launched. Fresh device to be shut down after final identity capture; no devices erased/deleted.

---

# Sentry re-verification — November 8, 2026

The six source-fixed issues remain resolved. Closed 2F/2H as recovered historical service incidents after live production manifest HTTP 200 and public/authenticated current-catalog Range GET HTTP 206 with valid SQLite headers. No source repair or deployment claimed for these two incidents. Final live Sentry list: 15 unresolved; no newer occurrences since the previous inspection, which alone is not proof of repair. Other hangs/framework/native/provider/database/auth issues stay open. Evidence and exact remaining IDs: /Users/seancheick/pg_quality/sentry-20261108/TRIAGE.md and remaining-issues.json. No executable code changed or tests repeated in this verification pass.

---

# Warning contracts and Sentry source fixes — November 8, 2026

Goal: close verified warning-contract defects, preserve existing clinical policy and source attribution. Owner: `lib/services/warnings/warning_rule_ref_resolver.dart::_candidateSubentries/_subentryCopy/_resolvedWarning`; evidence: real212473 compact dose ref fails despite exact current threshold text. Pipeline companions: `build_final_db.py` citation projection, `enrich_supplements_v3.py::_collect_interaction_profile`, `export_schema.py` resolver. Will NOT create another warning owner, public field/status, threshold, grade inference or registry.

Implemented:273729f6 extends the existing reader to scope=None dose thresholds, preserves the /dose title and actual null optional action, retains source/evidence/applicability/dose decisions, and continues rejecting altered reviewed copy. Ten named resolver/schema bridge tests pass;42real-output/parser checks pass (including4fresh production dose warnings from the frozen11-product pipeline comparison). Focused analysis clean; independent read-only re-review clear. Pipeline source candidatefedca723b/docseb72a41d7 on main8d6bdab61: owner320passed; local564passed/24declared opt-in skips; all11cleaned/scored hashes exact, core values equal except volatile scored_date. Existing pipeline master-plan/LEDGER is the single execution register. Pipeline qualification PR414; paired app qualification is this branch, `codex/warning-contract-app-20261108`.

Existing Sentry source guards retained from baseline509acfea:473c68e1 toast-host lifetime,02b89f58 disposed FitScore ref,93203b53 scanner torch readiness. The primary Sentry lane owns live issue triage/resolution. Its last recorded6resolved/17open snapshot is historical, not re-queried here; database corruption and unexplained hangs remain unresolved. No repair/deletion of user_data.db or live Sentry status change in this lane.

Required combined app qualification: `PATH=/Users/seancheick/Development/flutter/bin:$PATH make check`; receipt `/Users/seancheick/pg_quality/warning-contract-app-check-final-20261108.log`. Final exact-source hosted CI results and PR links are retained by the pipeline integrator's CURRENT_HANDOFF and PR checks. First broad attempt was invalid: new checkout and generated test asset bundle held a133-byte LFS pointer. Verified the primary66MBcatalog SHA against the tracked LFS OID, hydrated only this checkout, cleared only generated unit_test_assets, then23affected release-gate tests passed; no source change, assertion weakening or missing-asset skip. Initial attempt is not a green checkpoint. Complete final combined check and hosted CI before integration.

Remaining delivery: both source branches require authorized main integration after green CI. Existing generated/bundled catalogs contain old warning copy. Select final integrated fingerprints before the existing nonpublishing rebuild and installed-app acceptance; no corpus build, catalog import, deployment, main merge or native delivery claimed. Preserve primary Sentry lane and all user data. Durable replay/source checksums and full deltas: `/Users/seancheick/pg_quality/warning-contract-20261108`.
