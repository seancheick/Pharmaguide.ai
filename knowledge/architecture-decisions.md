# Architecture Decision Records

> Append-only log of key technical decisions.  
> **Format:** ADR-NNN, one per decision. Never delete or modify a past ADR -- supersede it with a new one.  
> **Rule:** If you are about to make a choice that affects data flow, persistence, or user safety, document it here first.

---

## ADR-001: Two-Database Architecture

**Date:** 2026-04-05  
**Status:** ACCEPTED  
**Context:** The pipeline produces a read-only reference database (~90MB, ~180K products) that gets OTA updates. User data (profile, stacks, scan history, favorites, detail cache) must never be lost during OTA updates.  
**Decision:** Use two separate Drift databases on-device:
- `pharmaguide_core.db` -- read-only, bundled in assets, replaced atomically via OTA
- `user_data.db` -- read/write, created on first launch, never touched by OTA

**Consequences:**
- OTA swap is safe: staging -> checksum -> integrity check -> atomic rename -> reopen -> delete backup
- Cross-DB joins are not possible in Drift -- use application-level joins via dsld_id
- Detail cache lives in user_data.db so cached blobs survive OTA swaps
- Total on-device storage: ~90MB (core) + ~50-200MB (cache) + <1MB (user data)

**Alternatives considered:**
- Single database with migrations: rejected because OTA would require complex migration scripts and risk user data loss
- Server-only: rejected because offline-first is a core requirement

---

## ADR-002: Two-Layer Interaction System

**Date:** 2026-04-05  
**Status:** ACCEPTED  
**Context:** Drug-supplement interactions need to be checked at two levels: (1) general class-level interactions from the pipeline data, and (2) specific drug interactions that require more granular data than the pipeline provides.  
**Decision:** Implement a two-layer interaction system:
- **Layer 1 (Pipeline):** Class-level interactions baked into `interaction_summary_hint` and `interaction_summary` in scored data. Covers broad categories (e.g., "blood thinners" as a class).
- **Layer 2 (Flutter):** Drug-specific interactions loaded from a separate interaction database on-device. Populated from Supp.ai or similar validated source. Enables checking "warfarin + vitamin K" not just "blood thinners + vitamin K."

**Consequences:**
- Layer 1 is available instantly from SQLite (interaction_summary_hint column)
- Layer 2 requires a separate data import/validation step before Flutter can use it
- Users see immediate class-level warnings, then refined drug-specific warnings after detail hydration
- The two layers may occasionally disagree -- Layer 2 (more specific) takes precedence in display

**Alternatives considered:**
- Pipeline-only: rejected because pipeline only knows drug classes, not specific drugs the user takes
- Flutter-only: rejected because pipeline already computes useful class-level interactions

---

## ADR-003: Drug Class Checklist in Profile for V1.0

**Date:** 2026-04-05  
**Status:** ACCEPTED (superseded in V1.1)  
**Context:** ScoreFitCalculator E2c section needs to know what drug classes the user takes to compute interaction penalties. In V1.0, we don't have a drug-specific stack, so we can't derive drug classes automatically.  
**Decision:** Keep a manual drug class checklist (9 classes) in the profile setup flow for V1.0. The 9 classes match `clinical_risk_taxonomy.drug_classes` in the pipeline reference data.  
**Consequences:**
- Users must manually select drug classes during profile setup
- UX is slightly heavier (one more step in onboarding)
- ScoreFitCalculator has the data it needs for V1.0
- V1.1 will derive drug classes from the user's actual medication stack, making this checklist optional

**Drug classes (V1.0):**
1. Blood thinners / anticoagulants
2. Blood pressure medications
3. Diabetes medications
4. Thyroid medications
5. Immunosuppressants
6. Antidepressants / SSRIs
7. Statins
8. Seizure medications
9. Chemotherapy / cancer drugs

---

## ADR-004: Stack Safety Score Separate from FitScore

**Date:** 2026-04-07  
**Status:** ACCEPTED  
**Context:** Users need two distinct safety signals: (1) how good a single product is for their profile (FitScore), and (2) how safe their overall supplement stack is when taken together (Stack Safety Score).  
**Decision:** Keep these as separate scores with different formulas:
- **FitScore (0-100):** Per-product. Computed from pipeline score + profile adjustments (conditions, drug classes, allergens, goals). Never persisted.
- **Stack Safety Score (0-100):** Per-stack. Computed from interaction cross-checks across all products in the stack. Has hard-stop caps (if any product is BLOCKED, stack score caps at 0).

**Consequences:**
- UI must clearly distinguish between the two scores (different colors, labels, locations)
- Stack Safety Score requires ingredient fingerprint cross-referencing across products
- Hard-stop cap means one bad product tanks the entire stack score -- this is intentional for safety
- Both scores are computed on-device, never sent to server

**Alternatives considered:**
- Combined score: rejected because mixing product quality with stack safety conflates different concerns
- Stack score as average of FitScores: rejected because it misses interaction effects entirely

---

## ADR-005: Supp.ai as Data Source for Flutter Interaction DB

**Date:** 2026-04-07  
**Status:** PROPOSED (needs validation)  
**Context:** Layer 2 of the interaction system (ADR-002) needs a validated source of drug-supplement interactions at the specific-drug level. Options evaluated: Supp.ai (University of Washington NLP-extracted interactions from literature), DrugBank (comprehensive but expensive license), NHP-Drug-Interaction-Checker (Canadian, limited scope), and manual curation.  
**Decision:** Use Supp.ai as the primary data source for the Flutter interaction database. Before import, each interaction entry must be validated against at least one corroborating source (PubMed, FDA label, or clinical guideline).  
**Consequences:**
- Supp.ai data is NLP-extracted, so it has false positives -- validation step is mandatory
- Free for academic/research use; need to verify license for commercial app
- Coverage is good for common supplements but may miss niche products
- Import pipeline: Supp.ai dump -> validation script -> staging DB -> human review -> production DB
- Must track provenance (source URL, validation date, validator) for each interaction rule

**Alternatives considered:**
- DrugBank: comprehensive and validated but $25K+/year license
- Manual curation: highest quality but doesn't scale; could supplement Supp.ai for high-priority interactions
- NHP-Drug-Interaction-Checker: too narrow (Canadian regulations only)

**Action items:**
- [ ] Verify Supp.ai license terms for commercial use
- [ ] Build validation script that cross-references Supp.ai entries against PubMed
- [ ] Define minimum confidence threshold for auto-approval vs. manual review

---

## ADR-006: Stack Health Uses One Tier and Signal Snapshot

**Date:** 2026-08-08
**Status:** ACCEPTED
**Supersedes:** The user-facing Stack Safety Score portions of ADR-004. FitScore and Stack Health remain separate concepts.
**Context:** A numeric, score-derived label and independently assembled UI finding lists allowed the Home card, Stack summary, warning banner, and details sheet to disagree. Incomplete evaluations could also receive a graded "Decent" label, while profile-specific cumulative dose alerts affected the tier without appearing in the review count.

**Decision:**
- `StackIntelligence.deriveTier` is the only Stack Health tier engine. The internal numeric score may rank otherwise-clean complete stacks, but is never rendered or converted to a second verdict.
- Tier precedence is Unsafe (banned/recalled/contraindicated), Concerning (avoid or at least two UL-proximity warnings), Decent (caution or one UL-proximity warning), More info needed (materially incomplete with no actionable gate), then Solid/Optimized.
- Incomplete intentionally overrides monitor-only and score-band labels. Known monitor signals remain visible in the review list.
- One `StackHealthSnapshot` owns the tier, ordered review signals, count, and completeness state consumed by every Stack Health surface.
- Dose-threshold alerts are typed clinical signals. Their identity includes target type/id, canonical ingredient, comparator, normalized threshold, and unit.

