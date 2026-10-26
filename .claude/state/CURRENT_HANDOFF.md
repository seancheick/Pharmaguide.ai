# Current handoff — release verification closeout

Branch codex/release-verification-closeout from e7255417. Pipeline peer branch codex/collagen-review-attribution, candidate746cfa78 on CI. Preserve all actual assets and user DB; no import/publication performed.

Owner: scripts/import_catalog_artifact.sh — journal recovery, checksum-backed rollback, permanent target-local concurrency lock;18tests pass/1existing opt-in skip. Owner: scripts/verify_native_app.py — read-only installed binary/catalog/product identity;8tests pass. Owner: native_catalog_journey_test.dart + driver + existing search tiles — normal navigation, exact ID keys, retained host screenshots/metadata, unexpected post-startup error capture and fatal missed taps. Will NOT create a scorer, clinical registry or replacement release path.

Native normal app launch on owned iOS26.5 simulator7CDB670B-94FE-4B4A-A810-EAE42F50E832 reproduced original caffeine295048 old wording, visible source ID, score78 and dose limitation. Doctor captured app1.0.0+23 and catalog2026.10.22.012241. Wording fix89a35e8d is already on pipeline main; rebuilt caffeine output corrected but blocked before publication. No new scorer edit warranted.

Integration native-host-06 passed normal Home→search→exactlabel→Testing&Brand, including screenshots and equality with installed detail blob; does NOT establish delivery of new wording. Earlier runs failed harness navigation/visibility and are retained as failures. iOS26 UIKit tab control is not reliable under integration binding: complete onboarding through normal app/CUA first; normal tab interaction was verified separately. Host capture survives test cleanup; --keep-app-running preserves owned state.

Cold fresh-agent expected-new-wording check finished: ordinary navigation and installed-data parity pass, expected corrected sentence fails as intended against old catalog. Evidence fresh-eval-01/RESULT.md. Full analyze has no issues;61search/pillar/offline owner-consumer tests pass. Import recovery18pass/1opt-in skip;doctor8pass. Integrated origin/main 38529c20 submission correction repair into the candidate; combined CI and merge remain. Source to build receipt was dirty and source snapshot retained; no delivered-fix claim. Evidence .claude/state/release_verification_20261026; bundle importer receipts .claude/state/bundle_recovery_20261026. No corpus or publication authorized in this batch.

## Integrated peer lane (preserved qualification)

# Current handoff — submission correction repair

Goal completed: repair independently reported sync/import, approved-submitter deletion, evidence, queue, client, and shared migration-history defects. Behavioral batch; no corpus generation, catalog publication or App Store release.

Owner: existing Supabase review transitions, approval history/evidence revisions; console uploadReviewerEvidence; ProductSubmissionSummary; pipeline materialize_approved_submissions and Storage upload/sync. Migration assembler extends the shared deployment stream. Evidence: report reproductions, matrix/glossary and named caller searches. Will NOT create another scoring, product identity, review engine, evidence store or points owner.

Integrated: app PR149 merge11b53739 (tested source4c477302); pipeline PR252 merge44f252ac (tested source738b1d2a). Exact source CI passed: app40362086808; pipeline40361539272 all four shards. Independent spec/adversarial review completed; accepted PR findings fixed. Suspected retake revision race ruled out by the existing helper's retained FOR UPDATE lock and a two-connection proof.

Verification: SQL137 including concurrency, Edge76, affected Flutter72 plus reviewer source17, clean analysis. Final importer/sync192 plus privacy-recovery3; adversarial12 and tamper probes. Final pipeline local546 passed24 declared opt-in skips. Full local Flutter check's six golden differences reproduce unchanged on e7255417; no affected widget/golden sources changed. CI's existing platform-sensitive golden exclusion remains. No bug-free claim.

Deployment: forward20261026160229 and separate historical stack-index restoration20261026164414 applied from the canonical pinned stream. All65 prior production ledger records and SQL remain byte-for-byte unchanged;67 canonical versions now match, empty dry run. Full disposable replay passes; live schema matches1017 distinct public definitions/access records, named column attributes and indexes. Historical physical column order is excluded. Deployment config and SQL hashes are verified.

Reviewer Edge version37 ACTIVE with JWT verification; all14 deployed source files exactly match merged files. Unauthenticated POST401; stale synthetic UUID rejected55000. No unrelated approval reopened. No missing current snapshots or invalid revision ordering.25 approvals,15 contribution entries150points and149 private submission/reviewer objects unchanged; approval/promotion, ledger, current catalog manifest and private Storage metadata hashes unchanged.

Advisors: existing security warnings/info unchanged. Performance adds one unused-index info for the restored existing active-stack index; other classes/counts unchanged. Existing reviewer-account provenance RESTRICT foreign keys remain; the approved-submitter deletion regression is fixed without weakening ordinary history immutability.

Recovery evidence: /Users/seancheick/.codex/submission-repair-* receipts/logs, including before/after migration history, business hashes, full replay, deployed function source and baseline golden evidence. Original dirty pipeline lane/private submissions preserved. Sean may run the updated pipeline later; corrected approvals wait for release until then.
