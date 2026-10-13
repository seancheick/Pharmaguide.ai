# mcp-personal

The personal PharmaGuide MCP server has two read-only tools:

- `get_my_supplements`: the supplement names, PharmaGuide product ids and ingredient keys already synced by the user. Medications, conditions and doses are excluded.
- `get_my_stack_snapshot`: the scoped brief explicitly shared to this connection from the phone, decrypted with `AI_SHARE_SNAPSHOT_KEY_V<n>`. This tool needs an active connection and its own consented snapshot; it does not imply consent to other health data.

Every request verifies the OAuth token, resolves the existing `ai_connections` owner, validates the live Supabase Auth session, and applies the connection's scope and rate limit. Database access uses the server key, filtered by the verified user; assistant tokens are never forwarded to PostgREST. See `docs/security/ai-connector-threat-model.md`.

## Audit status — October 13, 2026

The audit candidate is implemented and verified locally; these fixes are not deployed. The full Deno suite passed 211 tests and the disposable PostgreSQL suite passed. The full app check passed analysis and 3,901 tests before the final verified-client display correction; its affected screen suites then passed 16 tests and focused analysis. Record the exact candidate and final CI receipt in the current handoff; the full app check above predates the final display-only correction. Local tests do not establish live OAuth readiness.

**S2 remains an open release blocker.** The current token hook stamps the personal MCP audience on OAuth tokens. Requiring that audience rejects a deliberately wrong-audience test token, but does not prove that a token originally requested for another resource cannot receive the stamped audience. The real authorization-server attack test, including refresh, remains required. Do not connect real health data or describe personal sharing as release-ready while this is unresolved.

S6's accepted phone-pairing requirement and S9's privacy/policy review also remain open. The first real Claude/ChatGPT connection, actual callback configuration, consent, snapshot retrieval, disconnect and expiry still need recorded live verification.

## Required live gates

| Requirement | Automated coverage | Live acceptance still required |
|---|---|---|
| S1 Database isolation | `auth_isolation_test.ts`; `scripts/test_ai_connector_rls.sh` | A real OAuth token cannot read PostgREST tables, private Storage or privileged RPCs, or call app-only functions. |
| S2 Resource binding | `resource_binding_test.ts`; SQL hook cases | Request a token for another resource from the actual AS and replay it here, including after refresh. It must be rejected. Current hook tests do not prove this. |
| S3 Client identity | Website `tests/ai-connector.test.cjs` | Pre-register actual client ids and exact callback URIs. Production DCR stays off under ADR-009. Verify rejected clients and callback mismatches. |
| S5 Revocation | `revocation_purge_test.ts`; app sign-out tests; SQL suite | Disconnect, then reuse the same unexpired token: access denied; refresh also fails. Offline app sign-out is best-effort and can leave an existing snapshot until later deletion or expiry. |
| S10 Session and grant ownership | `grant_authorization_test.ts`; SQL session matrix | A refreshed older session cannot bind a newer consent; deleted Auth sessions fail; wrong user/client/scope cannot read a connection or snapshot. |

## Deployment order for the reviewed candidate

Deployment requires the applicable approval and closed release gates; this is an order of operations, not evidence that deployment has happened.

1. Review pending migrations and apply the connector prerequisites: restrictive RLS, `ai_connections`, the token hook, snapshot storage, the PostgREST pre-request guard, and connection display metadata. Preserve the existing per-connection owner.
2. Apply `20261013165631_ai_connection_session_binding.sql` **before** deploying the updated `mcp-personal`. Its service-role-only RPC `bind_ai_connection_session` checks `auth.sessions` existence, user, OAuth client, original `created_at`, and `not_after`, then atomically validates/binds an active, unrevoked, unexpired connection. Without the RPC the new function fails closed.
3. Deploy the coordinated website approval route. It must insert the consent row before asking Supabase Auth to approve the authorization. The resulting OAuth session must be created at or after that row. The browser must not independently approve the same authorization.
4. Deploy `ai-share-snapshot` and use the coordinated app build. Snapshot POST now **requires `generated_at`**, the report's actual collection time in UTC, alongside the existing scope, payload and revision. Older app builds without this field are rejected. Lifetime starts at upload acceptance; generation time is not replaced by upload time. Future device timestamps are rejected; the app directs users to check date/time and refresh the preview.
5. Deploy the personal function with its reviewed audience, asymmetric signing keys, snapshot keys and app-only function guards. Configure trusted clients from the actual provider setup flow and the website's `AI_CONNECTOR_TRUSTED_CLIENTS`; verify rather than guess callback values.
6. Run the real gates above on the deployed versions and record the receipts before widening access.

The `stale` flag checks synchronized supplement changes, including removals, after the report's generation time. It cannot detect unsynced phone changes or later medication/profile edits that never reached the server. `stale: false` is not proof that the user's current health information is unchanged. A snapshot is a dated report, not a live safety check.

## Local commands

```bash
deno test --allow-read --allow-env supabase/functions
scripts/test_ai_connector_rls.sh
supabase functions serve mcp-personal --env-file <local environment file>
```

Deno tests sign fixture tokens with an ephemeral RSA key and use injected repositories. The SQL suite uses a disposable Docker database and accepts no remote database URL. Rate limits and catalog caches are per function instance, not global. Never put real keys or health payloads in test logs.
