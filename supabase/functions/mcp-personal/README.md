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
