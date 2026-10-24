# AI connector threat model

Accepted with ADR-009 (`knowledge/architecture-decisions.md`, 2026-10-12). Scope: the public catalog
MCP (`supabase/functions/mcp-public`), the personal MCP (`supabase/functions/mcp-personal`), the
consent and connections pages on the website, and the app's AI-share consent flow (Phase 2
snapshots).

Current status, October24,2026: public catalog and personal MCP are deployed. Codex is qualified
against normal production OAuth/read/snapshot endpoints, including automatic renewal and immediate
revocation. Existing WorkOS and Supabase owners remain authoritative. See the production release
boundary below for exact candidate CI, two-account qualification, selected-scope tests and limits.
Sean deferred other assistant acceptance so he can test Claude separately.

The former Supabase audience-stamping hook did not prove requested-resource binding. Its
containment remains enabled and ordinary app sessions are unchanged. WorkOS tokens are verified
separately and are never treated as Supabase sessions or forwarded to PostgREST.
See `supabase/functions/mcp-personal/README.md` for activation gates.

## Assets

| Asset | Where it lives | Sensitivity |
|---|---|---|
| Supplement list (names, `dsld_id`, `ingredient_keys`) | Phone `user_data.db`; `user_stacks` for signed-in users | Personal; a new disclosure when sent to a provider |
| Medications, doses, conditions, allergens, pregnancy flags | Phone only; inside an encrypted `ai_share_snapshots` row only when the user shares them | Health data |
| PharmaGuide findings for a stack | Computed on the phone; inside a snapshot when shared | Health-derived |
| OAuth grants, access and refresh tokens | WorkOS for the candidate; the AI client. Legacy Supabase third-party issuance remains disabled | Credential |
| Snapshot data keys | Supabase Vault or function secrets, versioned by `key_version` | Secret |
| `ai_connections`, `mcp_access_log` | Supabase DB | Metadata; the log holds no payloads |
| Public catalog (`catalog_search`, detail blobs) | Supabase DB and Storage | Public |

## Trust boundaries

1. **Phone.** Source of truth for the stack and profile. It builds the scoped payload, shows the
   preview and starts every share. Health data leaves the phone only through a consented snapshot
   (ADR-009); stack sync never carries medication rows.
2. **Supabase.** The DB (`user_stacks`, `ai_connections`, `ai_share_snapshots`, `mcp_access_log`,
   `catalog_search` and every other user-owned table), Storage (public catalog blobs, private
   submission-photo buckets), Edge Functions (`mcp-public`, `mcp-personal`, and the user-JWT
   functions `delete-account` and `register-push-token`), Auth (ordinary app sessions; legacy third-party issuance disabled) and
   Vault. WorkOS owns candidate assistant OAuth issuance; its tokens have no database-session authority.
3. **Website (pharmaguide.io, PharmaGuide Website repo).** The consent page
   (`src/app/oauth/authorize/`), the connections page (`src/app/account/connections/`) and the
   existing service-role routes (for example `src/app/api/share/route.ts`).
4. **AI provider (Claude, ChatGPT, Claude Code).** An MCP client acting with the user's grant. It
   receives tool output and keeps chat history under its own policy. Everything it sends to
   PharmaGuide is untrusted input; everything PharmaGuide returns may be read by a model, so returned
   text is data, never an instruction.

Crossings: phone → Supabase (TLS, user session JWT); provider → MCP servers (OAuth access token, or
none for the public server); browser → Supabase sign-in → website → WorkOS consent; exact signed consent → phone approval; MCP output → provider
→ the provider's chat history (outside PharmaGuide's control).

## Requirements, threats, controls and tests

