# AI connector threat model

Accepted with ADR-009 (`knowledge/architecture-decisions.md`, 2026-10-12). Scope: the public catalog
MCP (`supabase/functions/mcp-public`), the personal MCP (`supabase/functions/mcp-personal`), the
consent and connections pages on the website, and the app's AI-share consent flow (Phase 2
snapshots).

Audit status, October 13, 2026: containment is merged (PR114/main14152b88) and deployed.
Exact runtime015a43fe passed CI38441160359: 3,858 CI-scoped Flutter tests,214 Deno tests,
analysis, harness and formatting; disposable PostgreSQL checks also passed. Public hostname
routing is deployed via website PR6 and verified in Codex. WorkOS staging hosted login and
synthetic authenticated requests work, but stronger provider qualification failed the S2
resource-binding contract. The sanitized reproduction was sent privately to WorkOS support with
Sean's authorization. No managed authorization runtime is integrated. S2, S6 phone pairing,
S9 policy review and integrated real-client acceptance remain open. Paths below identify actual
coverage; planned controls are marked explicitly.

The former audience-stamping hook did not prove S2: the original requested resource was not
verified. Deployed containment refuses third-party issuance/refresh in the existing hook, returns 503
for every production personal read (including old tokens), and refuses new snapshot uploads.
Authenticated snapshot deletion and public discovery metadata remain available. Ordinary app
sessions are unchanged. This is containment, not resource binding; a reviewed issuer repair and
live wrong-resource issuance/refresh tests remain required before enabling personal access.
See `supabase/functions/mcp-personal/README.md` for deployment ordering and the exact remaining gates.

## Assets

| Asset | Where it lives | Sensitivity |
|---|---|---|
| Supplement list (names, `dsld_id`, `ingredient_keys`) | Phone `user_data.db`; `user_stacks` for signed-in users | Personal; a new disclosure when sent to a provider |
| Medications, doses, conditions, allergens, pregnancy flags | Phone only; inside an encrypted `ai_share_snapshots` row only when the user shares them | Health data |
| PharmaGuide findings for a stack | Computed on the phone; inside a snapshot when shared | Health-derived |
| OAuth grants, access and refresh tokens | Supabase Auth; the AI provider | Credential |
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
   functions `delete-account` and `register-push-token`), Auth (the OAuth 2.1 server, in beta) and
   Vault. An OAuth token is untrusted here until S1 and S2 hold.
3. **Website (pharmaguide.io, PharmaGuide Website repo).** The consent page
   (`src/app/oauth/authorize/`), the connections page (`src/app/account/connections/`) and the
   existing service-role routes (for example `src/app/api/share/route.ts`).
4. **AI provider (Claude, ChatGPT, Claude Code).** An MCP client acting with the user's grant. It
   receives tool output and keeps chat history under its own policy. Everything it sends to
   PharmaGuide is untrusted input; everything PharmaGuide returns may be read by a model, so returned
   text is data, never an instruction.

Crossings: phone → Supabase (TLS, user session JWT); provider → MCP servers (OAuth access token, or
none for the public server); browser → website consent page → Supabase Auth; MCP output → provider
→ the provider's chat history (outside PharmaGuide's control).

## Requirements, threats, controls and tests

