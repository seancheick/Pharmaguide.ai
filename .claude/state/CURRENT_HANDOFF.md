# Current handoff — submission correction repair

Goal completed: repair independently reported sync/import, approved-submitter deletion, evidence, queue, client, and shared migration-history defects. Behavioral batch; no corpus generation, catalog publication or App Store release.

Owner: existing Supabase review transitions, approval history/evidence revisions; console uploadReviewerEvidence; ProductSubmissionSummary; pipeline materialize_approved_submissions and Storage upload/sync. Migration assembler extends the shared deployment stream. Evidence: report reproductions, matrix/glossary and named caller searches. Will NOT create another scoring, product identity, review engine, evidence store or points owner.

Integrated: app PR149 merge11b53739 (tested source4c477302); pipeline PR252 merge44f252ac (tested source738b1d2a). Exact source CI passed: app40362086808; pipeline40361539272 all four shards. Independent spec/adversarial review completed; accepted PR findings fixed. Suspected retake revision race ruled out by the existing helper's retained FOR UPDATE lock and a two-connection proof.

Verification: SQL137 including concurrency, Edge76, affected Flutter72 plus reviewer source17, clean analysis. Final importer/sync192 plus privacy-recovery3; adversarial12 and tamper probes. Final pipeline local546 passed24 declared opt-in skips. Full local Flutter check's six golden differences reproduce unchanged on e7255417; no affected widget/golden sources changed. CI's existing platform-sensitive golden exclusion remains. No bug-free claim.

Deployment: forward20261026160229 and separate historical stack-index restoration20261026164414 applied from the canonical pinned stream. All65 prior production ledger records and SQL remain byte-for-byte unchanged;67 canonical versions now match, empty dry run. Full disposable replay passes; live schema matches1017 distinct public definitions/access records, named column attributes and indexes. Historical physical column order is excluded. Deployment config and SQL hashes are verified.

Reviewer Edge version37 ACTIVE with JWT verification; all14 deployed source files exactly match merged files. Unauthenticated POST401; stale synthetic UUID rejected55000. No unrelated approval reopened. No missing current snapshots or invalid revision ordering.25 approvals,15 contribution entries150points and149 private submission/reviewer objects unchanged; approval/promotion, ledger, current catalog manifest and private Storage metadata hashes unchanged.

Advisors: existing security warnings/info unchanged. Performance adds one unused-index info for the restored existing active-stack index; other classes/counts unchanged. Existing reviewer-account provenance RESTRICT foreign keys remain; the approved-submitter deletion regression is fixed without weakening ordinary history immutability.

Recovery evidence: /Users/seancheick/.codex/submission-repair-* receipts/logs, including before/after migration history, business hashes, full replay, deployed function source and baseline golden evidence. Original dirty pipeline lane/private submissions preserved. Sean may run the updated pipeline later; corrected approvals wait for release until then.
