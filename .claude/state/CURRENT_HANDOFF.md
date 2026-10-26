# Current handoff — submission approval corrections

Goal: implement immutable approval revisions, audited reopen/reapprove, reviewer and submitter replacement evidence, conservative correction-state UI, and exact-revision release fences without changing scoring, clinical, product-identity, or contribution-point policy.

Lane: integrated by PR 148; feature commits `85e35c92` and `1c1ae32d` are contained in `main` merge `8fb31692`.

Owner: Supabase review transition RPCs and `product_submission_approved_labels`; console `setApprovedReadOnly`, `setDecisionAvailability`, and existing evidence workflow; Flutter `ProductSubmissionSummary`; evidence owner `product_submission_photos`/reviewer evidence RPCs. Evidence: `rg -n "product_submission_approved_labels|review_product_submission|setApprovedReadOnly|setDecisionAvailability|ProductSubmissionSummary|product_submission_photos" supabase scripts lib test`. Will NOT create: another review engine, identity owner, photo store, points rule, status enum, or scoring path.

Implemented: immutable numbered approval snapshots and backfill; fenced/idempotent reopen; seeded draft and fresh attestation requirement; reviewer replacement photos in the existing evidence revision/store; pending-upload recovery; purged-evidence block; correction-state Flutter copy; exact atomic publication RPC; one-time points preservation; explicit function revokes/grants.

Verification and deployment:
- Submission SQL harness with advisors: 131 tests pass, concurrency checks pass, no security/performance advisor findings.
- Reviewer Edge Function: 74 Deno tests pass.
- Affected Flutter suites: 87 tests pass; `make analyze` has no issues.
- Full `make check` reached six unrelated tiny golden-image diffs; all six reproduce on clean `main` at `f1e12a77`, and this branch changes none of those widgets or goldens. Exact-candidate CI remains the environment gate.
- Deno/Dart formatting, shell syntax, and `git diff --check`: pass.
- Independent adversarial review completed; accepted findings fixed for audit immutability, evidence retention/recovery/provenance, competing upload keys, global catalog-version uniqueness, release races, stale fences, and duplicate points.
- Exact-candidate app CI passed before merge. Pipeline PR 251 passed its final four-shard CI after the cross-repository contract was integrated.
- Migration `20261026132208_submission_approval_revisions.sql` is deployed and recorded under the repository version; `review-product-submissions` version 36 is ACTIVE with JWT verification enabled.
- Post-deploy backfill, grants, immutable triggers, contribution totals, unauthenticated 401, and stale-revision refusal checks passed. Production advisors report existing warning/info classes; the new authenticated reviewer entry points keep explicit reviewer checks, while release fences remain service-role only.

Next: Sean may run the updated product pipeline when ready. Until then, newer corrected approvals remain awaiting release. No app release or catalog publication was performed in this batch.