| Requirement | Threat | Control | Automated test |
|---|---|---|---|
| S1 Database isolation | An OAuth access token carries the full user session and reads `user_stacks`, submissions, push tokens, Storage objects or RPCs directly; user A reads user B through MCP. | `AS RESTRICTIVE` policies `((auth.jwt()->>'client_id') IS NULL)` on every user-owned table and on `storage.objects`; `client_id IS NULL` guards in every SECURITY DEFINER RPC and user-JWT edge function. MCP servers verify the JWT (JWKS, `iss`, `exp`, `aud`, `client_id`, `sub`) and read with the service role filtered by the verified `sub`; they never forward the token. Review includes the website's service-role routes. | `supabase/tests/ai_connector/restrictive_rls.sql`; `supabase/functions/mcp-personal/auth_isolation_test.ts` |
| S2 Resource binding | A token issued for another MCP resource on the same authorization server (supabase/auth #2610) is replayed against the personal MCP. | The existing Auth hook now refuses third-party issuance/refresh; production MCP returns 503 even for old tokens, and snapshot POST refuses new uploads. Discovery and authenticated deletion remain available. S2 remains unresolved until issuer repair and real issuance/replay/refresh tests. | `supabase/functions/mcp-personal/resource_binding_test.ts` tests production containment and synthetic audience checks; `supabase/functions/ai-share-snapshot/index_test.ts` tests denied uploads and permitted authenticated deletion; SQL hook cases test issuance/refresh refusal. Actual AS binding remains unproven |
| S3 Client identity | A look-alike client or redirect URI collects the authorization code; open DCR lets anyone register. | Pre-registered trusted clients (Claude, ChatGPT, Claude Code) with exact callback-URI matching in production; production DCR=false applied and verified; loopback callbacks only for the approved native client; the consent page shows the verified client and callback host in large type. | Website repo `tests/ai-connector.test.cjs`; exact hosted Codex staging registration/callback verified; production registration remains pending |
| S4 Consent preview | The user shares more than intended, or a derived finding discloses an excluded category. | The preview names the destination (client and host), categories, duration, the three data locations and the revocation path (`pharmaguide.io/account/connections` and in-app Settings). The payload shown is the payload sent; derived findings follow their category. | `test/release_gate/ai_share_snapshot_scope_test.dart` (excluded categories absent, including medication-derived findings; preview equals payload); `test/features/ai_share/ai_share_consent_preview_test.dart`; `test/features/ai_share/ai_connections_screen_test.dart` (stored verified client name/host and legacy identifier fallback) |
| S5 Revocation and purge | Access or data outlives the user's decision: an unexpired access token keeps working after Disconnect; snapshots survive sign-out or account deletion. | Disconnect calls `revokeGrant`, marks the connection revoked and deletes its snapshots and log rows; `delete-account` purges everything; app sign-out stops refreshes and attempts deletion before ending the session; offline deletion may fail and is not promised immediate. Expiry denies reads; configured cleanup removes expired rows. | `supabase/functions/mcp-personal/revocation_purge_test.ts`; `test/release_gate/ai_share_snapshot_signout_purge_test.dart` |
| S6 Desktop approval | A desktop consent is phished, or approved from the initiating session. | Default-off pairing code binds the verified request to approval by a different live session of the same account. This is not device attestation. | `supabase/tests/ai_connector/phone_pairing.sql`, website authorization tests and app pairing tests cover expiry, replay, isolation and races. Hosted flow and real-device acceptance remain open |
| S7 Audit, rate limits, caching | Abuse goes unseen; anonymous lookups cause unbounded Storage reads; the log turns into a health-data store. | `mcp_access_log(connection_id, tool, at)` with no payload columns; per-IP and per-client limits on the public server, per-connection limits on the personal server; in-function caching of the manifest and index, CDN-served blobs. | `supabase/functions/mcp-public/index_test.ts`; `supabase/functions/_shared/catalog_test.ts`; `supabase/functions/mcp-personal/access_log_test.ts`; limits are per instance |
| S8 Tool output is data | A hostile product label or user-entered name returned by a tool instructs the assistant (prompt injection). | Public product facts and supplement-list names are length-capped and source-tagged in a data envelope. Snapshots preserve the previewed Markdown within a scoped, dated payload. Instructions identify tool content as data; this does not guarantee a provider will resist hostile text. | `supabase/functions/_shared/catalog_test.ts`; `supabase/functions/mcp-public/index_test.ts`; live hostile-content checks remain required |
| S9 Policy and legal | Health data is disclosed without policy cover; a connector carrying PHI is listed in a directory against provider policy. | Privacy policy update; FTC Health Breach Notification Rule review; directory listing for the public server only; the personal connector stays private until OpenAI's policy is confirmed. | `supabase/functions/_shared/catalog_test.ts` and `supabase/functions/mcp-public/index_test.ts` cover the public allowlist; policy items require Sean's review |
| S10 Grant-level authorization | A valid token reaches tools or categories its connection was never granted; one connection's scope leaks into another ("supplements to Claude, medications to ChatGPT"). | An `ai_connections` row is created at consent. Every personal request uses the service-only `bind_ai_connection_session` RPC to check the live Auth session's user, client, original creation time and expiry against an active, unrevoked, unexpired connection. Initial binding returns current state rather than a cached approval; bound sessions are checked again on every request. Tool categories and snapshot connection binding remain independent. | `supabase/functions/mcp-personal/grant_authorization_test.ts`; `supabase/tests/ai_connector/snapshots_pre_request.sql` |

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


## October 23 implementation plan — phone approval, Codex first

Approved by Sean: OAuth, phone approval, read-only scoped snapshots; full-flow acceptance before personal activation.
Goal: finish the phone-approval seam while retaining issuer containment. This is a partial implementation checkpoint, not personal-access readiness.
Architecture: the existing website consent route verifies the pending OAuth client/callback; the existing app connections screen approves a short-lived challenge; the consent route consumes that exact approval before creating the existing ai_connections grant. Snapshot scope and clinical findings remain owned by AiShareScope/AiBriefBuilder and the existing Dart engine.
Tech stack: existing Next.js consent route, PostgreSQL transaction/RPC, Flutter connections repository/screen.

Owner: src/app/api/ai-connections/route.ts and src/lib/ai-connector.ts (website) — rg authorize/approve/connection; lib/features/ai_share/ai_connections_repository.dart and ai_connections_screen.dart (app) — rg connection/pairing; ai_connections and snapshots migrations — schema inspection. No pairing protocol-state owner: searched both repos, matrix and glossary; ADR-009 already requires pairing. Extend the connection feature with an expiring ai_connection_pairings protocol table, not another connection or clinical authority. Will NOT create another scorer, medication sync, issuer, snapshot format or public personal-access enable switch.

- [x] Add fail-first PostgreSQL pairing tests in the existing disposable ai_connector harness. Start/preview/approve/consume are atomic RPCs; no direct client table writes. Store SHA-256 of a cryptographically random 12-character base32 code, never the raw code. Five-minute expiry, bounded attempts/rate, same account, different live non-OAuth Auth sessions for browser and approval. Exact authorization ID/client/callback binding, one-time consumption, no concurrent replay; expire or consume stale challenges. Pairing confirms an action in the signed-in app flow; it is not hardware attestation and cannot distinguish another client holding a valid app-session credential.
- [x] Extend existing website route/helper with pair_start, pair_status and existing approve requiring atomic pairing consumption. Keep server rollout flag off by default. Verify identity against Auth, never trust client-provided user/client/callback. Existing client allowlist adds Codex only after callback verification. Return verified destination, five-minute code and pending/approved status; never tokens. The website displays the code and waits for phone approval before enabling completion. Denial and all errors fail closed. Keep browser consent from approving itself.
- [x] Extend existing Flutter repository/screen with enter-code, preview verified assistant/destination/expiry, approve and cancel. Reuse signed-in Supabase session and existing styling; feature flag off by default. No snapshot upload or OAuth approval happens on preview. Keep medication/profile default exclusions and exact share preview unchanged.
- [ ] Run SQL, website owner tests/typecheck, Flutter focused tests/analyze and simulator rendering. Review full diff and adversarial cases (wrong user/session, expired/replayed/mismatched approval, concurrent completion, deleted session, failed issuer). Run source CI for completed candidate before merge.
- [ ] Full hosted OAuth + phone + snapshot + Codex acceptance: blocked by managed issuer contract. WorkOS engineering reply October20 explicitly says immutable authorization/refresh-family identity is unavailable, no date; sid remains reusable consent. No substitution of mutable claims or latest-consent lookup. Production mcp-personal and snapshot POST must remain503. Requalify resource-less requests and exact-grant binding before integrating issuer; then run two-account isolation, PKCE/callback/resource negatives, refresh, disconnect/reconnect races, snapshot scope/expiry, and read-only Codex calls with synthetic data. S9 and real-device approval remain separate release gates.

Evidence: /Users/seancheick/pg_quality/workos_retest_20261015/REPORT.md and current support thread read October23. No support message sent. No real health data needed for tests.

Plan review refinement: connection replacement/creation and pairing consumption must share one database transaction. Cancellation and disconnect invalidate pending approvals under the same user/client locking boundary, so delayed completion cannot recreate access. Enforce rate/attempt limits in PostgreSQL, not only per-process. UI confirmation is different-session approval, not device attestation; S6 live device acceptance stays open. Backend contracts below are internal to this existing feature.

Pairing RPC contract (JSON replies except explicitly void operations): start_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text,p_client_id text,p_client_name text,p_redirect_uri text,p_code_hash text) -> {expires_at}; ai_connection_pairing_status(p_user_id uuid,p_session_id uuid,p_authorization_id text) -> {approved,expires_at}; preview_ai_connection_pairing(p_code text) -> {client_name,callback_host,expires_at}; approve_ai_connection_pairing(p_code text) -> {approved:true}; complete_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text,p_client_id text,p_redirect_uri text) -> {connection_id,expires_at}; cancel_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text) -> void. Start/status/complete/cancel service-role only; phone preview/approve authenticated only, own verified JWT and live session. Existing disconnect path must call revoke_ai_connection_pairings(p_user_id uuid,p_client_id text), service-only, prior to grant revocation, sharing completion's lock and invalidating pending state. Complete grants only existing supplements category; a separately previewed snapshot still controls sensitive categories. Hash canonical code: upper-case, remove hyphens/whitespace; alphabet ABCDEFGHJKLMNPQRSTUVWXYZ23456789, 12 random characters. Client code validates format; DB revalidates. Errors are generic without raw code/token logging. All website new actions including approve are disabled unless AI_CONNECTOR_PAIRING_ENABLED=true; existing disconnect stays available. Flutter entry default disabled via PHARMAGUIDE_AI_PAIRING_ENABLED. No production flag enabled.

Verification checkpoint October23: disposable SQL suite passed, including overlapping complete/complete and disconnect/complete; 60 focused Flutter owner/release-gate tests passed; 56 Deno containment/auth/snapshot tests passed. App focused analysis passed. Synthetic phone rendering at 390x844 and 1.3 text scale was inspected; no real-device or hosted OAuth acceptance is claimed. Website 30 connector tests, 8 privacy tests and 2 routing tests passed; focused lint/typecheck passed. Independent app/SQL/website source review found no remaining material findings after correction of empty void-RPC responses and duplicate disconnect cleanup. Exact-candidate CI remains pending. Apply migration `20261023193612_ai_connection_phone_pairing.sql` before deploying the website: disconnect depends on its atomic revoke RPC even while pairing is disabled. No migration, website deployment or flag enablement performed.