| Requirement | Threat | Control | Automated test |
|---|---|---|---|
| S1 Database isolation | An OAuth access token carries the full user session and reads `user_stacks`, submissions, push tokens, Storage objects or RPCs directly; user A reads user B through MCP. | `AS RESTRICTIVE` policies `((auth.jwt()->>'client_id') IS NULL)` on every user-owned table and on `storage.objects`; `client_id IS NULL` guards in every SECURITY DEFINER RPC and user-JWT edge function. MCP servers verify the JWT (JWKS, `iss`, `exp`, `aud`, `client_id`, `sub`) and read with the service role filtered by the verified `sub`; they never forward the token. Review includes the website's service-role routes. | `supabase/tests/ai_connector/restrictive_rls.sql`; `supabase/functions/mcp-personal/auth_isolation_test.ts` |
| S2 Resource binding | A token issued for another MCP resource on the same authorization server (supabase/auth #2610) is replayed against the personal MCP. | The existing Auth hook now refuses third-party issuance/refresh; production MCP returns 503 even for old tokens, and snapshot POST refuses new uploads. Discovery and authenticated deletion remain available. The candidate separately verifies WorkOS exact issuer/audience/client/consent and current same-token UserInfo. Hosted missing-resource rejection and revoked-token tests pass; controlled production acceptance passed; public activation remains separate. | `supabase/functions/mcp-personal/resource_binding_test.ts` tests production containment and synthetic audience checks; `supabase/functions/ai-share-snapshot/index_test.ts` tests denied uploads and permitted authenticated deletion; SQL hook cases test issuance/refresh refusal. Fresh hosted evidence below supplements these tests; production activation is not inferred |
| S3 Client identity | A look-alike client or redirect URI collects the authorization code; open DCR lets anyone register. | Production rollout pre-registers Codex only, with exact callback-URI matching; production DCR/CIMD disabled and verified; loopback callbacks only for the approved native client; the consent page shows the verified client and callback host in large type. | Website repo `tests/ai-connector.test.cjs`; exact hosted Codex staging and production registration/callback verified; controlled production OAuth acceptance passed; public activation remains separate |
| S4 Consent preview | The user shares more than intended, or a derived finding discloses an excluded category. | The preview names the destination (client and host), categories, duration, the three data locations and the revocation path (`pharmaguide.io/account/connections` and in-app Settings). The payload shown is the payload sent; derived findings follow their category. | `test/release_gate/ai_share_snapshot_scope_test.dart` (excluded categories absent, including medication-derived findings; preview equals payload); `test/features/ai_share/ai_share_consent_preview_test.dart`; `test/features/ai_share/ai_connections_screen_test.dart` (stored verified client name/host and legacy identifier fallback) |
| S5 Revocation and purge | Access or data outlives the user's decision: an unexpired access token keeps working after Disconnect; snapshots survive sign-out or account deletion. | WorkOS disconnect atomically blocks local access, purges snapshots/logs and cancels pending approvals before revoking the exact provider application; failures retain a retry barrier; `delete-account` purges everything; app sign-out stops refreshes and attempts deletion before ending the session; offline deletion may fail and is not promised immediate. Expiry denies reads; configured cleanup removes expired rows. | `supabase/functions/mcp-personal/revocation_purge_test.ts`; `test/release_gate/ai_share_snapshot_signout_purge_test.dart` |
| S6 Desktop approval | A desktop consent is phished, or approved from the initiating session. | Default-off pairing code binds the verified request to approval by a different live session of the same account. This is not device attestation. | `supabase/tests/ai_connector/phone_pairing.sql`, website authorization tests and app pairing tests cover expiry, replay, isolation and races. Hosted phone approval and real-device acceptance passed; separate two-account hosted isolation is recorded below |
| S7 Audit, rate limits, caching | Abuse goes unseen; anonymous lookups cause unbounded Storage reads; the log turns into a health-data store. | `mcp_access_log(connection_id, tool, at)` with no payload columns; per-IP and per-client limits on the public server, per-connection limits on the personal server; in-function caching of the manifest and index, CDN-served blobs. | `supabase/functions/mcp-public/index_test.ts`; `supabase/functions/_shared/catalog_test.ts`; `supabase/functions/mcp-personal/access_log_test.ts`; limits are per instance |
| S8 Tool output is data | A hostile product label or user-entered name returned by a tool instructs the assistant (prompt injection). | Public product facts and supplement-list names are length-capped and source-tagged in a data envelope. Snapshots preserve the previewed Markdown within a scoped, dated payload. Instructions identify tool content as data; this does not guarantee a provider will resist hostile text. | `supabase/functions/_shared/catalog_test.ts`; `supabase/functions/mcp-public/index_test.ts`; live hostile-content checks remain required |
| S9 Policy and legal | Health data is disclosed without policy cover; a connector carrying PHI is listed in a directory against provider policy. | Current OpenAI terms prohibit HIPAA-defined PHI and condition other sensitive data on lawful disclosure and consent. Sean confirmed direct-to-consumer adults-only operation without provider/covered-entity contracts. Privacy/Terms, pre-Save notice, incident procedure and deletion controls are reviewed below; this is not HIPAA or legal compliance certification. Directory listing remains public catalog only. | `supabase/functions/_shared/catalog_test.ts` and `supabase/functions/mcp-public/index_test.ts` cover the public allowlist; policy items require Sean's review |
| S10 Grant-level authorization | Old or unrelated consent binds to newer access, or reads unshared categories. | WorkOS requests resolve exact issuer/sub/client/sid, never latest consent. Durable active rows remain subject to local revocation, category and snapshot checks. Registration captures a generation before fresh UserInfo verification; disconnect invalidates stale requests. Legacy Supabase binding stays separate and cannot replace WorkOS state. | `grant_authorization_test.ts`, `auth_isolation_test.ts`, `phone_pairing.sql`; disposable SQL includes overlapping completion/revocation tests |

Snapshot freshness and lifecycle limits:

- The coordinated app/function contract requires the report's `generated_at`; upload acceptance
  cannot make an older report appear newly evaluated. `stale` detects synchronized supplement
  changes only, not unsynced medication/profile changes.
- Opt-in refresh reuses chosen categories, including new entries within those categories. Pending
  refreshes respect consent changes; explicit upload completion cannot restore a disconnected or
  disabled preference. Default profile exclusion withholds personal nutrient comparisons while
  preserving generic fallback UL warnings whose provenance is explicit.
- Apply the S2 containment migration `20261013171928_ai_connector_deny_unbound_oauth.sql`, keep
  the Auth hook enabled, and deploy both contained functions together so existing tokens cannot
  read and new snapshots cannot be collected. Apply
  `20261013165631_ai_connection_session_binding.sql` before the updated personal function.
  Both migrations and contained functions were applied to the remote service on October13 with approval. The installed phone app was not replaced.

Existing guards that stay in force:

- `test/release_gate/phi_medication_no_sync_test.dart`: unchanged; stack sync never carries
  medication rows.
- `test/safety_invariants/no_health_in_supabase_test.dart`: its allowlist gains exactly the snapshot
  path, nothing broader.

## Out of scope

- Provider chat retention: what Claude or ChatGPT keeps in chat history, memory or training after a
  tool call. Revocation cannot reach it, and the consent preview says so (S4).
- A compromised phone, or a user who copies their own data elsewhere (including the Phase 0 AI brief,
  which has no backend).
- Compromise of the Supabase platform or its key store. Application-level encryption limits the
  exposure of snapshots at rest; it is not end-to-end.
- Correctness of catalog content and clinical rules (the pipeline contract and the Dart engine; the
  ADR-009 completeness and wording rules govern how findings are worded).
- Hosting a server-side engine (Phase 4, ADR-010) and expert review (Phase 5).


## October 23 execution register — durable WorkOS connection

Sean approved durable OAuth, phone approval, read-only scoped snapshots and Codex-first acceptance;
no daily manual tokens. Repeat OAuth approval may retain the same active consent. Disconnect
must permanently deny that consent, and reconnect must obtain a new one. Production activation
is separate from this authorized implementation.

Owner: `_shared/oauth_token.ts::verifyOAuthAccessToken`, `_shared/connection_gate.ts::resolveConnection`,
`mcp-personal/index.ts`, existing `ai_connections` / `ai_connection_pairings` / pairing limits;
website `api/ai-connections` and `lib/ai-connector`; Flutter `ai_connections_repository.dart` and
screen; existing snapshot scope/encryption owners. Evidence: caller/schema inspection and rg
consent/pairing across both repos; matrix/glossary searched. Will NOT create another identity
store, clinical engine, latest-consent fallback, mutable token metadata binding or manual token UI.

### Contract and implementation

- WorkOS standalone completes using the verified Supabase user ID (the external ID becomes token
  `sub`). No caller-selected user identity. Opaque `external_auth_id` does not prove client/callback;
  the login screen does not invent them. The hosted response is pinned to the configured HTTPS issuer.
- Verify signature, exact issuer and scalar resource audience, allowed client, consent SID, bounded
  claims and current same-token `POST /oauth2/userinfo` with matching subject. No redirects/cache;
  bounded timeout and fail closed. PKCE remains enabled; a client secret is not needed.
- OAuth completes before data access. Explicit `connect_my_pharmaguide` registers an opaque setup
  reference for the verified consent. Existing website/phone pairing binds that exact reference.
  The initiating browser and approving app must have different live Supabase sessions of the same
  user. This is not physical-device attestation. Trusted client configuration supplies destination;
  the JWT does not prove a per-attempt callback URI.
- Existing SQL owners consume approval and create/reuse the exact connection atomically. WorkOS
  connections carry explicit issuer/consent and no Supabase session ID. Repeat setup preserves an
  active connection and its scope/snapshot. Revoked consents cannot be rebound. Generation barriers
  prevent delayed registration/completion crossing disconnect. Cancellation must not revoke a
  pre-existing active connection merely because setup was repeated.
- Connection duration is until disconnect; snapshot duration remains separately chosen (24 hours
  by default, 30 days maximum). The app shows that distinction. No medication sync or clinical
  calculation changes.
- Disconnect blocks locally and purges first, then looks up the WorkOS user by external ID, lists
  exact authorized applications and deletes the matching application ID. Never derive IDs by prefix
  substitution. Only successful provider revocation completes the generation-bound barrier.

### Evidence and remaining gates

Private synthetic receipts: `/Users/seancheick/pg_quality/workos_durable_20261023/`.
No real health data or raw token logs. WorkOS staging tests observed repeat consent SID, a new SID
on reconnect, five old refresh generations rejected before/after reconnect, delayed code exchange
rejected after revocation, and missing-resource authorization rejected. Same-token UserInfo returned
401 for old access after disconnect and reconnect, and 201 for current access. This revocation
behavior is observed, not a documented timing SLA. A later concurrent refresh/revoke test returned a new token during the overlap, then rejected that access/refresh credential after revocation and again after reconnect; only the new consent worked. The PKCE application correctly rejects creating
a client secret; PKCE was not disabled.

- [x] Implement exact-consent auth, pairing, durable connection and snapshot consumers using existing owners.
- [x] Focused auth/authorization/snapshot and Flutter tests, disposable SQL races and website checks.
- [x] Independent security review and fail-first regressions: unbound denial now cancels; pending-only denial atomically starts the revocation barrier and exposes retry; repeated setup cancellation preserves existing access.
- [x] Actual installed Codex synthetic transport: OAuth login, discovery, approval-required error, opaque setup link, simulated approval, scoped supplement read, encrypted snapshot read, missing/expired snapshot messages, repeated connection and old-credential denial. Phone approval and repositories were synthetic adapters, not live database/device acceptance. Fixed the observed disconnected-call timeout with a correlated tool error; no authorization was relaxed.
- [x] Exact implementation candidates passed combined CI: app 44febbd9 / CI40030396012; website 63ba1b2 / CI40030380010 (including production build), plus Vercel preview. Subsequent receipt updates change documentation only.
- [x] Merge app PR135 (92791702) and website PR8 (99eb036d), with explicit approval. Apply phone-pairing and durable-consent migrations to hosted Supabase in order after separate explicit approval; verify connector table RLS and RPC role boundaries.
- [ ] Finish controlled test runtime configuration; verify hosted database isolation, two-account browser/phone approval, scoped encrypted snapshot retrieval/refresh/expiry, disconnect/reconnect and old-token denial through Codex. Physical phone connected; actual WorkOS OAuth, phone approval, durable hosted connection and Codex supplement read passed. Phone-authored scoped snapshot retrieval, automatic remove/restore updates, opt-out persistence and real revocation passed; Post-fix freshness acceptance passed; same-phone browser return and root navigation passed on physical touch.
- [x] Real-device approval, scoped snapshots, freshness/opt-out, revocation and return navigation passed.
- [x] Hosted two-account RPC/RLS/snapshot isolation and real-provider account-deletion qualification passed on disposable accounts; OAuth identity injection in the isolation layer is explicitly distinguished from prior real OAuth evidence.
- [x] Publish reviewed S9 disclosures and complete production configuration/acceptance; public Codex activation is recorded in the release boundary below.

WorkOS is retained: the fresh durable-consent tests pass, so a replacement provider is not warranted
by the current evidence. Pre-registered Codex configuration is qualified first; arbitrary-client
CIMD/DCR onboarding is not claimed or enabled.

Final focused candidate checks: 79 Deno tests, 32 Flutter tests, 41 website connector tests, focused analysis/typecheck and disposable SQL with Deny/completion races passed. Synthetic test grant revoked and Codex test credentials removed. Durable UI rendered at 390x844; production containment remains visible. Implementation candidate CI passed as recorded above. Merge/release approval remains with Sean.

October23 seamless-flow candidate: existing phone approval now finalizes WorkOS authority atomically; browser retries read the exact existing connection. Existing snapshot table trigger serializes writes with disconnect and rejects late writes. Full disposable SQL includes both race orders; review found no remaining must-fix. Migration applied with explicit approval. Private test snapshot wrapper is exact-user/connection/client/issuer and time-limited for POST, with authenticated deletion retained; normal public factories remain disabled. Updated phone build installed. Focused app/share/website tests pass; real phone snapshot and keep-updated remove/restore/opt-out passed. Original refresh credentials were rejected before and after reconnect; a fresh grant was disconnected while its access token was unexpired and both personal tools returned401. The original access replay after reconnect was already expired, so it does not establish unexpired replay rejection. Same-phone hosted handoff and post-fix freshness acceptance passed in the final physical run. Test credentials and health logs stay outside repository.

October24 continuation: corrected canonical stack sender timestamps to UTC after a real HTTP-payload regression reproduced a four-hour shift.24focused sync/PHI tests passed. Saved access scope/TTL and connection refresh on app resume use existing owners;35focused UI tests and analysis passed. Combined personal MCP/snapshot Deno suite83passed. MCP guidance now distinguishes synced account records from currentphone and retrievaltime from lastsync. User confirmed phone authoritative; six exact cloud-only rows tombstoned using existing LWW mechanism, preserving fourphone rows and11prior tombstones (21total). No historical timestamp offset guessed. Latest phone build installed; disconnected rows visibly say Access ended. These are development acceptance receipts, not public activation or final CI qualification.

October 24 final disconnect acceptance: the physical phone completed protected hosted sign-in and revoked the current Codex grant. Both personal tools rejected the frozen current access token with HTTP 401 while it remained unexpired, returning no data. Original disconnected refresh credentials remained HTTP 400 invalid_grant after reconnect. Hosted verification found zero snapshots, retained consent revocation tombstone and a cleared provider revocation barrier. Both normal public personal endpoints remain HTTP 503. Automatic-update remove/restore changed the selected snapshot; opt-out preserved its payload and marked it stale. Sanitized receipts reside in the private operator acceptance folder. The final physical Return to PharmaGuide tap closed the native browser and refreshed all three rows to Disconnected/Access ended; root Back returned Profile. Mirroring taps did not reliably deliver this browser action. The actual Flutter navigation-channel regression also passed. The ordinary production-entrypoint Make build was installed and home verified; the temporary acceptance entrypoint and diagnostics were removed. No public activation or final CI qualification is claimed.


## Production release boundary — updated October 24, 2026

Production service branding and the existing PharmaGuide Codex application logos are now saved
in WorkOS, using existing website assets. Light/dark saved previews and the real hosted OAuth
consent screen were verified; both real consent images loaded at 192×192 without letter fallbacks.
The visual check was cancelled before Allow access. Its exact-account test window was removed,
the normal contained website source was redeployed, and no new connection or snapshot remained.
At the branding-only checkpoint, normal personal reads/uploads remained503. Branding evidence is in the private operator folder
`~/pg_quality/workos_branding_20261024/verification.json`.

The later connection-list UX uses the existing live gate and revocation barrier: active connections
and retryable cleanup stay visible; ended connections are collapsed into history. Candidate cb98e8c2
passed full CI40110147051 and 75 focused owner/consumer tests; final phone installation and Sean's
screenshot confirmed collapsed history (5). This UI change does not requalify broader access scopes.

Public Codex activation is complete with Sean's explicit October24 authorization. App PR144/main
9ace97a5 (runtime candidate cd608862, CI40118612663) and website PR14/maina790dd4
(candidate d68630b, CI40119305487) are merged. Both existing factories use the existing explicit
AI_CONNECTOR_PAIRING_ENABLED switch; defaultoff preserves discovery/deletion for rollback.
Production normal MCP and snapshot functions are deployed, Supabase/Vercel switches are true,
and the public phone build is installed. Temporary exact-user website keys were removed.

Qualification closed the earlier live limits: two disposable accounts used real WorkOS browser
PKCE OAuth and distinct real Supabase phone sessions. Both got only their own snapshot; foreign
approval/write/read/delete paths were denied. Old consent credentials stayed denied after fresh
phone approval while the old access token still had164 seconds remaining. Existing Dart-generated
synthetic fixtures exercised60 normalized scope combinations through enabled factories/hosted
repositories, then minimal/full scopes and isolation passed on the normal deployed endpoints and
production encryption keyring. This is synthetic transport/privacy qualification, not clinical
validation or two human Google sign-ins.

Installed Codex performed normal public OAuth and successful list/snapshot/setup calls, then
renewed access/refresh credentials automatically without another login. Final normal disconnect
returned both tools401 and UserInfo401 with231 seconds remaining on the renewed access token;
refresh returned400 invalid_grant. Prior physical-phone update/restore/opt-out and disconnect
receipts remain applicable. Sanitized current receipts: ~/pg_quality/public_activation_20261024/.

Claude static PKCE registration, exact callback and branding are prepared; its real connection
test was explicitly deferred by Sean so he can test Claude himself. No ChatGPT/Gemini/Perplexity/
Muse personal compatibility claim is made. Their registration/acceptance is follow-up work and
does not hold up the active Codex release. CIMD/DCR remains disabled.

Rollback uses the existing switch in BOTH Supabase and Vercel; redeploy website configuration
and verify reads/uploads503 while discovery, authenticated deletion and revocation recovery
remain available. Installed phone entry does not grant access without server/phone approval.

### Completed activation preparation


Owner: existing SQL pairing/revocation gates, MCP verifier/repositories, account-deletion function and website privacy disclosure. No second auth or health-data owner is introduced.

Hosted isolation qualification passed 26 assertions using two disposable accounts, four real Supabase sessions and hosted PostgREST/RPC/RLS. Foreign phone approval, preview, connection lookup, snapshot write/read and deletion were denied; each account received only its own marker. Disposable rows and accounts were removed. WorkOS identity was injected at the verifier boundary for this layer, so this is not a second claim of full browser/OAuth acceptance. The separate real WorkOS/Codex lifecycle receipts remain applicable. Private sanitized receipt: `~/pg_quality/personal_phone_approval_20261023/hosted_two_account_isolation_20261024.json`.

Production WorkOS billing is unlocked. The approved server credential is installed in Supabase; production AuthKit issuer and exact pre-registered PKCE Codex client are verified, with DCR/CIMD disabled. The deployed runtime composition uses the existing WorkOS verifier/setup adapter, validates exact configuration and keeps the production factory hard-disabled. The canonical resource remains the already-published Supabase personal Edge URL; no second branded route is introduced. Installed Codex probes verify a fixed callback port, repeatable callback and refusal on port conflict.

Account deletion now uses the existing account-wide revocation barrier before provider cleanup and final auth deletion. Sean approved its persisted meaning; migration `20261024023658_ai_account_deletion_barrier.sql` was applied. Real WorkOS staging/Supabase deletion qualification passed 19 checks, including provider failure, retained retry identity/barrier, successful retry and zero fixture rows. Website standalone completion checks deletion before and after provisioning and compensates an exact identity if deletion wins. A timed-out provider request can remain ambiguous; failed cleanup is surfaced and requires operator reconciliation of identity metadata, never restoration of revoked health access. App PR138 is integrated at f393e00; website PR10/11 are integrated at 3672756 and deployed. The production account-deletion HTTP retry also passed the same 19 checks using an identity created, looked up and deleted with the matching production key; all disposable rows were removed. Controlled production OAuth, actual Codex automatic refresh, phone approval, minimal snapshot decryption, automatic update/opt-out and first-grant revocation passed. Fresh reconnect used a new consent ID, retained rejection of the old refresh credentials and did not restore the old snapshot. The corrected native Disconnect passed physical phone acceptance: no browser handoff, snapshot purge, completed provider cleanup, and denial of the still-unexpired access token and refresh token.

Sean confirmed direct-to-consumer adults-only use without healthcare-organization or business-associate contracts. The S9 review found no automatic private-MCP exemption and no blanket ban on all non-HIPAA consumer health data. Current provider terms require appropriate notice/consent. Published Privacy/Terms and installed app consent disclose the processors, durable lifetime, separate snapshot expiry, assistant retention/training settings and withdrawal limits; unsupported blanket compliance and retention promises were removed. Initial scope excludes under-18 use and provider/BA workflows. This bounded source/technical review is not a legal certification or approval of future clients/geographies. See the website master plan for dated primary sources and the exact policy diff.

### S9 incident-response procedure and tabletop

Sean is the incident owner. On suspected unauthorized access or disclosure, suspend personal reads/uploads, stop affected connections and preserve minimal access/configuration evidence without copying health payloads into logs. Establish discovery time, affected accounts, disclosed fields, recipients and authorization; investigate infrastructure, assistant and processor reports. Notify affected vendors and OpenAI promptly where its terms require it. Assess HIPAA, FTC HBNR and applicable regional duties; encryption alone does not resolve a disclosure after decryption. If HBNR applies, notify individuals without unreasonable delay and within 60 days; FTC timing and media duties depend on affected counts and location. Prepare required channels, incident facts, mitigation and contact details; obtain incident-specific review before sending. Document remediation and verify denial before restoring access. Sources: [FTC guidance](https://www.ftc.gov/business-guidance/resources/complying-ftcs-health-breach-notification-rule-0), [OpenAI terms §2](https://openai.com/policies/developer-apps-terms/).

A tabletop using the completed synthetic cross-account-denial and revoked-token receipts verifies the containment and evidence steps only. It sends no breach notifications and does not prove real-world notification delivery, mailbox monitoring, statutory applicability or compliance certification. Public activation is not authorized by this rehearsal.


### Production acceptance corrections

The production run reproduced a missing-scope token from default Codex discovery. The canonical metadata now advertises `openid` and `offline_access`; the identity guard remains unchanged. Actual bundled Codex0.164 default discovery requests both scopes. Homebrew0.159 requires explicit login scopes; the connection guide names the tested binary and fixes the initial-add callback port.

The existing native Disconnect browser handoff required another browser sign-in. The native flow now calls the existing verified website disconnect action with the signed-in app session, disables automatic updates first and derives incomplete-provider recovery from the existing revocation barrier. Focused tests and independent review cover account changes during asynchronous work, same-session refresh, repeated taps, partial cleanup and recovery with no connection row. Physical native acceptance passed. The combined candidate297e1d14 passed CI40059380264; this final evidence update changes documentation only. Public personal access remains disabled.


Production qualification closeout: PR140 merged at app main09883f87. The temporary snapshot endpoint, all qualification secrets and the website's exact-user window were removed; canonical public personal reads/uploads return503, metadata returns200 with the configured production issuer/scopes, and the test account has zero active connections, snapshots and access-log rows. Final normal-config phone launch persisted Disconnected rows and the public-disabled state. Production credentials remain server-only. Public activation is an intentional separate launch decision; the completed private test does not qualify other assistants or directory listing.