**Consequences:**
- Avoid remains Concerning; this ADR does not silently change clinical policy.
- Two UL-proximity warnings remain Concerning.
- Home, Stack, the hero warning, and the details sheet use the same signal count and noun.
- “Optimized” means no identified concerns under the checks that completed; it does not mean an ideal or universally safe supplement stack.
- Score-derived `RiskTier` and `healthLabel` APIs are removed to prevent a second classification path from returning.

---

## ADR-007: Guest scope, first run, and never affirming "safe"

**Date:** 2026-09-28
**Status:** ACCEPTED (Sean, product/UX audit round 2; see docs/PRODUCT_UX_AUDIT_2026-09-28.md §12)
**Supersedes:** the 2026-05-18 access tier "Guest: no saved stack" (dcd5c5fc).
**Context:** The audit found that the app asserted more certainty and protection than it has: "Safe to add" on an empty stack, safety phrases in quality-tier copy, a safety-green scan flash before any personal check, and a Face ID switch with no lock behind it. It also found a sign-in wall before any value, even though stack and wishlist data never needed an account.

**Decision:**
- No surface affirms "safe". A clear pre-add check reads "No known interactions with your stack". An empty stack reads "nothing to check against yet". A product missing from the catalog counts as not checked. Quality tiers describe quality only. The scan flash means "found" (brand accent), never a safety colour.
- Guests keep a stack and wishlist on the device. An account adds backup and sync of the supplement stack only. Profile, medications and allergies never upload. Guests still get 3 scans a day.
- First run is one screen with no sign-in step. The account is offered when someone wants sync. Returning users skip the splash.
- iOS excludes app data from backups (Documents and Application Support), matching Android's `allowBackup="false"`.

**Consequences:**
- A signed-out device keeps showing its local stack and wishlist (as the stack already did). A different account signing in clears them (AccountSwitchGuard).
- A new phone starts fresh unless the user signed in; the supplement stack syncs back.
- The first sign-in adopts guest rows and pushes the supplement rows. The medication-never-syncs guards are unchanged (release-gate test).

---

## ADR-008: Apple's own tab bar on iOS 26, Flutter bar elsewhere

**Date:** 2026-09-28
**Status:** ACCEPTED (Sean: "I want the legit one"; see docs/PRODUCT_UX_AUDIT_2026-09-28.md §12.3)
**Context:** A Flutter imitation of iOS 26 Liquid Glass (lens, blur, springs) didn't read as Apple's material, and its accessibility fallback looked wrong. Flutter 3.44 has no Liquid Glass support, and the HIG says the material ships inside Apple's frameworks and other stacks can only approximate it.

**Decision:**
- On iOS 26+, the shell's tab bar is a real `UITabBar` hosted as a platform view (`ios/Runner/NativeTabBar.swift`). The system owns the material, the interaction and the accessibility states. `PGTabBar` (`lib/core/widgets/pg_tab_bar.dart`) makes the choice.
- On Android and iOS 18–25, `PGFrostedNavBar` stays as it was.
- Glass is added elsewhere only with native iOS 26 controls, and only in the functional layer (scanner controls, the segmented control, floating toolbar actions). There is no Flutter glass imitation, and no glass on content, warnings or evidence.

**Consequences:**
- Every tab screen composites one platform view on iOS 26. That needs a physical-device scroll check before release; the simulator can't profile.
- Tabs are declared once, as `PGTab` entries (label, Material icons, SF Symbols), and both bars read from them.
- Flutter exposes no Reduce Transparency flag, so Flutter-drawn blur reads it from `ReduceTransparency.of(context)` (`AppDelegate.swift` bridge).
- Taps: `NativeTabBar.swift` removes Flutter's delaying recognizer from the bar's host view, because quick taps (under ~30 ms) were being dropped. `PGTabBar` switches the bar off while a modal route covers the shell. Re-check both after any Flutter upgrade.

**Addendum 2026-09-28: chat (Ask PharmaGuide).** Sean decided that chat answers on the device, is stack-aware, and is personal (medications, conditions, allergies, sex, age). This replaces the cloud Gemini plan in SPRINT_TRACKER V2.0, and the Profile preview ("answered on this device and aren't sent anywhere") commits to it. Before launch, choose the on-device model. Apple's Foundation Models framework needs an Apple Intelligence iPhone, so decide what other phones get. Chat stays out of the tab bar until it works (App Review 2.1(a)). The copy never says "pharmacist" (a protected title under state pharmacy acts, e.g. Fla. Stat. §465.015), "first", or "safe".

---

## ADR-009: AI-assistant sharing — public catalog MCP, personal connector, consented one-shot stack snapshots

**Date:** 2026-10-12
**Status:** ACCEPTED (Sean, 2026-10-12, after two external reviews; every factual claim was reproduced against a primary source before it was adopted)
**Context:** Sean wants a user talking to ChatGPT or Claude to connect PharmaGuide, so the assistant reads what the user chose to share (supplements, medications, findings) and advises on it. Long term, the assistant asks PharmaGuide's engine to check a proposed product against the user's real regimen before suggesting it. Today's rules point the other way. ADR-007 says profile, medications and allergies never upload. Stack sync excludes medications at three layers (the Drift filter and assert in `lib/features/stack/services/stack_sync_queue.dart`, the `user_stacks` `CHECK (type = 'supplement')`, and RLS `WITH CHECK`), pinned by `test/release_gate/phi_medication_no_sync_test.dart`. The ADR-008 addendum promises that Ask PharmaGuide chat answers on the device. External facts, verified on 2026-10-12:
- Claude and ChatGPT accept a remote MCP server for personal data only with OAuth 2.1 (protected-resource metadata, PKCE S256, DCR or CIMD; no static keys).
- Supabase Auth's OAuth 2.1 server is in beta. Its access tokens carry the user's full database session; scopes have no effect on table access, so only RLS on `auth.jwt()->>'client_id'` restricts them.
- supabase/auth #2610 (open since 2026-07-02): the `resource` parameter is ignored and `aud` is always `"authenticated"`, so a token is not bound to one MCP resource.
- Apple Health medications are read-only for third-party apps (iOS 26), with per-medication read authorization and no supplement category.
- OpenAI's directory guidelines list PHI as restricted data for listed plugins; private connectors are not addressed.

**Decision:**
- **PharmaGuide evaluates; the LLM explains.** Findings come from the one Dart engine with versioned evidence. No clinical rule is re-implemented in TypeScript or any other server language. If a server-side engine is needed, it runs the same Dart code (Phase 4 spike; the hosting decision goes in ADR-010).
- **Two endpoints, two trust levels.**
  - Public catalog MCP (`supabase/functions/mcp-public`): no account, product discovery and catalog assessments from pipeline-published artifacts, no personal data. It is the only candidate for a directory listing.
  - Personal MCP (`supabase/functions/mcp-personal`): OAuth. First the supplements already synced to `user_stacks`; later consented snapshots and stack checks. Private and unlisted.
