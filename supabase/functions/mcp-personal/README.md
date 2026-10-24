# mcp-personal

**Personal production access remains disabled.** Every production personal read returns 503;
new snapshot uploads also return 503. Discovery and authenticated deletion remain available.
Public catalog testing works today at `https://mcp.pharmaguide.io/public`; its setup commands
are in [mcp-public/README.md](../mcp-public/README.md).

## Durable WorkOS candidate — October 23, 2026

Sean approved OAuth automatic renewal, phone approval and read-only snapshots, Codex first.
The candidate follows WorkOS's durable consent model. Supabase remains the ordinary app identity
and data owner; no clinical engine, medication sync or manual token workflow is introduced.

1. Codex completes PKCE OAuth through WorkOS. The existing website signs the user into PharmaGuide
   and completes standalone authentication with the verified Supabase user ID as external ID.
2. The MCP verifier checks signature, issuer, exact resource audience, allowed client and consent
   SID, then checks the same token at the pinned WorkOS UserInfo endpoint. No redirect or cache.
3. `connect_my_pharmaguide` registers an opaque pending setup reference for that exact consent.
   The user opens the existing website setup link, obtains a short-lived approval code and approves
   it from a different live signed-in app session. This does not attest physical device possession.
4. SQL atomically consumes the approval and creates/reuses the exact consent connection. The
   connection lasts until disconnect; repeated approval preserves its existing scope and snapshot.
5. Personal tools enforce that connection on every call. Disconnect first blocks and purges locally,
   then revokes the exact WorkOS application. Failed provider revocation stays blocked and retryable.
   Old consent cannot bind to a new connection. A new connection requires a new consent SID.

Tools:

- `connect_my_pharmaguide`: setup only; returns an approval link, no personal data. Available only
  when the injected WorkOS setup adapter is configured.
- `get_my_supplements`: names, product IDs and ingredient keys from existing supplement sync.
  No medications, doses or conditions.
- `get_my_stack_snapshot`: only the scoped, encrypted brief explicitly shared to this connection.
  It reports its generation time, expiry and limited freshness check. Missing or expired shares
  produce a clear explanation. Snapshot lifetime is separate from connection lifetime: default
  24 hours, maximum 30 days; ongoing refresh remains a separate opt-in.

Verified OAuth identity alone does not authorize personal data. A valid token for a disconnected
connection receives a correlated tool error and reconnect instructions, without reads or setup
registration. Invalid/revoked provider tokens fail authentication. Tokens are never forwarded to
PostgREST; server reads are filtered by verified user and exact connection.

## Evidence and remaining acceptance

Fresh hosted synthetic qualification observed normal refresh, repeated active SID, new SID after
revocation, five old refresh generations rejected before and after reconnect, old access rejected
by UserInfo, delayed code exchange rejected, and missing-resource requests rejected. This removes
the earlier reason to wait for a per-authorization WorkOS identifier. UserInfo revocation timing
is observed behavior, not a documented SLA. Keep PKCE; these applications do not support a client
secret, and this design does not require one.

Actual installed Codex tests use hosted WorkOS OAuth plus the real MCP/verifier and synthetic
repository adapters. They cover setup, approval denial, synthetic reads, snapshot availability and
disconnect messages. Simulated approval is explicitly not a real phone/database acceptance test.
The existing SQL harness separately verifies ownership, revocation barriers and concurrent races.
Current evidence and the single execution register live in
[the threat model](../../../docs/security/ai-connector-threat-model.md).

Before personal production activation:

- Finish exact-candidate CI and independent review.
- Apply both phone-pairing and durable-consent migrations in timestamp order before the coordinated
  website. Disconnect uses these RPCs even with setup disabled.
- Configure a reviewed test deployment with exact WorkOS issuer, resource and pre-registered client
  callbacks. `postgrestRepositories` accepts the existing trusted client names/redirects for setup;
  do not infer callback details from opaque standalone authorization IDs or JWT claims.
- Exercise the real browser → app approval → SQL → encrypted snapshot → Codex flow, two-account
  isolation, resource/callback/PKCE negatives, refresh, expiry and disconnect/reconnect with old tokens.
- Complete S9 review and obtain release authorization. The production factory still returns 503;
  the CLI entry point remains contained. Testing the injected implementation does not activate it.

Website: `WORKOS_ISSUER` (exact HTTPS origin), server-only `WORKOS_API_KEY`, existing trusted-client
configuration and Supabase settings. `AI_CONNECTOR_PAIRING_ENABLED` defaults off. App pairing uses
`PHARMAGUIDE_AI_PAIRING_ENABLED`, also off by default. Arbitrary-client CIMD/DCR onboarding is not
qualified; this batch targets the exact pre-registered Codex client.

## Contained production runtime configuration

`createProductionDependencies` in `index.ts` composes the existing WorkOS verifier,
PostgREST repositories and snapshot keyring. The candidate entrypoint no longer falls back
to Supabase OAuth. **`createProductionHandler` still returns 503 for personal calls:**
configuration alone does not activate access. Missing or malformed configuration also returns
503, without logging configuration values. A complete configuration advertises the pinned
WorkOS issuer in protected-resource discovery.

Required server settings:

