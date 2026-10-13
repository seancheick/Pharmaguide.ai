# mcp-personal

**Production personal access is disabled in this candidate until S2 is repaired.** Every personal MCP request returns 503, including requests with previously issued tokens; protected-resource discovery metadata remains available. Snapshot POST uploads also return 503, while authenticated DELETE/purge stays available. These changes are local, not deployed.

The dependency-injected implementation has two read-only tools for synthetic testing:

- `get_my_supplements`: the supplement names, PharmaGuide product ids and ingredient keys already synced by the user. Medications, conditions and doses are excluded.
- `get_my_stack_snapshot`: the scoped brief explicitly shared to this connection from the phone, decrypted with `AI_SHARE_SNAPSHOT_KEY_V<n>`. This tool needs an active connection and its own consented snapshot; it does not imply consent to other health data.

The dormant implementation verifies the OAuth token, resolves the existing `ai_connections` owner, validates the live Supabase Auth session, and applies the connection's scope and rate limit. Database access uses the server key, filtered by the verified user; assistant tokens are never forwarded to PostgREST. See `docs/security/ai-connector-threat-model.md`.

## Audit status — October 13, 2026

The audit candidate is implemented and verified locally; these fixes are not deployed. The full Deno suite passed 214 tests and the disposable PostgreSQL suite passed. The full app check passed analysis and 3,901 tests before the final verified-client/expiry display corrections; their affected suites passed 17 tests and focused analysis. Final runtime source `015a43fe` passed CI `38441160359`: 3,858 CI-scoped Flutter tests, 214 Deno tests, analysis, harness and formatting. Bundle assets were available; the existing CI profile excludes golden-tagged cases. Documentation-only closeout reuses this source checkpoint. Local tests do not establish live OAuth readiness.

**S2 remains an open release blocker.** The former token hook stamped the personal MCP audience on OAuth tokens. Requiring that audience rejects a deliberately wrong-audience test token, but does not prove that a token originally requested for another resource cannot receive the stamped audience. The forward containment migration now refuses all third-party token issuance and refresh through the existing hook. Ordinary app sessions are unchanged. This contains exposure; it does not implement resource binding. The real authorization-server attack test, including refresh, remains required. Do not connect real health data or describe personal sharing as release-ready while this is unresolved.

S6's accepted phone-pairing requirement and S9's privacy/policy review also remain open. The first real Claude/ChatGPT connection, actual callback configuration, consent, snapshot retrieval, disconnect and expiry still need recorded live verification.

## Required live gates

| Requirement | Automated coverage | Live acceptance still required |
|---|---|---|
| S1 Database isolation | `auth_isolation_test.ts`; `scripts/test_ai_connector_rls.sh` | A real OAuth token cannot read PostgREST tables, private Storage or privileged RPCs, or call app-only functions. |
| S2 Resource binding | `resource_binding_test.ts` verifies production 503 and metadata; SQL hook cases verify denied issuance/refresh with unchanged app sessions | Request a token for another resource from the actual AS and replay it here, including after refresh. It must be rejected. Current hook tests do not prove this. |
| S3 Client identity | Website `tests/ai-connector.test.cjs` | Pre-register actual client ids and exact callback URIs. Checked-in DCR is off under ADR-009; the audit observed live DCR still enabled, and has not changed it. Verify rejected clients and callback mismatches. |
| S5 Revocation | `revocation_purge_test.ts`; app sign-out tests; SQL suite | Disconnect, then reuse the same unexpired token: access denied; refresh also fails. Offline app sign-out is best-effort and can leave an existing snapshot until later deletion or expiry. |
| S10 Session and grant ownership | `grant_authorization_test.ts`; SQL session matrix | A refreshed older session cannot bind a newer consent; deleted Auth sessions fail; wrong user/client/scope cannot read a connection or snapshot. |

## Deployment order for the reviewed candidate

Containment deployment requires the applicable approval and leaves the personal connector disabled. Enabling personal access additionally requires closed release gates and a reviewed issuer repair; this is an order of operations, not evidence that deployment has happened.

1. Apply pending connector migrations in timestamp order, including prerequisites, `20261013165631_ai_connection_session_binding.sql`, and `20261013171928_ai_connector_deny_unbound_oauth.sql`. The session RPC must exist before the updated personal function is deployed; absent RPC fails closed. It validates Auth session existence, user, client, original creation time and expiry against the active connection.
2. Verify the existing Auth custom-access-token hook remains enabled. Third-party issuance and refresh must fail; ordinary app sign-in/refresh must still work. Apply checked-in production DCR=false. The audit did not change live configuration.
3. Deploy both contained functions: `mcp-personal` denies every personal read, including old tokens; `ai-share-snapshot` denies new uploads and preserves authenticated deletion. A hook change alone does not stop already-issued tokens. Preserve configured audience, signing keys and snapshot keys; do not remove containment without a reviewed issuer repair.
4. Deploy the coordinated website approval route. It must insert the consent row before Supabase Auth approves the authorization, so the resulting session is created at or after consent. The browser must not independently approve the same authorization. Actual connection attempts remain disabled by the hook.
5. Keep the coordinated app/function contract ready for a later reviewed re-enable. Snapshot POST requires `generated_at`, the report's actual collection time in UTC; older app builds without it are rejected. Lifetime starts at upload acceptance, without replacing generation time. Future device timestamps are rejected; the app directs users to check date/time and refresh the preview.
6. After the issuer is repaired and containment is deliberately replaced in a reviewed candidate, run the live gates above on deployed test versions and record the receipts before enabling personal access. Configure trusted clients from their actual setup flow and verify callback values. Current production factory tests must continue to prove containment until then.

The `stale` flag checks synchronized supplement changes, including removals, after the report's generation time. It cannot detect unsynced phone changes or later medication/profile edits that never reached the server. `stale: false` is not proof that the user's current health information is unchanged. A snapshot is a dated report, not a live safety check.

## Local commands

```bash
deno test --allow-read --allow-env supabase/functions
scripts/test_ai_connector_rls.sh
supabase functions serve mcp-personal --env-file <local environment file>
```

Deno tests sign fixture tokens with an ephemeral RSA key and use injected repositories. The SQL suite uses a disposable Docker database and accepts no remote database URL. Rate limits and catalog caches are per function instance, not global. Never put real keys or health payloads in test logs.