- **One scoped exception to "medications never reach Supabase".** The only path is a user-initiated, one-shot snapshot. The user picks the scope in the app (`AiShareScope`), sees a preview of the exact payload, and shares it explicitly. The snapshot is bound to one `ai_connections` row and stored in `ai_share_snapshots`, encrypted with application-level AES-GCM in the edge function; keys live in Supabase Vault or function secrets with a `key_version` (pgsodium is pending deprecation). Honest wording: encrypted at rest; PharmaGuide's server can decrypt it while the share is live; it is not end-to-end encrypted. Default lifetime is 24 h, at most 30 d. It is deleted on disconnect, app sign-out, account deletion or expiry. Ongoing refresh is a separate opt-in, off by default and ended with one tap; a category added later (a medication, a condition, a pregnancy flag) is never shared silently. The stack-sync path and its three medication guards are unchanged: stack sync still never carries medication rows.
- **Three data locations.** Shared data can be stored by PharmaGuide, transmitted to the AI provider, and retained in the provider's chat history. Revocation reaches the first and ends the second; it cannot reach the third, and the consent copy says so. A supplement list sent to a provider is a new disclosure even when PharmaGuide stores nothing new, so it gets the same consent preview.
- **Security requirements S1–S10**, each with an automated test (full table: `docs/security/ai-connector-threat-model.md`):
  - S1 Database isolation: restrictive `client_id IS NULL` RLS on user-owned tables, Storage, SECURITY DEFINER RPCs and user-JWT functions; MCP servers verify the JWT themselves and never forward it.
  - S2 Resource binding: verify the issuer actually binds tokens to the requested MCP resource; audience stamping alone is insufficient. Legacy Supabase third-party issuance remains disabled.
  - S3 Client identity: production accepts only pre-registered clients with exact callback URIs; DCR runs on staging only.
  - S4 Consent preview: destination, categories, duration, the three data locations and the revocation path.
  - S5 Revocation and purge: disconnect, sign-out and account deletion delete snapshots and log rows; an unexpired token loses access immediately.
  - S6 Desktop approval: a short-lived pairing code; the deep link is the same-device path only.
  - S7 Audit, rate limits, caching: a payload-free access log, per-IP, per-client and per-connection limits, and cached catalog reads.
  - S8 Tool output is data: label and user strings are tagged by source, length-capped and wrapped in a data envelope.
  - S9 Policy and legal: privacy policy, FTC Health Breach Notification Rule review, and a directory listing for the public server only.
  - S10 Grant-level authorization: every personal tool call resolves to an active, unexpired connection and enforces that connection's own categories.
- **Completeness rule.** "No known concerns" is permitted only when identity resolution, the relevant medication list, amounts/doses and the evaluated rule sets are all present for the shared scope. `mapped_coverage` is one input, never sufficient on its own. Otherwise the answer lists exactly what was not assessed ("not fully checked: medications not shared; 2 ingredients unresolved").
- **Wording rule.** No tool output makes an unsupported declaration that a product or regimen is safe. Pipeline- and clinician-authored classifications (for example "unsafe" or "contraindicated") pass through verbatim with their `evidence_level` and source.

**October 23 accepted refinement (Sean):** WorkOS durable consent is the assistant OAuth owner;
Supabase retains ordinary app identity and all existing data owners. OAuth automatic renewal lasts
until disconnect. Bind phone approval to the verified issuer/sub/client/sid, never mutable metadata
or the latest connection. A repeated active consent retains existing scope; disconnected consent
stays revoked and reconnect requires a new SID. Same-token pinned UserInfo supplements local JWT
and connection checks. Disconnect blocks/purges locally before provider revocation and retains a
retry barrier on failure. Snapshot lifetime and explicit sharing remain independent. The existing
threat-model execution register owns evidence and rollout gates; this refinement does not enable
personal production access or change clinical decisions.

**Consequences:**
- `test/safety_invariants/no_health_in_supabase_test.dart` gains exactly the snapshot path in its allowlist, nothing broader. `test/release_gate/phi_medication_no_sync_test.dart` stays unchanged.
- Privacy copy that promises device-only health data needs a connected-case amendment before snapshots ship: the Ask PharmaGuide preview ("answered on this device and aren't sent anywhere", still true for chat itself) and "Your health profile and medication list stay on this device." in `lib/features/settings/v2/settings_v2_screen.dart`, and "saved on this device only" in `lib/features/medications/v2/medication_entry_v2_screen.dart`. The wording is Sean's decision.
- The privacy policy is updated and the FTC Health Breach Notification Rule is reviewed before a personal connector reaches users (S9).
- Supabase Auth as the authorization server stays conditional on the S1–S3 adversarial tests passing on a staging project. If it cannot pass, the authorization server is replaced (own server or hosted IdP) and Supabase keeps the database and functions.
- The personal connector stays private and unlisted until OpenAI's policy for private connectors is confirmed; only the public server goes to directories.
- Snapshots (Phase 2) start only after this ADR and the AGENTS.md amendment are merged, the personal-connector gate (S1–S3, S5, S10) is green on staging, and `AiShareScope` has landed.
- Apple Health import is one-way (Health → PharmaGuide medications), stays on the device, and never implies AI sharing.
- ADR-007's "Profile, medications and allergies never upload" now carries this one exception; the ADR-008 chat addendum is unchanged.

---

## ADR-010: One engine, server-side via dart2js in the edge function (native Dart as fallback)

**Date:** 2026-10-12
**Status:** PROPOSED (spike evidence in `docs/spikes/2026-10-12-engine-service-spike.md`; Sean decides the refactor investment, estimated 20–25 files, 3–5 days)
**Context:** Phase 4 of ADR-009 ("check against my stack" for AI assistants) needs the same findings the app shows: interactions with evidence levels, depletions, duplication and dose context. A TypeScript re-implementation would create a second safety brain. The spike compiled the unchanged Dart engine (29 files) with `dart compile js -O2` and `dart compile exe` through a compile-time overlay that swaps only the three Drift database libraries and `crash_reporting_service`, plus `flutter/foundation` and `material` shims. On a real-catalog fixture (ginkgo candidate; fish oil, garlic and warfarin in the stack) the JS, AOT and VM outputs and the app's own provider path over the full interaction DB produced byte-identical findings. A 10-item stack costs about 1 ms warm in Deno and under 1 ms native; the bundle is about 0.5 MB. The 25 MB interaction DB is about 90% `research_pairs`, which the safety checks never read; the live safety ruleset is about 2.1 MB. Edge Functions allow 256 MB and 2 s CPU per request.

**Decision (proposed):**
- The engine stays in Dart in this repository. No clinical rule is re-implemented in TypeScript or any other server language (ADR-009).
- Before any server use, `lib/` exposes a pure engine API: an `InteractionRuleSource` interface, plain or platform-neutral row types, the orchestration extracted from the Riverpod providers (`stack_safety_providers.dart`) into `lib/services/engine/`, an injectable severity drift hook in place of the Sentry import in `severity.dart`, and `meta` in place of `flutter/foundation`. The app providers become thin adapters over that API.
- The server build is `dart compile js` of that API, called from the personal MCP edge function through a `dart:js_interop` export. TypeScript handles only auth, MCP transport and JSON.
- The pipeline publishes the live safety ruleset (interactions, `drug_class_map`, `profile_warning_rules`) and the reference JSON as one versioned artifact. `research_pairs` is served by an indexed query or left out of assistant answers.
- Release gate: golden fixtures over a fixed set of stacks and products, including blob-backed dose and UL cases, must produce identical findings on the VM and on JS in CI (JS treats ints and doubles alike, so numeric semantics are a tested surface).
- Fallback: if the Supabase Edge Runtime cannot run the JS within limits, the same API is built with `dart compile exe` as a container service called by the MCP function. Decision rules are identical.

**Consequences:** a one-time refactor that also simplifies testing the app; rule and reference updates ship with the catalog version, not with function deploys; completeness flags (`checks_incomplete`, unresolved identity, missing blobs) cross the API unchanged, so "no known concerns" is only emitted under the ADR-009 completeness rule. Open: the Supabase Edge Runtime itself was not exercised (only the Deno CLI and Node); dose, UL, FitScore, profile-gate and timing paths compiled but were not golden-checked for lack of blobs; whether research-pair evidence belongs in assistant answers at all.

---

## ADR-011: Private observed identifiers and complete no-GTIN submissions

**Date:**2026-10-26  
**Status:** ACCEPTED by Sean, including activation concurrency, PG_SUB lineage, frozen-null GTIN and rejection-resubmission amendments.

The existing submission/draft/intent/evidence/review owners support an optional validated GTIN plus private `identifier` evidence (exact observed_code, contributor code_type/issuer, brandName/fullName, optional listing_url, explicit no_code). Contributor classification never attests reviewer verification. Revision-bound no-code waives only barcode-photo completeness; core label evidence remains required. No alternate-code scanning or public identifier mapping is introduced.

Existing reviewer match checks support explicit label_review/new_product_verified against complete current released and pending candidates; unknown/empty search does not prove absence. Approval, reopening, identifier changes, catalog activation and active search-generation writes share one transaction identity lock before row/manifest locks. Stale/conflicting candidates block approval or publication, including empty/unrelated release approval lists. Approval snapshots stay immutable.

