# Current handoff — submission approval corrections

Goal: implement immutable approval revisions, audited reopen/reapprove, reviewer and submitter replacement evidence, conservative correction-state UI, and exact-revision release fences without changing scoring, clinical, product-identity, or contribution-point policy.

Lane: `codex/submission-approval-revisions`, based on freshly fetched `origin/main` at `f1e12a77`. The primary checkout remains untouched.

Owner: Supabase review transition RPCs and `product_submission_approved_labels`; console `setApprovedReadOnly`, `setDecisionAvailability`, and existing evidence workflow; Flutter `ProductSubmissionSummary`; evidence owner `product_submission_photos`/reviewer evidence RPCs. Evidence: `rg -n "product_submission_approved_labels|review_product_submission|setApprovedReadOnly|setDecisionAvailability|ProductSubmissionSummary|product_submission_photos" supabase scripts lib test`. Will NOT create: another review engine, identity owner, photo store, points rule, status enum, or scoring path.

Implemented: immutable numbered approval snapshots and backfill; fenced/idempotent reopen; seeded draft and fresh attestation requirement; reviewer replacement photos in the existing evidence revision/store; pending-upload recovery; purged-evidence block; correction-state Flutter copy; exact atomic publication RPC; one-time points preservation; explicit function revokes/grants.

Verification on candidate:
- Submission SQL harness with advisors: 131 tests pass, concurrency checks pass, no security/performance advisor findings.
- Reviewer Edge Function: 74 Deno tests pass.
- Affected Flutter suites: 87 tests pass; `make analyze` has no issues.
- Full `make check` reached six unrelated tiny golden-image diffs; all six reproduce on clean `main` at `f1e12a77`, and this branch changes none of those widgets or goldens. Exact-candidate CI remains the environment gate.
- Deno/Dart formatting, shell syntax, and `git diff --check`: pass.
- Independent adversarial review completed; accepted findings fixed for audit immutability, evidence retention/recovery/provenance, competing upload keys, global catalog-version uniqueness, release races, stale fences, and duplicate points.

Next: fetch/rebase if main moved, commit, push, exact-candidate CI, merge, verify containment, then deploy this migration before `review-product-submissions` and run post-deploy probes. No app release or catalog publication.
