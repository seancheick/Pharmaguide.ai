# PharmaGuide personal MCP

Public personal access is enabled as of October 24, 2026. Codex is verified against the normal
hosted production endpoint. A WorkOS login alone never grants personal reads: the user must
approve the connection from a different signed-in PharmaGuide app session.

The public product catalog remains available without sign-in at `https://mcp.pharmaguide.io/public`.
It does not read anyone's stack. Personal endpoint:

`https://omayamxacvacrnvdvzhr.supabase.co/functions/v1/mcp-personal`

## Connect Codex

The tested installed client is Codex `0.164.0-alpha.11.1`. On this Mac:

```bash
PG_CODEX="/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
"$PG_CODEX" -c mcp_oauth_callback_port=3199 mcp add pharmaguide_personal \
  --url https://omayamxacvacrnvdvzhr.supabase.co/functions/v1/mcp-personal \
  --oauth-client-id client_01M5NXSNSESQFXNCBNPA547059 \
  --oauth-resource https://omayamxacvacrnvdvzhr.supabase.co/functions/v1/mcp-personal
"$PG_CODEX" -c mcp_servers.pharmaguide_personal.oauth.callback_port=3199 mcp login pharmaguide_personal --scopes openid,offline_access
```

`mcp add` begins OAuth immediately. The process-only initial port override is necessary for this
pre-registered callback. For subsequent logins, preserve the client/resource settings and set
`callback_port = 3199` in `[mcp_servers.pharmaguide_personal.oauth]`. Port conflicts fail rather
than silently changing callbacks. The exact registered callback is
`http://127.0.0.1:3199/callback/S6tE1k6DOX3Z`.

After sign-in, ask Codex to run `connect_my_pharmaguide`. Open its setup link and approve from
PharmaGuide → Profile → Connected AI assistants, using the app handoff or approval code.
`get_my_supplements` reads the existing signed-in supplement sync. In that connection's
**Access settings**, preview and **Save** any additional information you choose to allow.
`get_my_stack_snapshot` reads only that encrypted selected copy, with generation/expiry and
freshness information. Automatic updates are an independent opt-in; no daily manual token is
needed. Disconnect ends future access and deletes the stored snapshot, but cannot erase data
already received by the assistant.

## Existing owners and runtime controls

- WorkOS Standalone Connect delegates login to the website's verified Supabase session.
- `_shared/oauth_token.ts` verifies signature, exact issuer/resource/client, required scopes and
  consent SID, then performs a fresh pinned UserInfo check on every request.
- Existing SQL phone approval, connection/revocation/deletion barriers and exact consent lookup
  remain the data authority. Reconnection never revives an old consent or snapshot.
- Existing Dart brief/scope owners select findings and optional medication/profile details;
  ordinary supplement sync never gains medication rows. The assistant receives findings and
  does not become a second clinical engine.
- Existing `AI_CONNECTOR_PAIRING_ENABLED=true` is configured separately in Supabase server secrets
  and Vercel Production. Both production factories default off and use the existing handlers
  only when explicitly enabled. The phone approval entry defaults on, with a compile override
  available for containment builds.

Rollback: set `AI_CONNECTOR_PAIRING_ENABLED=false` in **both** Supabase and Vercel, redeploy the
website, and verify personal reads/uploads return503. Discovery, authenticated snapshot deletion
and disconnect/revocation recovery remain available. A phone entry alone grants no access.

Server configuration remains `SUPABASE_URL`, the existing server admin-key resolver,
`WORKOS_ISSUER`, `MCP_PERSONAL_RESOURCE_URL`, `MCP_PERSONAL_WEBSITE_URL`,
`AI_CONNECTOR_TRUSTED_CLIENTS` and the existing `AI_SHARE_SNAPSHOT_KEY_V*` keyring. The website and
account-deletion function also require the existing server-only `WORKOS_API_KEY`.
Never expose server secrets to clients or log tokens/health payloads.

`AI_CONNECTOR_TRUSTED_CLIENTS` uses the existing operator-reviewed static JSON entries
`{client_id,name,kind,redirect_uri}`. Supported validators cover Codex, Claude, ChatGPT and Claude
Code; every production entry requires an exact reviewed callback. WorkOS CIMD/DCR remains off.
Only actually configured clients can connect; validation support alone is not qualification.

## Other assistants

Claude's public PKCE client is registered and configured with the exact
`https://claude.ai/api/mcp/auth_callback` destination. In Claude custom connector settings, use
**Sign in now → Use your own OAuth client**, client ID
`client_01M5QGZYAKS74G2HWQ4ZAJZDB5`, and no client secret. The custom connector named
**PharmaGuide personal** is prepared in Sean's Claude account but is **not connected**.
Sean explicitly deferred its connection test; do not claim Claude end-to-end qualification.
Claude Code is signed out on this Mac.

ChatGPT, Gemini, Perplexity and Muse personal connections are not qualified or advertised as
working by this release. Their client registration/callback and live acceptance are separate
follow-up work; they do not disable the completed Codex release. Muse directory submission is
also separate. Do not offer a manual long-lived token or reuse Codex's identity for another client.

## Verification

App PR144 is merged at `9ace97a5`; exact runtime candidate `cd608862` passed full
CI40118612663. Website PR14 is merged at `a790dd4`; candidate `d68630b` passed
CI40119305487. Focused checks: Deno261, Flutter95, website connector63/privacy12/routing2,
analyze, typecheck, independent security review and real bundled-catalog verification (20 blobs).

Two disposable accounts completed real WorkOS browser PKCE OAuth with distinct external users
and consent IDs, plus distinct real Supabase browser/phone sessions. Existing Dart-generated
synthetic briefs passed 60 normalized scope combinations through hosted encrypted repositories
and the enabled production factories locally; minimal/full selections and two-account isolation
then passed again against the **normal deployed production endpoints and keyring**.

Old access and refresh credentials stayed denied after reconnect; the original access token
still had164 seconds remaining after fresh phone approval. Installed Codex completed production
OAuth, normal list/snapshot/setup calls and automatic access/refresh rotation. Final public
disconnect rejected both tools and UserInfo while the renewed access token had231 seconds left;
refresh returned400 invalid_grant. Prior physical-phone automatic-update/opt-out, native disconnect
and account-deletion qualification remains recorded with its original limits. The final public
phone build was installed; test accounts use synthetic information, not a second human Google
sign-in or clinical validation.

Sanitized receipts: `~/pg_quality/public_activation_20261024/`. The single execution register is
[the threat model](../../../docs/security/ai-connector-threat-model.md#production-release-boundary--updated-october-24-2026).
For future logo changes, use [the existing branding guide](../mcp-public/README.md).

Local regression commands:

```bash
deno test --allow-read --allow-env supabase/functions/mcp-personal supabase/functions/ai-share-snapshot
scripts/test_ai_connector_rls.sh
```