New manual_label_v2 is the existing canonical approval payload/hash over `{label,identity}`. Identity freezes observed evidence, reviewed decision/GTIN/association, evidence binding and existing bigint match_check_id. The importer validates the whole private envelope, then projects label only. Raw code/URL/rationale remain private; the existing public approval digest remains a hash-only audit commitment, not a lookup key or anonymity claim. Full normative contract/ownership: paired pipeline docs/adr/0006-submission-identifier-contract.md and source_of_truth_matrix.json.

Transport retry, interrupted capture, sign-in continuation and requested retakes retain the submission UUID. Explicit rejection resubmission keeps a new UUID plus resubmissionOf. Numeric clients/drafts/v1 approvals remain compatible. A verified GTIN added later never replaces a stable product ID; a conflicting published identity blocks pending separate resolution. Correction B to A's PG_SUB product preserves A's lineage and saved references, while B supplies new approval evidence. Frozen reviewed GTIN controls export even when null; mutable candidate UPC never fills it.

No personal profile/medication/goal data is added to Supabase. Publication and installed-app delivery remain separately verified release activities.

---

## ADR-012: One immutable release folder per catalog and rules update

**Date:** 2026-11-02
**Status:** ACCEPTED for implementation on 2026-11-03 (hardening plan A2 and A3). The open choices below were closed before coding. Remote rules stay off for public builds until A9 finishes and Sean adds a production key in an app release.
**Context:**
- The catalog (`pharmaguide_core.db`) updates over the air. The interaction rules (`interaction_db.sqlite`) ship only with the app, so a clinical correction waits for App Store review, and nothing checks that the installed rules are the pair the catalog was built against, although the catalog's manifest already names them (`interaction_db_version`, `interaction_db_checksum`).
- Updates rename files in place. SQLite fails reads on an open handle with a disk I/O error (6922) once its file has moved, even after it moves back (reproduced 2026-11-02 on macOS through drift with the bundled SQLite 3.54.0; Python's SQLite 3.54 does not do this and Linux CI keeps reading the old file, so it depends on the build, and iOS has not been run). In-flight checks can therefore fail during every update, though they never read the new catalog (`test/services/catalog_rollback_test.dart`).
- Each release replaces nearly every detail blob. Hashes changed for 91.6%, 100% and 100% of shared products across the three catalog transitions on this machine (2026.10.12 to 2026.11.02). In a sample of 30 products from the last transition, all 30 changed scoring provenance and 13 changed `warnings[].dose_decision`, so an old blob can't be assumed equal to the new one. This is real content, not build noise: a rebuild with no scoring change altered 2 of 15,447 blobs, and removing every version and date stamp would have saved about 0.5% (upper bound 1.6%). Churn should fall as the pipeline settles, but a scoring version bump still rewrites every blob (pipeline master plan, "November 2 — detail-blob churn diagnosis").
- The updater ignores any version that isn't newer, so an older release can't simply be re-pointed at.

**Decision:**
- **Release folders.** `Documents/releases/<id>/` holds `catalog.db`, `rules.sqlite` and `release.json`. The id is `s<sequence>_<catalog version>_<rules version>_p<preparation>`, because bundled, migrated and unsigned releases all have sequence 0 and still need separate folders. A folder never changes after it is complete, and assembling the same id twice reuses it.
- **One pointer.** `Documents/releases/active.json` names the active folder, the previous one, whether the active one has been confirmed, the highest verified sequence, known revocations and refused folders. It is replaced by atomic rename, the only step that changes what is active. The write is durable: flush the temporary file, rename it, then flush the directory. A missing or invalid pointer falls back to the newest kept release it can validate, then the bundled pair; a folder is only ever complete after it validated, so every kept folder qualifies. A confirmed release that later fails to open follows the same path, and it is recorded so that it isn't selected again. A crash leaves the old pointer or the new one, and each names a complete folder.
- **Activation order.** Download to `releases/staging/`, verify hashes and manifest, run integrity and version gates on both files, check the pair, prepare the files (below), fetch the stack's blobs, rename the folder into `releases/`, then swap the pointer.
- **Existing installs.** The `.backup` and `.activation.json` recovery from 2026-11-02 now runs once, during migration: it settles what an interrupted update left in the root, then the root files move into a folder. A leftover root `.staging` is deleted and downloaded again.
- **Confirmation.** Opening both files and validating them confirms the release. An unconfirmed release that fails goes back to `previous`, then to the bundled pair. This replaces the `.backup` handling added for A3.
- **In-session switch.** Nothing open is ever moved, so running checks finish on the old release. New handles open from the new folder and `_scopeVersion` rebuilds the provider tree, which picks up both databases once `interactionDb` moves from a `widget` field to bootstrap state. No app restart is needed.
- **Old-reader lifetime.** Neither rule the proposal offered. A replaced release's handles stay open until the process ends, so a running check can always finish, whatever gaps sit between its queries. Counting statements can't see those gaps (a check can wait on a blob fetch between two reads), and counting or cancelling whole checks would instrument every reader for a cost that doesn't justify it: at most one extra pair of idle handles per update in a session, and updates arrive days apart. A running check that outlives the switch finishes on the old release, and its provider tree is already gone, so nothing shows it. Retention runs only at launch, so an open file is never deleted; re-selecting after a revocation during a session (`ReleaseStore.reselect`) deletes nothing.
- **One selected release.** A release fixes the catalog, the rules, the required reference versions and evaluator compatibility together. A check never mixes parts of two releases.
- **Immutable files and open-time writes.** Release files open read-only (`PRAGMA query_only`), and the open-time columns and indexes run once during activation, on the staged copy, after its hash and signature are checked and before its folder is complete. The signature and hash therefore cover the bytes as published. The prepared bytes are local and are not re-hashed; a local attacker with file access is outside this threat model, because the same access could read or change `user_data.db`. `release.json` records the preparation version. A build whose open-time work changed (`kReleasePreparation`, pinned by a test against the column and index lists) assembles a new folder from the same sources at launch, so nothing is ever written in place.
- **Retention.** Keep the active release and the previous one, and delete the rest at launch. Peak disk is about two releases plus staging, so the disk-space check (B1) covers all of it.
- **Bundled pair.** The app's assets are release 0 and the last resort. Existing installs migrate on first launch by moving today's root files into a folder. A root catalog at least as new as the bundled one moves rather than copies, because the old build needed no free space and the upgrade mustn't either. If nothing can be written, the root files open read-only where they are and the next launch tries again. A root catalog that can't be read right now is kept, and the app shows its unavailable state and retries rather than replacing it with an older bundled one; only a file that really is invalid gives way. The bundle counts as seen only once its files are in use, so rules that fail once at first launch come back on the next. After an app update, the bundled catalog replaces the active one only if its version is newer, and the bundled rules replace the active ones only if their version is newer and they satisfy the active release's pair rule. Blocked versions are never picked. When only one side changes, a new folder is assembled from the active part and the bundled part, so a new app build's rule correction still reaches a phone holding a newer catalog.
- **Manifest.** Extend the `export_manifest` table rather than adding one: `release_sequence` (monotonic, separate from content versions, enforced by the publication RPC), `signed_release` (the exact signed JSON text) and `release_signature`. The fields the proposal listed as columns (`rules_version`, `rules_path`, `rules_checksum`, `rules_schema`) live inside `signed_release`, because anything unsigned can't affect activation and a second copy would be a second owner. The app compares sequence numbers. Builds without this code keep comparing `db_version`, so a rollback must also carry a newer `db_version` until they age out. `min_app_version` and the existing schema-major gates apply to each file.
- **Pair rule.** `signed_release` names `catalog` and `rules`, each with version, path, sha256, schema version and minimum app version, plus `min_rules_version`. `rules` is null for a catalog-only release. The pair is the named rules, or the phone's current rules when null; it activates only if the rules version is at least `min_rules_version`, isn't blocked, and every per-file gate passes. An unparseable version fails closed. A release that keeps the same `catalog.sha256` reuses the local file, so a rules-only release downloads only the rules.
- **Stack data moves with the release.** A release doesn't activate until the blobs for the active stack have been fetched and verified against that release's hashes, so an update can't leave a stack waiting for a connection. If they can't be fetched, the phone stays on its last complete release and retries. The old blob is never used for the new release: that would present an assessment built from data the release replaced. Until this ships, `stackDetailReadyProvider` fetches right after activation, which leaves a short window where an offline phone shows incomplete checks.
- **Authenticity.** The manifest is signed with Ed25519 by a restricted release-signing process, separate from Supabase storage and from the app's runtime. Hashes alone don't help if the storage credential leaks, because an attacker can rewrite the hash too, and these files change clinical behaviour on every phone. The app contains only verification public keys. A valid signature proves who published a release, not that its content is clinically correct, so the A9 review stays independent.
- **What is signed.** Exact canonical bytes, with a key ID. The fields are at least: release sequence, every path and hash, schemas, app and rules compatibility, and revocations. Anything unsigned can't affect activation. The app refuses a sequence lower than the highest it has verified, which stops a replay of an old signed release; re-publishing good data uses a new sequence.
- **Key rotation.** The app bundles the current public key and a next one. Rotation ships the next key in an app release, waits until supported builds carry it, then switches signing. A build with no keys ignores the signed fields and behaves as a catalog-only legacy client, so it can never activate remote rules. A build with keys refuses any unsigned row, which rules out stripping a signature to downgrade. The order is therefore: pipeline starts signing, then the first keyed build ships. The written procedure must exist before the first signed release. It names Sean as the accountable custodian, a protected runner or hardware-backed custody for the private key, recovery from a lost key, revocation, and what happens if a key is exposed.
- **Data versus logic.** Remote rules are data read by the bundled Dart engine. A rule needing new evaluation logic raises `rules_schema` and goes through an app release; older builds refuse that file and keep their pair.
- **Rollout.** A catalog-only release keeps the phone's current rules if they satisfy the pair rule. Public builds carry no key until A9 is complete, and the pipeline refuses to publish a rules path to production until its gate file records that sign-off, so two independent locks hold remote rules off. Test builds take a key through a dart-define that release mode ignores.
- **Individual clinical risks use the alert feed.** It is versioned, checksummed and matched on the device, and it can only touch what it names. Older builds skip a kind they can't read and keep any earlier revision of that alert (`safety_alert_repository.dart`).
- **Known revocations persist.** Known revocations are stored on the phone so they survive a restart while offline.
- **What doesn't invalidate a release.** Age, being offline and a blob hash changing are not revocations. A hash change alone doesn't prove that an older complete, compatible release is clinically wrong; a known correction or revocation is published as one.
- **Supported builds.** Older builds can't enforce an alert or rule type they can't read. Every new format ships with a matrix of supported builds and what each one does with it, tested before it is published.
- **Release-level revocation stays separate from alerts.** The signed manifest carries `blocked_versions`, with `catalog` and `rules` lists of content versions, read during the update check. Content versions, not sequences, because a bad rules file stays bad whichever release carried it, and bundled pairs have no sequence. A phone on a blocked version installs the replacement, or returns to its previous confirmed release if that isn't blocked. When only the rules are blocked, the phone keeps its newer catalog (Sean's decision, 2026-11-03): it goes back only to a catalog no older than its own, with rules that meet its minimum, and otherwise withholds interaction checks. If neither is possible, it withholds only the affected assessment and shows a specific notice: blocked rules leave interaction checks in their existing unavailable state, and a blocked catalog becomes a local copy with quality scores removed (`not_scored`, assessment `failed`), so every score surface shows its existing not-scored state through the existing owners. Products stay searchable, and catalog safety status and rules are never touched. It must never disable otherwise valid products. Emergency recovery is a republish under a newer sequence, which `blocked_versions` doesn't replace.

