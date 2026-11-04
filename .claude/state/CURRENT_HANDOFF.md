# Profile and Stack safety — PR199 current handoff

Goal: preserve honest incomplete checks without hiding independently known findings. Branch codex/profile-stack-safety; root integrates/pushes. Other Claude worktrees remain untouched. Source qualification only; no catalog publication, signed build or installed-device claim.

## Current source

PR196 merged16f89781 after green required checks. Main privacy PR179 at1aeefc9b is integrated. PR199 baseline56c89a92 passed full hosted CI41764670580; the following review corrections require CI on the new tip, so the old green is not its qualification:

- c48d553f: transport failures are not cached as successful empty medication lookup results; successful empty responses still cache. Partial class endpoint failure retries.
- 785ff73f: optional dose/schedule edits no longer cancel medication identity hydration and strand Save. Existing dose confirmation invalidation/stale-identity guards remain; each visible warning shows its canonical evidence label.
- 642c108f: unread profile is nullable/unavailable, never an invented empty profile. Independent interactions/food advisories/timing survive; dose-check failure cannot discard the snapshot's known interactions and catalog recall. The snapshot remains incomplete. Missing flags/classes skip only rules whose requires/excludes need those inputs; readable condition-only warnings survive. Both Home and Stack can retry the canonical profile load, including pull-to-refresh, without discarding a healthy loaded profile. Distinct visible warning headlines retain distinct signal identities.

Earlier PR199 fixes remain: class-only entries validated through bundled medication map; all applicable entry warnings shown; DB read/init/malformed-profile failures block unread saves and expose retry in both editors; shared Product Detail composition/schema3 resolution/allergen matching in Stack; cumulative dose/UL/regulatory owners retained; actionable Home/Stack counts exclude informational notes while Good to know and existing banner presentation remain available.

## Owner check

Owner: profile_provider.dart::ProfileNotifier/readiness and profile_load_gate.dart::retryProfileLoad; medication_entry_v2_screen.dart identity/context generation; rxnorm_api_service.dart lookup caches; medication_class_bridge.dart::resolve; warnings_pipeline.dart::composeGuardedWarnings/partitionProfileWarnings; profile_warning_rule_provider.dart; allergen_match.dart::matchAllergens; stack_dose_summer.dart::stackDoseThresholdRulesFromWarnings; stack_safety_providers.dart::stackSafetyReportProvider/stackHealthSnapshotProvider. Evidence: direct reads/rg plus pipeline matrix/glossary. Will NOT create a second clinical evaluator, new registry, persisted status, exported field, guessed medication class or scoring policy.

## Verification

Behavioral class. Review follow-up fail-first receipts: PROFILE_PARTIAL_RED.log (profile failure erased report), PROFILE_REVIEW_EDGES_RED.log (5 missing-input/identity/retry failures), MED_LOOKUP_RED.log and MED_SCHEDULE_RED.log (lookup/edit/evidence cases; initial schedule tap corrected before valid RED). All under /Users/seancheick/pg_quality/codex_takeover_20261103/.

Current focused green:72 safety/profile/Home/Stack/cumulative tests (PROFILE_PARTIAL_GREEN.log);46 medication owner/entry tests (MED_LOOKUP_GREEN.log). Full Flutter analysis clean (PROFILE_PARTIAL_ANALYZE.log). Independent final review found no remaining concrete defect. Formatting/diff checks clean. Prior integrated88 and earlier76/148/28/11 receipts cover initial source, not a substitute for new-tip CI. No device reproduction claimed.

## Next / integration

1. Push new completed tip and inspect required CI; fix actual failures with named nodes. PR199 is not release authorization. Required CI and review-thread status on GitHub are authoritative, not a stale green in this file.
2. A4 label-warning integration must retain this broader shared Stack pass instead of adding its narrow section1b/_labelStatementResult beside it. Keep A4's paired taxonomy/sex/export work. LABEL product/text identity matches its candidate; verbatim statement dedup regression passes. Male-TTC applicability remains the paired A4 rollout.
3. Release still needs remaining dose/identity/completion/Evidence and label-warning integration, signed feed/catalog delivery, final fingerprint-bound clinical receipts and release gates. Sean owns the final catalog run, followed by combined candidate/device validation and a signed TestFlight build. Recheck live plan/PR state before asserting unresolved decisions. Evidence policy is committed through pipeline346; this app PR does not implement scoring calibration.
