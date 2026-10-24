# Personal connector activation readiness — October 23, 2026

Goal: complete hosted two-account isolation, S9 review and production WorkOS setup using existing owners. Public personal reads/uploads remain disabled until all acceptance gates pass. User requested completion and fixes; prior merge authority remains for this task's validated changes.

Owner: existing mcp-personal index/verifier/PostgREST repositories, SQL pairing/revocation/snapshot owners, website privacy/consent owners. Evidence: source matrix and existing callers/tests/harness. Will NOT create a second auth issuer, clinical owner, sync path or snapshot contract.

Baseline: app main449cc250 (PR137 merged), website main198305c (PR9 merged). Exact premerge candidates passed CI; app postmerge CI40054043114 passed. Other pipeline and primary website lanes contain unrelated work and must be preserved.

Ownership: workos_database handles hosted disposable two-account tests and sanitized receipts; pairing_flutter handles default-disabled production WorkOS runtime composition in existing MCP owner; workos_website handles S9 official-source policy review and accurate website privacy disclosure. Parent integrates, owns this handoff/threat model and WorkOS dashboard setup. Branch codex/personal-production-readiness.

Current evidence: prior realphone/Codex saved scopes, automatic updates/optout, unexpired access rejection, old refresh rejection, snapshot purge, browser return and root navigation passed. Current fresh grant is disconnected. No public activation.

Blocker: WorkOS Production environment opens Add billing information dialog; user asked to complete financial details directly. Production config cannot be asserted until readback. User is adding billing directly.

Next: finish bounded tests and source corrections, run exactcandidate checks/review/CI, configure production without health-access activation, record genuinely external policy/billing gates. Do not claim legal certification or client-wide compatibility from Codex-only evidence.

Completed this batch: hosted two-account isolation26checks, realWorkOS-staging/account-deletion19checks with providerfailure/retry and zero fixture rows; exact hosted migration20261024023658 applied after explicit approval. Existing revocation barrier now covers account deletion. Website pre/post-complete guards and exact-identity compensation prevent redirect on concurrent deletion; ambiguous provider timeouts remain explicit operator reconciliation cases. Runtime WorkOS factory/default503, fixedCodex callback/config, app provider-training/Privacy notice and18+ approval copy are prepared. Website Privacy/Terms truthful18+ directconsumer scope and current-source S9 review prepared. No new auth/sync/clinical owner.

Checks: combined97Deno passed after correcting obsolete direct-delete source assertion to require atomicrevocation/tombstones/providerdelete/authdelete order; full disposableSQL and2Dart deletion contracts passed;47Flutter consent/connection tests and focusedanalysis/rendering passed; website58connector+11privacy tests/typecheck/lint/diffcheck passed. Parent reviewed runtime/deletion/migration and route guard; no remaining observed source blocker. Exactcandidate CI pending new PRs. Public production personal handlers still503; existingrealgrant revoked and testfixtures cleaned.

Next: PR/CI/integration; verifyproductionbilling, set exactissuer/resource/pre-registeredCodexclient and server-only productionkey, deploy tested contained factories and coordinatedsite, run controlledproductionOAuth acceptance without broadpersonal activation. Don't mark production setup complete or S9 operational disclosure publication complete until actualreadback/deployment.