**Alternatives rejected:**
- Swapping the two files in place with a backup: not atomic across two files, and it moves open files.
- Storing results with a dependency fingerprint: results aren't stored, and storing them would add the staleness this avoids.

**Known limits:** nothing reaches a phone that stays offline. It keeps its last complete release. A pointer file that can't be read loses the stored revocations, the replay floor and the record that this bundle was already reconciled until the next online check, which restores the first two; the release itself comes from the newest kept folder. A known-blocked catalog withholds quality at the database read boundary even if a full disk prevents creating its scoreless copy. The memory-only projection preserves product identity, safety status and search row IDs; the original file stays intact, and a later launch can still prepare the copy. Stack blobs are stored just before the pointer swap, because either order leaves a window: a kill inside it leaves the old release with new-hash blobs, so a stack product offline reads as incomplete until the next online check, which is honest and never a false reassurance. A launch that can read nothing on disk, as before first unlock, opens no catalog until the next launch and changes nothing. If a fallback serves such a launch, revocations covering the fallback apply at the next launch or check. Local tampering on a jailbroken phone is outside the threat model.

**What a rules-only release can change (device run, 2026-11-03):** the Stack tab's interaction signals, live and with no app update. It can't change the product page's pregnancy or condition wording on a schema 2 catalog. That wording is inline in the detail blob, and `profile_warning_rules` is read only for schema 3 blobs (`warning_rule_refs`), so such a correction looks published and changes nothing. Ship it as a signed catalog release, which also needs no app update and was proved on screen. A new medication rule doesn't reach the product page today either: `_interactionResultToWarning` carries `class:*` ids and the page compares them against the crosswalked profile ids, so the row is filtered out and the page can say "No known concerns" while the Stack tab says Concerning. Tracked as its own fix, not part of this decision.

**Timing:** a routine release waits 0-60 minutes before it downloads, and a running app checks hourly with no check on resume. A release that blocks the installed catalog or rules skips the wait. The first launch that moves the catalog into `Documents/releases/` took 27 s on a simulator under heavy load (load average 75-107), against 7 s for a relaunch; the unloaded time wasn't measured. Installing an update moves the app's data container; the pointer holds release ids, not paths, so this is harmless.

**Rollback procedure:** republish known-good data under a newer `release_sequence`, naming the bad versions in `blocked_versions`. Steps and key custody are in the pipeline's `docs/RELEASE_SIGNING_RUNBOOK.md`. Phones compare sequences, so older content versions are accepted; a replay of the bad release is refused. Proved by `test/services/release/release_end_to_end_test.dart` and the `rollback` group in `release_store_test.dart`.

**Withholding:** a blocked rules file with no replacement uses the existing unavailable state, so the product page shows "Personalized checks are incomplete", and it keeps the catalog the phone has. A new folder pairing that catalog with the older rules is not built: nothing has validated that pair. A blocked catalog with no replacement becomes a local copy with quality scores removed, which reads as not scored. Safety status and the product list are untouched. No new copy was added; a notice that names the correction is Sean's copy decision. Withholding a blocked catalog's scores doesn't depend on the rules: a release with no rules gets a scoreless copy with none, and rules that recover later stay beside the withheld scores. The copy needs room for a second catalog. On a phone without it, the scores stay readable until a launch that has room.

**Open decision for Sean:** an alert of a new kind that names a product this build can't read currently leaves that product page able to say "no known concerns" (the alert is skipped; `isComplete` reaches only signal resolution). Offline must not trigger any hedge, so a fix has to act only on an unreadable alert that names this product, and it needs new copy such as "a safety notice for this product needs a newer app". No current feed does this. Outside review on 2026-11-02 supports a notice limited to the affected product that keeps existing known concerns and doesn't invent the unreadable alert's severity. Still to settle before A4 publishes a new kind: Sean's approval of the copy, how scope is matched when the alert can't be parsed, and what current and older builds do.

**Tests required:** a crash at each activation step leaves one complete release; a stack's blobs are in hand before activation; a blocked version withholds only the affected assessment; an incompatible pair never activates; a bad signature or hash never activates; a device that skipped several releases updates; rollback survives a real restart; a running check finishes during a switch; release files are unchanged after open; rules change with no app update on a test build; current and older supported builds read every new format.