| Setting | Value contract |
| --- | --- |
| `SUPABASE_URL` | Exact HTTPS project origin |
| `SUPABASE_SECRET_KEY` | Server-only admin credential; existing `SUPABASE_SECRET_KEYS` bundle or legacy service-role resolver also supported |
| `WORKOS_ISSUER` | Exact HTTPS AuthKit origin for the reviewed environment; no path, query or trailing slash |
| `MCP_PERSONAL_RESOURCE_URL` | Exact HTTPS hosted personal MCP resource/audience, no query or fragment |
| `MCP_PERSONAL_WEBSITE_URL` | Reviewed HTTPS website `/oauth/authorize` setup page, no query or fragment |
| `AI_CONNECTOR_TRUSTED_CLIENTS` | Same JSON array as the website: `{client_id,name,kind,redirect_uri}`. This contained rollout accepts only `kind: "codex"`, nonduplicate IDs and exact reviewed `http://127.0.0.1[:port]/callback/<id>` callbacks |
| `AI_SHARE_SNAPSHOT_KEY_V1` (and retained rotation versions) | Base64 32-byte encryption keys shared with the existing snapshot writer; at least one valid key is mandatory |

The MCP runtime does not need `WORKOS_API_KEY`: live token validity uses the pinned UserInfo
endpoint. The website's standalone-completion/revocation owner and account-deletion owner need
that server-only key from the same WorkOS environment. Never copy staging identities or old
loopback test URLs into production configuration.

The original acceptance callback is tied to its loopback MCP URL. Codex's callback-specific mode
derives the path ID from the full MCP server URL; its default listener port is ephemeral.
For bounded pre-registration, configure a fixed Codex OAuth callback listener port, register its
exact callback for the final hosted resource, and verify fresh login twice before rollout.
Do not widen callbacks or enable arbitrary-client registration to bypass this check. Current
Codex also supports issuer-bound callbacks in some configurations; verify the installed client's
actual authorization request rather than assuming a path from another version.

The canonical resource already published in protected-resource metadata is:

`https://omayamxacvacrnvdvzhr.supabase.co/functions/v1/mcp-personal`

Set `MCP_PERSONAL_RESOURCE_URL` to that exact value, without a trailing slash. No new branded
route is required. For the callback-specific Codex mode and fixed listener port `3199`, the
source-derived exact callback is `http://127.0.0.1:3199/callback/S6tE1k6DOX3Z`.
The ID is base64url of the first nine SHA-256 bytes of the canonical resource URL. Record that
same callback in the production WorkOS application and the website/MCP trusted-client entry.
Do not reuse the private loopback-resource callback.

Operator setup, **after** production issuer/client registration is available and the release
checks permit OAuth acceptance (replace the placeholder with the actual reviewed client ID):

```bash
codex mcp add pharmaguide_personal \
  --url https://omayamxacvacrnvdvzhr.supabase.co/functions/v1/mcp-personal \
  --oauth-client-id '<reviewed-production-client-id>' \
  --oauth-resource https://omayamxacvacrnvdvzhr.supabase.co/functions/v1/mcp-personal
codex -c mcp_servers.pharmaguide_personal.oauth.callback_port=3199 mcp login pharmaguide_personal
```

For repeat logins, set `callback_port = 3199` in the existing
`[mcp_servers.pharmaguide_personal.oauth]` configuration table, preserving its client settings.
This per-server setting leaves other MCP servers' callback configuration unchanged; a global
`mcp_oauth_callback_port` setting is unnecessary. The per-server configuration was verified
against installed Codex `0.164.0-alpha.11.1`: two isolated local
metadata probes generated the same callback with S256, and an occupied port failed rather than
falling back. The canonical hosted-resource probe currently stops at its intentional root 503,
before producing an authorization URL; its derived callback still needs a real production
metadata/login check after deployment and explicit acceptance authorization. No grant was created
by these probes. Verify two fresh logins with the registered client and inspect the actual redirect
URI before declaring production onboarding ready.

Primary references: [WorkOS Standalone Connect](https://workos.com/docs/authkit/connect/standalone),
[WorkOS discovery](https://workos.com/docs/reference/workos-connect/metadata/oauth-authorization-server),
[Codex callback identity source](https://github.com/openai/codex/blob/main/codex-rs/rmcp-client/src/oauth_callback.rs),
[Codex configuration reference](https://developers.openai.com/codex/config-reference).
Generic WorkOS MCP guidance recommends CIMD; this exact-client qualification does not establish
CIMD/DCR support or public onboarding readiness.

## Local checks

```bash
deno test --allow-read --allow-env supabase/functions/mcp-personal supabase/functions/ai-share-snapshot
scripts/test_ai_connector_rls.sh
```

Tests use disposable identities, keys and a disposable local database. Never log real tokens or
health payloads. Snapshot encryption stays owned by `_shared/snapshot_crypto.ts`; keys remain in
server secrets. `stale: false` only means no synchronized supplement changes were detected; it
cannot certify that unsynced medication/profile information is current.

Prior deployed containment and public usability: PR114/main14152b88 (October13), then public fixes
PR134 / pipeline PR243 (October23). Public v4, personal v3 and snapshot v3 were deployed with
approval; all 15 HTTP checks and six Codex public calls passed. That authorization excluded the
new personal-access rollout. Claude testing was deferred by Sean due quota.
