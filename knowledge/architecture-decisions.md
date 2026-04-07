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