---

## ADR-013: Each account's health data lives in its own storage

**Date:** 2026-11-02
**Status:** Storage and switching are merged. Encryption is implemented on branch `claude/a5-finish-7dbae8` and isn't adopted until its device checks pass (see "Encryption, 2026-11-02"). A5 is not done and public release stays blocked.
**Supersedes:** ADR-007's "A different account signing in clears them".
**Context:**
- `user_data.db` has no owner column. `getProfile` and `getActiveStack` read whatever is there, and sign-out deliberately keeps everything (`pg_auth_service.dart`), so a guest using the phone after sign-out sees the previous person's medications. Reproduced 2026-11-02 by `test/safety/guest_cannot_read_previous_account_test.dart`, which stays skipped until this ADR is implemented and must pass before public release.
- A different account signing in destroys the previous person's local data, which has no cloud copy.
- Sean decided during the hardening plan that sign-out offers keep or remove, with keep as the default, and that kept data stays locked to the account.

**Threat model:**

| Threat | Answer |
|---|---|
| Someone else uses the same unlocked phone, as a guest or their own account | The main threat. Separate storage; the other person's handle is closed |
| Screens, searches or background jobs surviving an account change | Rebuild the provider tree and reset navigation on every change; test each store |
| Files copied off the device | Already out of backups (iOS exclusion, Android `allowBackup="false"`). Per-account encryption, with keys in Keychain or Android Keystore, covers the rest |
| Lost or stolen locked phone | OS data protection. Keys use after-first-unlock, this-device-only, so background reminders still run |
| Malware or a jailbroken phone while unlocked | Out of scope; no app-level measure holds up here |

OS encryption protects a locked phone. It does nothing about two people using the same app, so both layers are needed.

**Decision:**
- **Layout.** `users/<sha256(uid)>/` and `users/guest/` under Application Support, each holding `user_data.db` and attachments (`account_storage.dart::AccountStorage`). Submission drafts stay where they are, because `ProductSubmissionDraftStore` already keeps one directory per uid and refuses a guest; that path does contain the uid. Health History events store an attachment's absolute path, so a file is found by its name inside the current owner's folder. The hash keeps the uid out of the path. Rejected: a `user_id` column on every table, because one missed filter is a leak, whereas a closed file fails safe.
- **Encryption.** SQLCipher on `user_data.db` with a random per-owner key in secure storage (`flutter_secure_storage`, already a dependency), adopted only if it passes its conditions: per-account keys handled securely, migration tests, measured app size, and validation on physical iOS and Android devices. If it fails any of them, this decision comes back for review; per-account files remain required either way. The spike comes first and has to prove: bindings that work with the locked drift and sqlite3 versions, that the cipher is present and a wrong key is rejected on release builds, that the key is durably stored before the migration commits, that `user_version` is preserved, that WAL files and a partial migration are handled, and that recovery never opens an owner's plaintext data as guest. After-first-unlock keeps background reminders working but leaves the keys usable while a phone is locked after its first unlock; this is the accepted trade-off to confirm. **Spike, 2026-11-02** (throwaway app on drift 2.31.0, sqlite3 2.9.4, `sqlcipher_flutter_libs` 0.6.8; evidence in `~/pg_quality/sqlcipher_spike_20261102/`). On a macOS release build and an iOS simulator debug build: SQLCipher 4.10.0 over SQLite 3.50.4 links and runs, a wrong key and no key are both rejected with error 26, no plaintext stays in the file, WAL sidecars clear on close, and an unencrypted file still opens without a key. Three findings bind the implementation: `sqlcipher_export` doesn't copy `user_version` (it came back 0, not 13), so the migration must set it, or drift would treat the file as new; `PRAGMA key` does nothing on plain SQLite, so an open must check `PRAGMA cipher_version` and fail closed; and `sqlcipher_flutter_libs` 0.7.0 is an end-of-life stub for sqlite3 3.x, so adoption either pins the 0.6 line or moves to sqlite3 3.x first. Not run: Android (the local AVD fails with "No initial system image"), any physical device, and the size change in the real app. SQLCipher therefore isn't adopted. If SQLCipher is adopted, "Remove" must delete the key and the folder. Today it deletes the plaintext account folder; cryptographic erasure is not implemented. Attachments are files, so they rely on the folder separation and OS protection; encrypting them is a later decision if photos warrant it.
- **Preferences.** Recent searches get an owner suffix. AI-share prefs are cleared when the owner changes instead of being scoped: sign-out already cleared them, so a returning user re-enables them either way. A pending-submission intent is cleared when leaving a signed-in account, but survives guest-to-account authentication so the requested submission can resume. Startup performs outgoing-owner cleanup when the recorded owner differs from the launch session; independent cleanup steps are all attempted even if notifications fail.
- **Single owner of switching.** Extend `AccountSwitchGuard` rather than add a second one. On any auth change, in order and one at a time: take down the provider tree, which stops the sync, AI-share and push listeners; drain outstanding reminder scheduling calls for up to five seconds, then cancel scheduled notifications, and cancel again if a call that outlasted the wait finishes later; close the database, so work still in flight fails rather than landing in someone else's data; open the new owner's; record the owner; build a new tree and return to home, where reminders schedule again from the new owner's data. If the new database won't open, the app shows a retry and never another person's data or an empty database, which would read as having no medications. Any session-bearing event can correct the open folder, since switching destroys nothing.
- **Reopening needs the account.** Kept data opens only for a live session of that uid. A signed-out app can only reach the guest folder. Retry after a failed open rechecks the current session rather than reopening the uid captured by the failed attempt; the open also checks the session immediately before exposing its database. A storage-presence lookup cannot prevent sign-out from closing the old account.
- **Sign-out.** A choice with keep as the default, and "remove" deleting the account's folder, recent searches and drafts, which replaces `clearAllLocalUserData`. A sign-out with no sheet, such as an expired session, keeps. Copy, approved only for use once A5 works: "Keep your health data on this phone? It stays locked to your account, and only you can open it by signing in again." Buttons: "Keep on this phone" and "Remove from this phone". The app must not make this promise until the tests below prove that kept data can't be reached until the original owner signs in again. The final copy must also make clear that Remove affects this phone, and that kept data isn't a backup that can be recovered from the cloud. Sean approves that wording.
- **Different account signs in.** `clearAndAdopt` is retired, because separate storage means nothing has to be destroyed.
- **First sign-in.** When the account has no data on this phone and the guest has personal data, the app asks once: "Add the items already on this phone to your account?" Sean approved the question, the text under it and the button wording on 2026-11-02. It exists because whoever used the phone signed out may not be the person signing in. Yes makes the guest folder the account's folder. No opens an empty account and leaves the guest folder where it was, so nothing is destroyed and the items stay available to anyone using the app signed out. The account isn't asked again, because it now has a folder. A guest with no personal data is adopted without asking, and a store from before this ADR moves silently, because it is the person's own. An unreadable guest database counts as something to ask about. If the account already has data here, the two stay separate, with no silent merge of health data.
- **Migration.** One-way at first launch: the file goes to the recorded owner's folder, or to guest if there is no owner, by renaming the main file last, so each step can repeat after a crash. An existing target is never overwritten. Colliding legacy databases and attachments are moved into that original owner's `legacy/` subfolder, which no runtime reader uses and account removal deletes. An older build can recreate the shared store, so each leftover takes the next free archive spot: refusing would lock the person out on every launch, and replacing would lose what was kept. They must not remain at the shared root, where a later launch could assign them using a different active-owner record. If SQLCipher is adopted, encrypting each folder is a separate later step. With no owner on record and a session present, the guest folder is adopted, as it would have been had the sign-in event been handled.
- **Unchanged.** Stack sync, and the rule that medication rows never sync. The catalog and rules open unencrypted under SQLCipher's library.
- **Image cache.** Shared. It holds public product photos with no link to an owner and nothing in the app lists it. Noted rather than changed.

