# mcp-personal

The personal PharmaGuide MCP server (Phase 1b). It gives an assistant the user approved one
read-only tool, `get_my_supplements`: the supplement names, PharmaGuide product ids and
ingredient keys the user already syncs, with `not_included: [medications, conditions, doses]`.
Phase 2 adds `get_my_stack_snapshot`: the brief the user shared to this exact connection from
the app (`supabase/functions/ai-share-snapshot`), decrypted with `AI_SHARE_SNAPSHOT_KEY_V<n>`
(`_shared/snapshot_crypto.ts`), with `stale` from `user_stacks.client_updated_at`. It needs no
connection-wide category: the share itself is the user's per-connection consent.
Threat model: `docs/security/ai-connector-threat-model.md` (S1–S10).

Every request: verify the OAuth token (`_shared/oauth_token.ts`) → resolve its
`ai_connections` row (`_shared/connection_gate.ts`) → per-connection rate limit → scope check →
`mcp_access_log` row → service-role read of `user_stacks` filtered by the verified `sub`. The
OAuth token is never forwarded to the database.

## Gate: green on a staging project before any real user connects

| Requirement | Automated here | Staging check (Sean or the integrator) |
|---|---|---|
| S1 Database isolation | `auth_isolation_test.ts`; `scripts/test_ai_connector_rls.sh` | With a real OAuth access token: PostgREST `GET /rest/v1/user_stacks`, a Storage object read and `rpc/get_product_submission_intake` all return zero rows or 42501; `delete-account` and `register-push-token` return 403 |
| S2 Resource binding | `resource_binding_test.ts`; hook cases in the SQL suite | Register a second (attacker) MCP resource on the staging AS, mint a token for it, replay it here: 401. Repeat after a `refresh_token` grant and with a DCR-registered client |
| S3 Client identity | consent-page allowlist tests (website repo) | An unregistered or inexact callback cannot be approved; loopback is refused for every client except Claude Code |
| S5 Revocation and purge | `revocation_purge_test.ts`; cascade cases in the SQL suite | Disconnect on `/account/connections`, then call the tool with the same unexpired access token: 403. Refresh fails after `revokeGrant` |
| S10 Grant-level authorization | `grant_authorization_test.ts` | Approve Claude with supplements, connect ChatGPT with an empty scope: ChatGPT's calls get 403 |

## Sean's dashboard steps (staging first, then production)

1. **Authentication → OAuth Server:** enable it. Turn on dynamic client registration on the
   **staging project only**; production keeps it off.
2. **Authorization path:** set the consent page URL to `https://pharmaguide.io/oauth/authorize`
   (staging: the preview URL). Add it, and `https://pharmaguide.io/account/connections`, to
   **Authentication → URL Configuration → Redirect URLs** so website sign-in can return there.
3. **Pre-register the trusted clients** with exact redirect URIs:
   - Claude: `https://claude.ai/api/mcp/auth_callback`
   - ChatGPT: `https://chatgpt.com/connector_platform_oauth_redirect` (add the
     `https://chatgpt.com/connector/oauth/{callback_id}` value ChatGPT shows, if it gives one)
   - Claude Code: `http://localhost/callback` and `http://127.0.0.1/callback` (loopback, port-agnostic)

   Put the three client ids into the website's `AI_CONNECTOR_TRUSTED_CLIENTS` setting.
4. **JWT signing keys:** confirm the project signs with an asymmetric key (ES256 or RS256). This
   server refuses HS256.
5. **Apply the migrations** (`supabase db push`): `20261012120000_ai_connector_restrictive_rls`,
   `20261012120100_ai_connections`, `20261012120200_custom_access_token_hook`.
6. **Audience:** `UPDATE public.ai_connector_config SET value = 'https://<ref>.supabase.co/functions/v1/mcp-personal' WHERE key = 'personal_mcp_audience';`
7. **Authentication → Hooks → Customize Access Token (JWT) Claims:** Postgres,
   `public.custom_access_token_hook`, enable. Then sign in to the app once and confirm app
   sessions still work (their claims are untouched; only tokens with `client_id` change).
8. **Function secret:** `supabase secrets set MCP_PERSONAL_RESOURCE_URL=<the same URL as step 6>`,
   then `supabase functions deploy mcp-personal` (config: `verify_jwt = false`).
9. Deploy `delete-account` and `register-push-token` (they now refuse OAuth client tokens).

Until step 6 the hook stamps an unroutable placeholder, so every OAuth token is rejected here.
Without `MCP_PERSONAL_RESOURCE_URL` the function answers 503 to everything.

## Local commands

```bash
deno test --allow-read --allow-env supabase/functions   # all function tests, no network at runtime
scripts/test_ai_connector_rls.sh                        # SQL suite; needs Docker running
supabase functions serve mcp-personal --env-file <file with SUPABASE_URL, MCP_PERSONAL_RESOURCE_URL, SUPABASE_SECRET_KEY>
```

The tests sign tokens with an RSA key generated per run and inject the JWKS; repositories are
in-memory fakes. Rate limits are per function instance, not global.
