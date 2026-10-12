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
  - S2 Resource binding: an access-token hook stamps the personal MCP audience, and a token minted for another resource is rejected.
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

**Consequences:**
- `test/safety_invariants/no_health_in_supabase_test.dart` gains exactly the snapshot path in its allowlist, nothing broader. `test/release_gate/phi_medication_no_sync_test.dart` stays unchanged.
- Privacy copy that promises device-only health data needs a connected-case amendment before snapshots ship: the Ask PharmaGuide preview ("answered on this device and aren't sent anywhere", still true for chat itself) and "Your health profile and medication list stay on this device." in `lib/features/settings/v2/settings_v2_screen.dart`, and "saved on this device only" in `lib/features/medications/v2/medication_entry_v2_screen.dart`. The wording is Sean's decision.
- The privacy policy is updated and the FTC Health Breach Notification Rule is reviewed before a personal connector reaches users (S9).
- Supabase Auth as the authorization server stays conditional on the S1–S3 adversarial tests passing on a staging project. If it cannot pass, the authorization server is replaced (own server or hosted IdP) and Supabase keeps the database and functions.
- The personal connector stays private and unlisted until OpenAI's policy for private connectors is confirmed; only the public server goes to directories.
- Snapshots (Phase 2) start only after this ADR and the AGENTS.md amendment are merged, the personal-connector gate (S1–S3, S5, S10) is green on staging, and `AiShareScope` has landed.
- Apple Health import is one-way (Health → PharmaGuide medications), stays on the device, and never implies AI sharing.
- ADR-007's "Profile, medications and allergies never upload" now carries this one exception; the ADR-008 chat addendum is unchanged.