**Encryption, 2026-11-02 (`account_database_cipher.dart::AccountDatabaseCipher`).** Rerun on sqlite3 3.8.0 and drift 2.34.4 with `hooks: user_defines: sqlite3: source: sqlcipher` and no `sqlite3_flutter_libs`. SQLCipher 4.19.0 over SQLite 3.53.4 ran on macOS and the iOS 26.5 simulator. A wrong key and no key were both rejected with error 26, no plaintext stayed in the file or the WAL, and the catalog (FTS, 4,621 rows for `magnesium`) and rules (131 rows) opened with no key and stayed plain. iOS simulator debug timings: create 185 ms, 1,000 inserts 455 ms, catalog query 23 ms, rules query 4 ms. What the implementation binds:
- **A key must survive a restart before it encrypts anything.** On Android, `flutter_secure_storage` 11.2.0 saves with `SharedPreferences.apply()`, so its write returns before the key is on disk, and a read in the same run only sees memory. A kill in that gap would leave an encrypted database with no key, which for medication data means permanent loss. So the first session on any database stays plain and stores a key, and the next launch encrypts with that key once it reads back. A device whose key store loses keys stays plain and keeps working. The cost: a new account's first session is plaintext until the app next launches, and an account that signs out after one session and never returns stays plaintext.
- **A missing or unreadable key never opens a new database.** Only the file's first 16 bytes decide. An encrypted file with no readable key throws, and the guard shows its retry. No code path creates a key for an encrypted file.
- **The key id lives in the account's folder**, in `database_key_id`, so adoption is still one rename with no key store write to lose.
- **Migration** writes `user_data.db.enc-tmp`, verifies it (cipher check, integrity check, schema, row counts, `user_version`), and replaces the plain file in one rename. A kill at any point leaves one whole database, and the next launch starts again. A failure keeps the plain file working and reports it.
- **Storage options.** Android `resetOnError: false`, because the default erases the whole store on a read error, and a namespace of its own. iOS after-first-unlock, this device only.
- **App size, iOS.** Two release IPAs from the same source: 69,760,631 bytes without SQLCipher and 69,788,363 with it, so 27,732 bytes more (0.04%). Installed, the app grows by 84 KB, and the SQLite framework goes from 1,648,832 to 1,734,896 bytes. On iOS this build uses Apple's CommonCrypto (`commoncrypto` in the binary, linked to `Security.framework`). Android isn't measured yet.
- **Crash reports never carry a key.** A `SqliteException` includes its statement, and `ATTACH ... KEY` contains the key, so those errors are rethrown without it.

**Android size, release AAB:** 126,877,098 bytes at `7aa16b95`, 134,280,067 with SQLCipher (+7,402,969, about 5.8%). The arm64 library grows from 1,749,200 to 5,086,272 bytes. An AAB holds every ABI, so this isn't the download size for one phone, which wasn't measured.

**Checked on devices, build `6c911765`:**
- **Real process kills, iOS 26.5 simulator.** A throwaway app ran this cipher file (one import swapped), the real Keychain and a copy of a real plaintext database. It killed itself after each migration step and during the copy (at 1.1 MB), then relaunched: every case resumed with all rows, encrypted, and no plaintext. A removed key threw, left the file unchanged and created no key, also after a restart, and restoring the key opened the data (`~/pg_quality/a5_finish_20261102/kill_harness_ios_sim.txt`).
- **Real-app upgrade, iOS 26.5 simulator.** A's plaintext data stayed plain on the first launch and was encrypted on the next: `sqlite3` gets error 26, the medication name is gone from the file, and the medication, Health History event and attachment still show. A's reminder fired on this build.
- **Real-app upgrade, iPhone 17 Pro Max.** A store from before this ADR with 9 stack rows and 19 events moved to the account's folder on the first launch, passing its integrity check, and was encrypted on the second (`sqlite3` gets error 26, empty WAL, no copy left).

**Encryption limits:** a database stays plaintext until its next launch, and an account that doesn't come back stays plaintext because encryption runs only when its folder opens. Attachments, recent searches (preferences), `legacy/` archives and product submission drafts stay plaintext, as do deleted blocks of the old plain file until the OS reuses them. The shared image cache `libCachedImageData.db` holds plain product image URLs, so it shows which products were viewed on this device, across accounts. Each clinician report share leaves the full PDF in clear in the system temp folder, outside every account folder (`printing` 5.15.1). `AccountSwitchGuard` clears it at sign-out, switch, Remove and every launch, not when the share call returns, because the share sheet may still need it; a report already shared stays with its recipient, and copies from older builds go only once a fixed build launches. Remove deletes the key and the folder. A key lost for good leaves the account's data locked, and the retry screen has no way out. Sean decides what it offers. `ITSAppUsesNonExemptEncryption` is false in `Info.plist`, and shipping SQLCipher may change that answer, so Sean decides before a release. A build without SQLCipher can't open an encrypted database, so rolling the app back to one shows the retry screen; any release rollback has to stay on a SQLCipher build. A phone moved by device-to-device transfer may carry files but not this-device-only keys; unverified.

**Dependency integration (2026-11-02):** the combined candidate upgrades to sqlite3 3.8.0 and drift 2.34.4 and removes sqlite3_flutter_libs, using sqlite3 build hooks for the native library. This remains plaintext storage. The SQLCipher spike above used the older dependencies and does not qualify encryption on this candidate; its adoption and device checks remain open.

**Known limits:** kept data has no recovery if the phone is lost or the app is deleted, because medications may not sync; any fix needs its own decision. Reminder text on the lock screen is outside this ADR. A provider rebuild doesn't prove that the app-switcher snapshot is replaced, so this is unverified until it is checked on physical devices.

**Checked on the iOS 26.5 simulator with a real account (2026-11-02):** sign-in adopted the guest folder, sign-out with keep left the account's data in its folder and opened an empty guest, and signing back in reopened the account's data without merging the guest's. On the combined hardening build `17f09a86` (before the later dependency integration), sign-out with remove deleted the account's folder and left the guest's data intact, a restart stayed signed out, and the next sign-in into an account with no data here adopted the guest's data. After sign-out the app switcher shows the guest's screen. Later on 2026-11-02, on the build with the sign-in question and the cover: the app switcher showed only the logo on a plain screen in light and dark, and the app returned unchanged. The question appeared after a real sign-in into an account with no data here and nothing moved until it was answered. A restart during it asked again. No left the account empty and the guest's row in the guest folder. Yes moved the row into the account, and it stayed after a restart. The cover also appears behind system sheets such as permission prompts and Face ID. **Still open:** a switch between two real accounts; the cover on Android; reminders rescheduling end to end; SQLCipher. Sean approved the sign-out wording in `sign_out_choice_sheet.dart` on 2026-11-02. An upgrade from build 23 was checked on the iOS 26.5 simulator: the old store moved into `users/guest/` with its WAL and SHM files, and the Stack screen read from there.

**Tests required, before implementation is called done:** Person B or a guest can't reach Person A's data through screens, cached views, background jobs, searches or retained files, across sign-out, guest, account switch and restart; the checks run through real auth transitions, not only provider overrides; a failure partway through a switch leaves no one on another person's data; attachments and preferences follow their owner; work in flight during a switch (sync, AI share, reminders, fetches) can't write to or read from the wrong owner; `test/safety/guest_cannot_read_previous_account_test.dart` is unskipped and made an enforced release gate, because a skipped test blocks nothing; an account switch mid-request drops the old result; migration killed at each step loses nothing; "remove" leaves no file or key; SQLCipher works on real iOS and Android devices, with the app-size change measured.

---

## ADR-014: Verified unavailable states remain effective across app consumers

**Date:** 2026-11-03
**Status:** Implemented in #193 and follow-up #194; publication and native candidate acceptance remain separate gates.
**Supersedes:** ADR-012's **Withholding** low-space limitation and the current-runtime behavior described under **Open decision for Sean**. Historical text above is retained; the future-format publication decisions remain open.

