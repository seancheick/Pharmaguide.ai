# Profile and Stack safety follow-up — November 3, 2026

Goal: close the confirmed unread-profile, class-only medication and ordinary supplement profile/allergen gaps. Source qualification only; no catalog/app publication or device claim.

## Integrated source

PR196 is merged at16f897819a8c0d561c7f0db7593aa9ce0ec76059; exact candidate581b82a7 passed hosted run41759115849 (Analyze & Test and Merge readiness). Its old branch is removed. Main privacy PR179 at1aeefc9b is integrated here by b75d128f. This branch is codex/profile-stack-safety; root owns push/qualification. Other active Claude worktrees were not modified.

- d0e994d5: bundled-map-verified class-only medications reach existing profile warning rules; identity-bearing membership/exclusions retain precedence.
- c3e14bd2: Stack reuses Product Detail composition, schema-3 resolution, profile gating and allergen matching; readable static findings survive a failed rule reference. Cumulative dose/UL/regulatory owners remain separate. Informational facility findings remain informational.
- 0f50ea24: failed DB initialization/read or malformed stored profile lists remain unavailable; unread baseline cannot be overwritten. Existing readiness providers permit explicit retry; both editors share their gate. Compatible mixed lists remain accepted.
- 4a70ed3f: shared actionableSignals getter corrects Home/Stack review counts while full signals remain in Good to know details. Existing banner presentation is preserved.
- 12f93ff4: medication entry displays every existing applicable warning. Test assets are cleared per widget test to prevent cached futures crossing fake-async zones; original identity-race assertions remain unchanged.

## Owner check

Owner: profile_provider.dart::ProfileNotifier/load readiness; medication_class_bridge.dart::resolve/profileGateIdsForClasses; product_detail/v2/warnings_pipeline.dart::composeGuardedWarnings/partitionProfileWarnings; profile_warning_rule_provider.dart; allergen_match.dart::matchAllergens; stack_dose_summer.dart::stackDoseThresholdRulesFromWarnings; stack_safety_providers.dart::stackSafetyReportProvider; stack_intelligence_engine.dart::StackHealthSnapshot. Evidence: direct owner/caller reads, rg, pipeline matrix and glossary. Will NOT create a second clinical evaluator, clinical registry, exported field, persisted verdict, guessed class, or scoring policy.

## Verification

Behavioral class. Fail-first receipts in /Users/seancheick/pg_quality/codex_takeover_20261103/: profile read/save/init and malformed-list regressions, offline bridge/entry/saved-stack failures, Stack frozen SJW/allergen failures, and two informational-count widget failures.

Focused green: profile six-file76; offline entry11 plus bridge/crosswalk/saved-stack/identity owner cases; Stack/Product Detail/cumulative/Home five-file148. Follow-up actionable slice passed Home/Stack and ordinary warning cases; three banner compatibility failures were resolved by restoring the unchanged contextual banner, then banner28 passed. Scoped analysis clean. Independent review findings resolved; no device/catalog clinical accuracy claim. Integrated named profile/medication/Stack slice:88 passed; full Flutter analysis:no issues, both on b75d128f; durable logs PROFILE_STACK_INTEGRATED_GREEN.log and PROFILE_STACK_ANALYZE.log hold final receipts. Hosted PR checks are authoritative for exact candidate CI; do not infer green from this handoff.

## Next unchecked items / integration

1. Root pushes completed candidate and waits for required hosted CI; fix any actual failures using named nodes. Follow-up PR is not release authorization.
2. A4 label-warning integration MUST retain this broader shared Stack pass instead of adding its narrow section1b/_labelStatementResult beside it. Keep A4's separate taxonomy/sex and label-export work. LABEL product/text identities match its candidate, and regression preserves one verbatim printed statement. Male-TTC/applicability remains A4's paired contract work.
3. Release still needs unfinished pipeline dose/identity and completion/Evidence work, paired app consumers, label warnings, signed feed and clinical/release approvals, then Sean's final catalog build and combined app/device validation. Evidence policy is committed via pipeline PR346; it is not implemented by this app fix. Recheck live PR/plan state before asserting remaining blockers.