**Context:** A verified revocation must not leave quality scores readable merely because preparing a second catalog or saving the pointer fails. A failed or unreadable alert check must not become an all-clear in a different consumer. These are corrections to the existing withholding and offline contracts, not new clinical meanings.

**Decision:**
- A blocked catalog's read boundary withholds quality scores with a memory-only projection when a scoreless copy cannot be prepared. Product identity, safety status and search row IDs remain readable. Failed preparation cleans up its own staging folder in the same session.
- Verified revocations take effect in memory even if the small pointer cannot be saved. Offline relaunch durability still requires a successful pointer write; this does not promise persistence on a full or unwritable disk.
- A missing or unreadable verified alert feed withholds the all-clear while retaining known findings. A readable saved feed remains usable offline. A missing extended feed remains incomplete when loaded from cache, even if no older interaction rows were retained. A verified cache matching the extended-feed checksum does not need another download.
- Home, Stack and the canonical export snapshot consume the existing alert matcher and its device-profile completeness. A changed matching context cannot reuse the previous context's clean result. The export waits for current matches and retains their typed provenance and existing sharing-category restrictions.

**Unchanged gates:** A4 must review candidate feed overlap and compatibility before publication. Product-specific upgrade copy, future alert-format support, clinical rule sign-off and actual publication remain separate decisions. This record grants none of those approvals.

**Verification:** Regression tests cover pointer-write failure, failed preparation cleanup, offline partial feeds, refresh versus dependency reload, and canonical report availability/provenance/consent. Device screenshots, relaunch and disk-pressure acceptance remain part of the combined candidate session.

---

## ADR-015: The safety-alert feed is signed before its first publish

**Date:** 2026-11-03. **Decision by:** Sean (signature before first publish, and he alone holds the key).

**Context:** No alert release has been published. The feed had a checksum in its release row and no signature, so anyone able to write to Supabase could replace both. ADR-012's signing already exists for catalogs.

**Decision:**
- Reuse ADR-012's signing: canonical JSON, Ed25519, `<key id>:<base64>`, `verifySignedText` here and `scripts/release_manifest.py` in the pipeline. There is no second system.
- The signature is detached and travels as `manifest.signed_feed` on the release row. The feed bytes, `feed_path` and `checksum` don't change, so installed builds read what they read before. The dispatcher never reads `manifest`.
- The signed statement names the base and extended feed by checksum, and a sequence. This build reads those from the statement, not from the row. A statement carries a `purpose`, so it can't pass as a catalog manifest, or the reverse.
- Keys are pinned apart, in `_kProductionAlertFeedKeys` and `alert_feed_keys`. A key in the release lists starts signed-only catalogs and keyed catalog behaviour, which waits on A9. The feed must neither wait for that nor cause it.
- A missing or bad signature is a failed fetch through the existing owners: a saved copy stays, and a phone that never verified a feed gets no all-clear. A saved copy nothing vouches for keeps its alerts and gives no all-clear. There is no new copy and no new verdict.
- A lower sequence than the saved copy is refused. The sequence lives in the existing cache entry, along with the statement and signature, all of which are public.

**Differs from ADR-012:** a catalog may be unsigned until the first key is pinned, and a keyless build ignores signed fields, because phones already depended on unsigned catalogs. The feed has no such history, so the publisher always refuses and a keyless build verifies nothing. `scripts/require_alert_feed_key.sh` refuses a store build with no key; TestFlight may go without one.

**Accepted cost:** if the key is lost with no standby, keyed builds get no new alert until an app update. So the runbook generates a standby and pins it from the start.

**Limits:** builds from before this change don't check. A signature can't prove a release is the latest, nor that it is clinically correct.

**Steps:** the pipeline's `docs/RELEASE_SIGNING_RUNBOOK.md`, "The safety-alert feed".

## ADR-016: Safety checks decide "No known concerns"; each incomplete message speaks for its own assessment

**Date:** 2026-11-03
**Status:** DECIDED. Implemented in PR #177, on the contract in pipeline PR #338. They land together.

**Context:** PR #177 first withheld "No known concerns" unless the public quality score was complete, using quality completion as a stand-in for safety completion. Sean then answered, asked "May a product missing only evidence review say 'no known concerns' once its safety checks are done?": "Yes, safety checks decide." On reviewing the page, where "Assessment incomplete" sat directly above "No known concerns", he answered six open questions:

1. Caution products: "No. Caution products should not say "No known concerns." Use the proposed qualified wording and investigate the 17 informational "avoid" interactions and the critical warning before treating those cases as correct."
2. Evidence-only products: "No. Don't pair "Assessment incomplete" with "No known concerns." Show the incomplete assessment without the all-clear."
3. Products with no safety signal and no barcode: "Keep them in search, can't be scanned without a barcode."
4. A hard interaction with no warning row: "Leave for now. No current product reaches that state; revisit the wording when one does."
5. The For You card going away on withheld products: "Accept if the incomplete status remains clear elsewhere on the product."
6. Unknown safety status with no incomplete copy: "Leave for now, but add coverage so an unknown safety status can't accidentally appear as an all-clear."

**Decision:** Sean then narrowed decision 2: "A quality evidence gap alone must not imply that safety checks failed; genuinely unavailable or incomplete required safety checks must still withhold an all-clear." The ambiguous wording was the problem, so it is replaced rather than paired. He set these two messages, relayed through the integrator:

- Quality assessment incomplete: "We haven't finished assessing this product's quality yet."
- Safety checks incomplete: "We haven't finished this product's safety checks yet."

Each shows only when that assessment is incomplete, so a finished quality score never gets the quality message. Missing safety checks must have an explanation, including when no quality score is available. Existing concerns stay visible.

**What this means in the code:**

- `catalogProductCanReportNoConcerns` reads a known catalog safety status and `safety_assessment_status`, not quality completion. Only `complete` allows the all-clear; any other value withholds it.
- A null value means a catalog older than the column: the app backfills it as null and accepts that catalog, so those rows keep the stricter rule of a finished public assessment. A release build cannot write null (`--strict`, pipeline PR #338).
- `catalogProductSafetyChecksIncomplete` decides the safety note, whatever the quality state. It is true for a `not_assessed` catalog safety status and for any declared `safety_assessment_status` other than `complete`.
- A null status with a finished score keeps the older rule and gets no note. A suppressed score with no number doesn't count as finished. With a partial score or no score, the all-clear is withheld and the note explains it, under Sean's rule that missing safety checks must have an explanation.
- An unknown catalog safety status gets no note unless the status says unfinished (decision 6). It withholds the all-clear without making that claim.
- A folder an older build prepared lacks the column when the rebuild can't run, such as on a full phone. Typed reads use `SELECT *` and read a missing nullable column as null, so that phone keeps working under the older-catalog rule. A test pins this.
- The quality message is the hero's, and Compare uses the same title. A product with no score keeps "Product quality score unavailable."
- `quality_assessment_status` says whether the quality assessment finished, and `catalogProductHasCompletePublicScore` stays as it is for ranking and quality surfaces. A product with a quality gap still shows no completed score or tier.
- A block keeps the page to itself: `safety_assessment_status` never lifts or hides one, and a blocked product gets neither the all-clear nor the note.
- A catalog caution with no personal finding reads "Nothing specific to your profile" / "This product has general safety notes." Only a product with a Product Safety card adds "See Product Safety below." It gets this wording only when its checks can report, so unfinished checks show the note instead.
- A concern the checks found always leads, on any of these products. Failed personal checks, an unreadable alert feed, missing rules (ADR-014) and coverage below the floor still withhold the all-clear.
- The clinician line (`kLifeStageClinicianNote`) stays for a pregnant or breastfeeding user, because it's advice for the life stage and not a finding about the product.

**Not changed:** the pipeline's `safety_assessment_status` field and its rule, and the page's wording for a hard interaction with no warning row (decision 4). Product counts for each state belong to the measured release build, not this record.
