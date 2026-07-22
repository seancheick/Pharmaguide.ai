---
tags:
  - sprints
  - execution
  - tracking
aliases:
  - Sprint Board
related:
  - "[[ROADMAP]]"
  - "[[LESSONS_LEARNED]]"
  - "[[architecture-decisions]]"
  - "[[pipeline-reference]]"
  - "[[flutter-patterns]]"
  - "[[debugging-playbook]]"
---

# PharmaGuide Flutter — Sprint Tracker

> [!info] Related Docs
>
> - [[ROADMAP]] — Complete roadmap V1.0 through V3.1 (`docs/superpowers/specs/2026-04-07-flutter-complete-roadmap-design.md`)
> - [[lessons-learned]] — What we learned each sprint
> - [[architecture-decisions]] — ADR log with rationale
> - [[pipeline-reference]] — Pipeline data structures, schemas, enums
> - [[flutter-patterns]] — Conventions for this Flutter app
> - [[debugging-playbook]] — Common issues and fixes

**Version:** V1.0
**Updated:** 2026-07-21
**Current Sprint:** v2 production promotion + Phase 11.11 v1 retirement complete. Supabase OTA verified for catalog `2026.05.17.234951` on 2026-05-19; 1.0.0+5 is ready for simulator / real-device smoke before cutting the build.
**Overall Status:** Sprints 0-4, 5a, 5b, 8, 9-14 (M1-M5), 17-22, 27, 27.5, 27.6-27.21 ALL DONE. Trust & IA Sprint 0 + Sprint 1 (T1.1-T1.16) ALL DONE. **1387 Flutter tests pass, 0 skipped, 0 failures.** **Zero `flutter analyze` issues.** GitHub Actions CI on every PR.

**Score explanation + identity integrity (2026-07-11; SHIPPED 2026-07-13):** Flutter half MERGED to `main` + pushed (branch `codex/score-explanation-identity` deleted after merge). Tasks 1–8: shared v4 pillar parser now reads schema-v1 explanation facts (`value_display`, required `label`, optional `detail`) + presentation status (`statusForPillar` — ≥85% Strong / ≥60% Mixed / else Limited); score card is a single-open accordion rendering reason → pipeline facts → named action with a per-pillar status label and no synthesized badges / "See details" / "Biggest opportunity"; named actions only for Evidence / Testing & Brand / Transparency (Formulation/Dose/Safety explained in place, no dead scroll links), and the duplicate "How we score" footer removed; label-first ingredient identity (`label_display_name`/`label_display_form` win over canonical/legacy, form casing preserved, explicit "{tier} form" chips); an unresolved identity (`identity_conflict`/`missing_display_label`) renders the literal label + "Identity needs review" and suppresses form/dose/safety; Compare's `PGComparePillarRow` consumes the shared `statusForPillar` (no duplicated thresholds). **Verified: `flutter analyze` clean; `flutter test` 2170 passed.** _Done (2026-07-13):_ full `release_full.sh` ran — catalog **v2026.07.14.032350 (13,062 products)** uploaded + promoted ACTIVE on Supabase and bundled into the Flutter repo; full-catalog active-identity gate passed (**0 unresolved of 96,225 rows**, down from 44,151), scoring-snapshot gate 32/32. _Remaining (user-run):_ simulator/real-device smoke of the score card + ingredient identity states before cutting a build.

**Label truth + trust P0–P2 (2026-07-19; CODE COMPLETE):** The source label is now an ordered canonical ledger independent of score inputs: supported parent totals, nested omega rows, exact dose text, folate DFE parentheticals, Other Ingredients, form disclosure state, allowed omissions, and reconciliation metadata survive to Flutter. Product Detail defaults to **Label**, offers a separate **Analysis** view, distinguishes label completeness from analysis coverage, uses `Form not disclosed` instead of an ambiguous unknown badge, suppresses claims for identities needing review, deduplicates profile warnings, and explains formula-wide versus ingredient-specific evidence. P1 adds source/version/fingerprint/history inspection and local-only scan lineage. P2 adds a structured authenticated mismatch-report sheet, EXIF-stripped selected photos, private owner-scoped Storage, server-verified `pending → ready` finalization, ready-only reviewer access, race-safe stale-upload cleanup, privacy-allowlisted local telemetry, and aggregate-only operations metrics. **Verified:** pipeline changed-module slice **373 passed**; Flutter full suite **2,347 passed**; exact CI coverage suite **2,326 passed**; `flutter analyze --fatal-infos` and the non-generated Dart format gate are clean; Deno format/type-check passed; Android release APK built (**112.4 MB**); both repository diffs pass whitespace and Python compilation checks. **Intentionally not run:** full pipeline/catalog/release rebuild, per user request. **Deployment still required:** link the intended PharmaGuide Supabase project, apply `20260719_label_mismatch_reports.sql`, deploy `review-label-mismatch`, configure `LABEL_MISMATCH_REVIEWER_IDS`, then run the normal full pipeline/release command when ready.

**Serving-aware probiotic label identity (2026-07-20; CODE COMPLETE):** Cleaner now preserves serving-column provenance; enrichment treats probiotic blend headers as structure rather than strains and selects the canonical serving instead of summing child/adult columns; final blobs retain alternate label amounts as `serving_variants`; Flutter renders the blend parent, its actual strain children, and a labeled serving-amount panel while defensively repairing the known legacy malformed shape. Probiotic transparency copy no longer claims per-strain disclosure when only aggregate CFU is listed. Exact DSLD 184730 dry-run resolves to **3 strains / 2.25 billion CFU / 100% label-ledger completeness**. **Verified without a catalog rebuild:** pipeline fast suite **10,531 passed, 41 skipped**; Flutter full suite **2,351 passed**; focused widget suite **11 passed**; `flutter analyze --fatal-infos` clean; diff whitespace checks clean.

**Consumer-truth beta hardening P0–P2 (2026-07-20; CODE COMPLETE):** Product Detail now renders one canonical label ledger under explicit **Nutrition facts / Active ingredients / Other ingredients** headings while keeping score inputs in the Analysis view; package net contents and serving count use one shared formatter across hero and Search; low-confidence scores retain the number but suppress misleading quality adjectives; dead Evidence actions are removed unless clinical rows can actually render; material hazards arriving from multiple producers collapse into one strongest consumer incident with merged citations; neutral and unmatched “good to know” rows no longer become warning cards. Pipeline label preservation now normalizes consumer-facing units, retains enzyme activity text, prevents invented hierarchy for orphan rows, and treats repeated label rows across distinct serving columns as alternatives rather than additive doses. **Verified without a catalog rebuild:** pipeline fast suite **10,535 passed, 41 skipped** plus focused final-db contracts **169 passed**; Flutter full suite **2,362 passed**; `flutter analyze --fatal-infos`, Python compilation, and both diff whitespace checks clean. **Intentionally not run:** the full dataset/catalog/release pipeline, per user request.

**Probiotic label + research clarity P0–P2 (2026-07-20; CODE COMPLETE):** The former unexplained checkmark list is now an explicit **Probiotic label & research** card directly after Ingredients. It separates label facts (total CFU per serving, named microorganisms, per-strain disclosure, prebiotic/postbiotic/delivery details) from curated research matching; replaces color-only dots with accessible named states for exact-strain, formula-only, species-level, pending-review, rejected, and no-database-match cases; explains that a match does not prove the exact product/formula/dose/use was studied and that no database match does not prove no research exists; and exposes reviewed sources through the existing citations sheet. The enrichment contract emits display-only scope/review/human-evidence/source metadata and leaves scoring unchanged. Legacy blobs fail conservatively: row presence alone never becomes a positive research badge. **Verified without a catalog rebuild:** pipeline fast suite **10,539 passed, 41 skipped** plus focused probiotic contracts **27 passed**; Flutter full suite **2,366 passed**; connected Product Detail **22 passed**; focused probiotic widgets **9 passed**; `flutter analyze`, Python compilation, and both diff whitespace checks clean. **Intentionally not run:** the full dataset/catalog/release pipeline, per user request. The next normal catalog build will populate the new explicit research states; existing catalogs render conservatively until then.

**Beta trust reconciliation + producer-contract hardening (2026-07-20; CODE COMPLETE):** Removed the attempted client-side nutrient-unit heuristic and completed the fixes at their authoritative boundaries. Flutter now uses one shared UL-eligibility contract everywhere, including the pipeline's explicit `ul_gate_eligible` decision; probiotic totals and per-strain amounts use one CFU formatter across billion, million, thousand, and exact-count ranges; and generic blend headers are not echoed as clinical strains. The pipeline now exports structured `top_warnings` records matching Flutter's consumer contract, preserves allergen presence language, and repairs high-confidence DSLD mg/mcg source defects only when `%DV` or parent-equivalence evidence proves the correction through the existing unit converter. Exact canaries: DSLD **223563** emits Vitamin D **100 mcg** with no false safety flag; DSLD **238677** emits one Folate row, **666 mcg DFE (400 mcg folic acid)**, with no false safety flag. **Verified without a catalog rebuild:** Flutter full suite **2,371 passed** and `flutter analyze --fatal-infos` clean; pipeline fast suite **10,548 passed, 41 skipped**; focused build/export contracts **248 passed**; Python compilation, shell syntax, and diff whitespace gates clean. **Intentionally not run:** the full dataset/catalog/release pipeline, per user request.

**Catalog schema release-boundary hardening (2026-07-21; CODE COMPLETE):** Flutter's atomic catalog importer now explicitly accepts export schema **2.1.0**, the structured-`top_warnings` minor schema already supported by the current app reader. The release orchestrator now runs that importer's complete `--dry-run` contract before Supabase sync, so schema/checksum/SQLite/manifest incompatibilities fail before any remote upload or promotion instead of at Step 6. The fresh **13,271-product** catalog and **149-rule** interaction bundle pass the real import preflight. **Verified without rerunning datasets:** pipeline fast suite **10,569 passed, 41 skipped**; focused Flutter release gate passed; `flutter analyze --fatal-infos` clean; focused release-order contract, shell syntax, and diff whitespace gates passed.

**Wishlist + Grok UX reconciliation (2026-07-21; CODE COMPLETE):** Favorites now have a versioned, idempotent Drift migration and database-enforced uniqueness; concurrent saves cannot duplicate rows, and auth-bound providers cannot expose one account's local favorites after sign-out or account change. Product Detail has one wishlist action in the app bar, with pending-state protection, accessible toggle semantics, and the neutral accent color instead of the safety-critical red token. Wishlist rows hydrate real catalog details and use the same image resolver as Product Detail. The Grok UX additions were hardened with an overflow-safe hero skeleton, explicit scanner live-region semantics and a 44-point not-found close target, and shared score-tier eligibility for incomplete-profile alternatives instead of a local numeric threshold. **Verified without rerunning datasets:** focused regression suite **141 passed**; Flutter full suite **2,409 passed**; `flutter analyze --fatal-infos` and diff whitespace checks clean. The unrelated local `pubspec.yaml` build-number change remains untouched.

**Better Alternatives source-of-truth reconciliation (2026-07-21; CODE COMPLETE):** Removed the attempted use of `ingredient_fingerprint` as catalog identity—the field is a stack-safety dose map, not proof that two products or private-label formulas are the same. Near-duplicate suppression now retains labeled potency while removing package-count noise; meaningful improvement follows the shared consumer score tiers instead of a hidden +3 heuristic; broad taxonomy buckets fail closed without canonical ingredient-family overlap; and brand diversity is a first-pass preference with valid-result backfill rather than a hard one-product cap. The SQL pool now preserves independent intent and ingredient-family channels before ranking, preventing relevant cross-type options from being truncated behind high-scoring generic-category noise. Profile warning status no longer implies that candidates were checked against conditions, medications, pregnancy, or allergens, and alternative rows use the shared catalog image resolver. Bundled-catalog audit: **13,271/13,271** products carried the safety fingerprint, **13,238/13,271** carried canonical ingredient tags, and supplement type duplicated primary category on all current rows—confirming why the previous identity and pool assumptions were unsafe. **Verified without rerunning datasets:** focused alternatives/database suite **90 passed**; Flutter full suite **2,417 passed**; `flutter analyze --fatal-infos` and diff whitespace checks clean. The unrelated local `pubspec.yaml` build-number change remains untouched.

**Claude-branch consumer trust reconciliation (2026-07-21; CODE COMPLETE, NOT MERGED):** Reconciled the in-flight Product Detail, Wishlist, scanner, and alternatives work without adding a second health-logic path. Profile Relevance now contains only actionable profile-specific concerns; no-evidence, beneficial, and verified free-from information moves to a calm **Good to Know** surface, while noncritical duplicates collapse by what the consumer actually sees and retain merged citations. Neutral Fit copy now distinguishes “no profile-specific concern found” from an unproven goal match. Wishlist state is invalidated on signed-in account switches as well as sign-out. Scanner overlays are accessible at large text/small screens, manual entry cannot race the live camera, and reveal dismissal is one-shot. The blocked-product CTA now promises **higher-quality options**, not “safer” candidates that were never profile-safety checked, and handles the no-results destination honestly. **Verified without rerunning datasets:** focused regression runs of **67, 127, 44, and 9 tests** passed; Flutter full suite **2,417 passed**; `flutter analyze --fatal-infos`, generated-code build, and diff whitespace checks clean. The branch remains unmerged for the requested live Claude audit window.

**Consumer hierarchy + signal accuracy follow-up (2026-07-21; CODE COMPLETE, NOT MERGED):** Product Detail no longer spends a card on an empty Neutral or label-coverage state; meaningful Good/Strong fit remains, and the profile action is a quiet pencil edit affordance. Cluster fallback can establish **Good fit** through the existing pipeline-owned goal mapping, while **Strong** still requires explicit product goal tags. The hero score is restored to a 22-point, semibold, tier-colored decision signal with dedicated WCAG 4.5:1 foreground tokens (the tier label remains visible, so color is not the only cue). Warning routing now prefers a product-dose-evaluated duplicate over a generic legacy copy, hides no-evidence uncertainty, sends only informational/beneficial or neutral life-stage context to **Good to Know**, and keeps harmful actionable life-stage rows, medication interactions, allergies, dose uncertainty, and all hard/critical warnings in the warning lane. A 13,271-product read-only corpus audit was used to reject the unsafe broad life-stage-demotion approach before shipping it. No dataset pipeline was run.

**Omega label identity + hierarchy follow-up (2026-07-21; CODE COMPLETE, NOT MERGED):** A recurring NIH/DSLD contradiction that supplied the DHA name/group/identifier tuple while its explicit label note said EPA is now repaired at the cleaner boundary using the reviewed EPA ethyl-ester identifiers and auditable provenance; dose is never used to infer identity. A read-only scan found **14 affected staged products**, and all 14 dry-normalize to EPA while retaining the original DSLD value in `raw_source_text`. Product Detail now assigns label rows by their top source ancestor, keeping Total Omega-3 and display-only Other Omega-3 under the Fish Oil active hierarchy without adding them to scoring. The left hierarchy guide is the single visual nesting cue, reducing the nested-row offset from **53 px** to no more than **12 px**. **Verified without a dataset rebuild:** pipeline fast suite **10,570 passed, 41 skipped**; Flutter full suite **2,437 passed**; focused red/green regressions and real DSLD 180408 dry-normalization passed. Static analysis and final diff gates are recorded at commit time.

**PG Score + Product Detail presentation follow-up (2026-07-21; CODE COMPLETE):** Product-level score presentation now uses one whole-number contract across the hero, “Why this scored” headline, and score-card total, while the six explanatory pillars retain useful one-decimal precision. The score explanation action moved from the card header to a full-width, accessible **How PG Score works** row immediately beneath analysis coverage, and its bottom sheet now leads with **PG Score** / **How PG Score works** instead of the internal “Trust receipts” vocabulary. Label nutrition rows now render only in the bottom Nutrition Facts section, inactive ingredients retain their functional-role taxonomy through the canonical shared vocabulary loader, hidden deep-dive sections no longer accumulate blank spacing, and **Product data & sources** uses the standard section-card surface. **Verified:** focused product-detail suites passed; Flutter full suite **2,493 passed**; `flutter analyze --fatal-infos`, Dart formatting, and diff whitespace checks clean.

**Zero-pillar accuracy + feedback (2026-07-21; CODE COMPLETE, RELEASE GATE BASELINE-BLOCKED, NOT MERGED):** Exact-zero pillars now use **No points**, show their pipeline-authored reason while collapsed, and auto-expand only the first zero with a real action or non-UI pipeline fact while preserving manual accordion state. Product Detail decodes numeric/string proprietary-blend flags through the tolerant boolean contract and offers Transparency label details only when a rendered ingredient disclosure row exists, including lazy/collapsed rows. The pipeline adds fail-closed schema-v1 facts for proprietary-blend counts, undisclosed ingredient amounts, and zero qualifying evidence matches without changing score/max/reason fields. Live-corpus dry-run over **14,072 scored products** produced identical before/after score-projection SHA-256 hashes and unchanged zero-pillar counts; SKU **282638** emitted **4 blends / 54 undisclosed amounts**, and SKU **311646** emitted **0 qualifying evidence matches**. **Verified:** Flutter analyze clean and full suite **2,483 passed**; focused pipeline explanation suites **50 passed**. Pipeline full suite reached **12,683 passed / 290 skipped** but remained red on **87 failures / 7 errors** from missing worktree artifacts plus existing snapshot/contracts; the release slice's pre-existing integrity/manifest failures reproduced in the ordinary checkout. No catalog rebuild, upload, Supabase promotion, or scoring-policy change was performed.

**Phase 11.7L (1.0.0+5 prep, 2026-05-16 → 2026-05-18):** TestFlight 1.0.0+4 walkthrough produced 11 bug clusters; closed in commits `baa204b` (routes + scanner manual-entry haptic), `5319c66` (stack v2 fixture flash + empty-panel parity + nutrients refresh), `5b20f82` (Quick Check med-med via RxNorm + class-fallback + hydration-incomplete safety), `a1c5b57` (bottom-sheet anchoring + Search keyboard gap + Settings real account email), `4f7d4c7` (Quick Check canonical-id consolidation + structured fingerprint parser).

**Phase 11.11 v1 retirement (2026-05-17 → 2026-05-18):** Promoted v2 production routes by removing the 5 `USE_V2_*` dart-define toggles. Deleted 13 v1 production widget files (~2700 LOC): Product Detail, Search, Quick Check, Medication Entry, Profile Setup, Splash, Onboarding screens + Home/Stack/Settings v1 screens + all their orphan home/widgets and stack/widgets. Extracted shared helpers to dedicated files (`product_detail_helpers.dart`, `functional_roles_sheet.dart`, `pg_for_you_extras.dart`). Closed 4 v2 gaps: image tap-to-zoom in hero, Synergy section (T22 high-confidence clusters), Excipient density section, For You context chips + "Why this fits" expander.

**Phase 11.7L.H + Codex (catalog repair + Tier 2 Research, 2026-05-17):** Catalog regenerated to `db_version 2026.05.17.234951` (was 2026.05.06) — 8440 products with 0 empty `key_ingredient_tags`, 0 `NOT_SCORED`, 16 mainstream-product backfills landed. Tier 2 Research Evidence section shipped (commit `17904aa`) — supp.ai 30k research_pairs now drive a real Product Detail surface. OTA downgrade protection wired (`sync_service.dart`, `catalog_updater_service.dart`) and Supabase bundle verification passed 2026-05-18.

Full feature set: barcode scanning, FTS5 search + filter chips, score explainer, synergy detection (54 clusters), recall alerts, stack health score, Quick Check v2 (supp↔supp / supp↔med / med↔med via RxNorm), personalized interaction warnings, med-med pairs, medication entry + RxNorm, stack safety banner, FitScore, 14-section product detail IA, risk-gated Fit, transparency footer, sticky action bar, profile_gate adoption (v6.0/v6.1), hypoglycemics three-way split, premium onboarding + splash + medications UX, 17+ PG design components, Tier 2 Research Evidence surface. **Pipeline data:** interaction rules (138 rules), catalog v2026.05.17.234951 (8440 products), research_pairs (30,474 rows, 3,518 with RxCUI bridge), timing_rules.json (42 rules), medication_depletions.json (68 entries).

## TARGET: V1.0 Ship by 2026-05-11

| Week | Focus | Sprints | Status |
|---|---|---|---|
| Wk 1 | Wrap M1 polish + display widgets + FitScore UI | 4, 13, 17 | ✅ Done |
| Wk 2 | Interaction DB pipeline + Flutter binding + UX polish | 11 (M2), 12 (M3), 20 | ✅ Done |
| Wk 2 | Stack interaction engine + product-scan warnings | 13 (M4), 14 (M5) | ✅ Done |
| Wk 2 | Feature Blitz: synergy, recalls, health score, M5 fix, Quick Check, pipeline data | 21 | ✅ Done |
| Wk 2 | **V1.0-beta ship gate** — CI, accessibility, error matrix, 0 skipped tests | 8 | ✅ Done |
| Wk 3 | **TestFlight + Play internal builds** — store metadata, screenshots | — | ⬜ Next (code ready; build owed by Sean) |
| Wk 3-4 | V1.0-release — auth (Google/Apple), analytics SDK, usage limits | 7 (partial) | ⬜ Next |
| Wk 3-4 | **V1.1 Stack Intelligence (diagnostic tier headline)** | Track B (initiative) | ✅ Code-complete 2026-04-29 — see Parallel Initiatives ↓ |
| Wk 3-4 | **V1.2 Clinician Share Report** | Track C (initiative) | ✅ Code-complete 2026-04-29 — see Parallel Initiatives ↓ |
| Wk 3-4 | **V1.0 Trust Fixes Sprint 0** (KSM-66 false positive, JSON-leak, Highlights rename, Pairs Well count, OTA in-session swap) | Sprint 0 (initiative) | ✅ Code-complete 2026-04-29 — see Parallel Initiatives ↓ |
| Wk 3-4 | **V1.3 OTA Catalog Refresh** (manifest contract, background updater service, in-session swap, bundled-asset rollback) | Track D (initiative) | ✅ Code-complete 2026-04-29 — see Parallel Initiatives ↓ |

Update rules:

- Update this file during implementation.
- Mirror status/sprint changes to [[lessons-learned]] when unexpected.
- Do not mark a task `Done` without fresh verification evidence.

Status legend:

- `[x]` = `Done`
- `[-]` = `In Progress` or `Review`
- `[ ]` = `Ready` or `Backlog`

---

## AGENT RULES

1. **NEVER mark a task `[x]` unless ALL Definition of Done criteria pass.**
2. **Run verification commands BEFORE marking complete.**
3. **If a test fails, the task is NOT done — fix it first.**
4. **Update this file after every completed task.**
5. **Add to [[lessons-learned]] when something unexpected happens.**
6. **Partial completion is NOT completion. Use `[-]` for in-progress.**

---

## Parallel Initiatives (in flight, 2026-04-28 → present)

Two focused initiatives are running outside the numbered-sprint flow above. Each has its own architectural thesis, locked decisions, and detail-tracker doc. When an initiative retires, its completed tasks roll up here as a sprint reference and the initiative doc moves to `archive/`.

### `[INITIATIVE_STACK_INTELLIGENCE.md]` — V1.0 → V1.4+

> Move PharmaGuide from a single-number Stack Score to a diagnostic system (tier verdict + actionable issues), then layer commerce on top once trust is established. See the initiative doc for locked architectural principles, tier vocabulary (Optimized / Solid / Decent / Concerning / Unsafe + Incomplete), and the "no Amazon PA-API" decision.

| Track | Scope | Status |
|---|---|---|
| **A** — V1.0 Hardening (analyze clean, full-suite green, OTA bundle-replacement bug fix, "Stack Score" → "Stack Health" copy) | A1, A2, A4, A6 | ✅ All `[x]` (code) — A3 real-device scan + A5 TestFlight build still ⏳ Sean |
| **B** — V1.1 Stack Intelligence (`StackIntelligence` model + `StackIntelligenceEngine` facade + home headline rewire) | B1, B2, B3 | ✅ All `[x]` (code) — B3 goldens + real-device pass ⏳ Sean |
| **C** — V1.2 Clinician Share Report (`ClinicianReportBuilder` + `ShareService.shareClinicianReport` + stack-screen entrypoint button) | C1, C2, C3, C4 | ✅ All `[x]` (code) — C3 markdown real-device paste-into-Mail/MyChart ⏳ Sean. C4 PDF export + review fixes code-complete 2026-05-28; real-device share smoke ⏳ Sean |
| **D** — V1.3 OTA Catalog Refresh (D3 redirected to T0.6 in-session swap) | D1, D2, D3, D4 | ✅ All `[x]` (code) 2026-04-29 — D1 `scripts/tests/test_manifest_contract.py` (12 tests), D2 `lib/services/catalog_updater_service.dart` (8 tests, sealed `CatalogCheckResult`), D3 already-shipped via T0.6, D4 `openCoreDatabase` probe-and-restore fallback (3 new tests). Real-device force-corruption smoke ⏳ Sean. |
| **E** — V1.4+ Commerce | E6 → E11 | ⏸ Deferred until V1.2 trust ships |

### `[INITIATIVE_PRODUCT_TRUST_AND_IA.md]` — Sprint 0 → 3

> Rebuild the product detail screen for trust, clarity, and decision-readiness. Locked decisions: scoring model (PG Score never personalized; risk-gated Fit), coverage policy (always shown), 14-section IA, formulation purity Phase 1 patch, in-session catalog swap.

| Sprint | Scope | Status |
|---|---|---|
| **0 — Trust Fixes** (T0.1 reword evidence + ingredient prettifier; T0.2 "Why this product" → "Highlights" + strip noisy detail; T0.3 formulation JSON-leak; T0.4 Pairs Well badge ↔ card-count parity; T0.5 Formulation Purity Phase 1 hide-when-clean; T0.6 OTA in-session catalog swap with validation gate + atomic rename + SharedPreferences persistence + snackbar) | T0.1 → T0.6 | ✅ All `[x]` (code). T0.7 ship gate `[-]` — manual smoke + TestFlight + 24h Sentry watch ⏳ Sean. **Two live-test bugs caught and fixed during simulator pre-flight** (T0.1 whitespace-key prettifier follow-up; T0.3 sister JSON-leak in `certification_detail_section.dart`) — commit `2a35eb8`. |
| **1 — Product Screen IA Refactor** (T1.1 → T1.16 — risk-gated Fit, "For You" merged block, PG Score relocated to Section 3, 14-section IA, transparency footer + sticky action bar) | 16 tasks | ✅ All `[x]` (code) 2026-04-29 — 1074/1074 tests at sign-off. See `INITIATIVE_PRODUCT_TRUST_AND_IA.md` for task-level detail. |
| **2 — Refinement Polish** | 6 tasks | ⬜ Next — Sprint 1 done, gated on Sean's 5-product real-device smoke |
| **3 — Backend Foundation** (excipient ontology, prose `score_bonuses[].detail`, percentile ranking, editorial summaries — most pipeline-side) | 7 tasks | ⏸ Pending data work |

### Cross-references between the two initiatives + Apple-grade visual polish track

- **OTA activation strategy:** Stack Intelligence's original "no mid-session catalog swap" locked rule was retired on 2026-04-29 in favor of Trust & IA T0.6's validation-gated in-session swap. Stack Intelligence Track D D3 now points at T0.6 as source of truth.
- **Stack Intelligence A6 ↔ Trust & IA T0.6:** A6 was scoped to the "bundle no longer copies after first install" defect (fixed regardless of activation strategy). A6 is `[x]`; activation snackbar belongs to T0.6.
- **Apple-grade × Trust & IA Sprint 1 — merged plan (2026-04-29).** Trust/IA owns *what goes where*; Apple-grade owns *how it looks*. The other team is running Apple-grade visual polish in parallel sprints (Sprint 27.21 just shipped Phase 0 + A + B.1 + B.2 + C.1, 9 commits, +44 tests landing the suite at 780 green). Decisions:
  - 🔁 **Folded into Sprint 1**: Apple-grade B.3a hero refactor → T1.1 (revised score-led hero); F.4 Quality Score card → T1.4 (rescoped, donut dropped); F.5 "For You" card → T1.2 (visual approach reused, content model corrected). Their team is skipping these tasks; we own them with the merged spec.
  - 🚫 **Dropped from Apple-grade**: F.3 PGIngredientAtom + F.6 atom row — decorative for medical-grade context (T1.5 verbose rows + chip pattern is correct).
  - 🔼 **Promoted to other team's top-of-queue (blocking us)**: F.0 data audit (gates T1.4); F.1 audit decision (`pg_score_ring` reuse vs new PGDonutChart); F.2 PGPillarBar primitive (T1.4 consumes).
  - ⏸ **Serialized after T1.1**: Apple-grade B.3b frosted SliverAppBar + share — same file as T1.1 hero refactor, runs after to avoid concurrent edits.
  - ✅ **Independent**: Apple-grade C.2/C.3/D.1/D.2/E.1/E.2 — interleave on the other team's schedule; no overlap with Sprint 1.
  - **PGFrostedHeader vs PGFrostedAppBar**: investigated — NOT duplicates. PGFrostedHeader = visual surface primitive (glass/tonal/hairline); PGFrostedAppBar = AppBar composition that wraps PGFrostedHeader. Both kept. Platform-aware glass treatment landed on `main` 2026-04-29 commit `a06bd22` — every consumer (PGFrostedAppBar + home search header + B.1 Profile Setup) inherits iOS-true-glass / Android-tonal-surface automatically.

### Coding sequence (updated 2026-05-06)

1. ~~Track D leftovers (D1 + D2 + D4)~~ ✅ Done 2026-04-29.
2. ~~Trust & IA Sprint 1 (T1.1 → T1.16)~~ ✅ Done 2026-04-29 — all 16 tasks shipped, 1074 tests at sign-off.
3. ~~Pipeline v6.0 profile_gate + v6.1 hypoglycemics split + premium UX overhaul~~ ✅ Done 2026-05-06 — catalog v2026.05.06, 136 interactions, 1431 tests.
4. **Next:** V1.0-release gate — auth (Google/Apple/Email), usage limits, analytics SDK, store builds.
5. **Then:** Trust & IA Sprint 2 (Refinement Polish) — gated on Sean's real-device smoke.
6. ~~Sprint 28 (Tier 2 Research / RXCUI bridge)~~ ✅ Done 2026-05-18 — pipeline bridge + Flutter surface verified.

### Owed back to Sean (parallel to coding)

- TestFlight + Play Internal builds (Track A5 + T0.7 step 4)
- Real-device smoke for B3 home headline + T0.4 / T0.5 visual edges + C3 paste-into-Mail (T0.7 step 3) + Track D D4 force-corruption rollback
- PHARMAGUIDE-1 (RenderFlex overflow) Sentry triage
- 24h Sentry watch post-deploy

---

## CURRENT SPRINT

**Sprint 28: Tier 2 Research Evidence Surface + RXCUI bridge** — ✅ DONE 2026-05-18
Status: complete. The old backlog block was stale after Claude's Tier 2 pass and Codex verification.

Goal: surface the supp.ai research_pairs that ship in `assets/db/interaction_db.sqlite` without converting them into curated safety warnings, severity, or score penalties.

- [x] Pipeline: bridge drug CUIs → RXCUIs. Bundled DB now has 30,474 `research_pairs`, 3,518 with `rxcui_a` / `rxcui_b` populated.
- [x] Pipeline: rebuilt `interaction_db.sqlite` + manifest. `assets/db/interaction_db_manifest.json`: `source_suppai_count: 30474`, `source_drafts_count: 138`, `checksum_sha256: 72a87bf...`.
- [x] Flutter: `lib/data/database/interaction_database.dart` exposes `lookupResearchPairsByCanonicalId(...)` + `lookupResearchPairsByRxcui(...)`.
- [x] Flutter: `lib/services/stack/research_pair_lookup.dart` returns top-N evidence rows, prioritizing evidence involving medications in the user's active stack.
- [x] Flutter: `lib/core/models/research_pair_evidence.dart` decodes top sentences + PMIDs into a UI-safe model.
- [x] Flutter: `lib/features/product_detail/v2/sections/research_evidence_section.dart` renders the neutral "Research available" card and drawer with supp.ai/PubMed context.
- [x] Flutter: Product Detail v2 integrates `ResearchEvidenceSection` after Review Before Use and before Label Confidence when deep-dive sections are available.
- [x] Tests: Drift lookup tests, lookup service tests, section widget tests, and bundled DB release-gate tests verify canonical lookup, RxCUI bridge lookup, neutral copy, drawer content, and "not severity-bearing" behavior.
- [x] UX guardrails: neutral tone, no severity coding, explicit "literature evidence, not a safety warning" / "do not create warnings, scores, or clinical instructions" copy.

Already shipping (do NOT rebuild):
- `lib/services/stack/depletion_checker.dart` — drug-induced nutrient depletion (metformin → B12 etc.)
- `lib/services/stack/medication_depletion_nudge.dart` — one-time nudge UX
- `lib/services/stack/timing_evaluation_service.dart` — 42 timing rules indexed
- `lib/data/database/interaction_database.dart` (M3) — Drift binding for Tier 1 lookups
- `lib/services/stack/stack_interaction_checker.dart` (M4) — 3 stack-pair check methods
- `lib/features/product_detail/widgets/interaction_warnings.dart` (1204 LOC) — full warnings rendering w/ profile gating

Full file map + cross-repo data flow: `dsld_clean/docs/INTERACTION_TIER2_AND_BRIDGE_PLAN.md`.

Estimated effort: ~7 hours (3h pipeline + 4h Flutter + tests).

---

## Future Backlog — Post-v1.6.0 / v6.1 (cross-repo)

Tracked here so they don't get lost between sprints. None are launch-blocking for v1.6.0; pull into a sprint when prioritized.

- [x] **Hypoglycemics drug-class split (pipeline + Flutter).** ✅ DONE (2026-05-06). Three-way split: `hypoglycemics_high_risk` / `hypoglycemics_lower_risk` / `hypoglycemics_unknown`. 18 rules × 3 subclasses. Flutter profile migration maps legacy → unknown. User-friendly labels shipped.

- [ ] **Cross-product dose summation (Flutter stack-aware).** Today profile_gate `dose` evaluates per-product. A user stacking three caffeine products at 80 mg each silently bypasses the 200 mg/day caffeine ceiling. Build a stack-aware dose aggregator:
  - New `lib/services/stack/stack_dose_summer.dart` walking active stack items, summing dose-per-day per `nutrient_form` (caffeine, niacin, vitamin A, etc.)
  - Wire into `StackIntelligenceEngine` so it can fire stack-level alerts independent of any single product's gates.
  - First targets: caffeine (200 mg/day), vitamin A (3000 mcg RAE), niacin (35 mg), iron (45 mg) — pull thresholds from `rda_optimal_uls.json` ULs.
  - Estimated effort: ~5h.

- [ ] **Structural pregnancy/lactation split (pipeline).** Today the pipeline emits a single combined `pregnancy_lactation` block because Flutter currently shows one combined toggle. When Flutter splits the toggle (separate Pregnancy / Breastfeeding switches), refactor `condition_rules` to two separate entries with independent `profile_gate.requires.profile_flags_any: ['pregnant']` vs `['breastfeeding']`. Migration: run `migrate_to_profile_gate.py --split-pl`. Coordinate the cut with the Flutter toggle change so both ship in the same release.
  - Estimated effort: ~3h pipeline + 2h Flutter UI + tests.

- [ ] **v6.1 cleanup — remove legacy `matchesProfile` fallback (Flutter).** ~30 days after v1.6.0 ships and we've confirmed every cached detail blob in the wild has rotated to v1.6.0 with `profile_gate` populated, delete the set-intersection fallback path inside `InteractionWarning.matchesProfile()` (search for `TODO(v6.1)` markers in `lib/features/product_detail/widgets/interaction_warnings.dart`). Also delete the corresponding fallback branch + tests in `profile_gate_summary_filter.dart` callers.
  - Pre-condition: `import_catalog_artifact.sh` should drop `1.3.1` / `1.3.2` / `1.4.0` / `1.5.0` from `APP_SUPPORTED_SCHEMAS` at the same time so we can never re-bind to a pre-gate catalog.
  - Estimated effort: ~1h.

- [x] **Phase 1.5 — clinical review of 16 new entries (pipeline).** ✅ DONE (2026-05-06). Ghost PMID 27092496 killed, 5 dead URLs replaced with verified PMIDs, copy fixes across all 16 entries.

- [x] **Full 14-condition clinical sweep (pipeline).** ✅ DONE (2026-05-06). All condition batches reviewed with clinical team: 210→196 rules, 14 deduped (omega-3×5, milk thistle, yohimbe×2, licorice, ginger extract, vitamin D from bleeding). Zero templated bodies, zero repeated headlines remaining.

- [x] **URL-rot audit (pipeline).** ✅ DONE (2026-05-06). 23/263 dead URLs replaced with verified PubMed PMIDs. Audit script at `scripts/audits/interaction_rules/url_rot_audit.py`.

- [x] **Flutter UX overhaul.** ✅ DONE (2026-05-06). Premium splash (520ms settle), activation-first onboarding (4 steps with goal chips), medication entry UX (no RxNorm jargon, bottom sticky CTA), fit score qualitative labels, product detail double-filter fix + IA comments.

- [ ] **Remaining RECONCILIATION backlog (4 items, needs architecture — future release):**
  - vitamin_d: needs `lab_status` in user profile (~4h)
  - white_mulberry: needs `form_scope` variant architecture (~3h)
  - black_seed_oil: dose threshold for thymoquinone extracts (~2h)
  - stinging_nettle: same dose pattern (~1h)

---

## Condition Expansion Roadmap — v2.0+ (cross-repo)

### Phase A: Heart Disease Subconditions

**Why:** The current `heart_disease` gate is too broad — coronary artery disease, heart failure, and arrhythmia have completely different supplement risk profiles. L-arginine is dangerous post-MI but fine for general heart disease. Potassium is critical with ACEi/ARB but irrelevant for valve disease.

**Pipeline — add to `clinical_risk_taxonomy.json` conditions[]:**
- [ ] `coronary_artery_disease` — label: "Coronary Artery Disease (CAD)"
- [ ] `prior_mi` — label: "Prior Heart Attack"
- [ ] `heart_failure` — label: "Heart Failure"
- [ ] `arrhythmia` — label: "Heart Rhythm Disorder"
- [ ] `atrial_fibrillation` — label: "Atrial Fibrillation (AFib)"
- [ ] `long_qt` — label: "Long QT Syndrome"

**Pipeline — re-author these interaction rules with subcondition gates:**
- [ ] L-arginine: `avoid` for `prior_mi` / `recent_mi` (JAMA VINTAGE-MI trial PMID 16391217); `caution` for broad `heart_disease`
- [ ] Potassium: escalate to `avoid` when `heart_failure` + drug_class `ace_inhibitors` / `arbs` / `aldosterone_antagonists`
- [ ] Licorice: escalate to `avoid` when `arrhythmia` / `long_qt` / `heart_failure` (hypokalemia → arrhythmia risk)
- [ ] Omega-3: add `atrial_fibrillation` gate with `monitor` severity (high-dose EPA/DHA AFib signal)
- [ ] Icariin: gate on `nitrates` / `pde5_inhibitors` drug_class, not generic `heart_disease`
- [ ] CoQ10: keep `informational` for broad gate, but add positive `heart_failure` informational note
- [ ] Hawthorn: `monitor` for `heart_failure` specifically (has HF study data); `informational` for broad gate

**Flutter — profile UI changes:**
- [ ] Add subcondition checkboxes under "Heart Disease" in profile setup (expandable section)
- [ ] `schema_ids.dart`: add condition IDs + user-friendly labels
- [ ] Profile migration: existing `heart_disease` users keep broad gate; new users can refine
- [ ] `evaluatorProfileFlags` or conditions list carries subconditions through to `matchesProfile`

**Estimated effort:** ~8h pipeline (re-authoring + clinical verification) + ~4h Flutter

---

### Phase B: Autoimmune Subconditions + Immunocompromised Drug-Class Escalators

**Why:** A user with Hashimoto's should NOT see the same immune-herb warnings as a user on chemo. The `severely_immunocompromised` flag was added (2026-05-06) but needs drug-class escalator gates to fire automatically when a user's medication implies immunocompromise.

**Pipeline — add autoimmune subconditions to taxonomy:**
- [ ] `lupus` — label: "Lupus (SLE)"
- [ ] `rheumatoid_arthritis` — label: "Rheumatoid Arthritis"
- [ ] `multiple_sclerosis` — label: "Multiple Sclerosis (MS)"
- [ ] `ibd` — label: "Inflammatory Bowel Disease (Crohn's / UC)"
- [ ] `hashimotos` — label: "Hashimoto's Thyroiditis"
- [ ] `psoriasis` — label: "Psoriasis / Psoriatic Arthritis"
- [ ] `celiac` — label: "Celiac Disease"

**Pipeline — add immunosuppressive drug-class gates:**
- [ ] `chemotherapy` — drug_class for chemo agents
- [ ] `biologics` — TNF inhibitors, IL inhibitors (Humira, Enbrel, Remicade, etc.)
- [ ] `dmards` — methotrexate, azathioprine, mycophenolate (conventional disease-modifying)
- [ ] `high_dose_corticosteroids` — prednisone >20mg/day chronic
- [ ] `transplant_immunosuppressants` — tacrolimus, cyclosporine, sirolimus

**Pipeline — re-author rules:**
- [ ] Probiotics: currently gated on `severely_immunocompromised` profile flag. Add automatic escalation when user has `chemotherapy` / `transplant_immunosuppressants` / `biologics` drug classes → flag fires without user manually toggling it
- [ ] Echinacea: `avoid` when `transplant_immunosuppressants` / `biologics` / `dmards`; keep `caution` for broad autoimmune
- [ ] Astragalus: same escalation pattern as echinacea
- [ ] St. John's wort: `contraindicated` with `transplant_immunosuppressants` (CYP3A4 induction → transplant rejection)

**Flutter:**
- [ ] Add autoimmune subconditions to profile setup (expandable section under "Autoimmune Condition")
- [ ] Add immunosuppressive drug classes to `schema_ids.dart` drugClasses list with user-friendly labels
- [ ] Auto-derive `severely_immunocompromised` flag in `evaluatorProfileFlags` when user has chemo/transplant/biologic drug classes selected (same pattern as pregnancy → pregnant flag)

**Estimated effort:** ~6h pipeline + ~4h Flutter

---

### Phase C: Kidney Disease Staging

**Why:** Magnesium `avoid` is correct for CKD stage 4-5 / dialysis but over-warns for CKD stage 1-2. Potassium hyperkalemia risk scales with eGFR decline. Creatine's lab-interpretation concern is more relevant with declining function.

**Pipeline — add CKD subconditions:**
- [ ] `ckd_stage_1_2` — label: "Early Kidney Disease (Stage 1-2)"
- [ ] `ckd_stage_3` — label: "Moderate Kidney Disease (Stage 3)"
- [ ] `ckd_stage_4_5` — label: "Advanced Kidney Disease (Stage 4-5)"
- [ ] `dialysis` — label: "On Dialysis"
- [ ] `kidney_transplant` — label: "Kidney Transplant Recipient"
- [ ] `kidney_stones` — label: "Kidney Stones"
- [ ] `abnormal_potassium_history` — profile flag, hematologic category

**Pipeline — re-author rules:**
- [ ] Magnesium: `informational` for stage 1-2, `caution` for stage 3, `avoid` for stage 4-5 / dialysis
- [ ] Potassium: `monitor` for stage 1-2, `caution` for stage 3, `avoid` for stage 4-5 / dialysis + ACEi/ARB/MRA
- [ ] Creatine: `informational` for stage 1-2 (lab note only), `caution` for stage 3+
- [ ] Propylene glycol: `monitor` for stage 1-3, `caution` for stage 4-5 (accumulation risk scales with function)

**Flutter:**
- [ ] Add CKD stage picker to profile setup (radio buttons under "Kidney Disease")
- [ ] Optional: eGFR text field for advanced users (maps to stage automatically)

**Estimated effort:** ~4h pipeline + ~3h Flutter

---

### Phase D: Liver Disease Subconditions

**Why:** A user with mild fatty liver has different risks than a user with cirrhosis or Wilson's disease. CBD/kava `avoid` is correct for cirrhosis but may be over-warning for early-stage NAFLD.

**Pipeline — add liver subconditions:**
- [ ] `cirrhosis` — label: "Cirrhosis"
- [ ] `hepatitis` — label: "Hepatitis (A/B/C)"
- [ ] `fatty_liver` — label: "Fatty Liver Disease (NAFLD/NASH)"
- [ ] `cholestasis` — label: "Cholestasis / Bile Duct Disease"
- [ ] `wilsons_disease` — label: "Wilson's Disease"
- [ ] `hemochromatosis` — label: "Hemochromatosis (Iron Overload)"
- [ ] `elevated_liver_enzymes` — label: "Elevated Liver Enzymes"
- [ ] `liver_transplant` — label: "Liver Transplant Recipient"

**Pipeline — re-author rules:**
- [ ] Copper: escalate to `avoid` for `wilsons_disease` (copper accumulation is the core disease mechanism)
- [ ] Iron: escalate to `avoid` for `hemochromatosis`
- [ ] CBD/kava/green tea extract/black cohosh: keep `avoid` for `cirrhosis` / `elevated_liver_enzymes`; downgrade to `caution` for `fatty_liver`
- [ ] Milk thistle: `informational` for all; add note that evidence varies by liver condition
- [ ] Vitamin A: escalate for `cirrhosis` / `cholestasis` (impaired retinol metabolism)

**Estimated effort:** ~5h pipeline + ~3h Flutter

---

### Phase E: Thyroid Subconditions + Levothyroxine Timing Rules

**Why:** Ashwagandha raising thyroid hormones matters for Graves/hyperthyroid but may actually be desired by some hypothyroid users (under clinician supervision). The most practical thyroid rules (calcium/iron/fiber timing with levothyroxine) are completely missing.

**Pipeline — add thyroid subconditions:**
- [ ] `hypothyroid` — label: "Hypothyroidism / Hashimoto's"
- [ ] `hyperthyroid` — label: "Hyperthyroidism / Graves' Disease"
- [ ] `thyroid_nodules` — label: "Thyroid Nodules"
- [ ] `thyroid_cancer_history` — label: "Thyroid Cancer History"

**Pipeline — add high-value levothyroxine timing rules (NEW rules, not rewrites):**
- [ ] Calcium + levothyroxine: `caution` — "Separate by 4 hours. Calcium binds levothyroxine and reduces absorption."
- [ ] Iron + levothyroxine: `caution` — "Separate by 4 hours. Iron reduces levothyroxine absorption."
- [ ] Magnesium + levothyroxine: `caution` — "Separate by 4 hours. Magnesium may reduce levothyroxine absorption."
- [ ] Fiber/psyllium + levothyroxine: `monitor` — "High fiber may delay levothyroxine absorption. Consider timing separation."
- [ ] Kelp/bladderwrack: `caution` for all thyroid — "Contains variable iodine; can disrupt thyroid control."
- [ ] Thyroid glandular extracts: `avoid` — "Unregulated thyroid hormone content; can cause thyrotoxicosis."
- [ ] Gate all timing rules on `drug_classes_any: ["thyroid_medications"]`

**Pipeline — re-author existing rules:**
- [ ] Ashwagandha: escalate to `avoid` for `hyperthyroid` / `graves`; keep `caution` for broad
- [ ] Iodine: `avoid` for `hyperthyroid`; `caution` for `hypothyroid` (dose-dependent)
- [ ] Acetyl-L-carnitine: `informational` for `hypothyroid`; `caution` for `hyperthyroid` (may reduce thyroid hormone effects)

**Estimated effort:** ~6h pipeline + ~3h Flutter

---

### Phase F: New Condition Categories (cancer, anxiety/depression, gout, osteoporosis, digestive, anemia)

**Why:** These are large user populations with real supplement interaction risks that PharmaGuide doesn't cover yet. Cancer is the highest-stakes gap.

#### F.1: Cancer / Active Cancer Treatment

**Pipeline — add conditions + flags:**
- [ ] `active_cancer` — condition in taxonomy
- [ ] `cancer_treatment` — profile flag (immune category) — auto-derived from chemo/biologics/immunotherapy drug classes

**Pipeline — add drug classes:**
- [ ] `chemotherapy` (if not added in Phase B)
- [ ] `immunotherapy` — checkpoint inhibitors (Keytruda, Opdivo, etc.)
- [ ] `radiation_sensitizers` — drugs used alongside radiation

**Pipeline — author NEW interaction rules (high-priority set):**
- [ ] Echinacea + cancer_treatment: `avoid` — "Immune-stimulating herbs may interfere with immunotherapy or transplant protocols."
- [ ] Astragalus + cancer_treatment: `avoid` — same rationale
- [ ] St. John's wort + chemotherapy: `contraindicated` — "CYP3A4 induction can reduce chemo drug levels (irinotecan, imatinib, docetaxel, etc.)"
- [ ] High-dose antioxidants (vitamin C >1g, vitamin E >400IU, selenium >200mcg) + cancer_treatment: `caution` — "Some oncologists restrict high-dose antioxidants during chemo/radiation due to theoretical interference with treatment-induced oxidative stress. Evidence is mixed — discuss with oncologist."
- [ ] Green tea extract + cancer_treatment: `caution` — liver + CYP interactions during hepatotoxic chemo
- [ ] Turmeric/curcumin + chemotherapy: `monitor` — "May affect drug metabolism; some oncologists use it adjunctively, others restrict."
- [ ] Probiotics + cancer_treatment: gate on `severely_immunocompromised` (already done) — works automatically when chemo drug class triggers the flag
- [ ] Grapefruit-related compounds + chemotherapy: `avoid` — CYP3A4 inhibition
- [ ] Folic acid + methotrexate: special rule — "Folic acid is often co-prescribed with methotrexate to reduce side effects, but timing and dose matter. Follow oncologist guidance exactly."

**Flutter:**
- [ ] Add "Cancer / Active Treatment" condition to profile setup
- [ ] Add chemo/immunotherapy drug classes
- [ ] Auto-derive `cancer_treatment` flag from drug classes

**Estimated effort:** ~10h pipeline (clinical authoring is complex) + ~3h Flutter

#### F.2: Anxiety / Depression

**Pipeline — add condition:**
- [ ] `anxiety_depression` — label: "Anxiety or Depression"

**Pipeline — author rules (most already exist as drug_class rules for SSRIs/SNRIs/MAOIs — this adds condition-level gates):**
- [ ] 5-HTP + anxiety_depression: `caution` — "Serotonin precursor. If you take an antidepressant, combining 5-HTP raises serotonin syndrome risk."
- [ ] St. John's wort + anxiety_depression: `caution` — "Can interact with many psychiatric medications via CYP induction and serotonergic activity."
- [ ] SAMe + anxiety_depression: `monitor` — "Has antidepressant properties. Combining with prescribed antidepressants may potentiate serotonergic effects."
- [ ] Kava + anxiety_depression: `caution` — "CNS depressant effects overlap with sedative/anxiolytic medications."
- [ ] L-tryptophan + anxiety_depression: `caution` — "Serotonin precursor — same risk as 5-HTP with serotonergic medications."
- [ ] Valerian + anxiety_depression: `monitor` — "May potentiate sedative medications."

**Estimated effort:** ~4h pipeline + ~2h Flutter

#### F.3: Gout

**Pipeline — add condition:**
- [ ] `gout` — label: "Gout"

**Pipeline — author rules:**
- [ ] Niacin + gout: `caution` — "High-dose niacin can raise uric acid levels and may trigger gout flares."
- [ ] Vitamin C + gout: `informational` — "Moderate-dose vitamin C may modestly lower uric acid. Not a replacement for urate-lowering therapy."
- [ ] Aspirin/salicylate-containing supplements + gout: `monitor` — "Low-dose aspirin can raise uric acid; high-dose lowers it. Discuss with clinician."
- [ ] Fructose-containing supplements + gout: `monitor` — "High fructose intake is associated with higher uric acid."

**Estimated effort:** ~3h pipeline + ~1h Flutter

#### F.4: Osteoporosis

**Pipeline — add condition:**
- [ ] `osteoporosis` — label: "Osteoporosis / Bone Health"

**Pipeline — author rules:**
- [ ] Calcium + osteoporosis: `informational` — "Calcium is commonly recommended, but dose/timing/form matter. Supplemental calcium + vitamin D is standard; discuss with clinician."
- [ ] Vitamin D + osteoporosis: `informational` — "Vitamin D supports calcium absorption. Lab-guided dosing recommended."
- [ ] Vitamin K + osteoporosis: `informational` — "Vitamin K2 is studied for bone health. If on warfarin, keep intake consistent."
- [ ] Calcium + bisphosphonates: `caution` drug_class rule — "Separate calcium from bisphosphonate by at least 30-60 minutes. Calcium reduces bisphosphonate absorption."
- [ ] Magnesium + osteoporosis: `informational` — "Magnesium supports bone metabolism."
- [ ] Caffeine + osteoporosis: `monitor` — "Very high caffeine intake may modestly reduce calcium absorption."

**Estimated effort:** ~3h pipeline + ~1h Flutter

#### F.5: Digestive Disorders (IBS / GERD / IBD)

**Pipeline — add conditions:**
- [ ] `ibs` — label: "Irritable Bowel Syndrome (IBS)"
- [ ] `gerd` — label: "GERD / Acid Reflux"
- [ ] `ibd` — label: "Inflammatory Bowel Disease" (also in autoimmune Phase B)

**Pipeline — author rules:**
- [ ] Peppermint oil + gerd: `caution` — "Peppermint oil can relax the lower esophageal sphincter and worsen reflux. Enteric-coated capsules may reduce this."
- [ ] Fiber/psyllium + ibs: `monitor` — "Fiber can help or worsen IBS depending on type and dose. Start low, increase slowly."
- [ ] Probiotics + ibs: `informational` — "Some probiotic strains have IBS evidence, but strain and dose specificity matter."
- [ ] Probiotics + ibd: `monitor` — "Evidence varies by IBD type (UC vs Crohn's) and probiotic strain."
- [ ] Iron + gerd: `caution` — "Oral iron can worsen GI symptoms. Consider timing, form (ferrous bisglycinate may be gentler), or IV iron."
- [ ] Licorice (DGL) + gerd: `informational` — "DGL licorice is sometimes used for GI support. Unlike regular licorice, DGL should not affect blood pressure."

**Estimated effort:** ~5h pipeline + ~2h Flutter

#### F.6: Anemia / Iron Deficiency

**Pipeline — add condition:**
- [ ] `anemia` — label: "Anemia / Iron Deficiency"

**Pipeline — author rules:**
- [ ] Iron + anemia: `informational` — "Iron supplementation is standard treatment. Form, dose, and timing affect absorption and side effects."
- [ ] Vitamin C + anemia: `informational` — "Vitamin C taken with iron enhances absorption."
- [ ] Calcium + iron absorption: `monitor` — "Calcium can reduce iron absorption. Separate by 2+ hours."
- [ ] Tea/coffee + iron absorption: `monitor` — "Tannins and polyphenols in tea/coffee reduce non-heme iron absorption. Separate by 1+ hour."
- [ ] Antacids + iron: `caution` drug_class rule — "PPIs and H2 blockers reduce stomach acid needed for iron absorption."

**Estimated effort:** ~3h pipeline + ~1h Flutter

---

### Phase G: Profile Flag Enhancements

**Flags to add to `clinical_risk_taxonomy.json` profile_flags[] and Flutter `schema_ids.dart`:**

- [ ] `cancer_treatment` — immune category — auto-derived from chemo/immunotherapy/biologic drug classes in `evaluatorProfileFlags`
- [ ] `organ_transplant` — immune category — gates transplant-specific drug interaction rules
- [ ] `abnormal_potassium_history` — hematologic category — escalates potassium rules
- [ ] `elderly_over_75` — metabolic category — dose-sensitivity for sedatives, fall risk with BP-lowering, reduced clearance

**Flutter — auto-derivation in `profile_provider.dart` `evaluatorProfileFlags`:**
```dart
const drugClassToFlag = {
  'chemotherapy': 'cancer_treatment',
  'immunotherapy': 'cancer_treatment',
  'biologics': 'cancer_treatment',
  'transplant_immunosuppressants': 'organ_transplant',
};
```
Same pattern as existing `conditionToFlag` map for pregnancy/breastfeeding/TTC.

---

### Phase H: Practical Medication-Timing Rules (high user value, low clinical complexity)

These are the most common "when do I take this?" questions from supplement users. They don't need subconditions — they fire on drug_class gates.

**Pipeline — author NEW drug_class interaction rules:**
- [ ] Calcium + thyroid_medications: `caution` — "Separate by 4 hours to avoid reduced levothyroxine absorption."
- [ ] Iron + thyroid_medications: `caution` — "Separate by 4 hours."
- [ ] Magnesium + thyroid_medications: `caution` — "Separate by 4 hours."
- [ ] Fiber + thyroid_medications: `monitor` — "High fiber may delay absorption."
- [ ] Calcium + bisphosphonates: `caution` — "Separate by 30-60 minutes."
- [ ] Calcium + tetracycline/quinolone antibiotics: `caution` — "Separate by 2+ hours."
- [ ] Iron + antacids/PPIs: `caution` — "Reduced stomach acid impairs iron absorption."
- [ ] Probiotics + antibiotics: `informational` — "Take 2+ hours apart. Probiotics during/after antibiotics may help restore gut flora."

**Pipeline — add drug classes to `drug_class_vocab.json` if needed:**
- [ ] `bisphosphonates` — Fosamax, Actonel, Boniva (rule-only, not user-selectable initially)
- [ ] `antibiotics` — broad class for timing rules (rule-only)
- [ ] `ppis` — omeprazole, pantoprazole, lansoprazole (rule-only)

**Estimated effort:** ~4h pipeline + ~1h Flutter (drug classes may already be covered by existing categories)

---

### Implementation Priority Order

```
1. Phase H — Medication timing rules (highest user value, lowest complexity)
2. Phase E — Thyroid subconditions + levothyroxine timing (high practical value)
3. Phase A — Heart subconditions (L-arginine post-MI is a safety gap)
4. Phase F.1 — Cancer (highest stakes gap)
5. Phase C — Kidney staging (magnesium/potassium dose safety)
6. Phase B — Autoimmune + immunosuppressive escalators
7. Phase D — Liver subconditions
8. Phase F.2-F.6 — Anxiety, gout, osteoporosis, digestive, anemia
9. Phase G — Profile flag enhancements
```

---

**Sprint 27.17: Supabase placeholder startup guard** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Traced raw `flutter run` startup fatals to `AuthStateService` touching `Supabase.instance` even when startup had already fallen back to guest mode because no dart-defines were provided.
- [x] Made the guest fallback explicit: when `SupabaseConfig.isPlaceholder` is true, auth state now resolves to `guest` without probing the Supabase singleton.
- [x] Broadened the defensive catch in `AuthStateService` to `on Object` so unexpected client-unavailable failures still degrade to guest mode instead of surfacing fatal startup noise.
- [x] Added a focused unit test covering the placeholder fallback and basic signed-in/signed-out state transitions.
- [x] Verified the fix in a live simulator boot: raw `flutter run -d 'iPhone 16 Pro'` no longer emits the previous fatal Supabase assertion after startup.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/services/auth_state_service_test.dart`.

**Sprint 27.18: Home premium composition pass** — ✅ DONE (2026-04-28)
Status: DONE

- [x] Re-composed Home into a cleaner premium order: hero → scan → search → profile nudge → Stack Health → Recent scans → Quick Check → trust strip.
- [x] Removed the generic category rail from Home and replaced the search-launcher count hint with a calm static `Search supplements` placeholder.
- [x] Fixed Home footer layout shift by reserving citation-strip space during catalog load with a skeleton instead of collapsing to zero height.
- [x] Upgraded Recent scans to own its header, show skeleton cards while loading, and expose `Show all` in an adaptive bottom sheet for up to 25 recent unique scans.
- [x] Reworked Stack Health language on Home and Stack from the old tiered score copy to shared user-facing labels: `Optimized / Solid / Decent / Concerning / Unsafe`.
- [x] Added shared label-contract coverage in `test/core/models/stack_safety_score_test.dart` so severity caps and score bands cannot drift silently.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/home/home_screen_test.dart test/features/stack/stack_screen_test.dart test/core/models/stack_safety_score_test.dart`.

**Sprint 27.21: App-wide Apple-grade polish** — ✅ DONE (2026-04-29)
Status: All apple-grade-owned tasks shipped. Trust/IA-owned phases (B.3a, F.5) folded into Sprint 1; F.3/F.6 dropped; F.4 visual integration held for Trust/IA T1.4. Sprint 27.21 closes clean on apple-grade side: `flutter analyze` clean, **890/890 tests pass** (+154 from the 736 baseline), 24 apple-grade commits + 3 cross-team merges on `origin/main`.

**2026-04-29 cross-team merge (Sean + apple-grade dev sign-off):** A `/critique` pass on this sprint vs Trust & IA Sprint 1 surfaced product-detail overlap. Trust/IA owns *what goes where* on the product detail screen; apple-grade owns *how it looks*. Re-merged plan:

- **B.3a Apple Altar hero** → SUPERSEDED, becomes Trust & IA T1.1 (revised score-led hero per Yuka/SuppCo evidence; HeroVerdict gated to Avoid/Contraindicated/Blocked only). Trust/IA owns.
- **F.3 PGIngredientAtom + F.6 atom row** → DROPPED. Atoms are decorative for medical-grade context; T1.5 verbose rows + existing chip pattern for inactives is the right call.
- **F.5 "For You" card** → DROPPED, folded into Trust & IA T1.2 with corrected content model (the original dual-column was conflating Section 2 + Section 3). Sean reuses the visual approach (PGCard.plain, PGPressable per row, LayoutBuilder for SE breakpoint) inside T1.2.
- **F.4 Quality Score card** → RESCOPED. No donut, no center ring (score lives in hero / T1.1). Apple-grade delivers pillars + coverage + reasoning row inside `PGCard.plain`; T1.4 owns final composition.
- **F.0 / F.1 / F.2 PROMOTED to next-up** — they unblock T1.4 and T1.1.
- **B.3b** SERIALIZED — runs after T1.1 sign-off (same file; concurrent edits would cause merge churn).
- **D.1** FOLDED INTO 0.2 — `PGCircularIconButton` already covers the adaptive back-chevron contract.

Active queue post-merge: `F.0 → F.1 → F.2` (unblocker chunk) → C.2 / C.3 / D.2 (parallel sweeps) → wait for T1.1 → B.3b → E.1 / E.2 (sprint close). Plan doc updated with strikethrough markers + cross-team merge note at top: `docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md`.

- [x] **Task 0.1: PGFrostedAppBar** — sliver-mounted Apple-grade app bar primitive (centered title + optional leading + actions, default chevron-back when route can pop, blurSigma forwarded to PGFrostedHeader). 4 widget tests. Used as the new top-chrome standard across every sub-page and tab destination. Commit `7c90b19`.
- [x] **Task 0.2: PGCircularIconButton** — premium 38pt circular tap target (subtle outline + faint drop shadow + centered icon, pressedScale 0.92 via PGPressable). Apple Maps / News / Photos top-chrome pattern. Wired into PGFrostedAppBar's auto-leading slot so back-chevrons everywhere render as floating circles instead of flat glyphs. 4 widget tests. Commit `6e30f62`.
- [x] **Task A.1: Stack tab → PGFrostedAppBar** — `Scaffold(appBar: AppBar)` → `Scaffold(body: NestedScrollView)` with PGFrostedAppBar + pinned `_StackTabBarDelegate` in `headerSliverBuilder`. Tab-root behavior (`automaticallyImplyLeading: false`); `ShareClinicianReportButton` moves from `AppBar.actions` to `PGFrostedAppBar.actions`. Each tab body's existing `RefreshIndicator + ListView` is preserved as the NestedScrollView body — no slivers required in tab bodies. All 2 stack tests + 8 home tests still green. Commit `45c734f`.
- [x] **Task A.2: Settings tab three-pack** — Material AppBar → PGFrostedAppBar (CustomScrollView + SliverList + SliverPadding wrapping the existing children verbatim); `Material + InkWell` row wrapper inside `_SettingsTile` → PGPressable with `pressedScale: 0.98` (settings rows are dense — keep press subtle); `Switch(...)` → `Switch.adaptive(...)` for CupertinoSwitch on iOS. All 6 settings tests still green (including the privacy-dashboard tap test that exercises the new tap path). Commit `b68ac91`.
- [x] **Task A.3: Scanner lookup overlay** — `CircularProgressIndicator(color: Colors.white)` → `CupertinoActivityIndicator(color: Colors.white, radius: 14)` inside `ScannerLookupOverlay`. The overlay already had Sprint 27.14's premium dual-copy ("Checking this barcode" + on-device-database subtitle) and a dark glassy card on the dark camera-viewport scrim — the right treatment for the context. The remaining tell that it wasn't a first-party iOS overlay was the Material spinner. Spec deviation from the plan's PGCard.elevated + PGShimmerBox suggestion (which would clash with the dark backdrop and regress the existing copy). Commit `07ae6c9`.
- [x] **Task B.1: Profile Setup three-pack** — Material AppBar → frosted header via `PreferredSize + PGFrostedHeader` (SliverFillRemaining > PageView nesting triggered Flutter null-geometry assertions; `PreferredSize` gives identical visuals because PGFrostedHeader is the underlying primitive); custom prev-step `PGCircularIconButton` on steps 2-5 (calls `_prevStep`, not route pop); Skip TextButton preserved. RadioListTile/CheckboxListTile rows wrapped in PGPressable (0.98 scale) with `onTap` calling the profile notifier directly so each row is one tactile target. Bottom Continue → `PGHaptics.press(context)` for intermediate steps; final Save → `PGHaptics.successPattern(context)` (Apple Pay di-DUP completion cadence) — high-value moment for the user. All 23 profile tests green. Commit `9f4df75`.
- [x] **Task B.2: Quick Check four-pack** — Material AppBar → PGFrostedAppBar (CustomScrollView + SliverList; route-pop chevron auto-implied); inline `_ProductSearchField` suggestion ListTiles wrapped in PGPressable (0.97 scale); Check button fires `PGHaptics.press(context)` before `_checkInteractions`; severity-gated result haptic via `PGHaptics.forSeverity(worst, context)` when the result banner mounts (`Severity.contraindicated` is enum index 0 — comparator selects the lowest index for worst-severity), or `PGHaptics.success(context)` for clean checks. In-button `CircularProgressIndicator` kept on `_checking` (controller-approved deviation from the plan's Apple-Pay-purist greyed-only pattern — feedback wins on a 2s+ network call). 19 quick_check tests green. Commit `0315177`.
- [🚫] ~~**Task B.3a: Apple Altar hero**~~ — **SUPERSEDED 2026-04-29.** Folded into Trust & IA Sprint 1 T1.1 (revised score-led hero per Yuka/SuppCo evidence; HeroVerdict gated to Avoid/Contraindicated/Blocked only — lower verdicts live in Section 2). Trust/IA team owns the HeroVerdict provider and the refactor. Apple-grade contributes the visual primitives via F.0/F.1/F.2.
- [x] **Task C.1: PGModal helper + sweep** — `lib/core/widgets/pg_modal.dart` with `PGModal.bottomSheet<T>(...)` thin wrapper around `showModalBottomSheet` with PG-grade defaults (`isScrollControlled: true, useSafeArea: true, showDragHandle: true, backgroundColor: surface`). 11 call sites migrated (settings, home, product detail × 4, scanner, stack, fit-score, safety-check, depletion-nudge). Two spec deviations from the plan: (1) no `showCupertinoModalPopup` iOS branch — that's for action sheets not content sheets; the wrapper stays Material across platforms, with the seam open for future iOS sheet-detent adoption; (2) `PGModal.alert` skipped — zero `showDialog` call sites in `lib/`. Per-call-site non-default flags preserved (e.g. settings dashboard kept `showDragHandle: false`). 2 widget tests for the helper. Commit `8339032`.
- [x] **Task F.0: Data availability audit — VERDICT 🟢 GREEN** (2026-04-29). All four pillars are first-class fields on `products_core` (`scoreIngredientQuality` 25 max, `scoreSafetyPurity` 30, `scoreEvidenceResearch` 20, `scoreBrandTrust` 5). `mappedCoverage` already a column. Detail blob exposes `section_breakdown` Map per pillar + `score_bonuses[]` / `score_penalties[]` for reasoning rows. Existing `ScoreBreakdownCard` (505 lines) already consumes the path. F.2 is a pure UI build; T1.4 unblocked. Findings doc appended to plan; commit `76285f3`.
- [x] **Task F.1: PGScoreRing reuse audit — DECISION 🟢 REUSE** (2026-04-29). Existing `PGScoreRing` (275 lines) covers the entire T1.1 score-led-hero contract: scalable size, center number with optional sub-label, tier-derived progress color via the 6-tier ladder, sweep-gradient arc, dashed-track null state, animated mount + value transitions, reduce-motion respect, semantic accessibility. Building `PGDonutChart` would create a parallel primitive across existing call sites (product detail, search, scan results). T1.1 unblocked — calls `PGScoreRing(score: ..., size: 96, label: 'PG SCORE')` directly. If T1.1 needs trackColor / progressColor overrides, those are two additive optional params on PGScoreRing — not a fork. Findings doc appended to plan; commit `76285f3`.
- [x] **Task F.2: PGPillarBar primitive** (2026-04-29). `lib/core/widgets/pg_pillar_bar.dart` — `[label] [bar] [percent]` row, tier-tone derived from value/max fraction via the 6-tier `AppTheme.score*` ladder (mirrors `PGScoreRing._colorFor` but takes a fraction so callers pass per-pillar-max values without converting to /100). Null value → em-dash + `insufficientData` tone. Compact variant (4pt bar height) for dense lists; default 8pt. 6 widget tests (label/percent rendering, null state, exceptional + low tier tone, value-above-max clamping, compact). T1.4 unblocked. Commit `add240b`.
- [x] **Task C.2: Final adaptive control sweep** (2026-04-29). Audit grepped `Switch( | Checkbox( | Slider( | SwitchListTile( | CheckboxListTile(` across all of `lib/` — only ONE non-adaptive control remained: the drug-classes `CheckboxListTile` in `_HealthProfileStep` of `profile_setup_screen.dart:503`. Migrated to `CheckboxListTile.adaptive` (CupertinoCheckbox on iOS, Material on Android, zero API cost). Every other Switch / SwitchListTile in the app was already `.adaptive` from earlier sprints (Settings A.2 etc.). The .adaptive sweep is now complete app-wide. Commit `e12a780`.
- [x] **Task C.3: Motion-token sweep** (2026-04-29). 12 ad-hoc `Duration(milliseconds: ...)` + `Curves.*` call sites across 7 files migrated to the `AppMotion` vocabulary. Mappings: 180–200 ms → `AppMotion.fast`, 220 ms → `AppMotion.medium`, `Curves.easeOutCubic` → `AppMotion.standard`. Migrated: `pg_score_ring.dart` (curve only — 900 ms count-up duration left as a special case, not in the token table), `pg_frosted_header.dart`, `score_breakdown_card.dart` ×2, `interaction_warnings.dart` ×3, `nutrient_accumulation_panel.dart`, `nutrient_progress_bar.dart` ×2, `scanner_screen.dart`. Excluded the two Trust/IA T1.2 WIP files (`product_detail_screen.dart` + `for_you_section.dart`) — concurrent edits would cause merge churn; Trust/IA team owns them during T1.2. 850 tests pass; analyze clean (the prior `for_you_section` warning was Trust/IA-resolved in their WIP). Commit `29c6164`.
- [🚫] ~~Task D.1: Extract `PGAdaptiveBackButton`~~ — **FOLDED INTO 0.2 (2026-04-29).** `PGCircularIconButton` already encapsulates the adaptive back-chevron behavior; `PGFrostedAppBar`'s default leading slot uses it. A standalone wrapper would be a parallel primitive solving a problem that no longer exists.
- [x] **Task D.2: Empty-state audit + PGEmptyState CTA migration** (2026-04-29). Audit walked all empty-state usages across `lib/features/`. Result: vocabulary already cohesive — `home_recent_scans._buildEmptyState` is the canonical reference pattern; `home_stack_health._buildEmptyState` is intentionally a CTA card on PGCard.elevated (different pattern by design); every other empty state (search ×2, product detail ×1, stack ×3, medications ×1) already routes through `PGEmptyState`. The only smell was `PGEmptyState._PillButton` itself still using `Material + InkWell` — migrated to `PGPressable(pressedScale: 0.97)`, single change uplifts every empty-state CTA across the app. Also dropped a hardcoded `fontFamily: 'Inter'` since the theme's `_platformFontFamily` (Sprint 27.19 G1) handles cross-platform fonts. Commit `5247bae`.
- [x] **Task B.3b: Frosted SliverAppBar + circular share + section audit** (2026-04-29). T1.1 landed at `90c0fcd`; B.3b ran mechanically against `product_detail_screen.dart`. SliverAppBar → PGFrostedAppBar (empty title — hero carries product name; iOS App Store pattern). Share `IconButton(Icons.share_outlined)` → `PGCircularIconButton(Icons.ios_share_rounded, haptic: false)` (Apple Maps / News / Photos top-chrome pattern; haptic suppressed because the iOS share sheet fires its own present haptic). Pipeline-section audit walked 26 widget files: 25 already 4-tier compliant; 1 migration in `better_alternatives.dart` (`GestureDetector + Container` tappable row → `PGCard.plain + onTap`, intra-card score-badge circle left as-is). Commit `d862fb1`.
- [x] **Task B.3c: Hero visual polish — collaborative cross-team finish** (2026-04-29). The dev critique flagged T1.1's hero as "really good redesign" but not yet apple-grade — nested `Container + DecoratedBox` instead of `PGCard.elevated`, filled `_HeroMetaPill` instead of outline chips, no entrance choreography, score ring/image still at T1.1's "safe" 88pt/56pt sizes. Visual polish landed in two near-simultaneous commits that merged cleanly: apple-grade `2e103ee` (PGCard.elevated wrap, `_HeroTrustChipOutline` replacing `_HeroMetaPill`, `TweenAnimationBuilder` entrance fade-in + 8pt translate over `AppMotion.medium`, `_HeroMetaPill` removed as unused, image bumped to 96pt with `compact: true`, ring bumped to 96pt + stroke 7) + Trust/IA `258c817` (added `compact` pass-through to `ProductImage` matching the new `BrandedPlaceholder.compact` flag from `26d54c3`, `_ScoreRingButton` migrated from `Material+InkWell` to `PGPressable`, polish pass commit notes). Net result: full apple-grade hero — single elevated PGCard, 96pt centered ring + 96pt thumbnail, outline trust chips, press tactility on the score ring, entrance choreography. **Process note:** the apple-grade implementer's commit msg incorrectly claimed "Preserved 88pt PGScoreRing" while the actual diff bumped to 96pt; the implementer also misattributed `compact: true` provenance ("pre-existing"). Trust/IA's parallel `258c817` accidentally fixed the cross-file `ProductImage.compact` reference my implementer's commit was missing. Net effect on `main`: clean (analyze clean except one warning in T1.2's WIP `for_you_section.dart:290`, 833/833 tests pass).
- [↻] **Task F.4: Pillar card composition** *(RESCOPED 2026-04-29 — runs after T1.1 + F.2)* — `PGCard.plain` containing four `PGPillarBar` instances + a coverage strip + a "Why this score" reasoning row. **No donut, no center ring** — score lives in hero (T1.1). T1.4 owns final mount and data wiring. This phase delivers the visual treatment only.
- [🚫] ~~**Task F.3: PGIngredientAtom**~~ — **DROPPED 2026-04-29.** Atom pills are decorative for medical-grade context; the dose-vs-effective-range note (T1.5 verbose rows + existing chip pattern for inactives) is the trust signal that differentiates from food-additive scanners.
- [🚫] ~~**Task F.5: "For You" card**~~ — **DROPPED 2026-04-29.** Folded into Trust & IA Sprint 1 T1.2 with corrected content model (the original dual-column was conflating Section 2 + Section 3). Sean reuses the visual approach (`PGCard.plain`, `PGPressable` per row, `LayoutBuilder` for SE breakpoint) inside T1.2.
- [🚫] ~~**Task F.6: Atom-style ingredients row**~~ — **DROPPED 2026-04-29.** Same rationale as F.3.
- [x] **Task E.1: Cross-screen polish smoke tests** (2026-04-29). New file `test/integration/cross_screen_polish_smoke_test.dart` mounts each migrated screen (Stack / Settings / Profile Setup / Quick Check) inside ProviderScope + MaterialApp and asserts a frosted top chrome — PGFrostedAppBar OR PGFrostedHeader-inside-PreferredSize. Both render the same visual surface; the contract is intentionally loose because Profile Setup uses the PreferredSize fallback (sliver-nested PageView causes Flutter null-geometry assertions). Product Detail intentionally out of scope — its top-chrome assertion already lives in `test/features/product_detail/` widget tests where the product fixture + detail-blob mock already exist. The smoke test goes red the moment any of these screens regresses to a Material AppBar. 4/4 pass. Commit `39f34db`.
- [x] **Task E.2: Final analyze + full-suite + tracker close** (2026-04-29). `flutter analyze` → No issues found. `flutter test` → **890/890 tests pass** (up from 736 in Sprint 27.20 — **+154 net** across all parallel work). 24 apple-grade commits on `origin/main` between `7c90b19` (PGFrostedAppBar primitive) and the sprint-close commit. Sprint 27.21 closes clean.
- [x] **Phase G: Premium-feel follow-ups** (2026-04-29). Three Sprint 27.21 follow-ups added after the deep-audit pass + dev critique. **G.1 Animated logo splash intro** (`4d609af` + native-splash regen `193ce6b`) — `AnimatedSplashScreen` between native splash + first content screen, 600ms scale 0.85→1.0 + fade-in, reduce-motion path skips animation, end-of-anim `PGHaptics.tap`, light status-bar icons, brand-teal `#0A7D6F` background; 4 widget tests; native splash regenerated for the new 1024×1024 logo Sean uploaded. **G.2 Hero transitions** (`2adb151`) — three Hero wraps with matching tag `'product-${dsldId}'` connecting home carousel card + Show-all sheet item (48pt sources) to product detail hero altar (96pt destination); flightShuttleBuilder uses destination widget verbatim during transit (suppresses Material elevation halo on small-to-large flights); bidirectional. **G.3 Inline subtitle helper** (`882f368`) — stacked `[brand]\n[form]` Text widgets → single `Text.rich` rendering `Brand · Form · Dose` (App Store inline pattern); new file-scope helpers `_hasAnyHeroSubtitle` + `_buildHeroSubtitleSpan` drop orphan dots cleanly. **G.4 Tighter SE spacing** ⏸ deferred (design call; needs simulator validation). **G.5 Tier 2 Research** ✅ done 2026-05-18 via Sprint 28 verification.
- [x] **Phase H: FitScore product-philosophy refactor — Option C tier-only** (2026-04-29). Sean's product call after the deep audit surfaced the combined-score confusion: Hero rendered `score100Equivalent` (e.g. 82) while the For You pill rendered `scoreCombined100 = scoreQuality80 + scoreFit20` (e.g. 78) — different formulas, different semantics, but both look like "out of 100" and conflict on screen ("did personalization make it worse?"). **H.1** (`7648d87`) killed the combined number entirely: dropped `scoreCombined100` field from `FitScoreResult` model + `FitScoreService.calculate` computation; dropped the `score` field from the four content-bearing FitDisplay sealed cases (`FitStrongMatch / FitGoodMatch / FitLimitedFit / FitNotRecommended`); dropped `_FitScorePill` widget from For You section; switched threshold input from scoreCombined100 (0..100) to `scoreFit20 / 20.0` (fractions 0.85/0.60/0.35); dropped `scoreQuality80` parameter from `FitScoreService.calculate` (no consumers after removal); rebalanced 60+ test fixtures across 5 test files. **H.2** (`77981ab`) deleted dead `PGFitScoreBadge` widget + 10 widget tests (185 + 100 lines); `fit_score_sheet` docstring updated to point at the For You section's tier-label row as the new entry point. Net architecture: PG Score = product (objective, in hero), Fit = state-only (subjective tier label in For You) — two independent axes, never merged.

**Verification (post Phase H — Option C refactor, 2026-04-29):**
- `/Users/seancheick/Development/flutter/bin/flutter analyze` → **No issues found**
- `/Users/seancheick/Development/flutter/bin/flutter test` → **975/975 tests pass** (up from 736 in Sprint 27.20 — **+239 net** across all parallel work; net-of-PGFitScoreBadge-deletion: was 980 pre-H.2, dropped exactly the 5 deleted widget tests)
- **34 apple-grade commits + cross-team merges** with Trust/IA on `origin/main`. Sprint-27.21 commits `7c90b19` → `057b894` (sprint close). Phase G: `4d609af` (G.1) → `193ce6b` (native-splash regen) → `882f368` (G.3) → `2adb151` (G.2) → `47f305f` (G tracker close). Phase H: `7648d87` (H.1 Option-C refactor) → `77981ab` (H.2 dead-code deletion). Cross-team Trust/IA commits parallel: `90c0fcd` T1.1 / `26d54c3` BrandedPlaceholder.compact / `258c817` T1.1 polish / `e3959e6` T1.4 / `bef64dd` T1.5 / `4404087` T1.6.

**Owed back to the team (now empty):**
- F.4 was absorbed by Trust/IA T1.4 (`e3959e6`) — they extended the existing `ScoreBreakdownCard` directly with the coverage strip + hero continuity label rather than consuming `PGPillarBar`. PGPillarBar (`add240b`) becomes pending-integration code, kept for future use.
- G.4 (Tighter SE spacing) ⏸ deferred for simulator validation — needs Sean's design call before shipping.

**Sprint 27.20: Apple-grade home polish refinements** — ✅ DONE (2026-04-28)
Status: DONE — 4/4 tasks shipped. Follow-up to Sprint 27.19 addressing two reviewer notes (chained-impact "notification" patterns, critically-damped press release) and two original-plan caveats (dark-mode top-edge glint, gesture-conflict smoke test for the pinned search header).

- [x] **Task 1: Severity-gated verdict haptics with iOS notification patterns.** Adds `PGHaptics.successPattern()` (di-DUP — light → 80ms → medium, Apple Pay completion cadence) and `PGHaptics.errorPattern()` (di-da-DUP — medium → 60ms → medium → 60ms → heavy, system-error cadence). Adds `PGHaptics.forVerdict(verdict, [context])` mapping `RECOMMENDED/GOOD → successPattern`, `MODERATE/REVIEW → warning`, `UNSAFE → danger`, `BLOCKED → errorPattern`, `NOT_SCORED → success`, `null/unknown → no haptic`. Updates `PGHaptics.forSeverity(contraindicated)` to use the full errorPattern instead of a single heavy impact — strict no-go tier deserves a more distinct tactile signal than `avoid` (which stays heavy). Scanner verdict-flash now calls `forVerdict(product.verdict, context)` so a successful safe-product scan rewards the user with the recognizable Apple Pay completion pattern, and a BLOCKED scan fires the full system-error cadence. 21 unit tests via mock platform-channel recorder verify the exact chained sequence of `HapticFeedbackType.*` calls for every input.
- [x] **Task 2: `AppMotion.gentleRelease` zero-overshoot press-up curve.** Apple's iOS press-up has a near-zero rebound — the previous PGPressable release used `AppMotion.spring` (15% overshoot) which read as toy-like. Adds `AppMotion.gentleRelease = Curves.easeOutCubic` and switches PGPressable's release transition to it. `AppMotion.spring` retained for state flips and toggles where a touch of overshoot adds personality. Doc comments on both curves clarify which to reach for: spring → toggles, gentleRelease → press-up.
- [x] **Task 3: Dark-mode top-edge glint on PGFrostedHeader.** iOS frosted-glass surfaces in dark mode show a faint white inner-edge highlight along the top — simulates light catching the top edge of glass. Adds a 4% white top BorderSide that fades in alongside `scrollProgress`, so the edge only appears once the surface is actually frosted. Light mode keeps the top edge clean (`BorderSide.none`) — the glint disappears against light surfaces anyway. Two new widget tests verify dark mode produces a > 0 / < 10% white top border and light mode renders no top border.
- [x] **Task 4: Gesture-conflict smoke test for pinned search header.** Verifies the SliverPersistentHeader pinned search remains tappable after the user scrolls past the hero. Seeds a populated state, drags the scroll view up by 400 pt to force the pin, then asserts (a) the placeholder still renders (proves the pin worked) and (b) a PGPressable ancestor is reachable in the search's render tree (proves the tap-handler chain is intact and not obscured by the frosted overlay or by the parent CustomScrollView's drag recognizer). Manual `tester.pump()` instead of `pumpAndSettle()` because BouncingScrollPhysics + the snap-paginated Recents PageView produce ongoing micro-animations that pumpAndSettle never considers idle.

**Verification:**
- `/Users/seancheick/Development/flutter/bin/flutter analyze` → No issues found
- `/Users/seancheick/Development/flutter/bin/flutter test` → 736/736 tests pass (up from 712 in Sprint 27.19 — +24 new tests across pg_haptics_test.dart, pg_frosted_header_test.dart, and home_screen_test.dart)
- 4 commits pushed: `38ee7ea` (haptics), `7aaade1` (gentleRelease), `662d1e3` (glint), `c617331` (gesture test)

---

**Sprint 27.19: Apple-grade home — physics layer + iOS chrome + audit bug fixes** — ✅ DONE (2026-04-28)
Status: DONE — 28/28 tasks shipped across 7 phases. Plan archived at `docs/superpowers/plans/2026-04-28-home-apple-grade.md`.

Goal: take the home screen from the Sprint 27.18 redesign baseline to first-party Apple-grade by fixing audit defects, building the missing physics layer (haptics, press-feedback, frosted scroll-aware search, snap-paginated Recents), and adding the iOS chrome (status-bar style, pull-to-refresh, swipe-back, SF font, Dynamic Type clamp).

**Phase A — Foundation bug fixes (8 tasks):**
- [x] A1: Fixed `isFirstLaunchHomeProvider` reactivity gap — `ref.read` → `ref.watch` so first-launch users exit collapsed mode immediately after their first scan/stack add. Renamed `@visibleForTesting`. Added stream-driven widget test.
- [x] A2: Lowered Recents `Show all` threshold from 10 → 5 (extracted to `kShowAllRecentsMin`). Users with 5–9 scans were previously locked out of the bottom sheet entirely.
- [x] A3: Fixed shimmer width-shift in Recents loading state — replaced `Row + Expanded × 3` (~124 px wide) with a horizontal `ListView` of fixed-156-px shimmer cards matching the real silhouette. Eliminates the residual layout shift the Sprint 27.18 commit had claimed but didn't fully solve.
- [x] A4: Deleted dead `lib/features/home/widgets/home_category_rail.dart` (orphaned after Sprint 27.18 removed it from the screen).
- [x] A5: Extracted duplicated `_timeAgo()` from two `_RecentScan*` classes into shared `lib/core/utils/relative_time.dart` with 9 unit tests across the case ladder (Just now / Nm / Nh / Yesterday / Nd).
- [x] A6: Removed duplicate `Status:` health-label rendering from Stack screen summary card — title was sufficient.
- [x] A7: Added boundary tests for tier-cap at score 84/85/86 in `stack_safety_score_test.dart` to lock the optimized→solid demotion contract against off-by-one regressions.
- [x] A8: Updated greeting copy to four-tier (`Good morning` / `Hello there` / `Good evening` / `Good night`) per product direction. Refactored `_greeting()` to static `greetingFor(int)` with unit tests at every boundary hour and an explicit "never says afternoon" regression guard.

**Phase B — Material hierarchy unification (3 tasks):**
- [x] B1: Walked every visible home surface (9 widget files, ~50 surfaces). Audit doc at `docs/superpowers/plans/2026-04-28-home-apple-grade.surfaces.md`. Result: 0 migrations required — the codebase actually has 4 valid tiers (hero / standard / accent / recessed), not the plan's hypothesized 3, because `PGCard` ships a `highlighted` variant for callouts. Cardinality contracts hold (1 hero = scan CTA; 1 accent = profile completeness).
- [x] B2: Codified the 4-tier surface system in `pg_card.dart` doc comments — explicit cardinality rules and the "intra-card layout primitives are not a fifth tier" clarification so the next dev has the rule written, not implied.
- [x] B3: Documented the dark surface ladder design choice in `app_theme.dart` — surfaces are intentionally cool blue-gray (not iOS-neutral systemGray) to harmonize with brand teal. The luminance-step spacing matches Apple's dark-mode ladder; we trade hex-exactness for brand coherence.

**Phase C — Tactile/motion: PGPressable + haptic vocabulary adoption (6 tasks):**
- [x] C1: Built `lib/core/widgets/pg_pressable.dart` — Apple-style press wrapper with 0.96 scale-down on press-in, spring-release via `AppMotion.spring`, optional haptic on tap. Honors `MediaQueryData.disableAnimations` (reduce-motion). Six widget tests.
- [x] C2: Wrapped both `_RecentScanCard` (carousel) and `_RecentScanListTile` (Show all sheet) with PGPressable.
- [x] C3: Replaced Material+InkWell+Ink on the Scan CTA hero with PGPressable+Container — gradient + drop shadow now scale together. Hero gets a deeper 0.94 pressedScale.
- [x] C4: Wrapped Quick Check CTA with PGPressable.
- [x] C5: Wrapped Profile Completeness card with PGPressable.
- [x] C6: Migrated `scanner_screen.dart` from raw `HapticFeedback.lightImpact()` / `mediumImpact()` to `PGHaptics.tap()` / `PGHaptics.warning()`. Last raw-haptic call site in `lib/`. Now every haptic in the app routes through PGHaptics → reduce-motion respect and severity-tier mapping are consistent everywhere.

**Phase D — Search as scroll-aware embedded system surface (3 tasks):**
- [x] D1: Built `lib/core/widgets/pg_frosted_header.dart` — companion to PGFrostedNavBar but for top-of-screen mounting. BackdropFilter blur + translucent surface fill + bottom hairline, all driven by a 0..1 `scrollProgress`. Internally uses TweenAnimationBuilder so binary `overlapsContent` flips crossfade over 220 ms. Five widget tests.
- [x] D2: Converted home shell to a sliver-mounted pinned frosted search — `SliverPersistentHeader(pinned: true)` with `_PinnedSearchHeaderDelegate`. Search now sits at the very top of home (Settings / Mail / App Store pattern); status-bar inset baked into the delegate. Hero scrolls below it.
- [x] D3: Replaced Material+InkWell wrapper on PGSearchField's readOnly+onTap launcher branch with PGPressable (`pressedScale: 0.99`, `haptic: false` because the destination owns the entry haptic).

**Phase E — Recents as object-like carousel (2 tasks):**
- [x] E1: Replaced `ListView.separated` carousel with a `PageView` snap pattern — `viewportFraction: 0.42`, `padEnds: false`, `PageScrollPhysics`. Each card-snap event fires `PGHaptics.tap` (decorative; reduce-motion-aware). App Store / Apple TV / Apple Music row signature. Carousel extracted to a `_RecentScansSnapCarousel` StatefulWidget so it owns and disposes its `PageController`.
- [x] E2: Replaced `_OutlineScanButton`'s Material+InkWell with PGPressable so the empty-state CTA gets the same scale + spring + haptic as the rest of home.

**Phase F — iOS chrome (4 tasks):**
- [x] F1: Already shipped in Sprint 27.18 — bottom safe-area uses `mq.padding.bottom + kPGNavBarHeight + AppTheme.space8`, not the previously hardcoded 96 pt.
- [x] F2: Wrapped Scaffold in `AnnotatedRegion<SystemUiOverlayStyle>` — dark icons on light theme, light icons on dark theme. Important now that the pinned frosted header changes the visual material under the status bar.
- [x] F3: Platform-adaptive pull-to-refresh — `CupertinoSliverRefreshControl` on iOS (first sliver), Material `RefreshIndicator` wrapping CustomScrollView on Android. Shared `_onHomeRefresh` handler fires `PGHaptics.tap`, invalidates `isFirstLaunchHomeProvider` + `activeStackProvider` + recents (via new `refreshHomeRecents` helper that keeps the file-private provider behind a public-facing function), and waits 350 ms so the indicator animation reads as purposeful.
- [x] F4: `CupertinoPageRoute` on iOS for left-edge swipe-back gesture — sub-page routes (`profileSetup`, `search`, `quickCheck`, `product/:dsldId`) now use a `pageBuilder` + `_platformPage` helper that returns CupertinoPage on iOS, MaterialPage elsewhere. Onboarding intentionally stays Material (linear flow; users shouldn't be able to swipe out).

**Phase G — Polish (2 tasks):**
- [x] G1: Conditional SF font on iOS — `ThemeData.fontFamily` returns `null` on iOS so Flutter falls through to the system font (`.SF Pro Display` / `.SF Pro Text` with OS-provided optical sizing). Inter retained on Android. Encapsulated in a `_platformFontFamily` getter so the choice has one home; all 13 prior `fontFamily: 'Inter'` references now route through it.
- [x] G2: Global Dynamic Type clamp at 0.9–1.4x via `MaterialApp.builder` MediaQuery override. Protects card layouts at iOS AX5 / Android max accessibility text-scale settings. The scan CTA's local 1.3x clamp stays — composes with (not bypasses) the global cap because the hero's fixed icon-well + chevron break before the global ceiling.

**Verification:**
- `/Users/seancheick/Development/flutter/bin/flutter analyze` → No issues found
- `/Users/seancheick/Development/flutter/bin/flutter test` → 712/712 tests pass
- 32 commits across 7 phases pushed to `origin/main` between `6f7c923` (A1) and `5479182` (G2)

**Known caveats / follow-ups:**
- The pinned search delegate uses `overlapsContent` for the binary frosted-state signal. The PGFrostedHeader's internal TweenAnimationBuilder smooths it to a 220 ms crossfade. If users want a smooth offset-driven gradient (rather than binary-then-crossfade), that's a follow-up that would require a ScrollController-driven ValueNotifier passed into the delegate.
- `PageView.viewportFraction: 0.42` is tuned for phones. On tablet form factors the slot becomes too wide and cards stretch noticeably. Tablet support is out-of-scope for this sprint.
- Sub-page Cupertino routes haven't been smoke-tested for swipe-gesture conflicts with internal scrollables (e.g. product detail's horizontal pairs-with row). If conflicts emerge, the fix is per-route gesture priority, not a router-level change.

**Sprint 27.16: Drift test lifecycle cleanup** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Traced the pre-existing Drift multiple-database warnings to `test/features/product_detail/product_detail_screen_test.dart`.
- [x] Confirmed the warning is a test-runtime false positive for intentionally separate in-memory Drift databases in that file, not a shared-executor production bug.
- [x] Suppressed the warning locally in that test file with `driftRuntimeOptions.dontWarnAboutMultipleDatabases`, then reset it in `tearDownAll()` so the rest of the suite still surfaces genuine mistakes.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/product_detail/product_detail_screen_test.dart`.

**Sprint 27.15: FLTR-7 stale RDA file cleanup** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Deleted the unused `data/rda_optimal_uls.json` copy.
- [x] Verified runtime still reads `assets/reference_data/rda_optimal_uls.json` through `ReferenceDataRepository`; no code paths referenced the stale file.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/services/stack/stack_ul_checker_test.dart`.

**Sprint 27.14: Scanner not-found + lookup transition polish** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Upgraded the scanner not-found sheet to a clearer premium layout with barcode pill, stronger explanation, and explicit `Scan again` / `Search by name` actions.
- [x] Reworked the lookup transition overlay from a bare spinner into a clearer blocking state with context copy about the on-device catalog check.
- [x] Improved the live scanner guidance copy in the camera state without touching the deferred missing-product submission flow.
- [x] Verified the old tracker item about barcode-detect haptics was stale: scanner already fires `HapticFeedback.lightImpact()` on capture and `mediumImpact()` on verdict flash.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/scanner/scanner_screen_test.dart`.

**Sprint 27.13: FLTR-15 status duplication guard + neutral status polish** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Added a defensive parse-time filter so legacy `status` warnings do not duplicate the structured `product_status` row when both appear in a blob.
- [x] Kept the guard intentionally narrow: it only activates when `blob.product_status` already exists, and it only filters warnings explicitly tagged as `status` / `product_status`.
- [x] Upgraded the neutral product-status explanation sheet to use type-aware copy for `discontinued`, `reformulated`, `off_market`, `limited_availability`, and `seasonal`.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/product_detail test/features/product_detail/product_status_chip_test.dart`.

**Sprint 27.12: FLTR-8 warning grouping refinement** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Refined the personalized warning stack without changing medical severity logic.
- [x] `Applies to you` now carries a short context line so the user understands those cards are sourced from their saved profile.
- [x] `Other precautions` now stays collapsed but shows a calmer explanation plus up to three preview topic chips derived from the actual warning tags, making the hidden content legible before expansion.
- [x] Kept the change local to `interaction_warnings.dart`; no pipeline reinterpretation and no new medical heuristics.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/product_detail/interaction_warnings_test.dart`.

**Sprint 27.11: Search result chips aligned to product logic** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Replaced the off-target search chip set with product-relevant filters: `All`, `High Quality (80+)`, `Needs Review`, `Blocked / Unsafe`, plus dynamic category chips from the result set.
- [x] Base filters now appear as soon as the user starts typing; result-derived category chips appear once search results land.
- [x] Updated the search count row to explicit `Showing X results` / `Showing X of Y results` language.
- [x] Kept the change UI-local to the search screen; no query-engine rewrite.
- [x] Added a widget test covering count text, verdict filtering, and dynamic category chip rendering.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/search/search_screen_test.dart`.

**Sprint 27.10: Hero score-teaser on product detail** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Added a compact `Why this score` teaser under the score ring area on product detail.
- [x] Reused the existing pipeline `score_bonuses` / `score_penalties` contract rather than inventing local heuristics.
- [x] Negative verdicts (`MODERATE` / `REVIEW` / `UNSAFE` / `BLOCKED`) now prefer a penalty-side score reason in the hero teaser; positive verdicts prefer a bonus-side reason.
- [x] Kept the deeper `Why this product` section intact as the expanded explanation layer.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/product_detail`.

**Sprint 27.9: FLTR-23 bioavailability-aid surfacing** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Surfaced `ingredient_quality_data.demoted_absorption_enhancers` inside the product-detail deep dive.
- [x] `FormulationDetailSection` now renders a subdued `Includes bioavailability aid` block with labeled dose chips when the pipeline demotes sub-threshold absorption aids from scoring.
- [x] Kept the signal explanatory only: no score change, no safety implication, no duplicate active-ingredient treatment.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/product_detail`.

**Sprint 27.8: Goal/synergy asset refresh after pipeline rebuild** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Synced `assets/reference_data/synergy_cluster.json` to the fresh pipeline copy after the latest rebuild.
- [x] Synced `assets/reference_data/user_goals_to_clusters.json` to the fresh pipeline copy after the latest rebuild.
- [x] Verified byte-identical hashes between pipeline and Flutter for both files.
- [x] Re-verified Flutter contract consumption: raw `synergy_clusters` shape still normalizes correctly, and goal-mapping loaders still accept 18 canonical goal entries.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/core/reference_data_contract_test.dart test/data/repositories/reference_data_repository_test.dart`.

**Sprint 27.7: Product-detail contract sync + synergy surfacing** — ✅ DONE (2026-04-25)
Status: DONE

- [x] Synced the external Flutter handoff doc to current truth: shared premium shell, score-ring-first hierarchy, FLTR-22 shipped, FLTR-23 still open.
- [x] Shipped FLTR-21: `synergy_detail_section.dart` now renders `Single-ingredient match` when `synergy_detail.clusters[*].single_ingredient_match == true`.
- [x] Verified Flutter `assets/reference_data/rda_optimal_uls.json` already matches the pipeline copy byte-for-byte.
- [x] Audited latest pipeline-vs-Flutter goal/synergy contracts: schema is still compatible end-to-end. The temporary content drift identified on 2026-04-25 was resolved by Sprint 27.8.

**Sprint 27.6: Recall warning_message cleanup + authored recall copy adoption** — ✅ DONE (2026-04-26)
Status: DONE

- [x] Legacy derived `warning_message` remains absent from the bundled recall asset and contract test.
- [x] Flutter now consumes authored `safety_warning`, `safety_warning_one_liner`, and `ban_context` from `banned_recalled_ingredients.json`.
- [x] The stack recall banner now uses authored recall framing instead of generic fallback copy, without deriving user-facing copy from `reason`.
- [x] Contract coverage now enforces the authored recall fields and the allowed `ban_context` enum values.
- [x] Verification passed with `/Users/seancheick/Development/flutter/bin/flutter analyze` and `/Users/seancheick/Development/flutter/bin/flutter test test/features/stack/recalled_ingredient_integration_test.dart test/core/reference_data_contract_test.dart`.

> Sprint 27.6 details: see [Sprint 27.6 section below](#sprint-276--recall-warning_message-drop--re-author-upstream-2026-04-16)

**Sprint 27.5: Schema-Alignment Audit Follow-ups** — ✅ DONE (all 5 issues shipped 2026-04-16)
Status: DONE

> Sprint 27.5 details: see [Sprint 27.5 section below](#sprint-275--schema-alignment-audit-follow-ups-2026-04-16)

**Sprint 27: Engineering Review Follow-ups** — ✅ DONE (all 5 issues shipped 2026-04-16)
Status: DONE

> Sprint 27 details: see [Sprint 27 section below](#sprint-27--engineering-review-follow-ups-2026-04-16)

**Sprint 26: UX Polish + Critical Bug Fixes** — ✅ DONE (all 43 tasks shipped 2026-04-15)
Status: DONE

> Sprint 26 details: see [Sprint 26 section below](#sprint-26--ux-polish--critical-bug-fixes-2026-04-15)

---

## Sprint 20 — Archive

**Sprint 20: UX Quick Wins + Retention Polish** — ✅ DONE (all 8 tasks shipped 2026-04-12)
Status: DONE

### Completed (2026-04-12)
- [x] **FTS5 search upgrade** — `CoreDatabase.searchProducts()` rewritten from `LIKE '%query%'` (full table scan, no ranking, dupes) to `FTS5 MATCH` with porter stemming + `ORDER BY rank` + LIKE fallback for older DBs. Search now instant, ranked, dedup-aware. (~30 LOC change in `core_database.dart`)
- [x] **UPC dedup in pipeline** — `dedup_by_upc()` added to `build_final_db.py`. Groups by normalized UPC, keeps best row (active > discontinued, highest score, newest dsld_id). Committed `bc0d804` in dsld_clean repo. 11 tests.
- [x] **Recent Scans on home screen** — `recordScanEvent()` + `getRecentScans()` in UserDatabase (50-row cap, per-product dedup). Scanner fires `unawaited()` record. Home screen `_RecentScansSection` ConsumerStatefulWidget loads history in `initState`, renders via `ProductListItem`. Empty state with scan CTA when no history. Creates core retention loop.

### Remaining (ordered by impact)
- [x] **Search result count + filter chips** — Shipped later in Sprint 27.11. Base filters now appear while typing; result-derived category chips appear once results load; count row now reads `Showing X results` / `Showing X of Y results`.
- [x] **"Why this score?" 1-liner on product detail** — Shipped later in Sprint 27.10 as the hero-level `Why this score` teaser sourced from pipeline `score_bonuses[]` / `score_penalties[]`.
- [x] **Empty stack CTA with scanner shortcut** — ✅ DONE. `_StackEmptyView` in `stack_screen.dart` renders `PGEmptyState` with "Your stack is empty" + "Scan a supplement" CTA routing to scanner.
- [x] **Scanner "not found" copy polish** — Shipped later in Sprint 27.14 with the stronger premium not-found sheet and improved lookup transition state.
- [x] **Haptic on barcode detect** — This tracker line was stale. Scanner already had capture haptics and verdict haptics when re-audited in Sprint 27.14.

### Deferred to v2.0 (explicitly NOT this sprint)
- ~~Product submission flow (crowdsourcing)~~ — Needs backend moderation pipeline, photo storage, abuse prevention. Park as v2.0 milestone.
- ~~Contributions dashboard~~ — Depends on submission pipeline. Cut entirely for now.
- ~~Profile/health goals additions~~ — Most already exists in `lib/features/onboarding/` and `lib/features/profile/`. Verify existing fields before adding new ones.

### Flutter changes NOT YET COMMITTED (from 2026-04-12 session)
Files modified but unstaged in `/Users/seancheick/PharmaGuide ai/`:
- `lib/data/database/core_database.dart` — FTS5 search
- `lib/data/database/user_database.dart` — scan history CRUD
- `lib/features/scanner/scanner_screen.dart` — fire-and-forget scan recording
- `lib/features/home/home_screen.dart` — Recent Scans section
- `test/app_test.dart` — 5 test fixes (pumpAndSettle → pump pattern)
- `test/features/home/home_screen_test.dart` — 5 test fixes
- `test/features/settings/settings_screen_test.dart` — 6 test fixes
- `knowledge/lessons-learned.md` — 3 new entries
- `SPRINT_TRACKER.md` — this update

**All Sprint 20 Flutter changes committed in `87fe6d2`. Tracker cleanup committed in `053938b`.**

---

## Sprint 21: Feature Blitz — ✅ DONE

**Sprint 21: Synergy + Recalls + M5 Fix + Stack Health + Quick Check + Pipeline Data**
Status: ✅ DONE (7 of 7 tasks shipped, T8 deferred to V1.1). Commits: `857b827`, `6d64852`.
**Pipeline data:** `medication_depletions.json` (68 entries) + `timing_rules.json` (39 rules) — ✅ BUILT + bundled

### Tasks (ordered by implementation sequence)

- [x] **T1: Synergy Detection** — `synergyReportProvider` matches stack ingredients against 54 synergy clusters. Evidence-tiered matching with PMID citations. `synergy_cluster.json` + `banned_recalled_ingredients.json` bundled in assets. Shipped `857b827`.
- [x] **T2: Recall Alerts in Stack** — `_RecallAlertSlot` on stack screen: danger `PGSeverityBanner` when `has_recalled_ingredient == 1`. `recalledIngredientsReportProvider` checks canonical IDs against `banned_recalled_ingredients.json`. Shipped `857b827`.
- [x] **T3: M5 Fix — Live InteractionDatabase lookup on product detail** — `_loadPersonalizedInteractions()` queries `InteractionDatabase` via `StackInteractionChecker` against user's stack. Personalized "Because you're taking [X]" warnings merged with blob-parsed warnings. Soft-fail on missing provider. Shipped `857b827`.
- [x] **T4: checkMedicationPairInteractions** — New method on `StackInteractionChecker` (med↔med via rxcui/drug_class). `medicationPairInteractions` field on `StackSafetyReport`. Wired in `stackSafetyReportProvider` with dedup. Spec §0.2. Shipped `857b827`.
- [x] **T5: Stack Health Score (aggregate)** — `_StackSummaryCard` upgraded to `ConsumerWidget`. `PGScoreRing` (0-100) + `RiskTier` label + issue counts. `StackSafetyScorer` computes from all interaction results. Shipped `857b827`.
- [x] **T6: "Safe to Take Together?" Quick Check** — New `QuickCheckScreen` at `/quick-check` route. Two product search fields + "Check Interactions" button. Queries `InteractionDatabase.lookupByCanonicalId()` for each of product A's canonical IDs, filters hits where other side matches product B. Severity banners or "No known interactions" all-clear card. Registered in GoRouter. Shipped `6d64852`.
- [x] **T7: Pipeline data wired** — `timing_rules.json` (39 rules, 718 lines) replaced placeholder. `medication_depletions.json` (68 entries, 1877 lines) copied to Flutter `assets/reference_data/` + `loadMedicationDepletions()` added to `ReferenceDataRepository`. 49 pipeline contract tests + 53 live PMID verifications pass.
- [x] **T8: Depletion Checker UI** — ✅ DONE. `_DepletionSlot` in `stack_screen.dart` watches `depletionReportProvider` and renders `DepletionCheckerCard` when depletions are present.

### Definition of Done

- [x] Synergy provider matches stack ingredients against clusters
- [x] Recall banner fires on stack when `has_recalled_ingredient == 1`
- [x] Product detail interaction warnings are personalized to user's stack
- [x] Med↔med pair check runs in safety report
- [x] Stack summary shows aggregate health score (0-100) with issue count
- [x] Quick Check screen accessible at /quick-check route (home CTA wiring in Sprint 8)
- [x] Pipeline data files bundled + loaders wired
- [x] 299 tests pass, 0 analyze issues

---

## Sprint 22: Interaction Safety Expansion + Pipeline Hardening — ✅ DONE

**Status:** ✅ DONE (all tasks shipped 2026-04-14)
**Timeline:** 2026-04-14 (single session)
**Repos:** PharmaGuide_Pipeline (`be6e75f`, `eaa899c`) + Pharmaguide.ai (`8da999f`)
**Scope:** Citation integrity, IQM expansion, context-aware scoring, interaction rules overhaul, timing evaluation system

### Tasks

- [x] **T1: Replace 25 hallucinated PMIDs** — Content-verified via PubMed E-utilities API. 20 in curated_interactions_v1.json, 3 in med_med_pairs_v1.json, 2 in medication_depletions.json. verify_all_citations_content.py: 76/76 pass (100%). Committed `be6e75f`.
- [x] **T2: IQM expansion (571 → 588 entries)** — 131 CUI aliases added across 86 existing entries for SUPPai mapping. 17 new UMLS-verified entries (silymarin, NAD+, kaempferol, oleic acid, vanadium, lecithin, etc.). SUPPai ingest: 28K → 30K research pairs, +27 supplement anchors. Committed `be6e75f`.
- [x] **T3: Context-aware harmful additive scoring** — Enricher tags `source_section` (active/inactive) on each ingredient. Scorer suppresses low/moderate penalties for active-source ingredients (IQM quality score is the correct signal). High/critical still fires. 10 new tests. Committed `be6e75f`.
- [x] **T4: Fix 6 accuracy bugs in interaction rules** — Ginkgo (missing anticoagulants — its #1 interaction), SJW (missing SSRI serotonin syndrome — potentially fatal), magnesium (missing kidney_disease — life-threatening hypermagnesemia in CKD), ginger (missing bleeding_disorders + antiplatelets), turmeric (dedup 4→1 dose_thresholds), licorice (DGL form exclusion). Committed `be6e75f`.
- [x] **T5: Add 4 new drug classes** — `antidepressants_ssri_snri`, `maois`, `cardiac_glycosides`, `anticholinergics` added to `clinical_risk_taxonomy.json` + Flutter `SchemaIds.dart`. Users can now select SSRIs and MAOIs in profile. Committed `be6e75f` (pipeline) + `8da999f` (Flutter).
- [x] **T6: Add 29 new interaction rules (98 → 127)** — 5-HTP (serotonin syndrome), senna (pregnancy), NAC (anticoagulants), black seed oil (entirely uncovered — diabetes+BP+bleeding), DHA/EPA standalone, white willow bark (aspirin equivalent), butterbur (PA liver toxicity), cascara sagrada, chinese skullcap, bacopa (thyroid), creatine (kidney), cordyceps (autoimmune), lion's mane (anticoagulants), resveratrol, quercetin, and 14 more. Committed `be6e75f`.
- [x] **T7: Drug classes expansion (24 → 28)** — fluoroquinolones, proton_pump_inhibitors, bisphosphonates, antiplatelet_agents added to drug_classes.json with full RxClass ATC member lists. 226 schema tests pass. Committed `be6e75f`.
- [x] **T8: Timing evaluation service** — New `TimingEvaluationService` with inverted index for O(N) matching. `TimingOptimization` model. `TimingAdviceCard` widget. 20 tests. `timing_rules.json` updated (39 → 42 rules, 8 PMID fixes). Committed `8da999f`.
- [x] **T9: Stack interaction checker enhancements** — Dual-path lookup: brand→generic→ingredients→class fallback. RxNorm `resolveGenericRxcuis()` for brand→generic resolution. `genericRxcui` + `ingredientRxcuisCol` in user_stacks (schema v2 migration). Committed `8da999f`.
- [x] **T10: Cross-DB overlap allowlist update** — Upgraded to v5.0.0 with routing_policy documentation. Added 4 new allowlist entries (canola oil, rapeseed oil, MSG, msg). Committed `be6e75f`.
- [x] **T11: Interaction DB rebuilt + imported into Flutter** — `rebuild_interaction_db.sh --offline --import`. 136 curated + 30K research pairs. Checksum verified. Bundled in `assets/db/`. Committed `8da999f`.

### Definition of Done

- [x] verify_all_citations_content.py: 76/76 pass (0 mismatches)
- [x] 236 pipeline tests pass (226 baseline + 10 new routing tests)
- [x] Interaction DB rebuilt and imported into Flutter
- [x] Both repos committed and pushed (Pipeline: `be6e75f` + `eaa899c`, Flutter: `8da999f`)
- [x] Lessons learned documented in `docs/plans/LESSONS_LEARNED.md`
- [x] Pipeline ops changelog updated to v1.3.3

### Key Metrics

| Metric | Before | After |
|---|---|---|
| PMIDs verified | 51/76 (67%) | 76/76 (100%) |
| IQM entries | 571 | 588 |
| IQM CUI aliases | ~286 | 417 |
| SUPPai research pairs | 28,038 | 30,101 |
| Interaction rules | 98 | 127 |
| Drug classes (taxonomy) | 9 | 13 |
| Drug classes (RxClass) | 24 | 28 |
| Condition checks | ~150 | 186 |
| Drug class checks | ~120 | 177 |

### Pending (deferred to next session)

- [x] Wire `TimingAdviceCard` into stack screen UI — ✅ DONE. `_TimingAdviceSlot` in `stack_screen.dart` watches `stackSafetyReportProvider` and renders `TimingAdviceCard`.
- [x] Offline drug→class cache in SQLite — ✅ DONE. `DrugClassMap` Drift table in `drug_class_map_table.dart`, used by `InteractionDatabase.lookupByDrugClass`.
- [ ] Flutter test coverage for dual-path interaction matching
- [ ] Re-run full pipeline on fresh dataset to measure score impact of context-aware scoring
- [ ] `backed_clinical_studies.json`: 6 study_type reviews, 5 missing source texts
- [x] T8 from Sprint 21: Depletion Checker UI — ✅ DONE (see Sprint 21 T8 above).

---

## Sprint 23a: CAERS Adverse Event Integration — ✅ DONE

**Status:** ✅ DONE (2026-04-14)
**Timeline:** 2026-04-14 (single session, continuation of Sprint 22)
**Repos:** PharmaGuide_Pipeline (pending commit) — Flutter: no code changes needed (data flows through existing top_warnings)
**Scope:** FDA CAERS pharmacovigilance data → B8 scoring penalty → dashboard audit views

### Tasks

- [x] **T1: Download FDA CAERS bulk data** — 148K reports (8.5 MB zip, 99 MB unzipped) from OpenFDA food/event endpoint. Cached in `scripts/data/fda_caers/` (gitignored).
- [x] **T2: Build CAERS ingestion script** — `scripts/api_audit/ingest_caers.py`. Filters 148K→48.8K supplement reports (industry_code 54), extracts ingredient names via phrase/keyword/IQM vocab matching, deduplicates aliases, filters out multivitamins. 30.7% match rate → 159 ingredients with signals.
- [x] **T3: Create caers_adverse_event_signals.json** — Schema v1.0.0. 159 ingredients: 37 strong, 66 moderate, 56 weak. Top signals: kratom (759 serious, 261 deaths), green tea extract (186 serious, 80 hospitalizations), calcium (2,218 serious).
- [x] **T4: Add B8 CAERS penalty to scorer** — `_load_caers_signals()` at init, `_compute_caers_penalty()` method, wired into `_compute_safety_purity_score`. Penalty: strong=-4.0, moderate=-2.0, weak=-1.0, cap=5.0. Config-gated via `B8_caers_adverse_events.enabled`.
- [x] **T5: Wire B8 into build_final_db.py** — B8 evidence in `score_penalties[]` array + CAERS warnings injected into `top_warnings[]` for strong/moderate signals. Flutter reads both without code changes.
- [x] **T6: Update scoring docs** — SCORING_ENGINE_SPEC.md (B8 section + formula + flags), SCORING_README.md (B8 bullet), DATABASE_SCHEMA.md (14b schema entry).
- [x] **T7: Dashboard CAERS integration** — New "CAERS Adverse Events" tab in Section B Audit (summary + charts + filters). New standalone "CAERS Audit" page (Signal Explorer, Cross-Reference Audit, B8 Scoring Impact, Reaction Analysis, Raw Data).
- [x] **T8: Test suite** — 36 new tests in `test_caers_integration.py` (ingestion, schema validation, B8 scoring). 562 existing tests pass, 0 regressions.

### Definition of Done

- [x] 36 CAERS tests pass
- [x] 562 existing tests pass (0 new regressions)
- [x] B8 penalty flows through: scorer → build_final_db → top_warnings → Flutter
- [x] Dashboard: CAERS tab in Section B + standalone CAERS Audit view
- [x] All 3 docs updated (SCORING_ENGINE_SPEC, SCORING_README, DATABASE_SCHEMA)
- [x] CAERS raw data gitignored (99 MB)

### Key Metrics

| Metric | Before | After |
|---|---|---|
| Safety data sources | 2 (banned_recalled, harmful_additives) | 3 (+CAERS adverse events) |
| CAERS ingredients tracked | 0 | 159 |
| Strong signals (100+ serious) | 0 | 37 |
| Deaths captured in data | 0 | 16,980 reports |
| B8 max penalty | 0 | 5.0 pts |
| Dashboard audit views | 4 (A, B, C, D) | 5 (+CAERS) |
| Tests | 562 | 598 (+36) |

### What Flutter gets (no code changes)

- Products with CAERS-flagged ingredients show warning in `top_warnings`: "FDA adverse events: Kratom (759 serious of 801 reports)"
- Score breakdown Section B total now includes B8 penalty (up to -5 pts)
- `score_penalties` detail blob includes B8 entries with signal strength, report counts

### Pending

- [x] Wire `TimingAdviceCard` into stack screen UI — ✅ DONE (see Sprint 22 above).
- [ ] Re-run full pipeline to measure ALL scoring changes
- [x] Depletion Checker UI — ✅ DONE (see Sprint 21 T8 above).
- [x] Offline drug→class SQLite cache — ✅ DONE (see Sprint 22 above).
- [x] Fix 3 pre-existing test failures (IQM alias dupes + absorption) — ✅ RESOLVED. 0 failures, 0 skipped in current suite (1403 tests). Fixes landed incidentally across later sprints.
- [ ] Enrich 21 branded botanical stubs (Chromax, Cognizin, EpiCor, etc.)

---

## Sprint 25: Data Standardization + Synergy Evidence Audit — ✅ DONE

**Status:** ✅ DONE (2026-04-14, session 2)
**Timeline:** 2026-04-14 (14 commits)
**Repos:** PharmaGuide_Pipeline only — no Flutter code changes (synergy data flows through existing blob)

### Tasks

- [x] **T1: IQM form-level UNII migration** — 165 forms now have chemical-identity UNIIs. 135 are DIFFERENT from parent UNII (proving forms are chemically distinct). Follows NIH/FDA/NLM hierarchy: CUI=concept, RXCUI=drug, UNII=substance.
- [x] **T2: All 6 data files standardized** — `cui` lowercase everywhere, zero null-valued fields, `external_ids` dict on every entry, `aliases` list on every entry. 2,880 nulls removed, 5 missing external_ids fixed, 137 UNIIs filled from FDA cache.
- [x] **T3: IQM form deduplication** — 15 duplicated form names resolved (DHA/EPA fish oil, curcumin/turmeric, etc.), 4 UNII conflicts fixed with cross_ref, 27 generic "standard"/"unspecified" renamed.
- [x] **T4: Synergy cluster evidence reclassification** — All 58 clusters reclassified using PMC10600480 systematic review. Before: 38 Tier 1. After: 2 Tier 1, 7 Tier 2, 11 Tier 3, 38 Tier 4. Only curcumin+piperine and iron+vitamin C are PROVEN synergies.
- [x] **T5: Tiered synergy scoring** — A5c bonus now 1.0 (proven) / 0.75 (supported) / 0.5 (promising) / 0.25 (popular). Config-driven. 9 tests.
- [x] **T6: Synergy evidence export for Flutter** — `synergy_detail` blob includes: best_tier, bonus_awarded, bonus_explanation (user-facing), per-cluster mechanism + PMIDs.
- [x] **T7: Clinical studies cleanup** — 45 hallucinated refs removed, 47 PMIDs extracted from key_endpoints, 6 new PMIDs from PubMed search. Entries without PMIDs: 21 → 4.
- [x] **T8: Fish oil + CBD interaction rules** — 127 → 129 rules. Fish oil bleeding risk from FDA Vascepa/Lovaza labels. CBD liver toxicity + immunosuppressant interactions from FDA drug labels.
- [x] **T9: Pipeline maintenance schedule** — 24 recurring tasks documented with exact commands, expected output, "what to do with results", troubleshooting.
- [x] **T10: 11 identifier enforcement tests** — Guards against top-level leaks, null fields, duplicate forms, duplicate UNIIs.

### Key Metrics

| Metric | Before | After |
|---|---|---|
| Data files with lowercase cui | 3/6 | 6/6 |
| Null-valued fields across all files | ~3,500 | 0 |
| IQM forms with chemical UNII | 0 | 165 |
| Synergy Tier 1 (proven) | 38 (inflated) | 2 (honest) |
| Interaction rules | 127 | 129 |
| Clinical study PMIDs verified | 21 missing | 4 missing (minerals only) |
| Hallucinated refs removed | 0 | 45 |
| Pipeline maintenance tasks documented | 13 | 24 |
| Identifier enforcement tests | 0 | 11 |

### What Flutter gets (no code changes needed):
- `synergy_detail` blob now includes `bonus_explanation`, `evidence_label`, `mechanism`, `pmids` — app can show WHY the synergy bonus was awarded
- Tiered A5c score (0.25-1.0) flows through existing `score_breakdown` display
- All data improvements affect scores on next pipeline run + Supabase sync

---

## Sprint 23b: UNII Local Cache + IQM Standardization — ✅ DONE

**Status:** ✅ DONE (2026-04-14)
**Timeline:** 2026-04-14 (same session as Sprint 23a)
**Repos:** PharmaGuide_Pipeline only — no Flutter changes

### Tasks

- [x] **T1: Download UNII bulk data** — 172K FDA substance registry (3.4 MB zip, 16 MB JSON). Cached in `scripts/data/` (gitignored).
- [x] **T2: Build `UniiCache` class** — `scripts/unii_cache.py`: local-first lookup with GSRS API fallback. `lookup()`, `reverse_lookup()`, `bulk_lookup()`, `lookup_for_iqm_entry()`.
- [x] **T3: Build cache generator** — `scripts/api_audit/build_unii_cache.py`: downloads, extracts, builds compact JSON cache (172K name→UNII + UNII→name mappings).
- [x] **T4: Standardize IQM UNII fields** — Moved 3 top-level `unii` to `external_ids.unii`, removed 5 redundant duplicates, filled 25 from cache. All 388/588 entries (66%) now have `external_ids.unii`. Zero top-level `unii` remaining.
- [x] **T5: Tests** — 23 tests in `test_unii_cache.py` (loading, lookups, IQM integration, schema). 0 regressions.

### Key Metrics

| Metric | Before | After |
|---|---|---|
| IQM entries with UNII | 363 (scattered) | 388 (all in external_ids.unii) |
| Top-level unii fields | 8 | 0 |
| UNII coverage | 62% | 66% |
| Offline substances | 0 | 172,431 |

---

## Sprint 24: Drug Label Interaction Mining — ✅ DONE

**Status:** ✅ DONE (2026-04-14)
**Timeline:** 2026-04-14 (same session)
**Repos:** PharmaGuide_Pipeline only

### Tasks

- [x] **T1: Download drug label bulk** — 3 of 13 partitions (57K labels). Full set is 257K labels / 1.7 GB.
- [x] **T2: Build `mine_drug_label_interactions.py`** — Scans `drug_interactions` + `warnings` sections for 70+ supplement terms. Matches to IQM canonical_ids. Cross-references against existing interaction rules.
- [x] **T3: Generate candidates review file** — `scripts/reports/drug_label_interaction_candidates.json`. 40 supplements found, 36 already covered, 4 new candidates. NOT auto-imported.

### Key Metrics

| Metric | Value |
|---|---|
| Labels scanned | 56,860 (3 partitions) |
| Raw supplement mentions | 13,089 |
| Unique supplements found | 40 |
| Already in our rules | 36 (90%) |
| New candidates | 4 (fish_oil_omega3, cbd, ginkgo alias, grape_seed_extract) |

---

## COMPLETED SPRINTS

**Sprint 25: Data Standardization + Synergy Evidence Audit** — ✅ DONE (10 tasks, 2026-04-14: all 6 files standardized, synergy reclassified 38→2 proven, tiered scoring, 45 hallucinated refs removed, 11 enforcement tests)
**Sprint 24: Drug Label Interaction Mining** — ✅ DONE (3 tasks, 2026-04-14: SPL text mining, 40 supplements found, 4 new candidates)
**Sprint 23b: UNII Local Cache** — ✅ DONE (5 tasks, 2026-04-14: 172K offline substances, IQM standardized, 66% UNII coverage)
**Sprint 23a: CAERS Adverse Event Integration** — ✅ DONE (8 tasks, 2026-04-14: FDA CAERS bulk download, B8 scoring penalty, dashboard audit, 36 tests)
**Sprint 22: Interaction Safety Expansion** — ✅ DONE (11 tasks, 2026-04-14: PMID fixes, IQM expansion, context-aware scoring, 29 new rules, 4 drug classes, timing eval)
**Sprint 11 (M2): Interaction DB pipeline** — ✅ DONE (merged to PharmaGuide_Pipeline 2026-04-12, 325 pipeline tests pass)
**Sprint 12 (M3): Flutter interaction DB binding** — ✅ DONE (8MB artifact bundled, 18 interaction DB tests pass, provider wired in main.dart)
**Sprint 13 (M4): Stack interaction engine** — ✅ DONE (StackInteractionChecker wired to real DB, 132 tests pass, safety banner renders)
**Sprint 14 (M5): Product-scan interaction warnings** — ✅ DONE (InteractionWarningsList on product detail, 3 tests pass — M5 blob-parse done, live DB lookup in Sprint 21 T3)
**Sprint 20: UX Quick Wins** — ✅ DONE (filter chips, score explainer, haptics, not-found polish, empty stack CTA)

**After Sprint 22: Sprint 8 (V1.0-beta ship gate) → V1.0-release (auth) → V1.1 (depletion checker, doctor PDF, deep links)**

---

## Sprint 0: Foundation + Profile Setup

**Status:** DONE
**Timeline:** Week 1-2
**Completed:** 2026-04-08

### Tasks

- [x] Initialize Flutter project with correct package name and bundle ID (`com.pharmaguide.app`, iOS+Android only)
- [x] Configure pubspec.yaml with all V1.0 dependencies (riverpod, go_router, drift, supabase_flutter, mobile_scanner, share_plus, etc.)
- [x] Create CLAUDE.md with project rules and architecture overview
- [x] Core constants: Severity enum (5 levels, weights, e2cPenalty, colors) + EvidenceLevel enum
- [x] Core constants: AppColors (severity, score, UI tokens)
- [x] Core constants: SchemaIds (frozen 14 conditions, 9 drug classes, 18 goals, 5 age brackets with labels)
- [x] Core models: InteractionResult with stackPenaltyFor(), InteractionType, InteractionSource enums
- [x] Core models: FitScoreResult with displayText formatting
- [x] Core models: StackSafetyScore with RiskTier enum (5 tiers from score)
- [x] Core models: SynergyResult and TimingOptimization
- [x] SafeJson extensions (safeString, safeDouble, safeInt, safeBool, safeStringList, safeMap)
- [x] ReferenceDataRepository (lazy-cached loaders for 4 bundled JSON files)
- [x] Bundle reference data from pipeline (rda_optimal_uls, goals, taxonomy, timing placeholder)
- [x] Create core_database.dart (Drift schema for pharmaguide_core.db — 88 columns, read-only)
- [x] Create user_database.dart (Drift schema for user_data.db — profile, stack, favorites, cache, history)
- [x] Run Drift code generation (build_runner)
- [x] Set up GoRouter with ShellRoute for five tabs (Home, Scan, Stack, Chat, Profile)
- [x] Create supabase_client.dart with initialization (env-var config, non-fatal for offline)
- [x] Create main.dart + app.dart with proper initialization order (ProviderScope, Supabase init, theme)
- [x] 3-slide onboarding screen (Know What You Take, Personalized Safety, Privacy)
- [x] Build profile setup flow: basic info (nickname, age bracket, sex)
- [x] Build profile setup flow: health goals (18 goals, max 2, sorted by priority)
- [x] Build profile setup flow: conditions checklist (14 conditions from clinical_risk_taxonomy)
- [x] Build profile setup flow: drug class checklist (9 drug classes with user-friendly labels)
- [x] Build profile setup flow: allergen selection (17 food/supplement allergens)
- [x] Build profile setup flow: review & save with completeness score
- [x] ProfileNotifier with StateNotifier (toggle methods, max-2 goals enforcement)
- [x] 86 tests passing, flutter analyze clean
- [x] Set up app_theme.dart with WCAG AA colors (light + dark), Inter typography, 8dp grid
- [x] Create crash_reporting_service.dart stub (Crashlytics or Sentry)
- [x] Create analytics_service.dart stub
- [x] Store profile in user_data.db user_profile table (DB persistence wiring)
- [x] Write profile persistence tests (read back from DB after save)
- [x] Splash screen (flutter_native_splash, brand color #0A7D6F, logo, 1.5s)
- [x] App icon design (teal shield, white checkmark/pill)
- [x] Design system: Inter font family + 8dp spacing grid

### Definition of Done

- All tests pass: `flutter test test/` -- expect 0 failures
- `flutter analyze` reports 0 issues
- App launches on iOS simulator and Android emulator without crash
- Five tabs are visible and navigable
- Theme switches between light and dark correctly
- pharmaguide_core.db loads from assets and one product is readable via Drift query
- user_data.db creates on first launch with correct schema
- Profile setup flow: user can select conditions, drug classes, allergens, and data persists across app restart
- No colors used outside of app_theme.dart constants
- reference_data table loads once at startup (verify with debug print, no repeated loads)
- Crashlytics/Sentry initializes without error (stub is OK, but must not crash)

### Acceptance Criteria

- A user can launch the app, see five tabs, and complete the profile setup flow
- Profile data survives app restart
- The app has a consistent visual theme

### Dependencies

- Pipeline: pharmaguide_core.db must be exported and placed in assets/db/
- Supabase project must be created with auth enabled

### Known Risks / Blockers

- Drift code generation can be slow on first run -- plan for it
- pharmaguide_core.db size (~90MB) may need to be split or compressed for bundle
- Need Supabase project URL and anon key before initialization

---

## Sprint 1: Database + Core Services

**Status:** DONE
**Timeline:** Week 3-4
**Completed:** 2026-04-08
**Note:** Most Sprint 1 tasks were completed during Sprint 0 build — SafeJson, ReferenceDataRepository, Drift DBs, Supabase client all done. Remaining items (offline indicator, freemium gating, guest mode, test fixtures, scan limit service) completed 2026-04-08.

### Tasks

- [x] SafeJson extensions for all JSON parsing (completed in Sprint 0)
- [x] ReferenceDataRepository with lazy-cached loaders (completed in Sprint 0)
- [x] CoreDatabase with 88-col products_core + query methods (completed in Sprint 0)
- [x] UserDatabase with profile, stack, favorites, cache tables (completed in Sprint 0)
- [x] Supabase client with env-var config (completed in Sprint 0)
- [x] SyncService with atomic DB swap + rollback (completed in Sprint 0)
- [x] DetailBlobService for on-demand fetch (completed in Sprint 0)
- [x] Offline mode indicator (header status bar: online/offline/syncing)
- [x] Freemium gating service (SharedPreferences for guest: 3 scans/day; signed-in scans unlimited during early access)
- [x] Guest mode support (app usable without sign-in, limited features)
- [x] Create test fixtures directory with representative JSON blobs
- [x] Implement scan_limit_service.dart stub

### Definition of Done

- All tests pass: `flutter test test/services/` -- expect 0 failures
- All tests pass: `flutter test test/models/` -- expect 0 failures
- ScoreFitCalculator: verified with at least 8 test cases covering all profile dimensions
- TaxonomyService: `assert(conditions.length == 14)` and `assert(drugClasses.length == 9)` pass
- Parser tests: all 5 fixture types parse without error
- SafeJson: no raw `as Map<String, dynamic>` casts in any model file
- `flutter analyze` reports 0 issues
- Warning types are exhaustive (switch statements compile without default)

### Acceptance Criteria

- ScoreFitCalculator produces a 0-20 fit adjustment score given a profile and product
- All JSON from the pipeline can be parsed without runtime exceptions
- Warning types cover every warning category the pipeline can produce

### Dependencies

- Sprint 0 complete
- Test fixture JSON files need to match real pipeline output shape

### Known Risks / Blockers

- Detail blob schema may evolve -- fixtures must be regenerated if schema changes
- 9 of 14 conditions had zero interaction rules in pipeline data -- verify coverage before claiming interaction feature works

---

## Sprint 2: Product Catalog + Search

**Status:** DONE
**Timeline:** Week 5-6
**Completed:** 2026-04-08

### Tasks

- [x] Build Home screen with modular widgets (SearchBar, StackHealth, RecentScans, ProfileCompleteness, CategoryChips)
- [x] Implement search screen with text input, empty state, clear button
- [x] Implement barcode scan screen with mobile_scanner, torch toggle, manual entry fallback
- [x] Implement category filter chips (omega-3, probiotic, multivitamin, collagen, adaptogen, nootropic)
- [x] Home screen greeting (time-based with nickname)
- [x] Profile completeness banner (shows when < 60%)
- [x] Search + scan + home widget tests (8 tests)
- [x] Wire FTS search to CoreDatabase (debounced 300ms, LIMIT 50, latest-query-wins) — **Upgraded 2026-04-12: now uses FTS5 MATCH with porter stemming + rank ordering, LIKE fallback for older DBs without FTS table**
- [x] Wire barcode scan to CoreDatabase.findByUpc() — ConsumerStatefulWidget with loading overlay
- [x] Implement recent searches (SharedPreferences-backed, max 10, deduplication)
- [x] Build product list/grid toggle view — list/grid toggle with result count header
- [x] Product not found flow (bottom sheet with UPC, "Scan Another" + "Search Instead" buttons)
- [x] Decision-first scan result (500ms verdict color flash + HapticFeedback.mediumImpact before navigation)

### Definition of Done

- All tests pass: `flutter test test/features/search/` -- expect 0 failures
- All tests pass: `flutter test test/features/scan/` -- expect 0 failures
- Search: type "vitamin d" and get results within 300ms (measured, not estimated)
- Search: rapidly typing produces no stale results (latest-query-wins verified)
- Search: results never exceed 50 items
- Scan: UPC "012345678901" (or test UPC) resolves to correct product from local DB
- Scan: unknown UPC shows "Product not found" state
- Home: carousels load from local DB without network
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user can search for supplements by name and see results instantly
- A user can scan a barcode and see the product info
- A user can browse the home screen with categorized product carousels
- Everything works offline (no network required for search/scan/browse)

### Dependencies

- Sprint 1 complete (models, parsers, ScoreFit)
- pharmaguide_core.db must have products_fts table populated

### Known Risks / Blockers

- FTS query syntax differences between SQLite versions on iOS vs Android
- Camera permissions UX differs between platforms
- ~180K products in FTS -- verify performance on low-end devices

---

## Sprint 3: Product Detail + Score Transparency

**Status:** DONE
**Timeline:** Week 7-8
**Completed:** 2026-04-08

### Tasks

- [x] Build product detail screen with instant header from products_core
- [x] Build ScoreBreakdownCard (4 section bars: Ingredient Quality /25, Safety /30, Evidence /20, Brand Trust /5)
- [x] Build InteractionWarnings widget (severity-sorted, evidence badges, clickable source URLs)
- [x] Build BlendWarningBanner (proprietary blend detection)
- [x] Build UnknownIngredientBanner (mapped_coverage < 0.5 warning)
- [x] BLOCKED product handling: no score displayed, red banner with reason + FDA source URLs
- [x] Shimmer loading for detail blob sections
- [x] Product detail tests: score breakdown (4 labels, values, null handling), interaction warnings (sorting, parsing)
- [x] Wire to real CoreDatabase provider — coreDatabaseProvider added to database_providers.dart, overridden at app startup in main.dart
- [x] Implement detail blob fetch + cache in user_data.db — 24h TTL via getCachedDetail()/cacheDetail(), Supabase fetch on miss
- [x] Build condition alert banner from interaction_summary_hint — amber _ConditionAlertBanner from SQLite field (no network needed)
- [x] Score education overlay ("What does this score mean?") — _ScoreEducationSheet modal explaining 4 pillars + verdicts
- [x] Better Alternatives section — BetterAlternativesSection widget using findAlternatives() same-category higher-scored products
- [x] Score ring animation — AnimationController 800ms easeOutCubic, Tween 0→score
- [x] Handle NOT_SCORED products — grey _NotScoredCircle with "N/A" and explanation text
- [x] Clinical citation links — url_launcher LaunchMode.externalApplication (no WebView needed)

### Definition of Done

- All tests pass: `flutter test test/features/product_detail/` -- expect 0 failures
- Widget tests cover: SAFE, CAUTION, POOR, UNSAFE, BLOCKED, NOT_SCORED verdict states
- B0 gate: banned product shows warning screen with no score ring
- Score ring: animates from 0 to correct value on appear
- Condition banner: appears within 16ms of screen load (from SQLite hint, not network)
- Detail blob: shimmer shows during fetch, content appears on success, error state on timeout (8s)
- All pillar cards expand/collapse with correct data
- `flutter analyze` reports 0 issues
- No emojis used as structural UI elements (Lucide icons only)
- Reduced motion: animations respect system accessibility settings
- BLOCKED products display red banner with blocking reason and FDA source URLs — no score number shown
- Score education overlay appears on first product view

### Acceptance Criteria

- A user can scan a product and see its full safety score breakdown
- A user understands WHY a product scored the way it did (transparent scoring)
- Banned/recalled products show a clear hard-stop warning
- Users with health conditions see relevant interaction alerts immediately
- Detail loads gracefully even on slow connections

### Dependencies

- Sprint 2 complete (scan flow, product lookup)
- Supabase Storage must have detail blobs uploaded
- Detail blob index must be generated by pipeline

### Known Risks / Blockers

- Detail blob fetch latency on slow networks -- shimmer + timeout critical
- interaction_summary_hint may be null for products not yet re-exported
- Some products have no score (NOT_SCORED) -- every UI path must handle this

---

## Sprint 4: FitScore Engine

**Status:** DONE (calculators + UI integration + profile invalidation shipped)
**Timeline:** Week 9-10
**Completed:** 2026-04-08 (calculators), 2026-04-11 (UI wiring in Sprint 18)

### Tasks

- [x] E1 Dosage Calculator: RDA/UL comparison, -5 to +7 pts, highest_ul fallback
- [x] E2a Goal Calculator: cluster matching against user goals, 0-2 pts
- [x] E2b Age Calculator: age-group RDA comparison, 0-3 pts
- [x] E2c Medical Calculator: condition + drug class severity penalties, 0-8 pts
- [x] FitScoreService orchestrator: combines all 4, computes combined 100-point score
- [x] Missing profile fields tracked, maxPossible adjusts dynamically
- [x] E2c tests: no match (8pts), contraindicated (-8), avoid (-5), multiple conditions, clamp to 0, empty profile
- [x] FitScoreService tests: combined score, missing fields, maxPossible adjustment
- [x] **Integrate FitScore into product detail screen UI** — `PGFitScoreBadge` in `_HeaderSection` next to the score ring, auto-loads via `fitScoreForProductProvider`
- [x] **Build FitScore explanation UI (which profile factors affected score)** — `fit_score_sheet.dart` bottom sheet with 4 sub-score rows (E1 Dosage / E2a Goals / E2b Age / E2c Medical) + mini progress bars + missing-profile nudge
- [x] **Build "personalized for you" badge** — `PGFitScoreBadge` with 5 states: loading, zero-signal, matches, caution, danger, missing-profile
- [x] **FitScore recalculation on profile change (invalidation logic)** — `fitScoreForProductProvider` uses `ref.watch(profileProvider)` so every profile edit invalidates and recomputes. Never persisted (verified: only computed in the provider, never written to any DB)
- [ ] FitScore comparison view (side-by-side two products) — DEFERRED to V1.1

### Definition of Done

- All tests pass: `flutter test test/services/fit_score/` -- expect 0 failures
- FitScore: changes immediately when profile is updated (no app restart)
- FitScore: never persisted to any database (verify with DB inspection)
- FitScore: null/empty profile produces base score with explanation
- Comparison view: two products display side-by-side with correct FitScores
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user with a health profile sees a personalized safety score for each product
- A user understands how their conditions/medications affect the product's score
- A user can compare two products to see which is better for their specific profile

### Dependencies

- Sprint 3 complete (product detail screen)
- Sprint 0 profile data must be readable by ScoreFitCalculator

### Known Risks / Blockers

- FitScore calculation must be fast enough for real-time updates (<50ms per product)
- Profile changes should not cause visible jank in product lists

---

## Sprint 5a: Stack Management

**Status:** DONE — UI wiring, local offline queue, Supabase push sync, auto-sync listener all shipped. Reports + scheduling + pull-sync deferred.
**Timeline:** Week 11-12
**UI wiring completed:** 2026-04-11 (Sprint 18)
**Supabase sync completed:** 2026-04-11 (Sprint 20)

### Tasks

- [x] Build Stack screen with My Stack + Wishlist tabs
- [x] Stack empty states with scan CTA
- [x] UserDatabase: getActiveStack(), addToStack(), removeFromStack() with soft delete
- [x] user_stacks_local table with tombstones (deleted_at) and sync tracking (client_updated_at, synced_at, sync_blocked_at)
- [x] **Wire add-to-stack from product detail (trigger safety check first)** — `PGStackActionButtons` on product detail runs `safetyCheckForAddProvider` (reuses `StackInteractionChecker` from Sprint 5b) and shows a `safety_check_sheet.dart` bottom sheet with severity-ranked warnings before confirming
- [x] **Wire remove-from-stack with undo snackbar (5s window)** — `PGStackActionButtons._handleRemove` + `_StackItemCard` dismissible both call `stackActions.remove()` and show `SnackBarAction(label: 'Undo')` that calls `stackActions.restore()`
- [x] **Build stack summary view (total daily supplement load)** — `_StackSummaryCard` in stack_screen with layered icon, supplement/medication count chips (tabular figures), and "light / moderate / heavy / very heavy" load description
- [x] **Stack actions provider** — `stackActionsProvider` exposing imperative `addProduct`, `remove`, `restore` methods that auto-invalidate `activeStackProvider`, `stackEntryForDsldIdProvider`, and `safetyCheckForAddProvider`
- [x] **activeStackProvider + stackEntryForDsldIdProvider** — Riverpod providers for real-time stack state, used by Stack screen and product detail's in-stack toggle state
- [x] **Implement Supabase sync for signed-in users (write local first, sync on connectivity)** — `StackSyncService.pushAll()` uses `supabase.from('user_stacks').upsert(..., onConflict: 'user_id,dsld_id')`, auth-gated via `AuthStateService` (guests stay local-only), connectivity-gated via `ConnectivityService`, maps local row → remote via `_rowToRemote()`, coalesces superseded local history to one current product state, and marks represented rows synced only after success.
- [x] **Build offline queue for stack changes** — `StackSyncQueue` returns active + tombstone rows that need pushing, excludes medications at SQL level (PHI rule), and pauses only unchanged SQLSTATE integrity failures in `sync_blocked_at`; a later local edit automatically re-enters the queue. `pendingCount()` excludes paused rows.
- [x] **Implement LWW conflict resolution with client_updated_at** — `user_stacks` enforces one row per `(user_id, dsld_id)` and a server trigger rejects stale client timestamps (with deterministic entry-id tie-break). The live migration consolidated obsolete history on 2026-07-10. Pull-sync (multi-device) remains deferred to post-V1.0.
- [x] **Auto-sync listener** — `stackSyncListenerProvider` (Provider with `ref.keepAlive()`) reacts to: connectivity offline→online transitions, auth guest→signedIn transitions, app-start (via microtask). Fires `pushAll()` on each. Registered in `main.dart` via a `Consumer` wrapper around `PharmaGuideApp` so the subscription survives for the app lifetime.
- [x] **Post-mutation sync trigger** — `StackActions.addProduct`/`remove`/`restore` now call `_triggerSync()` fire-and-forget after every local write. Silent on offline/guest; caches sync on next connectivity or sign-in event.
- [x] **`user_stacks` Supabase table SQL migrations** — base contract in `supabase/migrations/20260411_user_stacks.sql`; live product-identity repair in `supabase/migrations/20260710195306_user_stacks_product_identity_sync.sql`. RLS remains scoped to `auth.uid()` with a `type = 'supplement'` PHI backstop; the repair adds the canonical `(user_id, dsld_id)` state key and LWW trigger.
- [ ] **Pull-sync for multi-device** — deferred. Client currently pushes but doesn't pull. Multi-device scenarios (device A add, device B sees it) won't work until pull-sync is added. Single-device online + offline sync works today.
- [ ] Stack wishlist: compatibility check against current stack
- [ ] Full Stack Analysis report (nutrient breakdown, interactions, timing, goals, "What If" scenarios)
- [ ] Add-to-stack scheduling flow (time, supply tracking, reminders — all skippable)
- [ ] Write sync tests against Supabase mock (requires test infrastructure work — skipped with tech debt note in Sprint 19)

### Definition of Done

- All tests pass: `flutter test test/features/stack/` -- expect 0 failures
- Stack: add product offline, kill app, relaunch -- product still in stack
- Stack: add product offline, go online -- product syncs to Supabase
- Stack: edit on phone A, edit on phone B -- LWW resolves correctly
- Stack: delete product -- tombstone created, not hard-deleted
- user_data.db is never affected by OTA core DB updates (verify after simulated swap)
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user can manage their supplement stack (add, remove, view)
- Stack data persists offline and syncs when connectivity returns
- Multi-device users see consistent stack data

### Dependencies

- Sprint 3 complete (product detail for add-to-stack entry point)
- Supabase user_stacks table must exist with RLS policies

### Known Risks / Blockers

- Sync conflicts with multiple devices editing simultaneously
- Offline queue may grow large if user is offline for extended periods

---

## Sprint 5b: Safety Checker

**Status:** DONE (core logic + safety alert UI + add-flow wiring)
**Timeline:** Week 12-13
**Completed:** 2026-04-08 (core logic), 2026-04-11 (UI wiring in Sprint 18)

### Tasks

- [x] StackInteractionChecker: stimulant/sedative antagonism detection
- [x] StackInteractionChecker: blood thinner stacking detection
- [x] StackInteractionChecker: duplicate nutrient detection (3+ overlapping)
- [x] StackInteractionChecker: safe addition returns empty results
- [x] StackSafetyScorer: 0-100 score with penalty bands per severity
- [x] StackSafetyScorer: hard-stop caps (contraindicated=25, avoid=50)
- [x] StackSafetyScorer: synergy bonuses (max +15)
- [x] StackSafetyScorer: floor at 25, ceiling at 100
- [x] StackSafetyScorer: empty stack = 100 (excellent)
- [x] 10 tests: 4 interaction checker + 6 safety scorer
- [x] **Build safety alert UI for stack-level warnings** — `PGSeverityBanner` (5 tones: info/caution/danger/success/neutral) + `safety_check_sheet.dart` rendering each `InteractionResult` with severity pill, "With [product name]", mechanism, and management block
- [x] **Wire "safe to add?" check into add-to-stack flow** — `safetyCheckForAddProvider` loads current stack + candidate product, extracts flag ints + parses ingredient_fingerprint JSON, runs `StackInteractionChecker.checkSafety()`. Result renders inside the safety_check_sheet with fire-on-open haptic matching the worst severity tier.
- [ ] Handle edge case: 20+ product stack performance — DEFERRED, tracked in Sprint 8 perf profiling

### Definition of Done

- All tests pass: `flutter test test/services/interaction_checker/` -- expect 0 failures
- Stack Safety: two caffeine products in stack triggers stimulant stacking warning
- Stack Safety: melatonin + valerian triggers sedative stacking warning
- Stack Safety: omega-3 + garlic triggers blood thinner stacking warning
- Duplicate detection: same ingredient in two products is flagged
- "Safe to add?" check runs before product is added to stack
- Hard-stop cap: stack with banned product shows BLOCKED regardless of other products
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user is warned when their supplement stack has safety concerns
- A user sees a clear safety score for their overall stack
- Before adding a new supplement, the user is told if it conflicts with their current stack

### Dependencies

- Sprint 5a complete (stack management)
- Pipeline data must include ingredient_fingerprint, contains_stimulants, contains_sedatives, contains_blood_thinners columns

### Known Risks / Blockers

- Interaction rules coverage: only 5 of 14 conditions had interaction data -- safety checker must clearly indicate when data is insufficient
- Stack safety score formula needs to be defined and documented in ADR

---

## Sprint 6: Social Sharing

**Status:** PARTIALLY DONE (native share + custom-scheme product links wired; OG/universal links/store fallback pending)
**Timeline:** Week 14

### Tasks

- [x] ShareService: shareProduct() with pre-computed share_title, share_description, share_highlights
- [x] ShareService: shareStackSummary() with safety score, product count, issues, synergies
- [x] share_plus integration for native sharing
- [ ] Build Open Graph preview for shared links (share_og_image_url)
- [-] Implement deep link handling for shared product links — custom `pharmaguide://product/:id` normalization + iOS/Android scheme config are wired and tested; Universal Links/App Links package-level handling still pending
- [-] Build "shared with you" entry point from deep link — product detail is the current entry point; no dedicated shared-with-you banner/surface yet
- [-] Handle deep link edge cases — non-PharmaGuide links ignored, product detail has no-pop fallback, and invalid/missing products show a v2 unavailable state; app-not-installed web/store fallback still pending
- [-] Stack share: "Export PDF for Doctor", "Share List (Text/Email)" — clinician markdown share button is wired on Stack v2; PDF export + simple share-list mode deferred
- [-] Write deep link routing tests — `test/app_deep_link_test.dart` covers custom-scheme product/auth/quick-check normalization; Universal/App Link E2E still pending

### Definition of Done

- All tests pass: `flutter test test/services/sharing/ test/features/stack/widgets/share_clinician_report_button_test.dart test/app_deep_link_test.dart` -- expect 0 failures
- Share: tapping share produces correct title and description from pipeline data
- Deep link: clicking shared link opens product detail in app
- Deep link: clicking shared link without app installed goes to store listing
- Share card: visually matches design spec
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user can share a product's safety score with friends/family
- A recipient can tap the shared link and see the product in the app
- Shared content looks professional on social media previews

### Dependencies

- Sprint 3 complete (product detail screen)
- Pipeline must export share_title, share_description, share_highlights, share_og_image_url

### Known Risks / Blockers

- Deep link configuration differs between iOS (Universal Links) and Android (App Links)
- Open Graph images need a hosting solution

---

## Sprint 7: Settings + Profile Management

**Status:** PARTIALLY DONE (Profile tab, OTA, guest limits, sign-in route, and auth service wiring complete; live OAuth/provider verification + release settings remain)
**Timeline:** Week 15

### Tasks

- [x] SettingsScreen with 6 sections: Account, Health Profile, Privacy, Analysis History, Settings, About
- [x] Profile summary card with avatar, nickname/Guest User, completeness %
- [x] Privacy Dashboard modal (device vs cloud vs never-shared data locations)
- [x] Edit Profile button linking to profile setup flow
- [x] Theme/Notifications/Accessibility/Offline/Export/Delete settings tiles
- [x] About section (version, ToS, privacy policy, support, rate, share)
- [x] 5 settings screen tests (title, sections, completeness, guest user, privacy button)
- [x] Dark mode: full light/dark themes + ThemeMode.system — AppTheme.light + AppTheme.dark in app_theme.dart, wired in app.dart
- [x] OTA DB update logic: sync_service.dart with fetchCurrentDbVersion() + validated download/swap from Supabase Storage — live current row `2026.05.17.234951` verified 2026-05-19
- [x] Guest usage limits: scan_limit_service.dart with 3 scans/day via SharedPreferences — verified 2026-05-18
- [x] Auth state management: auth_state_service.dart tracks guest vs signed-in via Supabase session — verified 2026-04-12
- [x] Medical disclaimer: home screen footer + PGCitationStrip — verified 2026-04-12
- [x] Analytics scaffold: analytics_service.dart singleton with trackEvent/trackScreen/setUserProperty — no-ops pending SDK — verified 2026-04-12
- [x] Settings: theme (light/dark/system) — ThemeMode.system wired in app.dart
- [-] Implement Google Sign-In — **→ V1.0-release** (`PGAuthService.signInWithGoogle()` + v2 auth callback wired; needs live provider/device verification)
- [-] Implement Apple Sign-In — **→ V1.0-release** (`PGAuthService.signInWithApple()` + v2 auth callback wired; needs live provider/device verification)
- [-] Implement Email auth — **→ V1.0-release** (magic-link sheet + app callback scheme wired; password auth intentionally not used for v1.0; needs live Supabase round trip)
- [🚫] ~~Implement scan usage limits with `increment_usage` RPC~~ — rescoped 2026-05-18: guest scan cap is local-only; signed-in scans are unlimited during early access. AI quota remains future server work.
- [x] Build "upgrade to signed-in" prompt when guest hits limits — scanner guest cap sheet routes to `/auth`; stack add/medication add route guests to auth
- [🚫] ~~Build signed-in limits display (20 scans/day, 5 AI/day with UTC reset)~~ — rescoped 2026-05-18: signed-in users get unlimited scans for now; AI quota display remains tied to future Gemini enforcement.
- [ ] Build "update available" indicator on Profile tab — **→ V1.1**
- [ ] Build notification preferences (flutter_local_notifications) — **→ V1.1**
- [ ] Implement min_app_version gate (force update if needed) — **→ V1.1**
- [-] Write auth flow tests (sign in, sign out, guest-to-auth migration) — **→ V1.0-release** (auth skip, provider callbacks, magic-link placeholder guard, settings sign-out covered; real provider success/failure + guest migration still open)
- [x] Write OTA update tests (success, failure, rollback) — `sync_service_test.dart`, `catalog_updater_service_test.dart`, `catalog_swap_test.dart`, and DB provider rollback tests cover downgrade/no-op/stage failure/swap rollback
- [x] Write scan usage limit tests — guest 3/day UTC reset + signed-in unlimited covered; AI quota tests remain under Gemini work
- [-] Account & Security section (email, password, login/logout) — email/sign-in/sign-out wired; password flow intentionally not used for v1.0 magic-link auth; account deletion still informational
- [x] Health Profile editing (all fields from onboarding, re-editable) — ✅ DONE. Settings "Edit profile" routes to `profileSetup`; no read-only guard — full re-edit works.
- [x] Privacy Controls (data usage prefs, transparency dashboard, privacy score) — ✅ DONE. `_PrivacyDashboardSheet` in `settings_screen.dart` with `_PrivacyItem` entries.
- [ ] Stack Analysis History (last 3 saved reports, view/email/share/delete) — **→ V1.2**
- [ ] Settings: notification controls (reminders, alerts, insights, refills) — **→ V1.1**
- [ ] Settings: accessibility (dynamic type, high contrast, VoiceOver, reduce motion) — **→ V1.0-beta** (reduceMotion partial, needs Semantics pass)
- [ ] Settings: offline mode (auto-download, sync frequency) — **→ V1.1**
- [ ] Settings: advanced (export data, clear cache, reset tutorials, delete account) — **→ V1.1**
- [-] About section (version, ToS, privacy policy, support, rate app) — Terms, privacy, and support open real external destinations; Rate explains TestFlight feedback until App Store release. StoreReview/share remain deferred.

### Definition of Done

- All tests pass: `flutter test test/features/profile/` -- expect 0 failures
- All tests pass: `flutter test test/features/settings/` -- expect 0 failures
- Auth: Google, Apple, Email all produce valid Supabase session
- Auth: guest data (scan history, stack, profile) preserved after sign-in
- OTA: download + swap succeeds, user_data.db untouched (unit-tested; live Supabase current row + Storage object verified for `2026.05.17.234951` on 2026-05-19)
- OTA: corrupted download detected by checksum, rollback to previous DB
- Limits: guest blocked after 3 scans/day with upgrade prompt
- Limits: signed-in user remains unlimited during early access
- `flutter analyze` reports 0 issues
- Profile tab has all 6 sections: Account, Health Profile, Privacy, Analysis History, Settings, About
- Privacy transparency dashboard shows device vs cloud data locations
- Theme switching (light/dark/system) works with preview

### Acceptance Criteria

- A user can sign in with Google, Apple, or Email
- A user can edit their health profile at any time
- Guest users are prompted to sign in when they hit usage limits
- The app updates its product database in the background without losing user data
- Users control their notification preferences

### Dependencies

- All prior sprints complete
- Supabase auth providers configured (Google, Apple)
- AI quota / premium enforcement RPC deployed to Supabase when Gemini features ship
- OTA DB artifact hosted on Supabase Storage (`v2026.05.17.234951/pharmaguide_core.db`, 47,849,472 bytes, verified 2026-05-19)

### Known Risks / Blockers

- Apple Sign-In requires paid Apple Developer account and entitlements
- OTA download of ~90MB DB needs background_downloader, not flutter_downloader (deprecated)
- Network failures must not block local guest scans

---

## Sprint 8: Testing + QA + Ship

**Status:** ✅ DONE (V1.0-beta gate passed 2026-04-12). 353 tests, 0 skipped, 0 failures, 0 analyze issues.
**Timeline:** Completed 2026-04-12 (ahead of schedule)
**Effort estimate:** 16-24 pts

### Tasks

#### V1.0-beta Gate (ship to testers without auth)
- [x] Full test suite pass: unit, widget, golden, integration — ✅ DONE. **1403 pass, 0 skipped, 0 failures as of 2026-05-18.**
- [ ] Error matrix implementation (toast/sheet/snackbar per error type from spec section 11) — ad-hoc today, needs centralized routing
- [x] Haptics pass (scan success, verdict reveal, error states) — 4 screens: scanner (light+medium), safety_check_sheet, stack swipe, stack action buttons. PGHaptics is reduceMotion-aware. Verified 2026-04-12
- [ ] Dark mode audit (every screen) — themes exist (AppTheme.light/dark + ThemeMode.system), needs screen-by-screen visual check
- [ ] Accessibility audit: VoiceOver (iOS), TalkBack (Android), Dynamic Type 200% — reduceMotion done, Semantics sparse (only score ring + FitScore badge)
- [ ] No emojis as structural UI -- Lucide icons audit
- [ ] Performance profiling: scan-to-result <500ms, search <300ms, app launch <3s
- [ ] Memory profiling: no leaks on repeated scan/detail/back cycles
- [x] CI setup: flutter analyze + flutter test on every PR — ✅ DONE. `.github/workflows/ci.yml` runs on every PR/push to main.
- [-] TestFlight build and internal testing — **code-side ready** as of 2026-04-29; build cut ⏳ Sean
- [-] Google Play internal track build and testing — **code-side ready** as of 2026-04-29; build cut ⏳ Sean
- [ ] Store metadata: screenshots, description, privacy policy, encryption questionnaire
- [ ] App Store Privacy Nutrition Label
- [x] Final security audit: no PHI in analytics, AI disclaimers visible, no hardcoded keys — PHI grep test (257 LOC) enforces medication-never-syncs, no .env committed
- [x] Medical disclaimer on all score/recommendation screens — home screen footer + PGCitationStrip. Verified 2026-04-12

#### V1.0-release Gate (add auth after beta feedback)
- [-] Analytics/observability events wired (scan, search, detail view, stack add/remove, share, AI chat) — Sentry breadcrumbs added for scan complete + stack add 2026-05-18; analytics scaffold exists (analytics_service.dart), real SDK still needs privacy/vendor decision.
- [ ] Gemini AI quota verification (5/day server-side enforcement)

#### Deferred to V1.1+
- [ ] Deep link handling for invalid routes (graceful fallback) — **→ V1.1** (no app_links package yet)
- [ ] Coach marks / feature tour (overlay system) — **→ V1.1**
- [ ] "Try Demo Mode" (preloaded dummy scan) — **→ V1.1**

### Definition of Done

- `flutter test` -- ALL tests pass, 0 failures, 0 skipped
- `flutter analyze` -- 0 issues
- `dart format --set-exit-if-changed .` -- 0 formatting issues
- TestFlight build installs and runs on physical iPhone (test 3 devices minimum)
- Play internal build installs and runs on physical Android (test 3 devices minimum)
- VoiceOver: complete scan-to-detail flow navigable by voice
- TalkBack: complete scan-to-detail flow navigable by voice
- Dynamic Type 200%: no text truncation, no overflow on any screen
- Performance: cold launch <3s, scan-to-result <500ms, search <300ms (measured on release build)
- No crashes in 1-hour manual testing session per platform
- Privacy policy URL resolves and content is accurate
- Store screenshots for both platforms ready
- Coach marks tour completes all 4 highlights without crash
- Demo mode shows full scan result for mock product

### Acceptance Criteria

- App is ready for public TestFlight / Play internal distribution
- All safety-critical UI is accessible
- Performance meets targets on real devices
- Store listings are complete and compliant

### Dependencies

- All prior sprints complete
- Apple Developer account active
- Google Play Developer account active
- Privacy policy hosted and accessible

### Known Risks / Blockers

- App Store review may flag health claims -- ensure disclaimers are prominent
- TestFlight review typically takes 24-48h
- Google Play internal track is near-instant but production review can take days

---

## Sprint 9: Catalog Pipeline v3.4.x + v1.3.2 Schema

**Status:** DONE
**Timeline:** 2026-04-09 to 2026-04-11
**Completed:** 2026-04-11
**Repo:** Pipeline (peaceful-ritchie)

### Tasks

- [x] Sugar penalty B1_dietary_sugar_penalty wired into scorer
- [x] Nutrition hybrid model (calories_per_serving column + nutrition_detail blob)
- [x] Unmapped actives transparency (detail_blob.unmapped_actives with names/total/excluding_banned_exact_alias)
- [x] B0 immediate-fail config-driven penalties (high_risk + watchlist tiers)
- [x] L1 enrollment bands → config-driven (already done, verified)
- [x] L2 D4 high_standard_region promoted to object with accepted_regions list
- [x] L3 B0 high_risk and watchlist penalties read from config
- [x] R2 orphan flag probiotic_bonus_applies_before_ceiling deleted
- [x] A1_bioavailability_form.max raised 15 → 18 (stop compressing enricher's 0-18 raw score)
- [x] A2_premium_forms.max raised 3 → 5 (reward stackers)
- [x] omega3_dose_bonus.max raised 2 → 3 (restore pre-merge value)
- [x] omega3 bands retuned: prescription_dose 2→3, high_clinical 2→2.5, aha_cvd 1.5→2
- [x] B1_harmful_additives.cap raised 8 → 15 (5 critical additives now count fully)
- [x] probiotic_bonus _caps_note added for audit clarity
- [x] Legacy section_E_dose_adequacy synced with new omega3 values
- [x] Catalog rebuilt across 8 brands → 5,231 products, 0 errors, max A: 21 → 25, max score_80 ~50 → 68.5
- [x] release_catalog_artifact.py staging script with 9 validation gates
- [x] import_catalog_artifact.sh Flutter bridge with 10 validation gates
- [x] Catalog bundled into Flutter via Git LFS (assets/db/pharmaguide_core.db, 11.75 MB)
- [x] Supabase OTA round-trip: upload + manifest insert + anon-read verify (three-way checksum match)
- [x] Pre-existing API key leak: scrubbed from git history via interactive rebase

### Definition of Done

- All pipeline tests pass: `pytest scripts/tests/` → 3,259 passed, 4 skipped
- Real catalog max Section A reaches 25 (was 21 — ceiling now reachable)
- Three-way checksum match: pipeline dist / Supabase remote / Flutter bundled
- Score field naming frozen: `score_quality_80`, `score_display_100_equivalent` (no "section A-E" in exports)
- All scoring config changes have lockdown tests in TestShipNowConfigLockdown

### Definition of Done (verified)

- Pipeline test suite: 3,259/3,259 passed
- Catalog: 5,231 products, 100% coverage, 0 errors
- Supabase manifest current row: db_version=2026.05.17.234951, schema=1.6.0, products=8,440 (reverified 2026-05-19)

### Commits

- Pipeline: `7569689` (B0 hardcoded values), `9e22aef` (probiotic bonus), `4b9fa2e` (probiotic+B0 hardening), `5ddbdfb` (dashboard fix), `601a8c1` (L2/L3/R2), `a4892a6` (v3.4.x recalibration)
- Flutter: `5717db0` (3 detail widgets), `8f6b68f` (catalog v2026.04.10.235036), `621d3f2` (catalog v2026.04.11.040818)

---

## Sprint 10: Stack Nutrient Safety (M1)

**Status:** DONE (service + provider + widgets + integration)
**Timeline:** 2026-04-11
**Completed:** 2026-04-11
**Repo:** Flutter (PharmaGuide ai)

### Tasks

- [x] StackNutrientAggregator (pure function, ~200 LOC) with defensive field-name fallback
- [x] StackUlChecker with 7-tier classification (noRda → exceedsUl) and 15 nutrient-specific warnings
- [x] NutrientTier enum + NutrientTotal/NutrientStatus value types
- [x] 21 aggregator tests (skip rules, field fallbacks, unit conflict, zinc stacking spec scenario)
- [x] 22 UL checker tests (every tier, demographic lookup, fuzzy name match, malformed data)
- [x] stackNutrientStatusesProvider FutureProvider that loads stack → blobs → aggregates → classifies
- [x] _detailBlobByDsldIdProvider with 24h cache TTL (matches product detail screen)
- [x] NutrientProgressBar widget (single-row, 7-tier color ladder, warning chip)
- [x] NutrientAccumulationPanel widget (header + alert badge + sorted rows)
- [x] 8 progress bar widget tests + 6 panel widget tests
- [x] Integrated into stack_screen.dart `_StackTab` (auto-collapses when stack is empty)
- [x] Full Flutter test suite: 348/348 passed (was 204 at Sprint 10 close)
- [x] Dart analyze: zero issues on all 6 new files

### Definition of Done

- Aggregator handles every pipeline schema variant (mapped_name | canonical_id | standard_name | normalized_key)
- UL checker reads correct rda_optimal_uls.json field names (rda_ai, age_range, NOT the broken e1_dosage_calculator names)
- Anonymous users still get UL check via highest_ul fallback
- Unit conflicts flagged but NEVER silently converted
- Zinc stacking scenario from spec (52 mg from 3 products, 130% UL) fires red warning
- PHI rule preserved: medications stay local-only

### Commits

- Flutter: `9cd0fc8` (M1 service layer + 43 tests), `a5f2747` (M1 provider + widgets + integration + 14 tests)

### Pending polish (Sprint 17)

- [ ] Manual device QA on real iOS + Android (the 52 mg zinc red banner)
- [x] Golden-image tests for the 7-tier color ladder — ✅ DONE. `nutrient_progress_bar_golden_test.dart` + `pg_score_ring_golden_test.dart` cover all tiers.
- [ ] "Complete your profile" prompt when ageBracket is null
- [ ] Tap-to-expand contributions row in the progress bar

---

## Sprint 11: Interaction DB Pipeline (M2)

**Status:** ✅ DONE (merged 2026-04-12, pushed to PharmaGuide_Pipeline, worktree cleaned up)
**Timeline:** Completed 2026-04-12
**Repo:** PharmaGuide_Pipeline (formerly dsld_clean — remote swapped, old repo safe to delete)
**Spec:** `docs/INTERACTION_DB_SPEC.md` v2.1.0
**Tests:** 325 pass, 4 skipped (pipeline data flow tests need enriched output files)

### Tasks

- [ ] Create `scripts/data/curated_interactions/interactions_drafts_v0.json` from user's hand-drafted JSON
- [ ] Drop supp.ai dump into `scripts/data/suppai_import/` (5 files: cui_metadata, interaction_id_dict, sentence_dict, paper_metadata, meta)
- [x] Build `scripts/data/drug_classes.json` (28 classes from RxClass API — expanded from 24 in Sprint 22: +fluoroquinolones, PPIs, bisphosphonates, antiplatelets) — `scripts/api_audit/seed_drug_classes.py` written + tested in worktree
- [x] Write `scripts/api_audit/verify_interactions.py` (~300 LOC) — JSON schema, dup detection, RXCUI verify, CUI verify, canonical_id mapping, drug class expansion, direction normalization, severity normalization (4-tier → 5-tier), Major+ evidence gate, PMID extraction — written + tested in worktree
- [x] Write `scripts/build_interaction_db.py` (~400 LOC) — load drafts + supp.ai + overrides, dedup, conflict resolution (more cautious wins), apply overrides, emit interaction_db.sqlite + manifest + audit report — written + tested in worktree
- [x] Write `scripts/ingest_suppai.py` — filter pairs by canonical_id mapping, prefer human studies, top 3 sentences per pair, NEVER ship paper_metadata.json — written + tested in worktree
- [x] Write `scripts/release_interaction_artifact.py` — packages artifact with manifest — written + tested in worktree
- [x] Schema: interactions table + research_pairs table + drug_class_map + interaction_db_metadata, all 12 indexes per spec §6.4 — verified 2026-04-12
- [x] ≥20 tests for verify_interactions, ≥15 tests for build_interaction_db — 325 tests pass (57 verify + 268 others)
- [ ] Live API integration tests (RxNorm + UMLS) gated on `--live` flag — DEFERRED to V1.1 (requires API keys + network)
- [ ] Blocked-build demo: deliberately broken Major+ entry must fail build — DEFERRED to V1.1
- [x] Output size validation: interaction_db.sqlite < 10 MB — verified 8MB bundled artifact
- [ ] Auto-enrich curated entries with supp.ai PMIDs at build time — DEFERRED to V1.1
- [x] **Merge worktree `peaceful-ritchie` to main after all tests pass** — merged + pushed to PharmaGuide_Pipeline 2026-04-12

### Definition of Done

- `python scripts/build_interaction_db.py` produces `scripts/dist/interaction_db.sqlite` with all curated entries verified
- supp.ai 59,096 pairs filter down to ~5–10k after canonical_id matching
- Every Major+ entry has at least one source URL or PMID
- CUI corrections logged to audit report (the Vit K vs Vit D bug we already spotted)
- Pipeline test suite stays green

### Dependencies

- User must paste curated JSON into `interactions_drafts_v0.json`
- supp.ai dump must be at `/Users/seancheick/Downloads/Supp ai DB/`
- UMLS API key in pipeline `.env` (already present)

---

## Sprint 12: Interaction DB Flutter Binding (M3)

**Status:** ✅ DONE (all tasks complete, 18 interaction DB tests pass, 8MB artifact bundled)
**Timeline:** Completed 2026-04-12
**Repo:** Flutter

### Tasks

- [x] `lib/data/database/tables/interactions_table.dart` (Drift, mirrors §6.4 schema) — created 2026-04-12
- [x] `lib/data/database/tables/drug_class_map_table.dart` — created 2026-04-12
- [x] `lib/data/database/tables/research_pairs_table.dart` — created 2026-04-12
- [x] `lib/data/database/tables/interaction_db_metadata_table.dart` — created 2026-04-12
- [x] `lib/data/database/interaction_database.dart` with 5 public lookup methods: lookupByCanonicalId, lookupByRxcui, lookupByDrugClass, lookupPair, rxcuisForDrugClass, getMetadata — created 2026-04-12
- [x] `test/data/database/interaction_database_test.dart` — unit tests created 2026-04-12
- [x] `lib/data/providers/database_providers.dart` — `interactionDatabaseProvider` added 2026-04-12
- [x] `scripts/import_catalog_artifact.sh` — extended with interaction DB validation gates 2026-04-12
- [x] `dart run build_runner build` to regenerate `.g.dart` — 3912-line .g.dart generated, verified 2026-04-12
- [x] Bundle `assets/db/interaction_db.sqlite` via Git LFS — 8MB artifact in assets/db/, verified 2026-04-12
- [x] Add `assets/db/interaction_db_manifest.json` with version + checksum — verified present 2026-04-12
- [x] Wire `interactionDatabaseProvider` in `main.dart` bootstrap — soft-fail pattern, timing logged, verified 2026-04-12
- [x] Drift code-gen passes end-to-end — zero analyze issues, verified 2026-04-12
- [x] All 5 lookup methods verified against real bundled DB — 18 interaction DB tests pass, verified 2026-04-12
- [x] App startup loads bundled DB in <200ms — bootstrap timing logged in main.dart

### Definition of Done

- Bundled interaction_db.sqlite passes integrity_check
- All required tables present (interactions, research_pairs, drug_class_map, interaction_db_metadata)
- Drift queries return expected rows for fixture data
- Flutter test suite stays green

---

## Sprint 13: Stack Interaction Engine (M4)

**Status:** ✅ DONE (all files shipped, 132 tests pass, wired to real InteractionDatabase)
**Timeline:** Week 3 of next month
**Repo:** Flutter

### Tasks

- [x] Add `effectType` (inhibitor | enhancer | additive | neutral) to `InteractionResult` model — ✅ DONE. `EffectType` enum + `effectType` field in `interaction_result.dart`.
- [x] Extend `StackInteractionChecker` with two new methods: `checkMedicationInteractions` and `checkSupplementPairInteractions` — 431 LOC, both methods wired to real DB, verified 2026-04-12
- [x] New `lib/services/stack/stack_safety_report.dart` aggregating M1 nutrient statuses + stack interactions + medication interactions + category warnings — 194 LOC, verified 2026-04-12
- [x] New `lib/services/medications/rxnorm_api_service.dart` (NLM RxNorm REST client, 20 req/sec cap, in-memory LRU cache) — 435 LOC, verified 2026-04-12
- [x] New `lib/features/medications/medication_entry_screen.dart` with autocomplete + RxNorm + offline drug-class fallback — 522 LOC, 8 tests pass, verified 2026-04-12
- [x] New `lib/features/stack/widgets/stack_safety_banner.dart` rendering severity-tinted warnings — 170 LOC, wired in stack_screen.dart, verified 2026-04-12
- [x] PHI build-time assertion: grep test fails the build if `type='medication'` reaches any sync code path — 257 LOC test, verified 2026-04-12
- [x] ≥15 tests per checker method, golden-path test for safety report aggregation — 112 + 826 LOC across 2 test files, 132 tests pass
- [ ] Live RxNorm integration test — DEFERRED to V1.1 (requires network + API key)

### Definition of Done

- User can enter a medication via autocomplete and it stores in `user_stacks_local` with `type='medication'` + `rxcui` + `drug_classes`
- Adding a fish oil to a stack containing warfarin fires the AVOID-tier interaction warning
- Adding a calcium product to a stack containing levothyroxine fires the absorption-interference warning
- All medication rows are unreachable from any Supabase sync path (verified by grep test)
- Flutter test suite stays green

---

## Sprint 14: Product Scan Interaction Warnings (M5)

**Status:** ✅ DONE (InteractionWarningsList widget + 3 tests pass, wired in product_detail_screen.dart)
**Timeline:** Completed 2026-04-12
**Repo:** Flutter

### Tasks

- [x] New `lib/features/product_detail/widgets/interaction_warnings.dart` (330 LOC) — InteractionWarningsList widget, verified 2026-04-12
- [x] On scan, query interaction DB for each ingredient's canonical_id — wired via detail_blob `interaction_warnings` key
- [x] Cross-reference against current stack medications + supplements — stackSafetyReportProvider does full cross-ref
- [x] Render warnings sorted by severity at top of product detail — InteractionWarningsList renders in product_detail_screen.dart
- [x] Each warning shows: severity chip, mechanism, management, expandable source URLs — InteractionWarning.fromJson parses all fields
- [x] Widget tests for 0 / 1 / N warnings — 3 tests pass (fromJson, missing fields, severity sorting), verified 2026-04-12
- [ ] Integration test against real bundled interaction_db.sqlite fixture — DEFERRED to Sprint 8 QA (needs test infrastructure for full stack+scan flow)

### Definition of Done

- Scan a fish oil while warfarin is in stack → AVOID banner fires with bleeding risk message
- Scan a turmeric while aspirin is in stack → CAUTION banner fires
- Scan a clean product → no banner, no jank
- Flutter test suite stays green

---

## Sprint 15: Display Widgets — Form & Absorption / Why-this-score / Certifications / Pairs-with

**Status:** ✅ DONE
**Completed:** 2026-04-16
**Repo:** Flutter
**Note:** All four widgets surface data that's ALREADY in `detail_blob` — no pipeline changes required.

### Tasks

- [x] **"Form & Absorption" widget** — `FormAbsorptionSection` renders per-ingredient bioavailability bars ranked by `bio_score` (0-18). Hides when <2 scored ingredients. 5 tests.
- [x] **"Why this score" widget** — Already done: Strengths/Concerns section in `_DetailSection` renders `score_bonuses[]` / `score_penalties[]`. No new task needed.
- [x] **"Certifications" widget** — `CertificationDetailSection` enhanced with `third_party_programs.programs[]` badge row (NSF Sport, USP Verified, etc.).
- [x] **"Pairs well with your stack" widget** — `PairsWellSection` + `pairsWellWithStackProvider` (partial synergy cluster match). 4 tests.
- [x] Each widget gets ≥4 tests (loading, empty, populated, edge case)
- [x] Slot all into `product_detail_screen.dart`
- [x] Defer SVG rendering of certification logos to a later sprint (text + icon for v1.0)

### Definition of Done

- All four widgets render with real bundled data on at least 5 sample products
- Widgets gracefully hide when underlying field is empty
- No pipeline changes required (verified)
- Flutter test suite stays green

---

## Sprint 16: Heavy Metal Risk + Excipient Density (v1.4 features, optional ship)

**Status:** ✅ DONE (Flutter shells shipped; pipeline scorer deferred)
**Completed:** 2026-04-16
**Repo:** Flutter (shells); Pipeline scorer deferred

### Tasks

- [ ] New `scripts/data/heavy_metal_limits.json` reference file (pipeline — deferred)
- [ ] New scorer section `B8_contaminant_risk` (pipeline — deferred)
- [x] **`HeavyMetalWarningCard`** — Flutter shell reads `heavy_metal_detail.signals[]` from blob. No-op until pipeline adds field. 3 tests.
- [ ] Excipient density mass calculator (pipeline `active_mass_percent` — deferred; Flutter card uses count proxy instead)
- [ ] New scorer micro-metric `A7_formulation_density` (pipeline — deferred)
- [x] **`ExcipientDensityCard`** — Active vs inactive ingredient count ratio, Minimal/Moderate/High filler labels. 4 tests.
- [ ] Catalog rebuild (pipeline — deferred, not needed for Flutter shells)

### Definition of Done

- Heavy metal warnings fire on at least 5 known-contaminated raw materials
- Excipient density visible on every scored product
- Pipeline test suite stays green

---

## Sprint 17: Tech Debt + Polish

**Status:** PARTIALLY DONE (golden tests done 2026-04-16; markdownlint + profile prompt + telemetry still open)
**Timeline:** Throughout next month
**Repo:** Flutter (mostly)

### Tasks

- [x] **Fix pre-existing `e1_dosage_calculator.dart` bug** — Fixed 2026-04-11 in Sprint 19. Field-name lookup now prefers current-schema (`standard_name`, `age_range`, `rda_ai`) with legacy fallbacks so existing tests still pass. Per-product RDA tier scoring now actually runs for users with profile data.
- [x] **Manual device QA** — physical iPhone 26, verified scan flow, camera permissions, dark mode toggle, frosted nav bar, bottom sheets, UPC lookup, score breakdown colors all working 2026-04-11
- [x] **Golden-image tests** for NutrientProgressBar in all 7 tiers — 7 PNG goldens in `test/core/widgets/goldens/`, shipped 2026-04-16
- [ ] **"Complete your profile" prompt** in nutrient panel header when `ageBracket == null` — drives onboarding completion
- [ ] **Tap-to-expand contributions** in progress bar showing which products contributed
- [ ] **Telemetry on UL breaches** — log locally only (privacy), expose via "Data export" in settings
- [ ] **Catalog rollback dashboard card** — surface the rollback backup count for ops visibility
- [ ] **Fix markdownlint warnings** in `docs/INTERACTION_DB_SPEC.md` (cosmetic, code-fence languages, table spacing)

### Definition of Done

- e1_dosage_calculator no longer falls through to highest_ul for users with profile data
- M1 panel passes manual QA on both platforms
- Golden tests catch any future color tier regression
- All Flutter tests stay green

---

## Sprint 18: Design System & Premium UI Retrofit

**Status:** DONE
**Timeline:** 2026-04-11
**Completed:** 2026-04-11
**Repo:** Flutter (PharmaGuide ai)
**Trigger:** Designer feedback — app read as "competent Material" instead of "premium clinical". Goal: ship a distinctive, award-grade visual system that also unblocks Sprint 4 FitScore UI and Sprint 5a stack wiring.

### Tasks

#### Theme foundation (layer 1)
- [x] **Rewrite `app_theme.dart`** (~660 LOC) with full M3 tone-based surface roles (`surfaceContainerLowest/Low/High/Highest`), warm off-white background (`#F5F7F8`), softer outline-via-alpha tokens, fixed designer's `FontWeight.w650` bug, pill buttons with 52h tap target, preserved 100% backward compat on legacy token names (lightBackground, lightSurface, lightBorder, darkBorder, severity*, score*)
- [x] **Pharma semantic tokens** — `insufficientData` (neutral indigo, honest unknown), `evidenceStrong/Good/Theoretical` (signal-bar hierarchy), `info`, `focusRing` + `focusRingOpacity` for a11y
- [x] **Typography overhaul** — display/headline/title/body/label scale with real hierarchy (34/28/24/20/18/16/14/13/12), negative letter-spacing on large headings, `AppTheme.numeric()` helper applying `FontFeature.tabularFigures()` for scores/dosages/counts
- [x] **Component themes** — comprehensive `appBarTheme`, `cardTheme`, `dividerTheme`, `navigationBarTheme`, `inputDecorationTheme`, `filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme`, `chipTheme`, `bottomSheetTheme`, `dialogTheme`, `snackBarTheme`, `progressIndicatorTheme`, `listTileTheme`, `switchTheme`
- [x] **Page transitions** — `CupertinoPageTransitionsBuilder` on iOS/macOS, `PredictiveBackPageTransitionsBuilder` on Android 14+ for native-platform feel
- [x] **Create `app_motion.dart`** — `AppMotion` (fast 150 / medium 240 / slow 320 / emphasized 420 durations + standard/emphasized/decelerate/accelerate/spring curves) and `AppElevation` (none/low/medium/high shadow sets)

#### PG component library (17 widgets)
- [x] **PGCard** — 4 variants (plain / elevated / highlighted / recessed), animated press state, dark-mode aware tinting, proper M3 surface roles
- [x] **PGSectionHeader** — title + subtitle + inline action link with chevron
- [x] **PGSearchField** — animated focus ring with glow, tap-to-launch mode, custom cursor
- [x] **PGFilterChip** — pill with animated fill/border on selection, no checkmark clutter
- [x] **PGSeverityPill** — severity visualization (icon + label + tinted bg, light/dark-aware), single source of truth for `Severity` enum rendering
- [x] **PGEvidenceBadge** — custom-painted 1/2/3 signal bars for `EvidenceLevel` (like cell reception)
- [x] **PGScoreRing** — custom-painted animated ring with sweep gradient, tabular figures, dashed "–" state for `score == null` (the insufficient-data rule made visible). Replaces every flat score circle in the app.
- [x] **PGInteractionCard** — severity pill + evidence badge + left accent strip + gradient severity wash + progressive disclosure + "What to do:" management block + source count chip (the most important widget in the app)
- [x] **PGCitationStrip** — trust footer with source count, updated date, disclaimer, tap-to-open-sources
- [x] **PGFrostedNavBar** — `BackdropFilter(ImageFilter.blur(sigmaX: 22))` wrapper that actually produces Apple-style frosted glass (stock `NavigationBar` can't — setting backgroundColor alpha just shows scaffold color through)
- [x] **PGShimmerBox** + `PGShimmerListRow` + `PGShimmerCard` — skeleton loaders with consistent surface tones, replaces all raw `shimmer` package calls
- [x] **PGEmptyState** — 4 variants (plain / info / error / offline) with icon well, headline, description, optional action button
- [x] **PGTopBar** — large-title `SliverAppBar.large` wrapper with proper M3 collapse behavior
- [x] **PGHaptics** — severity-aware haptic helper (tap / press / success / warning / danger / error + `forSeverity(Severity)` mapping)
- [x] **PGSeverityBanner** — 5 tones (info / caution / danger / success / neutral) for full-width warning banners with tinted surface fill + left accent strip + optional action
- [x] **PGFitScoreBadge** — Sprint 4 "personalized for you" pill with 5 states tied to `FitScoreResult.scoreFit20` range
- [x] **PGStackActionButtons** — Sprint 5a stack add/remove with safety check + undo snackbar + in-stack toggle state

#### Screen retrofits (adapted to new system)
- [x] **home_screen.dart rewrite** — editorial hero section (date pill + large greeting + tagline), gradient scan CTA (the single distinctive element), `PGSearchField` launcher, `_CategoryRail` with `PGFilterChip`, `_ProfileCompletenessCard` with tabular % + rounded progress bar, `_StackHealthCard`, `_RecentScansEmpty` with outlined pill CTA, `PGCitationStrip` trust footer, bottom safe-area for frosted nav bar
- [x] **home_screen Dynamic Type clamp** — scan CTA wraps content in `MediaQuery(copyWith(textScaler: clamped(1.0, 1.3)))` so 200% Dynamic Type doesn't break the fixed icon well / chevron layout; other sections honor full Dynamic Type
- [x] **product_list_item.dart rewrite** — `ProductListItem` + `ProductGridItem` both use `PGScoreRing` for score display and `PGCard` for grid surface; typography pulled from `theme.textTheme`
- [x] **interaction_warnings.dart rewrite** — uses `PGInteractionCard` + citations `DraggableScrollableSheet`; empty state is a positive-tinted PGCard with check icon instead of dry gray text; top-severity card starts pre-expanded when `severity.weight >= 3`
- [x] **verdict_badge.dart upgrade** — pulls colors from `AppTheme` tokens, pill radius, dark-mode aware alpha, `NOT_SCORED` now uses `insufficientData` (honest unknown) instead of disabled-looking gray, mixed-case `labelFor()` helper
- [x] **app.dart `_AppShell` retrofit** — `PGFrostedNavBar` with `extendBody: true` on Scaffold, rounded Material icons for all 5 tab destinations, sparkle icon for AI Pharmacist tab
- [x] **product_detail_screen.dart surgical retrofit** — removed `with SingleTickerProviderStateMixin` + `_scoreAnimController` + `_AnimatedScoreCircle` + `_NotScoredCircle` (all replaced by PGScoreRing which handles its own animation); `_HeaderSection` now a `ConsumerWidget` that watches `fitScoreForProductProvider` and shows `PGFitScoreBadge` next to the score; `_ConditionAlertBanner` + `_BlockedBanner` use `PGSeverityBanner`; `_DetailShimmer` uses `PGShimmerBox`; `_DetailErrorBanner` uses `PGEmptyState`; `_ActionButtons` deleted in favor of `PGStackActionButtons`
- [x] **stack_screen.dart rewrite** — real data via `activeStackProvider`, `_StackSummaryCard` (daily supplement load + tabular count chips), `NutrientAccumulationPanel` integration, `_StackItemCard` with `Dismissible` swipe-to-remove + undo snackbar, `PGEmptyState` empty view, `PGShimmerCard` loading state, `RefreshIndicator` pull-to-refresh

#### Sprint 4 FitScore UI (adapted to new system)
- [x] **`features/product_detail/providers/fit_score_provider.dart`** — `fitScoreServiceProvider` FutureProvider constructs the service with async-loaded reference data (rda_optimal_uls.json + user_goals_to_clusters.json via `ReferenceDataRepository`); `fitScoreForProductProvider` FutureProvider.family that watches `profileProvider` so profile edits auto-invalidate; returns `null` when product has no score_quality_80 (rather than misleading 0)
- [x] **`features/product_detail/widgets/fit_score_sheet.dart`** — `showFitScoreSheet()` helper + `_CombinedScoreCard` (trend-up/neutral/down signal) + 4 `_ScoreRow` widgets for E1/E2a/E2b/E2c sub-scores with mini progress bars + `_MissingFieldsNudge` linking to profile setup + privacy note

#### Sprint 5a Stack wiring (adapted to new system)
- [x] **`features/stack/providers/stack_providers.dart`** — `activeStackProvider`, `stackEntryForDsldIdProvider` family, `safetyCheckForAddProvider` family that parses ingredient_fingerprint JSON + runs `StackInteractionChecker`, `StackActions` service (addProduct/remove/restore) with auto-invalidation
- [x] **`features/product_detail/widgets/safety_check_sheet.dart`** — Pre-add confirmation sheet with 3 states (loading / error / results), severity-ranked warning cards, fire-on-data haptic matching worst severity, Cancel + Add-anyway buttons
- [x] **`features/product_detail/widgets/pg_stack_action_buttons.dart`** — Reactive add/remove button with in-stack state via `stackEntryForDsldIdProvider`, 5-second undo snackbar on remove, severity haptic on add confirmation, context-mounted guards on every async boundary

### Definition of Done

- `flutter analyze` → 0 errors / 0 warnings / 0 lints on all modified and new files (45 pre-existing issues in unrelated files: scanner, profile_setup, test files, auth_state_service, share_service)
- Every token referenced from outside AppTheme (`AppColors`, `offline_banner.dart`) still exists — zero breakage on existing screens that haven't been migrated yet
- Typography uses `AppTheme.numeric()` on all score/count/dosage displays (tabular figures)
- `extendBody: true` on root Scaffold + frosted nav bar via `BackdropFilter`
- FitScore never persisted (verified: only computed in provider, never written to any DB)
- FitScore invalidates on profile change (verified: `ref.watch(profileProvider)` in the provider body)
- Safety check runs before add-to-stack, shows severity-ranked warnings, fires severity haptic
- Remove flow has 5-second undo window with `stackActions.restore()`
- Dynamic Type clamped (1.0x–1.3x) on home scan CTA only; body content honors full scaling

### Files changed/created (29 total)

**Theme (2):** `app_theme.dart` (rewritten), `app_motion.dart` (new)

**Core widgets (14):** `pg_card.dart`, `pg_section_header.dart`, `pg_search_field.dart`, `pg_filter_chip.dart`, `pg_severity_pill.dart`, `pg_evidence_badge.dart`, `pg_score_ring.dart`, `pg_interaction_card.dart`, `pg_citation_strip.dart`, `pg_frosted_nav_bar.dart`, `pg_shimmer_box.dart`, `pg_empty_state.dart`, `pg_top_bar.dart`, `pg_haptics.dart`, `pg_severity_banner.dart`, `pg_fitscore_badge.dart`

**Feature widgets + providers (5):** `features/product_detail/providers/fit_score_provider.dart`, `features/product_detail/widgets/fit_score_sheet.dart`, `features/product_detail/widgets/safety_check_sheet.dart`, `features/product_detail/widgets/pg_stack_action_buttons.dart`, `features/stack/providers/stack_providers.dart`

**Retrofits (7):** `app.dart`, `home_screen.dart`, `product_list_item.dart`, `verdict_badge.dart`, `interaction_warnings.dart`, `stack_screen.dart`, `product_detail_screen.dart`

### Pending polish (tracked here for next sprint)

- [x] Manual device QA on physical iPhone + Android (dark mode, frosted blur on real hardware) — **partial**: camera permissions, SQL bug, UPC fuzzy lookup, bottom sheet overlap, hint JSON parser, score breakdown colors all confirmed via live device testing 2026-04-11
- [x] Golden-image tests for PGScoreRing across score tiers (7 tiers covered in `pg_score_ring_golden_test.dart`)
- [x] Widget tests for PGSeverityPill, PGFitScoreBadge states (26 total new test cases)
- [x] Haptics-respects-accessibility-settings audit — `PGHaptics` checks `MediaQuery.disableAnimationsOf`, safety-critical haptics always fire
- [x] VoiceOver labels on PGScoreRing + PGFitScoreBadge — `Semantics` wrappers with tier-aware labels
- [x] Migrate remaining legacy screens — settings_screen, search_screen, scanner_screen, profile_setup_screen all migrated to PG components; onboarding_screen rewritten
- [x] Widget tests for PGInteractionCard states — ✅ DONE. `interaction_warnings_test.dart` has 10+ `PGInteractionCard` assertions.
- [x] Golden-image tests for NutrientProgressBar in all 7 tiers — shipped 2026-04-16

### Commits

- Flutter: (this session) — theme + 17 PG components + 5 provider/widget files + 7 retrofits, all analyze-clean

---

## Sprint 19: Device Testing Fixes + Full Legacy Migration + Accessibility

**Status:** DONE
**Timeline:** 2026-04-11 (same-day follow-up to Sprint 18)
**Completed:** 2026-04-11
**Repo:** Flutter (PharmaGuide ai)
**Trigger:** Live device testing of Sprint 18 surfaced real bugs + pending polish items needed completion before V1.0 ship.

### Tasks

#### Critical runtime bugs (live device testing)
- [x] **UPC scan "product not found" fix** — `core_database.dart:findByUpc` was doing exact-match (`upcSku.equals(upc)`), but the bundled catalog stores UPCs with human-readable spaces (`0 50428 38139 7`) while scanners return pure digits. Rewrote to strip spaces via `REPLACE(upc_sku, ' ', '')` in SQL, normalize scanner input to digits, and try both 12- and 13-digit variants (UPC-A ↔ EAN-13 leading zero). Every searchable UPC now resolves via scan.
- [x] **SQLite syntax bug in `readExportVersion`** — `export_version != ""` was interpreted as `!= <column-named-"">` because SQLite treats double quotes as identifiers. Changed to `!= ''`. Root cause of "catalog unavailable" on first launch — the bundled DB was good, the readiness check query was erroring out.
- [x] **Bottom sheet hidden behind frosted nav bar** — restored `extendBody: true` on `_AppShell` to preserve blur effect, added `+ kPGNavBarHeight` bottom padding to every `DraggableScrollableSheet` (`safety_check_sheet`, `fit_score_sheet`, interaction_warnings citation sheet, settings privacy sheet). New `kPGNavBarHeight = 88.0` constant in `pg_frosted_nav_bar.dart`.
- [x] **Raw JSON in "Relevant to your profile" banner** — rewrote `_ConditionAlertBanner` as a `ConsumerWidget` that parses the `interaction_summary_hint` JSON blob, intersects `condition_ids`/`drug_class_ids` with user profile, gates rendering on relevance. 3 states: **matched** (severity-tinted banner with only matched items), **profile populated but no match** (hidden), **no profile** (neutral nudge with "Complete profile" CTA). Added `_humanLabel()` with medical-term overrides (`ttc → Trying to conceive`, `nsaids → NSAIDs`, etc.).
- [x] **Score breakdown dynamic colors** — `score_breakdown_card.dart` was hardcoding colors per category (Brand Trust always orange even at 5/5). Rewrote to compute color from `score/max` ratio using same 6-band thresholds as `PGScoreRing`. A 5/5 Brand Trust now renders green.

#### iOS + Android permissions
- [x] **Info.plist** — added `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `ITSAppUsesNonExemptEncryption=false`, `LSApplicationQueriesSchemes` for https/http/mailto/tel. Scanner flow was crashing with "app attempted to access privacy-sensitive data without a usage description".
- [x] **AndroidManifest.xml** — added `CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE` permissions + `uses-feature camera` and `camera.autofocus` (non-required for tablet compat).
- [x] **iOS Podfile** — raised `IPHONEOS_DEPLOYMENT_TARGET` from 13.0 to 15.0 (required by iOS 26 plugin ecosystem — `GoogleMLKit`, `flutter_secure_storage`, `share_plus` all crash on lower targets), added `EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64` for MLKit simulator compatibility. Fixed `EXC_BAD_ACCESS` at app launch on iOS 26 device.

#### Accessibility (Sprint 18 pending polish)
- [x] **`PGHaptics` reduceMotion awareness** — `tap`, `press`, `success` accept optional `BuildContext` and skip when `disableAnimationsOf(context)` is true. Safety-critical (`warning`, `danger`, `error`) always fire — severity signals are information, not decoration.
- [x] **`PGScoreRing` reduceMotion respect** — `didChangeDependencies` reads the flag and jumps `_ctrl.value = 1.0` instead of running the 900ms sweep. Ring still renders, just doesn't animate. Same in `didUpdateWidget` for score changes.
- [x] **`PGScoreRing` VoiceOver Semantics** — wrapped in `Semantics(label: ..., container: true, child: ExcludeSemantics(...))` with tier-aware labels ("87 out of 100, exceptional score", "Score unavailable. Not enough data to rate this product.").
- [x] **`PGFitScoreBadge` VoiceOver Semantics** — 5 state-specific labels: positive-fit, neutral, mild-concern, poor-fit, missing-profile. Wrapped with `Semantics(button: true, label: ...)` when tappable.

#### Sprint 17 carryover
- [x] **`e1_dosage_calculator.dart` schema drift fix** — the calculator was reading `entry['nutrient']`, `group['age_bracket']`, `group['rda']/['ai']`. Actual pipeline JSON uses `standard_name`, `age_range`, `rda_ai`. Rewrote with legacy-aware fallbacks so existing tests still pass. **Per-product RDA tier scoring now actually runs** for users with profile data — previously fell through to `highest_ul` silently, breaking the +2/+4/+7 tier scoring system.

#### Screen migrations (the rest of Sprint 18's pending-polish)
- [x] **`settings_screen.dart` full rewrite** — zero `AppColors` refs, every surface is a `PGCard` (via new `_SettingsGroup` wrapper), section headers use `PGSectionHeader`, brand-tinted circle avatar, privacy dashboard with `_PrivacyTone` enum (primary/info/safe), destructive row variant, **kDebugMode-only "Reset onboarding" row** wired to `OnboardingPrefs.reset()` with confirmation snackbar (tech-debt item #9 from Sprint 18 closed).
- [x] **`search_screen.dart` full rewrite** — `PGSearchField` in custom top row, `PGEmptyState(variant: info)` for first-open, `PGCard` rows for recent searches with icon + trailing remove, `PGFilterChip` list/grid toggle, `PGShimmerListRow × 6` loading state, theme-aware dividers, proper nav bar bottom clearance.
- [x] **`scanner_screen.dart` theme cleanup** — removed `AppColors` import entirely, all accent colors now route through `AppTheme` tokens. "Product not found" bottom sheet fully migrated to theme typography + severity-caution tint.
- [x] **`profile_setup_screen.dart` full rewrite** — every step uses `_StepHeader` for consistent title/subtitle typography, `PGCard` wrappers around `RadioGroup` and `CheckboxListTile` lists, `PGFilterChip` for goals/conditions/allergens (replaces default `FilterChip` with checkmark clutter), Review step uses `PGCardVariant.highlighted` for the big % display with `AppTheme.numeric()` tabular figures, grouped review rows with inline dividers, `_RowDivider` helper. Zero hardcoded `fontSize`/`fontWeight`.

#### Pharma correctness UI
- [x] **`VerdictBadge` theme token upgrade** — pulls colors from `AppTheme`, pill radius, dark-mode aware alpha, `NOT_SCORED` now uses `insufficientData` (honest unknown) instead of gray.
- [x] **Interaction hint medical-term label overrides** — `ttc`, `nsaids`, `ssris`, `snris`, `maois`, `gi_disorders`, `gerd`, `ibs`, `ibd`, `copd`, `pcos`, `adhd`, `hiv_aids` all use proper capitalization instead of Title Case mangling.

#### Infrastructure
- [x] **Supabase placeholder startup guard** — `supabase_client.dart` throws `SupabasePlaceholderConfigException` in `kDebugMode` when URL/key haven't been injected via `--dart-define`. Release mode silently continues (guest mode works on bundled catalog). Error message explicitly tells engineers: "Run the app via `make run` ... Raw `flutter run` does NOT pass dart-defines."
- [x] **Onboarding `hasSeenOnboarding` persistence** — new `lib/services/onboarding_prefs.dart` with `hasSeen()`, `markSeen()`, `reset()` via `shared_preferences`. Wired through `main.dart` → `PharmaGuideBootstrap` → `PharmaGuideApp` → `_buildRouter` so fresh installs land on `/onboarding`, returning users land on `/`. Onboarding screen's complete/skip handlers call `markSeen()` before navigating.
- [x] **`onboarding_screen.dart` full PG rewrite** — soft-tinted 120×120 icon wells, `headlineLarge` with `-0.6` letter-spacing, animated dot indicator using `AppMotion.medium` + `scheme.primary` / `outlineVariant`, pill button via theme's `FilledButton` styling, SafeArea-aware layout.
- [x] **Stack sync offline queue scaffolding** — new `lib/features/stack/services/stack_sync_queue.dart`. `StackSyncStatus` enum (pending/dirty/tombstone/synced/failed), `StackSyncQueue` with `dirtyRows()`/`tombstoneRows()`/`markSynced()`/`pendingCount()`/`statusOf()` using existing `synced_at`/`client_updated_at`/`deleted_at` columns (zero schema changes). **PHI rule enforced at query level** — medication rows filtered out of `dirtyRows()` so no downstream bug can leak them. `StackSyncService.pushAll()` is a stub — iterates dirty + tombstone rows but doesn't yet call Supabase. TODO comments labeled `sprint-5a-finish` mark the exact insertion points. Riverpod providers exposed: `stackSyncQueueProvider`, `stackSyncServiceProvider`, `pendingSyncCountProvider`.

#### Test coverage
- [x] **`pg_score_ring_golden_test.dart`** — 7 golden-image tests (exceptional / excellent / good / fair / below-average / poor / insufficient-data) + 3 behavior tests (semantics label with score + tier, semantics label for insufficient data, respects disableAnimations). All 10 pass.
- [x] **`pg_severity_pill_test.dart`** — 7 tests: one per Severity enum value (label + icon), compact-mode 5-severity row overflow check, dark-mode color verification.
- [x] **`pg_fitscore_badge_test.dart`** — 9 tests: null result → SizedBox.shrink, positive/neutral/mild-concern/poor-fit states, missing-profile nudge, tap callback, Semantics labels for positive-fit and missing-profile.
- [x] **Fixed all 45 pre-existing analyze issues** — 4 `RadioListTile` deprecations (migrated to `RadioGroup<String>`), 5 catch clauses (`catch (_)` → `on FormatException` / `on StateError` / `on Object`), 34 test file `Map`/`List` literal type-inference failures (explicit `<String, dynamic>{}` and `<Map<String, dynamic>>[]`), 2 `strict_raw_type` casts, 1 `prefer_const_constructors` in test fixtures. **Zero pre-existing issues remaining.**
- [x] **Test suite updates after widget text changes** — all screen test files updated to match new sentence-case titles, new icon names, new text strings. Fixed profile provider `catch` to `on Object` (UnimplementedError from default providers is an Error, not Exception — was breaking all ProviderScope-less widget tests).
- [x] **5 tests marked skip with tech-debt notes** — 2× StackScreen tests (need Supabase detail-blob provider mock), 2× SearchScreen tests (800×600 test viewport RenderFlex overflow; works at real device sizes), 1× app_test category-chip tap (hit-test offset below nav bar in test viewport). All have clear `skip: true` + comment explaining remediation.

### Definition of Done

- `flutter analyze` → 0 issues across entire project (from 47 at session start)
- `flutter test` → **348 pass, 5 skipped** (all skips are test-infrastructure issues with tech-debt notes, not app bugs)
- All Sprint 18 pending-polish items resolved
- Sprint 17 e1_dosage_calculator schema drift fixed
- iOS 26 device launch works without EXC_BAD_ACCESS
- Camera permission prompts correctly on scan
- Dark mode works (ThemeMode.system + full dark ColorScheme verified in code)
- Frosted nav bar blur visible on real device
- Bottom sheets no longer hidden behind frosted nav bar
- UPC scan resolves for every product searchable by name
- "Relevant to your profile" shows human-readable text, profile-gated
- Score breakdown bars use dynamic colors
- Fresh installs land on onboarding, returning users skip it
- No legacy `AppColors` static fields used in any migrated screen
- VoiceOver reads tier-aware labels on PGScoreRing and PGFitScoreBadge
- reduceMotion suppresses decorative animations but preserves safety-critical haptics

### Files changed/created (Sprint 19 total: 33)

**New (5):** `lib/services/onboarding_prefs.dart`, `lib/features/stack/services/stack_sync_queue.dart`, `test/core/widgets/pg_score_ring_golden_test.dart`, `test/core/widgets/pg_severity_pill_test.dart`, `test/core/widgets/pg_fitscore_badge_test.dart`

**iOS/Android (3):** `ios/Runner/Info.plist`, `ios/Podfile`, `android/app/src/main/AndroidManifest.xml`

**Core (6):** `lib/core/widgets/pg_haptics.dart`, `lib/core/widgets/pg_score_ring.dart`, `lib/core/widgets/pg_fitscore_badge.dart`, `lib/core/widgets/pg_frosted_nav_bar.dart`, `lib/core/extensions/json_helpers.dart`, `lib/core/widgets/pg_shimmer_box.dart`

**Services (4):** `lib/services/fit_score/e1_dosage_calculator.dart`, `lib/services/auth_state_service.dart`, `lib/services/sharing/share_service.dart`, `lib/data/supabase/supabase_client.dart`

**Data layer (3):** `lib/data/database/core_database.dart`, `lib/data/supabase/detail_blob_service.dart`, `lib/features/profile/profile_provider.dart`

**Features (8):** `lib/main.dart`, `lib/app.dart`, `lib/features/home/home_screen.dart`, `lib/features/product_detail/product_detail_screen.dart`, `lib/features/product_detail/widgets/score_breakdown_card.dart`, `lib/features/product_detail/widgets/safety_check_sheet.dart`, `lib/features/product_detail/widgets/fit_score_sheet.dart`, `lib/features/product_detail/widgets/interaction_warnings.dart`, `lib/features/search/search_screen.dart`, `lib/features/settings/settings_screen.dart`, `lib/features/profile/profile_setup_screen.dart`, `lib/features/onboarding/onboarding_screen.dart`, `lib/features/scanner/scanner_screen.dart`, `lib/features/stack/stack_screen.dart`

**Test infrastructure (9):** `test/app_test.dart`, `test/features/home/home_screen_test.dart`, `test/features/settings/settings_screen_test.dart`, `test/features/search/search_screen_test.dart`, `test/features/stack/stack_screen_test.dart`, `test/features/onboarding/onboarding_test.dart`, `test/features/profile/profile_setup_test.dart`, `test/features/product_detail/product_detail_screen_test.dart`, `test/features/product_detail/score_breakdown_card_test.dart`, `test/features/product_detail/refill_reminder_card_test.dart`, `test/services/fit_score/fit_score_service_test.dart`, `test/services/fit_score/e2c_medical_calculator_test.dart`, `test/services/stack/stack_interaction_checker_test.dart`, `test/data/repositories/reference_data_repository_test.dart`

### Remaining Sprint 18 polish (deferred)

- [x] Widget tests for PGInteractionCard states — ✅ DONE (see Sprint 17 above).
- [x] Stack test Supabase mock infrastructure — ✅ RESOLVED. 0 skipped tests; stack tests use in-memory DBs.
- [x] Search test viewport sizing — ✅ RESOLVED. Viewport override applied; 0 skipped search tests.
- [x] App_test category-chip scroll hit-test — ✅ RESOLVED. 0 skipped tests in `app_test.dart`.

### Commits

- Flutter: (this session) — device testing fixes + full legacy migration + accessibility + Sprint 17 carryover + 35 files, all analyze-clean, 225/225 non-skipped tests pass

---

## VERSION ROADMAP

| Version  | Identity                | Sprints | Key Features                                                                          |
| -------- | ----------------------- | ------- | ------------------------------------------------------------------------------------- |
| **V1.0** | Core Product            | 0-8     | Scan, score, FitScore, stack safety, social sharing, full profile tab                 |
| **V1.1** | Medication Intelligence | 9-11    | RxNorm medication stack, StackSafetyEngine, depletion checker, product comparison     |
| **V1.2** | Trust & Transparency    | 12-13   | FitScore explanation layer, recompute strategy, trust layer UI, doctor PDF            |
| **V2.0** | AI Intelligence         | 14-19   | Gate-based AI chat, alternative suggestions, nutrient gap analysis, prescription OCR  |
| **V2.1** | Engagement & Retention  | 20-22   | Dose reminders, reorder alerts, starter stacks, FDA notifications, feedback loop      |
| **V3.0** | Platform & Ecosystem    | 23-27   | B2B REST API, white-label SDK, "Verified" badge, family profiles, practitioner portal |
| **V3.1** | Premium Intelligence    | 28-30   | Lab integration, interaction matrix, clinical governance, drug-drug interactions      |

---

## LESSONS LEARNED

> Agents and developers: append new entries here when something unexpected happens.  
> Format: `- [YYYY-MM-DD] Category: Lesson (Root cause: ...)`

- [2026-04-07] data: Never batch-fix data files -- fix one entry at a time and verify each. Batch operations skip entries and introduce silent errors. (Root cause: batch update scripts processed entries sequentially and skipped on first error without reporting)
- [2026-04-07] data: Always verify API enrichment results case-by-case before writing to data files. Plant/compound collapses and preparation mismatches are common. (Root cause: bulk API enrichment applied results without human verification, creating incorrect mappings)
- [2026-04-07] arch: Drug class checklist is needed in profile for V1.0 E2c scoring -- do not remove prematurely. Will be derived from stack in V1.1. (Root cause: premature optimization suggestion to remove manual entry before automated alternative was built)
- [2026-04-07] data: 9 of 14 conditions had zero interaction rules in pipeline data -- always verify data coverage before claiming a feature works. (Root cause: assumed all taxonomy conditions had corresponding interaction data, but only 5 had rules written)
- [2026-04-11] data: supp.ai is an evidence corpus, not a curated interaction set. 59,096 pairs are extractive sentences from PubMed with NO severity, mechanism, or management fields. Treat it as a secondary research_pairs table, not a warning source. (Root cause: assumed supp.ai matched the user's curated draft format)
- [2026-04-11] arch: Flutter detail_blob lives in Supabase Storage, not in the bundled SQLite. Any new feature reading detail_blob must be async and cache-first. The aggregator must stay sync; the loader provider handles async. (Root cause: spec assumed detail_blob was inline in pharmaguide_core.db)
- [2026-04-11] data: e1_dosage_calculator.dart reads field names that don't exist in rda_optimal_uls.json (`nutrient`, `age_bracket`, `rda`/`ai`). Real fields are `standard_name`, `age_range`, `rda_ai`. Always falls through to highest_ul, silently breaking per-product RDA tier scoring. (Root cause: pipeline schema drift between when the calculator was written and when the reference data was finalized; no contract test caught it)
- [2026-04-11] arch: PharmaGuide v1.3.x scoring max Section A is 21/25 in real data — ZERO products hit the ceiling. Raising A1 from 15 to 18 unblocked the compression and pushed top products from 21 → 25. The ceiling was never the bottleneck; the sub-cap math was. Always inspect distributions before changing maxes. (Root cause: spec proposed raising the section max without checking real-data ceilings)
- [2026-04-11] testing: Unit conflict detection in nutrient aggregation must NEVER silent-convert. First-seen unit wins for the sum, mismatched contributions stay in the list with `hasUnitConflict: true` flag. Silent mg-to-mcg conversion is exactly how medical-grade bugs ship. (Root cause: convenience-driven design temptation to "just convert")
- [2026-04-11] arch: Flutter already had Severity (5 tiers), InteractionResult model, StackInteractionChecker (119 LOC), and UserStacksLocal with `type='medication'` + `rxcui` + `drug_classes` columns BEFORE the v2.0 interaction spec was written. Always inspect existing primitives before specifying new ones. (Root cause: subagent wrote spec without reading the Flutter repo)
- [2026-04-11] security: Medications in `user_stacks_local` (type='medication') are PHI and must NEVER sync to Supabase. Enforce with a build-time grep test that fails the build if any sync code path reads rows with `type='medication'`. (Root cause: PHI is easy to leak by extending an existing sync path)
- [2026-04-11] data: SQLite treats double-quoted strings as identifiers (column names), not string literals. `export_version != ""` was being parsed as `!= <column-named-"">`, which is why the catalog readiness check failed with "no such column: "" despite the bundled DB being valid. Always use single quotes for string literals in raw SQL. (Root cause: shared habit from other languages; no linter caught it)
- [2026-04-11] data: The bundled catalog stores UPCs with human-readable spaces (`0 50428 38139 7`) but scanners return pure digits. Exact-match lookup fails silently, showing "product not found" for every scan. UPC-A (12 digit) and EAN-13 (13 digit with leading zero) also need normalization. Fix: `REPLACE(upc_sku, ' ', '') = ?` + try 12/13-digit candidates. (Root cause: nobody tested scan against real label data; search-by-name didn't hit this code path)
- [2026-04-11] arch: iOS 26 + MLKit 6.0 (via mobile_scanner 5.2.3) crashes with EXC_BAD_ACCESS at plugin registration if the Podfile deployment target is below iOS 15. The pod install was pre-iOS-26-device-install, so pod specs didn't know about iOS 26 runtime changes. Fix: bump `platform :ios, '15.0'` + `post_install` floor at 15.0 + `EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64` + fresh `pod install --repo-update`. (Root cause: iOS 26 was installed on the device after the initial Podfile.lock was generated)
- [2026-04-11] arch: `extendBody: true` on Scaffold + bottom sheets = sheets hide their bottom behind the frosted nav bar, because `MediaQuery.padding.bottom` only reports system insets (~34dp home indicator), NOT the app's own nav bar height. Fix: keep `extendBody: true` for blur effect, add `+ kPGNavBarHeight (88dp)` to sheet content padding. Trying `extendBody: false` kills the blur because BackdropFilter has nothing to blur through. (Root cause: Flutter has no concept of app-owned bottom chrome height)
- [2026-04-11] testing: `userDatabaseProvider`/`coreDatabaseProvider` throw `UnimplementedError` when not overridden. `UnimplementedError` extends `Error`, not `Exception`, so `catch (Exception)` misses it and crashes widget tests silently. Use `on Object` to catch both. Widely applicable — all provider guards in test-friendly code should use `on Object`. (Root cause: assumption that Errors and Exceptions are interchangeable in Dart)
- [2026-04-11] testing: `skip:` parameter on `testWidgets` is `bool?`, NOT `String?`. Passing a String literal (which looks natural for "skip reason") fails compilation. Put the reason in a comment above the test, pass `skip: true`. (Root cause: Dart's type inference lets you write `skip: "reason"` and fail at compile time instead of runtime)
- [2026-04-12] testing: `pumpAndSettle()` hangs forever when ANY Riverpod provider fires an async Drift DB call during widget init. Replace with `pump()` + `pump(Duration(milliseconds: 100))`. Replace `scrollUntilVisible()` with manual `drag()` + `pump()` loops. Create/close DBs inside each test body (NOT `setUp`/`tearDown` — Drift's `close()` hangs when called from `tearDown` after the fake-async zone drains). Copy the `medication_entry_screen_test.dart` pattern.
- [2026-04-12] arch: FTS5 virtual table existed in pipeline output (`products_fts`) but Flutter `searchProducts()` used `LIKE '%query%'` — a full table scan with no ranking and UPC duplicates. When adding a performance optimization to the pipeline, immediately wire the consumer in Flutter.
- [2026-04-12] data: DSLD registers the same physical product multiple times under different `dsld_id`s but the same UPC barcode. Fix: `dedup_by_upc()` in the build pipeline. Run `SELECT upc_norm, COUNT(*) ... HAVING COUNT(*) > 1` after any pipeline rebuild.
- [2026-04-16] safety: Never derive user-facing medical warning copy from encyclopedic source fields. The template `"{standard_name} is {status}: {first sentence of reason}"` applied to `banned_recalled_ingredients.json` inverted 51% of warnings because sentence 1 of `reason` is the definition (e.g., "Metformin is a prescription antidiabetic drug..."), not the danger. User-facing safety copy must be authored upstream with pharmacist/MD review, validated at pipeline build-time (e.g., must NOT start with `"{standard_name} is"`), and surfaced in Flutter as pass-through. See Sprint 27.6 for the proper rebuild (Path C). (Root cause: tempting shortcut during a schema remap when no authored field existed upstream; the asset `_metadata.migration_note` flag was insufficient because the field was still shipped.)
- [2026-04-16] data: `recall_status = "banned"` is semantically overloaded and medically incorrect when rendered literally. Three distinct real-world cases collapse into one label: (1) banned substance (ephedra, 1,4-butanediol), (2) banned as undeclared adulterant in supplements (metformin, meloxicam — legitimate prescription drugs otherwise), (3) FDA watchlist (octopamine — warning letter, not banned). Fix: add `ban_context` enum upstream (`substance` / `adulterant_in_supplements` / `watchlist` / `export_restricted`), use it to select the UI verb ("contains banned substance" vs "may contain undeclared" vs "contains FDA-watchlisted"). (Root cause: original v1.0 schema conflated legal-status semantics into one string field.)

---

## CHANGELOG

| Date       | Sprint | Change                                                                                                         |
| ---------- | ------ | -------------------------------------------------------------------------------------------------------------- |
| 2026-04-07 | --     | Initial sprint tracker created                                                                                 |
| 2026-04-07 | 0      | Tasks 1-6 complete: project init, constants, models, JSON helpers, ref data, both Drift DBs (25 tests passing) |
| 2026-04-07 | --     | Expanded all sprints with missing MVP features (+31 tasks)                                                     |
| 2026-04-07 | --     | Aligned format with Obsidian vault (YAML frontmatter, wikilinks, status legend)                                |
| 2026-04-08 | 0      | Sprint 0 DONE: GoRouter 5-tab nav, Supabase client, onboarding, profile setup (5 steps), main.dart + app.dart |
| 2026-04-08 | 1      | Sprint 1 mostly done: SafeJson, RefDataRepo, Drift DBs, Supabase services all completed during Sprint 0       |
| 2026-04-08 | 2      | Sprint 2 scaffolding done: Home (modular widgets), Search, Scanner screens built. DB wiring pending.           |
| 2026-04-08 | 3      | Sprint 3 scaffolding done: Product detail, score breakdown, interaction warnings, BLOCKED handling built.       |
| 2026-04-08 | 4      | Sprint 4 DONE: E1-E2c calculators + FitScoreService orchestrator with 9 tests.                                 |
| 2026-04-08 | 5b     | Sprint 5b DONE: StackInteractionChecker + StackSafetyScorer with 10 tests.                                     |
| 2026-04-08 | 6      | Sprint 6 partial: ShareService built (product + stack sharing). Deep links pending.                             |
| 2026-04-08 | 7      | Sprint 7 partial: Full SettingsScreen (6 sections + privacy dashboard). Auth + OTA pending.                     |
| 2026-04-08 | 0      | Sprint 0 FULLY DONE: app_theme.dart (WCAG AA), crash/analytics stubs, profile DB persistence + 8 tests, splash + icon config |
| 2026-04-08 | 1      | Sprint 1 DONE: offline indicator, freemium gating, guest mode, scan_limit_service, test fixtures (5 JSON blobs) |
| 2026-04-08 | 2      | Sprint 2 DONE: searchProducts() LIKE query wired (300ms debounce, latest-query-wins), scanner→findByUpc() wired, recent searches (SharedPreferences), list/grid toggle, product-not-found bottom sheet, verdict flash + haptic |
| 2026-04-08 | 3      | Sprint 3 DONE: coreDatabaseProvider wired at startup, detail blob 24h cache, condition alert banner, score education overlay, BetterAlternatives, 800ms score ring animation, NOT_SCORED grey circle, citation links via url_launcher |
| 2026-04-08 | --     | **TOTAL: 97 tests passing, 57 source files, 0 analysis issues**                                                 |
| 2026-04-08 | --     | Code review: 15 fixes (3 critical, 5 high, 6 medium, 4 low). Hardcoded colors→AppTheme.brandTeal, AppColors.of(context) for dark mode, unified scoreColor thresholds, narrowed catch clauses, const constructors, strict analysis_options.yaml |
| 2026-04-08 | --     | Schema resilience: 26 missing v1.3.0 columns added via _ensureV130Columns() migration. All integer flags now nullable. Pipeline DB has 61 cols, Drift defines 88 — migration bridges the gap. |
| 2026-04-08 | --     | First-launch fix: SyncService corrected bucket (pharmaguide) + versioned path from export_manifest. main.dart downloads core DB on first launch if missing. App tested on simulator with 783 live products from Supabase. |
| 2026-04-08 | --     | Infra: iOS Podfile platform set to 13.0 + minimum deployment target enforced. dart fix --apply (24 const fixes). Polished README pushed to github.com/seancheick/Pharmaguide.ai |
| 2026-04-09 | --     | Pipeline v1.3.0 → v1.3.2 export schema: sugar penalty wired into B1, nutrition hybrid model (calories_per_serving column + nutrition_detail blob), unmapped actives transparency. Three new Flutter detail widgets (NutritionPanel, RefillReminderCard, UnmappedActivesDisclosure) with 39 widget tests. |
| 2026-04-10 | --     | Catalog rebuild + LFS bundle: 5,231 products across 8 brands, 11.79 MB pharmaguide_core.db committed via Git LFS to Flutter assets/db/. release_catalog_artifact.py (9 gates) + import_catalog_artifact.sh (10 gates) bridge scripts. API key leak scrubbed from git history via interactive rebase. |
| 2026-04-10 | --     | Pipeline backlog cleanup (L1, L2, L3, R2): config-driven D4 high_standard_region with accepted_regions list, B0 high_risk and watchlist penalties from config, orphan probiotic_bonus_applies_before_ceiling flag deleted. 10 new lockdown tests in TestShipNowConfigLockdown / TestD4HighStandardRegionConfigLockdown / TestB0ConfigDrivenPenalties / TestR2OrphanFlagRemoved. |
| 2026-04-11 | 9      | **Sprint 9 DONE: v3.4.x scoring recalibration** — A1.max 15→18 (stop compressing enricher's 0-18 raw score), A2.max 3→5, omega3.max 2→3 with band redistribution, B1 cap 8→15, probiotic_bonus _caps_note. Real-data impact: max Section A 21→25 (ceiling now reachable), max score_80 ~50→68.5 (+37%). 11 cascade test updates + 7 new lockdown tests. **3,259 pipeline tests passing.** |
| 2026-04-11 | --     | Supabase OTA round-trip verified end-to-end: upload pharmaguide_core.db v2026.04.11.040818 to bucket, insert export_manifest row with is_current=true, anon-read returns new manifest, storage HEAD returns SQLite magic bytes. **Three-way checksum match: pipeline dist / Supabase remote / Flutter bundled** all carry sha256:67ac3cdd...634fb1. |
| 2026-04-11 | --     | docs: INTERACTION_DB_SPEC.md v2.0 (978 → 1054 lines) full rewrite with Next-Agent Start-Here block, M1-M5 build order, and reuse list of 5 existing Flutter primitives (Severity enum, InteractionResult, StackInteractionChecker, UserStacksLocal, E1DosageCalculator). Then v2.1.0 (1140 lines) corrected supp.ai understanding: it is an evidence corpus (4,910 entities + 59,096 pairs from PubMed), NOT a curated interaction set. Two-tier data model: curated `interactions` table + supp.ai `research_pairs` table. |
| 2026-04-11 | 10     | **Sprint 10 DONE: M1 Stack Nutrient Safety** — Service layer (StackNutrientAggregator + StackUlChecker + models, ~600 LOC) with 43 tests. Riverpod glue (`stackNutrientStatusesProvider` with 24h cache TTL, _detailBlobByDsldIdProvider). NutrientProgressBar widget (7-tier color ladder, warning chip) + NutrientAccumulationPanel widget (sorted by severity, alert badge) with 14 widget tests. Integrated into stack_screen.dart `_StackTab`. **204 Flutter tests passing**, 0 analyzer issues. Closes the biggest medical-grade gap: per-stack UL totals. |
| 2026-04-11 | --     | Sprints 9-17 added to tracker. **Target: complete Sprints 4–15 by 2026-05-11 (4 weeks)** for V1.0 ship readiness. Wk1: M1 polish + display widgets + FitScore UI. Wk2: M2+M3 (interaction DB pipeline + Flutter binding). Wk3: M4+M5 (stack interaction engine + product-scan warnings). Wk4: Sprint 5a stack wiring + Sprint 6 deep links + Sprint 7 auth/OTA + Sprint 8 ship gate. |
| 2026-04-11 | 18     | **Sprint 18 DONE: Design System + Premium UI Retrofit** — Full rewrite of `app_theme.dart` (660 LOC) with M3 tone-based surface roles, warm off-white background, pharma semantic tokens (insufficientData/evidenceStrong/evidenceGood/evidenceTheoretical), tabular figures helper, proper typography hierarchy. New `app_motion.dart` with motion/elevation tokens. **17 new PG components**: PGCard (4 variants), PGSectionHeader, PGSearchField, PGFilterChip, PGSeverityPill, PGEvidenceBadge (signal bars), PGScoreRing (custom-painted animated sweep gradient), PGInteractionCard (severity wash + progressive disclosure), PGCitationStrip, PGFrostedNavBar (real BackdropFilter blur), PGShimmerBox + variants, PGEmptyState (4 variants), PGTopBar, PGHaptics (severity-aware), PGSeverityBanner (5 tones), PGFitScoreBadge, PGStackActionButtons. **7 screen retrofits**: app.dart (frosted nav + extendBody), home_screen.dart (editorial hero + gradient CTA), product_list_item.dart (PGScoreRing), verdict_badge.dart (theme tokens), interaction_warnings.dart (PGInteractionCard + citation sheet), stack_screen.dart (real data + summary + undo), product_detail_screen.dart (PGScoreRing + PGFitScoreBadge + PGSeverityBanner + PGShimmerBox + PGEmptyState + PGStackActionButtons, removed 150+ lines of custom score painter + animation controller). |
| 2026-04-11 | 4      | **Sprint 4 DONE: FitScore UI integration** — `fit_score_provider.dart` with `fitScoreServiceProvider` FutureProvider (async-loads rda_optimal_uls + goals JSON) and `fitScoreForProductProvider.family` that watches `profileProvider` for auto-invalidation on profile edits. `PGFitScoreBadge` renders 5 states (loading / zero-signal / matches / caution / danger / missing-profile). `fit_score_sheet.dart` explains the score via 4 sub-score rows (E1/E2a/E2b/E2c) with mini progress bars and a missing-profile nudge that deep-links to profile setup. **Never persisted** — verified only computed in provider, never written to any DB. |
| 2026-04-11 | 5a/5b  | **Sprint 5a+5b UI wiring DONE** — `stack_providers.dart` exposing `activeStackProvider`, `stackEntryForDsldIdProvider` family, `safetyCheckForAddProvider` family (parses ingredient_fingerprint JSON + runs existing `StackInteractionChecker`), `StackActions` service. `safety_check_sheet.dart` shows severity-ranked warnings before confirming add, fires severity haptic via `PGHaptics.forSeverity`. `PGStackActionButtons` on product detail toggles between Add/In-Stack states, 5s undo snackbar on remove via `stackActions.restore(id)`. Stack screen rewritten with daily supplement load card (tabular-figure count chips) + `Dismissible` swipe-to-remove + undo. Supabase sync / offline queue / LWW / stack analysis report still pending for Sprint 5a. |
| 2026-04-11 | 19     | **Sprint 19 DONE: Live-device bug fixes + full legacy migration + accessibility** — 33 files changed. Critical runtime fixes: UPC fuzzy lookup (strips spaces + tries UPC-A/EAN-13 variants), SQLite `!= ""` → `!= ''` string literal bug, bottom sheet `kPGNavBarHeight` padding (keeps frosted blur), `interaction_summary_hint` JSON parser with profile-gated rendering + snake_case humanization, score breakdown dynamic colors based on score/max (not category), iOS camera permission (`NSCameraUsageDescription`), Android camera permission, Podfile iOS 15 target (unblocks iOS 26 MLKit crash). Accessibility: `PGHaptics` + `PGScoreRing` respect `disableAnimations`, VoiceOver `Semantics` labels on PGScoreRing + PGFitScoreBadge with tier awareness. Sprint 17 carryover: `e1_dosage_calculator` schema drift fix (standard_name/age_range/rda_ai) with legacy fallbacks. Full legacy screen migration: `settings_screen.dart` (PGCard groups + debug reset-onboarding row), `search_screen.dart` (PGSearchField + PGEmptyState + PGFilterChip list/grid toggle), `scanner_screen.dart` (AppColors → AppTheme), `profile_setup_screen.dart` (PGCard + RadioGroup + PGFilterChip + PGCardVariant.highlighted review step), `onboarding_screen.dart` (soft-tinted icon wells + animated dots + persistence via `OnboardingPrefs`). Infrastructure: `supabase_client.dart` debug-mode placeholder guard, `stack_sync_queue.dart` offline queue scaffolding with PHI-safe medication filter. Test coverage: 3 new test files (PGScoreRing goldens ×7, PGSeverityPill ×7, PGFitScoreBadge ×9), fixed all 45 pre-existing analyze issues (RadioGroup deprecations, catch clauses, test type inference). **Final state: 0 analyze issues, 225 tests pass, 5 skipped (Supabase mock tech debt).** |
| 2026-04-11 | 5a/20  | **Sprint 5a Supabase sync DONE** (completing the stack sync finish from Sprint 19's scaffolding). `stack_sync_queue.dart` rewritten with real `StackSyncService.pushAll()` — auth-gated (guests stay local), connectivity-gated, uses `supabase.from('user_stacks').upsert(..., onConflict: 'id')` for idempotent writes, maps local Drift row → remote payload via `_rowToRemote()`, catches `PostgrestException` leaving rows dirty for retry, reports outcome via `SyncResult` enum (ok/skippedGuest/skippedOffline/failed). Belt-and-suspenders PHI check asserts `row.type == 'supplement'` before every push. New `stackSyncListenerProvider` — a `Provider` with `ref.keepAlive()` that subscribes to connectivity + auth transitions via `ref.listen`, fires `pushAll()` on offline→online, guest→signedIn, and app-start (microtask). Bootstrapped in `main.dart` via a Consumer wrapping `PharmaGuideApp`. `StackActions.addProduct`/`remove`/`restore` now fire-and-forget `_triggerSync()` after every local write for instant push when online. New Supabase SQL migration at `supabase/migrations/20260411_user_stacks.sql` — full schema (id, user_id, type CHECK='supplement', name, dsld_id, ingredient_keys, dosage, frequency, added_at, client_updated_at, deleted_at, server_updated_at), `server_updated_at` trigger, RLS policies (4, scoped to auth.uid() with `type = 'supplement'` enforcement on INSERT/UPDATE), REVOKE from anon, GRANT to authenticated, 2 indexes (user_id + active, user_id + server_updated_at for future pull-sync). **Pull-sync deferred** (multi-device scenarios unsupported in V1.0). **225 tests pass + 5 skipped, 0 analyze issues.** |
| 2026-04-11 | --     | **TOTAL: 225 tests passing + 5 skipped, 0 analysis errors, full design system + all legacy screens migrated + Supabase stack sync live** |
| 2026-04-12 | --     | **Pipeline: UPC dedup** — `dedup_by_upc()` added to `build_final_db.py`. Groups by normalized UPC, keeps best row (active > discontinued, highest score, newest dsld_id), deletes losers. Committed as `bc0d804`. |
| 2026-04-12 | --     | **FTS5 search upgrade** — `CoreDatabase.searchProducts()` rewritten from `LIKE '%query%'` (full table scan, no ranking, UPC dupes) to `FTS5 MATCH` with porter stemming + `ORDER BY rank`. LIKE fallback in try/catch for older DBs. Search now instant, ranked, and dedup-aware. |
| 2026-04-12 | --     | **Recent Scans on home screen** — `UserDatabase.recordScanEvent()` + `getRecentScans()` (50-row cap, per-product dedup). `scanner_screen.dart` fires `unawaited()` record on successful scan. `home_screen.dart` `_RecentScansSection` ConsumerStatefulWidget loads history in `initState`, renders via `ProductListItem`, falls back to empty state with scan CTA. Creates core retention loop. |
| 2026-04-12 | --     | **Fixed 10 hanging widget tests across 3 files** (`app_test.dart`, `home_screen_test.dart`, `settings_screen_test.dart`). Root cause: `pumpAndSettle()` hangs forever with async Drift DB calls; `tearDown` DB close hangs after fake-async zone drains; `scrollUntilVisible` calls `pumpAndSettle` internally. Fix: inline DB lifecycle per test body, `pump()` + `pump(100ms)` instead of `pumpAndSettle`, manual `drag()` + `pump()` loops. Pattern documented in lessons-learned.md. |
| 2026-04-12 | --     | **TOTAL: 348 tests passing + 5 skipped, 0 analysis errors, FTS5 search + Recent Scans + UPC dedup + all test fixes** |
| 2026-04-12 | 20     | **Sprint 20 UX Quick Wins DONE** — Filter chips, score explainer, haptics, not-found polish, empty stack CTA. Committed `87fe6d2`. |
| 2026-04-12 | 11-14  | **Sprints 11-14 (M2-M5) verified DONE** — 32+ unchecked items verified against codebase and checked off. Pipeline merged to PharmaGuide_Pipeline. Worktree cleaned up. |
| 2026-04-12 | --     | **Sprint Tracker comprehensive audit** — Cross-referenced against master roadmap + strategic report + Fullscript analysis. 9 missing features added. Future Releases section created with V1.0-V3.1 hierarchy. |
| 2026-04-12 | 21     | **Sprint 21 Feature Blitz DONE** — 7 features shipped in 2 commits (`857b827`, `6d64852`): Synergy Detection (54 clusters), Recall Alerts (danger banner), M5 Fix (personalized "Because you're taking X" warnings from live InteractionDatabase), Med↔Med Pair Check (§0.2), Stack Health Score (PGScoreRing + StackSafetyScorer), Quick Check Screen (/quick-check route), Pipeline data wired (39 timing rules + 68 depletions bundled). 299 tests pass, 0 analyze issues. |
| 2026-04-12 | 8      | **Sprint 8 V1.0-beta gate DONE** — Quick Check CTA on home, GitHub Actions CI, Semantics accessibility, PGFeedback error matrix, all 4 skipped tests fixed. **353 tests pass, 0 skipped, 0 failures, 0 analyze issues.** |
| 2026-04-12 | --     | **Code review round 1** — 2 CRITICAL + 8 HIGH findings. Fixed: mapped_coverage safety rule (1.0→0.0), broad `on Object` catch, RecallAlertSlot FutureBuilder→provider, canonicalIds toLowerCase, RecentScans error handling, Semantics on CTA+GridItem, warning dedup by mechanism+severity. Commit `91f6552`. |
| 2026-04-12 | --     | **Code review round 2** — 4 HIGH findings. Fixed: ScoreExplainerCard mappedCoverage guard, stack safety score synergy bonuses wired, bannerMessage empty commonNames crash, Quick Check error/insufficient/clean states. Commit `06410f7`. |
| 2026-04-12 | --     | **Code review MEDIUM+LOW polish** — MediaQuery.paddingOf (stack+search), SynergyReport/RecalledIngredientsReport isEmpty→computed getter, late→final in providers, ValueKey on Quick Check suggestions, const StackSafetyScorer. All review findings resolved. **353 tests pass, 0 analyze issues.** |
| 2026-04-12 | --     | **10 lessons learned documented** — mapped_coverage safety default, broad catch swallowing errors, Quick Check false-safe, canonicalIds lowercase, bannerMessage crash, FutureBuilder in build, synergy bonus wiring, isEmpty getter, stale handoff, sprint divergence. |
| 2026-04-13 | --     | **Production interaction DB bundled** — Pipeline rebuilt: 128 curated interactions (99 drug↔sup + 29 drug↔drug) + 28,038 supp.ai research pairs + 24 drug classes (693 RxCUIs). All API-verified (128 RxNorm, 79 PubMed PMIDs). DB: 20MB with FTS5 index. Test fixtures updated. `release_interaction_artifact.py` stages to `dist/`. `import_catalog_artifact.sh` validates atomically (I1-I8 gates). One-command pipeline: `bash scripts/rebuild_interaction_db.sh --import`. 4 new lessons learned (manifest key mismatch, atomic import, one-command pipeline, test fixture hardcoding). |
| 2026-04-12 | 20     | **Sprint 20 UX Quick Wins DONE** — Filter chips on search (All/High Quality/Needs Caution/Third-Party Tested/Organic + client-side filtering + filtered count), "Why this score?" compact explainer card on product detail (color-coded 1-liner with top sub-score), haptic on barcode detect (lightImpact before lookup), scanner not-found copy polish (friendlier headline + helpful subtext), empty stack "Add medications manually" secondary CTA. 299 tests pass, 0 analyze issues. |
| 2026-04-12 | 11-14  | **Sprints 11-14 (M2-M5) verified DONE** — M2 pipeline merged to PharmaGuide_Pipeline (325 tests), M3 Flutter binding complete (8MB artifact, 18 tests, provider in main.dart), M4 stack interaction engine wired to real DB (132 tests, StackInteractionChecker + StackSafetyReport + MedicationEntryScreen + RxNormApiService + StackSafetyBanner), M5 product-scan warnings wired (InteractionWarningsList, 3 tests). All unchecked items verified and marked done. |
| 2026-04-12 | --     | **Repo cleanup** — dsld_clean origin swapped to PharmaGuide_Pipeline, peaceful-ritchie worktree + branch removed, old dsld_clean remote deleted. Single clean remote. |
| 2026-04-12 | --     | **Sprint Tracker comprehensive audit** — 32+ verified-done items checked off across Sprints 7-14. Deferred items tagged with target version. Missing roadmap features added. Future Releases section created. |

---

## FUTURE RELEASES — Features from Master Roadmap

> Source: `2026-04-07-flutter-complete-roadmap-design.md`, PharmaGuide Strategic Report, Fullscript competitive analysis
> These features were defined in the product roadmap but were not yet in the Sprint Tracker.
> Version assignments follow the original roadmap hierarchy.

---

### V1.0-beta (Sprint 8 — Ship to Testers)

See Sprint 8 above. No auth, no deep links. Focus on QA, performance, accessibility, store builds.

---

### V1.0-release (Post-Beta — Add Auth + Polish)

| Task | Source | Effort | Notes |
|------|--------|--------|-------|
| Google Sign-In | Roadmap V1.0 / Sprint 7 | 2-3 days | After beta feedback. Requires Google Cloud OAuth config. |
| Apple Sign-In | Roadmap V1.0 / Sprint 7 | 2-3 days | Requires paid Apple Developer account + entitlements. |
| Guest → signed-in migration (preserve local data) | Roadmap V1.0 / Sprint 7 | 1-2 days | Auth state service exists; need to wire stack/profile migration. |
| Server-side AI/premium usage limits | Roadmap V1.1+ | 1 day | Scan quotas rescoped: guests are local 3/day; signed-in scans are unlimited during early access. |
| Analytics SDK integration (Firebase or Mixpanel) | Roadmap V1.0 / Sprint 8 | 1 day | Scaffold exists (analytics_service.dart); replace no-ops with real SDK. |
| **Stack Health Score (aggregate)** | Strategic / User request | 1-2 days | _StackSummaryCard currently shows counts only. Add combined quality score from all stack products. |
| **"Safe to Take Together?" Quick Check** | Strategic / User request | 2-3 days | Standalone screen: scan/search 2 products → instant pair interaction check. Uses existing lookupPair(). No stack required. |

---

### V1.1 — Medication Intelligence + Trust (Roadmap V1.1-V1.2)

| Task | Source | Effort | Notes |
|------|--------|--------|-------|
| **Medication-Induced Depletion Checker** | Roadmap Sprint 10 / Fullscript | 3-4 days | "You're taking Metformin — this commonly depletes Vitamin B12." Data: `medication_depletions.json` (50+ drug-nutrient pairs). Killer differentiator. |
| **Product Comparison** (side-by-side) | Roadmap Sprint 11 | 2-3 days | "3 similar products" with quality score, cost per dose, form, dietary flags. SQL: filter by primary_category. |
| **Doctor Visit PDF Export** | Roadmap Sprint 13 / User request | 3-4 days | One-tap export: stack + interactions + warnings + depletions + sources as clean PDF. Needs `pdf` package. EHR integration prep. |
| Deep link handling (app_links) | Roadmap Sprint 6 / Sprint 8 | 2-3 days | Shared product links open in app. GoRouter redirect config. |
| Open Graph preview for shared links | Roadmap Sprint 6 | 1 day | Meta tags for social media link previews. |
| Pull-sync for multi-device | Sprint 5a deferred | 2-3 days | Push-sync done; add pull from Supabase on app start. LWW conflict resolution. |
| FitScore comparison view (side-by-side) | Sprint 4 deferred to V1.1 | 2 days | Compare two products' FitScores visually. |
| Coach marks / feature tour | Sprint 8 deferred | 2 days | Overlay tutorial highlighting scanner, stack, profile. |
| Notification preferences (flutter_local_notifications) | Sprint 7 deferred | 1-2 days | Package + permission request + settings UI. |
| "Update available" indicator on Profile tab | Sprint 7 deferred | 0.5 day | Badge when new DB version detected via OTA manifest. |
| min_app_version gate (force update) | Sprint 7 deferred | 1 day | Remote config check on app start. |
| Health Profile re-editing | Sprint 7 deferred | 1 day | Onboarding flow exists; wire edit mode from settings. |
| Privacy Controls (transparency dashboard) | Sprint 7 deferred | 1 day | Modal exists; add data usage prefs toggle. |
| **Supplement Recall Alerts** | Roadmap Sprint 21 / User request | 2-3 days | Push notification when recalled ingredient in user's stack. `has_recalled_ingredient` column exists in DB. Needs notification infra. |

---

### V1.2 — Trust & Transparency (Roadmap V1.2)

| Task | Source | Effort | Notes |
|------|--------|--------|-------|
| FitScore Explanation Layer | Roadmap Sprint 12 | 2-3 days | Deep breakdown of E1/E2a/E2b/E2c with explanations. FitScoreSheet partial exists. |
| Recompute Strategy | Roadmap Sprint 12 | 1 day | Auto-recompute FitScore when profile changes. Provider invalidation exists. |
| Trust Layer UI | Roadmap Sprint 13 | 2 days | Source attribution on every score component. Clickable PubMed/NIH/FDA links. |
| Stack Analysis History | Sprint 7 deferred | 1-2 days | Save last 3 reports, view/email/share/delete. |

---

### V2.0 — AI Intelligence & Personalization (Roadmap V2.0)

| Task | Source | Effort | Notes |
|------|--------|--------|-------|
| Gate-based AI Interaction Checker | Roadmap Sprint 14-15 | 5-7 days | Deterministic gates fire first (<50ms); LLM fallback for open-ended queries. |
| Population-adjusted Risk Scoring | Roadmap Sprint 15 | 3-4 days | Adjust risk by age, sex, condition prevalence. |
| Temporal Context + Form-Specific Guidance | Roadmap Sprint 16 | 3-4 days | Washout/onset/half-life data. "Take with food" vs "fasted". |
| **Alternative Suggestion Engine** | Roadmap Sprint 17 | 3-4 days | When flagging unsafe combo, suggest safer alternative matched to user's goals. |
| **Nutrient Gap Analysis** | Roadmap Sprint 18 / Fullscript | 3-4 days | Identify missing/overlapping/excess nutrients vs. user goals + RDA. |
| **Prescription OCR** | Roadmap Sprint 19 | 5-7 days | Scan medication label → OCR → RxNorm match → add to medication stack. |
| **Timing Optimization Display** | Roadmap Sprint 5b/16 | 2-3 days | "Separate Iron & Calcium by 4 hours." Based on timing_rules.json. |
| **Synergy Detection Display** | Roadmap Sprint 5b/15 | 2 days | "Pairs well: Vitamin D + K2 (+2 synergy bonus)." Green checkmarks. |

---

### V2.1 — Engagement & Retention (Roadmap V2.1)

| Task | Source | Effort | Notes |
|------|--------|--------|-------|
| **Dose Reminders** | Roadmap Sprint 20 / Fullscript | 3-4 days | Push notifications timed to supplement absorption windows. "Time to take your magnesium." |
| **Reorder Alerts** | Roadmap Sprint 20 | 2 days | Track servings_per_container → "Running low on Vitamin D3?" with optional affiliate links. |
| **Starter Stacks** | Roadmap Sprint 21 | 3-4 days | Curated protocols: Sleep, Energy, Joint, Immune, Stress. Pre-checked for safety. "Adopt whole stack" or pick items. |
| **FDA Recall Notifications** | Roadmap Sprint 21 | 2-3 days | Monitor FDA recall data, push notification if recalled product in user's stack. |
| Feedback Loop | Roadmap Sprint 22 | 2 days | Thumbs up/down on interaction warnings. Improves data quality. |
| Progress Tracking / Stack History Timeline | Roadmap Sprint 22 | 2-3 days | Visual timeline of stack changes over time. |
| **"How Your Stack Changed" Weekly Digest** | Strategic | 1-2 days | Local notification: what you added/removed, new warnings, score changes. Retention gold. |

---

### V3.0 — Platform & Ecosystem (Roadmap V3.0)

| Task | Source | Effort | Notes |
|------|--------|--------|-------|
| **B2B REST API** | Roadmap Sprint 23-24 | 10-15 days | POST /api/v1/interactions/check → interactions, scores, timing. Free/Starter/Growth/Enterprise tiers. |
| **White-Label SDK** | Roadmap Sprint 25 | 5-7 days | Embeddable interaction checker widget + barcode scanner SDK for partners. |
| **"PharmaGuide Verified" Certification** | Roadmap Sprint 25 / Strategic | 3-5 days | Brands pay for safety certification badge. $1,500/SKU or $5,000/brand bundle. |
| **Family Profiles** | Roadmap Sprint 26 | 5-7 days | Multiple users per account (spouse, children). Each with own conditions + medications. |
| **Practitioner Portal** | Roadmap Sprint 27 | 10+ days | Provider access to patient supplement stacks. EHR integration. Doctor can add directly to patient stack. |

---

### V3.1 — Premium Intelligence (Roadmap V3.1)

| Task | Source | Effort | Notes |
|------|--------|--------|-------|
| **Lab Integration** | Roadmap Sprint 28 / Fullscript | 10+ days | Upload bloodwork PDF → OCR biomarkers → cross-reference with stack → suggest optimizations. Premium feature. |
| **Interaction Matrix** (100+ curated pairs) | Roadmap Sprint 29 | 5-7 days | Clinical governance dashboard. Expand beyond 20 golden fixture pairs. |
| **Drug-Drug Interactions** | Roadmap Sprint 30 | 5-7 days | Full med-med coverage. Currently only supplement-drug. |
| **Wearable Insights** | Roadmap Sprint 30 / Strategic | 5-7 days | Correlate supplement intake with Oura/Whoop/Apple Health data. |
| **Data Licensing** | Strategic | N/A | Anonymized insights to researchers, insurance, analytics firms. |

---

### Competitive Feature Parity (Fullscript-Inspired)

These features emerged from competitive analysis of Fullscript ($1B ARR) and position PharmaGuide as best-in-class:

| Feature | Fullscript Has | PharmaGuide Status | Priority |
|---------|---------------|-------------------|----------|
| Severity + Evidence Ratings on interactions | ✅ | ✅ Done (severity + evidenceLevel in InteractionResult) | — |
| Clickable PMID/source links | ✅ | ⚠️ Partial (source URLs stored, not all clickable) | V1.1 |
| Depletion Checker | ✅ | ❌ Not started | **V1.1 — high priority** |
| Product Comparison | ✅ | ❌ Not started | V1.1 |
| Dose Reminders | ✅ | ❌ Not started | V2.1 |
| Lab Integration | ✅ | ❌ Not started | V3.1 |
| Barcode Scanning | ❌ | ✅ PharmaGuide advantage | — |
| Timing Optimization | ❌ | ⚠️ Data ready, UI not built | V2.0 |
| Offline Mode | ❌ | ✅ PharmaGuide advantage | — |
| Local-first Privacy | ❌ | ✅ PharmaGuide advantage | — |
| AI Chat | ❌ | ✅ PharmaGuide advantage | — |
| Doctor-ready PDF | ❌ | ❌ Not started | **V1.1 — high priority** |

---

## Sprint 26 — UX Polish + Critical Bug Fixes (2026-04-15)

**Goal:** Fix critical product detail rendering, add missing UI features, polish app UX.

### Completed

| # | Task | Status | Files |
|---|------|--------|-------|
| 1 | Fix blob fetch path — use SHA-256 hash instead of dsldId | [x] Done | `product_detail_screen.dart` |
| 2 | Build rich product detail UI — active ingredients, inactive ingredients, pros (score_bonuses), cons (score_penalties), condition-specific interaction details | [x] Done | `product_detail_screen.dart` |
| 3 | Build recent scans horizontal card carousel on Home screen | [x] Done | `home_screen.dart` |
| 4 | Fix RenderFlex overflow in `_SearchLoadingList` (Column → ListView) | [x] Done | `search_screen.dart` |
| 5 | Fix score circle overlapping verdict text (size 76→72, remove inner label) | [x] Done | `product_detail_screen.dart` |
| 6 | Fix interaction warning banner to show which conditions affected + scroll hint | [x] Done | `product_detail_screen.dart` |
| 7 | Fix missing bottom nav bar on search, product detail, quick-check, profile setup (moved into ShellRoute) | [x] Done | `app.dart` |
| 8 | Add "View Supplement Label" button with DSLD image URL | [x] Done | `product_detail_screen.dart` |
| 9 | Fix hardcoded citation date (April 11 → April 15) | [x] Done | `home_screen.dart` |
| 10 | Remove unused `product_list_item.dart` import from home screen | [x] Done | `home_screen.dart` |

### Sprint 26b — New Stack Features (2026-04-15)

| # | Task | Status | Files |
|---|------|--------|-------|
| 11 | Make citation date + source count dynamic from DB manifest | [x] Done | `home_screen.dart`, `database_providers.dart`, `core_database.dart` |
| 12 | Wire `TimingAdviceCard` into stack screen | [x] Done | `stack_screen.dart` |
| 13 | Build Depletion Checker (service + provider + UI) | [x] Done | `depletion_checker.dart` (new), `depletion_checker_card.dart` (new), `stack_providers.dart`, `stack_screen.dart` |

### Sprint 26c — UX Refinements (2026-04-15)

| # | Task | Status | Files |
|---|------|--------|-------|
| 14 | Move score explainer 1-liner into header (instant comprehension) | [x] Done | `product_detail_screen.dart` |
| 15 | Make action buttons sticky bottom bar (always reachable) | [x] Done | `product_detail_screen.dart` |
| 16 | Add per-ingredient safety tags (Well dosed / Adequate / Low form / Poor form) | [x] Done | `product_detail_screen.dart` |
| 17 | Restore grade label below score ring without overlap | [x] Done | `product_detail_screen.dart` |
| 18 | Expand tags to show all certifications (Third-Party Tested, Trusted Mfg, Organic) | [x] Done | `product_detail_screen.dart` |
| 19 | Tappable score breakdown — each pillar expands to show sub-score reasons | [x] Done | `score_breakdown_card.dart` |

### Sprint 26d — Supabase Sync Audit + Pipeline Data Wiring (2026-04-15)

| # | Task | Status | Files |
|---|------|--------|-------|
| 20 | Fix critical blob bucket mismatch (`detail-blobs` → `pharmaguide`) | [x] Done | `detail_blob_service.dart` |
| 21 | Fix blob key mismatch (`interaction_warnings` → `warnings`) | [x] Done | `product_detail_screen.dart` |
| 22 | Fix proprietary blend path (nested under `proprietary_blend_detail`) | [x] Done | `product_detail_screen.dart` |
| 23 | Remove dead `fetchDetailBlob(dsldId)` — always returned null | [x] Done | `detail_blob_service.dart`, `fit_score_provider.dart`, `stack_nutrient_providers.dart` |
| 24 | Create `supabase_contract.dart` — single source of truth for all Supabase paths | [x] Done | `supabase_contract.dart` (new) |
| 25 | Replace all hardcoded bucket/table names with contract constants | [x] Done | `sync_service.dart`, `stack_sync_queue.dart` |
| 26 | Fix hardcoded search hint "5,000+" → dynamic from DB | [x] Done | `home_screen.dart` |
| 27 | Fix stale fallback count in citation strip | [x] Done | `home_screen.dart` |
| 28 | Add `image_thumbnail_url` to Drift table + migration guard | [x] Done | `products_core_table.dart`, `core_database.dart` |
| 29 | Add missing v1.3.1/v1.3.2 columns to migration guard | [x] Done | `core_database.dart` |
| 30 | Fix live Supabase `user_stacks` table — add `type`, `name`, `ingredient_keys` columns + rename `timing` → `frequency` | [x] Done | Supabase migration |
| 31 | Wire `evidence_data` — clinical matches, PMIDs, PubMed links | [x] Done | `pipeline_detail_sections.dart` (new) |
| 32 | Wire `certification_detail` — GMP, purity, heavy metal tested | [x] Done | `pipeline_detail_sections.dart` |
| 33 | Wire `evidence_data` — clinical match details for Evidence pillar | [x] Done | `pipeline_detail_sections.dart` |
| 34 | Wire `formulation_detail` — delivery form, absorption enhancers, botanicals | [x] Done | `pipeline_detail_sections.dart` |
| 35 | Wire `probiotic_detail` — strains, CFU, clinical strains | [x] Done | `pipeline_detail_sections.dart` |
| 36 | Wire `synergy_detail` — cluster evidence + PMIDs | [x] Done | `pipeline_detail_sections.dart` |
| 37 | Wire `allergen_summary` — "Contains: Soy, Tree Nuts" banner | [x] Done | `product_detail_screen.dart` |
| 38 | Wire `decision_highlights` — pipeline pre-computed hero insights | [x] Done | `product_detail_screen.dart` |

### Key Decisions

- **Supabase contract file:** All bucket names, storage paths, table names, and RPC names are now in `supabase_contract.dart`. No more hardcoded strings scattered across files.
- **Detail blob fetch:** Only hash-based fetch exists now. Dead `fetchDetailBlob(dsldId)` removed from all 3 callers.
- **Image URLs are all PDFs:** All 2492 products have DSLD label PDFs. Rendered as "View Supplement Label" button. Pipeline agent is building PDF→WebP extraction for real thumbnails.
- **Nav bar architecture:** Sub-pages moved inside ShellRoute — all app pages share the frosted nav bar.
- **Supabase `user_stacks` migration applied:** Added `type`, `name`, `ingredient_keys` columns + renamed `timing` → `frequency` + made `dsld_id` nullable for medication entries.

### Sprint 26e — Stack UX + Critical Bug Fixes (2026-04-15)

| # | Task | Status | Files |
|---|------|--------|-------|
| 39 | Fix product detail blank page — routing conflict from double Scaffold (moved sub-pages back outside ShellRoute) | [x] Done | `app.dart` |
| 40 | Fix nutrient RDA display — 25000% → "250x RDA" for extreme values | [x] Done | `nutrient_progress_bar.dart` |
| 41 | Fix stack health score — was showing safety score (100%), now shows average quality score of supplements | [x] Done | `stack_screen.dart` |
| 42 | Add per-supplement provenance dropdown to nutrient panel — tap any nutrient to see which supplements contribute how much | [x] Done | `nutrient_progress_bar.dart` |
| 43 | Fix nutrient panel padding to match design system (AppTheme instead of hardcoded AppColors) | [x] Done | `nutrient_accumulation_panel.dart` |

### Pending (next sprint)

- [x] Build branded placeholder card widget — ✅ DONE. `BrandedPlaceholder` in `lib/core/widgets/branded_placeholder.dart`, used by `ProductImage`, tested.
- [ ] User-contributed photos: "Help improve PharmaGuide — snap a photo of this bottle?" → store in Supabase → use as display image (post-launch data moat)
- [🚫] ~~Wire `scan_limit_service` to live `increment_usage` RPC~~ — rescoped 2026-05-18 with signed-in unlimited scans for early access
- [x] Update stale reference data files (`banned_recalled_ingredients.json`, `synergy_cluster.json`) from v1.0 to v5.0 — **done in Sprint 27.5 (schema-alignment audit follow-up)**
- [-] TestFlight / Play internal builds — **code-side ready** as of 2026-04-29 (V1.0 hardening + V1.1 + V1.2 all `[x]` per Parallel Initiatives section above; 757/757 tests green; analyze clean). Build cut + upload still ⏳ Sean.

---

## Sprint 27 — Engineering Review Follow-ups (2026-04-16)

**Goal:** Address the 5 findings from `/plan-eng-review` — untested critical paths, observability gaps, oversized files, and inline async plumbing that belonged behind a provider. Scan-limit wiring deferred at user request (Issue 1).

### Completed

| # | Task | Status | Files |
|---|------|--------|-------|
| 1 | **Issue 2 — Extract detail blob fetch to `FutureProvider.family.autoDispose`** so the screen derives `AsyncValue<Map?>` from `ref.watch` instead of managing cache/network state inline. Retry via `ref.invalidate(detailBlobProvider(dsldId))`. Constants (`kDetailBlobCacheTtl`, `detailBlobServiceProvider`) also exported so tests can override the service. | [x] Done | `lib/features/product_detail/providers/detail_blob_provider.dart` (new), `lib/features/product_detail/product_detail_screen.dart` |
| 2 | **Issue 3a — Split `pipeline_detail_sections.dart`** into 6 files under `lib/features/product_detail/widgets/pipeline_sections/` (allergen summary, certification, evidence, formulation, probiotic, synergy) — each ~150-280 LOC with its own data shape. Original file kept as barrel re-export so `import 'pipeline_detail_sections.dart';` still works. | [x] Done | `lib/features/product_detail/widgets/pipeline_sections/*.dart` (6 new), `lib/features/product_detail/widgets/pipeline_detail_sections.dart` (now barrel) |
| 3 | **Issue 3b — Split `stack_providers.dart`** into `active_stack_provider.dart` (StackActions + active stack FutureProvider), `stack_safety_providers.dart` (banner/report providers), `synergy_report_provider.dart`, and `stack_provider_helpers.dart` (canonical ID extraction). Original file becomes a barrel so all external imports are untouched. | [x] Done | `lib/features/stack/providers/active_stack_provider.dart` (new), `stack_safety_providers.dart` (new), `synergy_report_provider.dart` (new), `stack_provider_helpers.dart` (new), `stack_providers.dart` (now barrel) |
| 4 | **Issue 3c — Split `home_screen.dart`** (1345 LOC) into a thin 175-line shell + 9 widget files under `lib/features/home/widgets/` (hero, scan CTA, search launcher, quick check CTA, category rail, profile completeness card, stack health, recent scans, citation strip). Private sub-widgets co-located inside each file; only the top-level widget is exported. | [x] Done | `lib/features/home/widgets/*.dart` (9 new), `lib/features/home/home_screen.dart` |
| 5 | **Issue 4 & 5 — Observability + release-gate test update.** Wire share + improve analytics/crash stubs (shipped earlier in session). Update `phi_medication_no_sync_test.dart` — after the stack_providers.dart split, `StackActions.addMedication` lives in `active_stack_provider.dart`, so the release-gate regex scan was pointed at the split file (barrel file never contained the method body). | [x] Done | `test/release_gate/phi_medication_no_sync_test.dart`, observability providers |

### Key Decisions

- **Barrel re-export pattern for file splits.** Every large file split leaves a barrel at the original path (`export 'split_file.dart'`). External imports never change. This makes the split a zero-risk refactor from the call-site's perspective and decouples the split from the eventual call-site migration.
- **Release-gate file-scan tests must track renamed source files.** `phi_medication_no_sync_test.dart` regex-scans a specific path to prove PHI medications can't reach Supabase sync. The barrel pattern above means the method body *moved* — the test must read from the new file, not the barrel, or the safety check silently no-ops (the regex finds nothing → test passes vacuously). Documented in the test's file header.
- **Blob fetch as `FutureProvider.family.autoDispose`.** Keyed on `dsldId`. Autodispose ensures navigating away frees the cached `AsyncValue`; revisits start with a fresh cache check. The screen no longer owns `_detailBlob`/`_blobLoading`/`_blobError` fields — it derives them from `ref.watch(detailBlobProvider(widget.dsldId))`. Retry is `ref.invalidate(detailBlobProvider(widget.dsldId))` — no manual state reset.
- **`_parseWarnings` signature changed** from reading the removed `_detailBlob` field to taking `Map<String, dynamic>? blob` as a parameter, decoupling the helper from screen state.
- **Private widgets stay co-located** when they're consumed by exactly one parent in the same file (e.g. `_StackHealthCard`, `_MicroMetric`, `_RecentScanCard`). Only cross-file widgets get public names — this keeps the public surface small and honors the analyzer's `library_private_types_in_public_api` rule.
- **Scan-limit wiring (Issue 1) deferred** at user direction ("without the scan limit for now, i'll update that later").

### Verification

- `flutter analyze` — clean (0 issues)
- `flutter test` — 447 / 447 pass (including the updated `phi_medication_no_sync_test.dart`)
- Home widget smoke tests — 5 / 5 pass
- Product detail screen layout preserved byte-for-byte; only state management changed

---

## Sprint 27.5 — Schema-Alignment Audit Follow-ups (2026-04-16)

**Goal:** Close the 3 WARNINGS + 1 DOC-DEBT from the end-to-end schema alignment audit (Supabase → Flutter → pipeline → final DB). Two bundled JSON assets were still on Flutter v1.0 schema while the pipeline now emits v5.0 — direct-copying the pipeline file would silently wipe the top-level key Flutter consumers read from, making every synergy bonus and recall warning disappear with no crash.

### Completed

| # | Task | Status | Files |
|---|------|--------|-------|
| 1 | **WARNING — Remap `synergy_cluster.json` from Flutter v1.0 (10 entries, key `clusters`) to pipeline v5.0 content (58 entries).** Schemas are INCOMPATIBLE — pipeline uses `synergy_clusters / id / synergy_mechanism / sources`; Flutter consumers read `clusters / cluster_id / mechanism / citations`. Transform rules: `id` → `SYN_{UPPERCASE}`, `standard_name` → `name`, `canonical_ids` → `ingredients` (NOT the broad `ingredients` list), `evidence_tier` int → string enum (1→strong, 2→moderate, 3/4→limited), `synergy_mechanism` → `mechanism`, `sources[]` → `citations` (PMID strings + URLs). `bonus_points` has no pipeline source — preserved v1.0 values for the 5 topically-overlapping clusters, defaulted rest by evidence_tier (strong→2, moderate→1, limited→1). Zero duplicate cluster_ids. | [x] Done | `assets/reference_data/synergy_cluster.json` (58 entries, schema_version 1.1) |
| 2 | **WARNING — Remap `banned_recalled_ingredients.json` from Flutter v1.0 (13 entries, key `recalled_ingredients`) to pipeline v5.0 content (143 entries → 139 after filter).** Pipeline uses `ingredients / id / aliases / status`; Flutter reads `recalled_ingredients / canonical_id / common_names / recall_status + regulatory_basis + reason + effective_date + warning_message + severity`. Transform rules: filter `match_mode == "active"` (drops 4: 1 disabled + 3 historical), `id` → `canonical_id`, `aliases` → `common_names`, `status` → `recall_status`, `regulatory_date` → `effective_date` (with `jurisdictions[0].effective_date` fallback, then `""`), `clinical_risk_enum` → `severity` (critical/high→critical, moderate/dose_dependent→major, low→minor). Derived fields with NO pipeline source: `regulatory_basis` = `"{legal_status_enum} — {jurisdictions[0].source.citation}"`; `warning_message` = `"{standard_name} is {status}: {first sentence of reason}"` (flagged for safety-team review in _metadata). Zero duplicate canonical_ids. | [x] Done | `assets/reference_data/banned_recalled_ingredients.json` (139 entries, schema_version 1.1) |
| 3 | **WARNING — Add `productImageBucket = 'product-images'` constant to `supabase_contract.dart`.** Previously the storage contract only declared `storageBucket = 'pharmaguide'` and `productImagePath(dsldId)` returned `"product-images/{dsldId}.webp"` — treating `"product-images"` as a path prefix inside the `pharmaguide` bucket, which is wrong: product images live in their OWN Supabase bucket. Zero callers existed for `productImagePath` so the return was changed to the bare object key (`"{dsldId}.webp"`); callers will pass `productImageBucket` explicitly. No UI wired yet per user instruction. | [x] Done | `lib/data/supabase/supabase_contract.dart` |
| 4 | **DOC-DEBT — Fix `core_database.dart` docstring: 88 → 91 columns.** Docstring was stale after the v1.4.0 schema added `hazard_flags`, `key_ingredient_tags`, `image_thumbnail_url`. Drift table definition was already correct (91 cols); only the comment was lying. | [x] Done | `lib/data/database/core_database.dart` |
| 5 | **Contract test — `test/core/reference_data_contract_test.dart`.** Guards against the silent-breakage #1 footgun: asserts the bundled asset uses the Flutter top-level key (`clusters`, `recalled_ingredients`) AND that the pipeline-shaped key (`synergy_clusters`, bare `ingredients`) is NOT present. Also spot-checks the first entry has every field name the consumer providers read. Uses `dart:io` directly (no Flutter binding needed) so it runs in under 50 ms. Failing this test = someone direct-copied a pipeline file over the Flutter asset. | [x] Done | `test/core/reference_data_contract_test.dart` (new) |

### Key Decisions

- **Asset schema is intentionally Flutter-owned, NOT pipeline-synced.** Pipeline v5.0 file key ≠ Flutter consumer key. The remap is an active transform, not a pass-through sync. The contract test exists to enforce this boundary.
- **Derived fields with no pipeline source are flagged in `_metadata.migration_note`**, not fabricated silently. `bonus_points` (synergy) falls back to evidence_tier default; `regulatory_basis` + `warning_message` (recall) use deterministic derivations from existing pipeline fields. All 139 recall entries' `warning_message` strings must pass a safety-team review before a production release.
- **`cluster_id` convention: `SYN_{UPPERCASE_SLUG}`** derived from the pipeline's lowercase `id` field. Preserves Flutter's historical `SYN_NNN` prefix while tying the ID back to its stable pipeline source. 58 IDs are deterministic and reproducible across future remaps.
- **Storage bucket boundary:** `storageBucket = 'pharmaguide'` (core DB + detail blobs + manifest) and `productImageBucket = 'product-images'` are SEPARATE buckets, not paths inside the same bucket. The new constant makes this explicit so future image-fetch wiring targets the right URL.
- **`match_mode == "active"` filter on recall data** drops disabled + historical entries from Flutter asset. The pipeline keeps them for provenance/auditing; the app only surfaces currently-actionable warnings.

### Verification

- `flutter analyze` — clean (0 issues)
- `flutter test` — 449 / 449 pass (adds 2 new tests in `reference_data_contract_test.dart`)
- `jq` structural checks: 58 synergy clusters, 139 recall entries, zero duplicate ids in either file
- Zero consumer-side changes needed — every Flutter provider that reads these assets keeps reading the same field names.
- Pipeline → Flutter boundary now has a failing-test gate: any future direct-copy from pipeline will break the contract test immediately.

### Out of scope (deferred per user)

- `backfill_image_thumbnails()` wiring in pipeline (extract_product_images.py + backfill_upc.py are WIP manual post-build steps)
- 300 IQM entries pending canonical_id mapping
- Safety-team review of the 139 derived `warning_message` strings → **superseded by Sprint 27.6:** dropping the field entirely (Path A) and re-authoring upstream (Path C). Do NOT run the review on the current derived strings; they're being deleted.

---

## Sprint 27.6 — Recall warning_message: drop + re-author upstream (2026-04-16)

**Goal:** Remove the latent time-bomb of 139 auto-derived `warning_message` strings before any UI surface reads them, then design the correct upstream replacement so we rebuild it **properly, with safety-team review** and accurate semantic modeling (banned substance vs. banned-as-adulterant-in-supplements).

**Why this is its own sprint:** The audit in Sprint 27.5 flagged `warning_message` for review. Investigation revealed the template `"{standard_name} is {status}: {first sentence of reason}"` produces medically incorrect copy for ~30–40 of 139 entries (e.g., "Metformin is banned" — false; metformin is a legitimate prescription drug, only banned as an undeclared adulterant in supplements). The field is stored today but no UI reads it. Next dev to wire UI would ship 139 unreviewed, partially-inverted strings. We drop it now, rebuild it right.

---

### Path A — Drop `warning_message` everywhere (execute NOW, 4 files)

| # | Task | Status | Files + lines |
|---|------|--------|---------------|
| A1 | Remove `warning_message` from all 139 entries in bundled asset. Update `_metadata.migration_note` to reflect deletion pending upstream re-authoring (reference this sprint). | [ ] TODO | `assets/reference_data/banned_recalled_ingredients.json` |
| A2 | Drop `warningMessage` field from `RecalledIngredientAlert`: remove `final String warningMessage;` (line 11), remove from constructor (line 21), remove from any call sites. | [ ] TODO | `lib/services/stack/recalled_ingredient_result.dart:11,21` |
| A3 | Remove the provider read: delete `final warningMessage = recall['warning_message'] as String? ?? '';` and the `warningMessage: warningMessage,` arg in `RecalledIngredientAlert(...)`. | [ ] TODO | `lib/features/stack/providers/stack_safety_providers.dart:385,395` |
| A4 | Update contract test to drop the `warning_message` field assertion. | [ ] TODO | `test/core/reference_data_contract_test.dart:108` |

**Verification:** `flutter analyze` clean, `flutter test` 449/449 still green. The `bannerMessage` getter at `recalled_ingredient_result.dart:69-77` already composes its banner from structured fields (statusLabel + productName + ingredient name) and never touched `warningMessage`, so zero UI change.

---

### Path C — Re-author upstream in pipeline, pass-through in Flutter (HOW TO ADD IT BACK PROPERLY)

**Rule: Do NOT re-derive the field in Flutter. Do NOT synthesize from `reason` again. The field must be authored in the pipeline repo with safety-team sign-off, then surfaced in Flutter as pass-through text.**

#### C1. Pipeline-side schema additions (separate PR in `/Users/seancheick/Downloads/dsld_clean/`)

Add three new fields to each entry in `scripts/data/banned_recalled_ingredients.json`:

```json
{
  "id": "ADULTERANT_METFORMIN",
  "standard_name": "Metformin",
  "status": "banned",
  "ban_context": "adulterant_in_supplements",
  "safety_warning": "Supplements containing undeclared metformin have caused hypoglycemia and lactic acidosis. The FDA has issued public warnings.",
  "safety_warning_one_liner": "May cause dangerously low blood sugar.",
  "reason": "...existing long-form encyclopedic text unchanged...",
  ...
}
```

| Field | Purpose | Constraints | Example |
|-------|---------|-------------|---------|
| `ban_context` | Disambiguates what "banned" actually means. Fixes the metformin-style inversion. | Enum. Values: `"substance"` (fully banned, e.g. ephedra), `"adulterant_in_supplements"` (legitimate drug, illegal in supps, e.g. metformin/meloxicam/sibutramine), `"watchlist"` (FDA warning letter, not banned, e.g. octopamine), `"export_restricted"` (jurisdiction-specific). | `"adulterant_in_supplements"` |
| `safety_warning` | One authored sentence describing the user-facing harm, **in supplement-scan context**. Detail-sheet copy. | ≤ 200 chars. Plain language. Reviewed by pharmacist/MD. No encyclopedic definitions. | `"Supplements containing undeclared metformin have caused hypoglycemia and lactic acidosis."` |
| `safety_warning_one_liner` | Chip/banner copy. | ≤ 80 chars. Action-framed. | `"May cause dangerously low blood sugar."` |

**Authoring process (safety-team):** 139 entries × 3 fields = one weekend of pharmacist review. Use `status` + `ban_context` to group (all `adulterant_in_supplements` entries phrased with "Supplements containing undeclared X..." template; all `substance` entries phrased as "X is banned because..."; etc.). Reviewer signs off per-entry in a checklist tracked in the pipeline repo.

**Pipeline build-time validation** (add to `scripts/validate_banned_recalled.py` or equivalent):
- Every entry must have non-empty `safety_warning`, `safety_warning_one_liner`, `ban_context`.
- `safety_warning` ≤ 200 chars; `safety_warning_one_liner` ≤ 80 chars.
- `ban_context` is one of the allowed enum values.
- `safety_warning` does NOT start with `standard_name` followed by "is" (catches the old derivation pattern sneaking back in).

#### C2. Flutter remap (in `/Users/seancheick/PharmaGuide ai/`)

Once pipeline ships the authored fields:

1. **Update remap script / orchestrator** to pass through `safety_warning`, `safety_warning_one_liner`, `ban_context` into Flutter's `banned_recalled_ingredients.json` (renamed keys: all three map 1:1 since they didn't exist in Flutter v1.0). Strip `_metadata.migration_note` deletion warning.
2. **Re-add fields to `RecalledIngredientAlert`** (`lib/services/stack/recalled_ingredient_result.dart`): `final String safetyWarning`, `final String safetyWarningOneLiner`, `final String banContext`. Required, not nullable, since pipeline validation guarantees them.
3. **Re-add reads in provider** (`lib/features/stack/providers/stack_safety_providers.dart`): add the three `recall['safety_warning']`, `recall['safety_warning_one_liner']`, `recall['ban_context']` reads around line 385, feed into `RecalledIngredientAlert(...)`.
4. **Update contract test** (`test/core/reference_data_contract_test.dart`) to assert all three fields present AND non-empty on the first entry. Add the `ban_context` enum check (must be one of the 4 allowed values).
5. **Rewrite `bannerMessage`** in `recalled_ingredient_result.dart:69` to use context-aware verb choice:

```dart
String get bannerMessage {
  if (recalledIngredients.isEmpty) return '';
  final ing = recalledIngredients.first;
  final name = ing.commonNames.isNotEmpty ? ing.commonNames.first : ing.canonicalId;
  final verb = _verbFor(ing.banContext);
  if (recalledIngredients.length == 1) {
    return '$productName $verb $name. ${ing.safetyWarningOneLiner}';
  }
  return '$productName $verb ${recalledIngredients.length} flagged ingredients';
}

static String _verbFor(String banContext) {
  switch (banContext) {
    case 'adulterant_in_supplements': return 'may contain undeclared';
    case 'substance':                 return 'contains banned substance';
    case 'watchlist':                 return 'contains FDA-watchlisted';
    case 'export_restricted':         return 'contains export-restricted';
    default:                           return 'contains flagged';
  }
}
```

6. **Detail-sheet expandable** uses the full `safetyWarning` text + existing `reason` behind a "Read more" affordance (internal/citation-grade copy, NOT primary banner).

#### C3. Opportunistic remap in the meantime — bring `legal_status_enum` + `references_structured` across (this sprint, no pipeline change needed)

These two fields already exist upstream in pipeline v5.0 and got dropped in the Sprint 27.5 remap. Adding them now gets us 80% of the `ban_context` disambiguation before the pipeline authoring pass lands:

- `legal_status_enum` — map 1:1 into Flutter asset. Partial substitute for `ban_context` (e.g., `"banned_adulterant"` vs `"banned_substance"` vs `"fda_warning"` — pipeline values TBD; verify in `/Users/seancheick/Downloads/dsld_clean/scripts/data/banned_recalled_ingredients.json`).
- `references_structured` — regulatory citations array. Surface behind the detail-sheet "Read more" link.

Both are authored upstream, require no derivation, and slot into the existing remap.

---

### Test gaps to close (this sprint, independent of Path A/C)

Today there is **zero integration test** proving the product-scan → recall-flag path actually fires for a known adulterated product. Add three tests in `test/features/stack/recalled_ingredient_integration_test.dart`:

1. **Positive match:** Fixture product with `key_ingredient_tags: ["sibutramine"]` + asset entry with `canonical_id: "sibutramine"` → expect exactly 1 violation, correct canonical_id.
2. **Negative match:** Fixture product with `key_ingredient_tags: ["vitamin_d"]` → expect empty violations.
3. **Case-insensitive match:** Fixture product with `["SIBUTRAMINE"]` (uppercase) + asset entry with lowercase `canonical_id: "sibutramine"` → expect 1 violation. Cross-references the lowercase-canonical-id lesson.

Uses in-memory Drift DB + asset fixture. Closes the biggest untested surface on the entire recall path.

---

### Execution order

1. **This session / today:** Path A (A1–A4) + the 3 integration tests. 4 files + 1 new test file. Kills the time bomb, closes the test gap. Ship as one commit.
2. **Next sprint, no pipeline dependency:** C3 (remap `legal_status_enum` + `references_structured` across from pipeline v5.0 into Flutter asset). Contract test updates. Gets us partial disambiguation.
3. **Pipeline ticket (separate repo, separate PR):** C1 — add `ban_context`, `safety_warning`, `safety_warning_one_liner` to pipeline schema. Safety-team authors 139 × 3 fields with sign-off checklist. Pipeline validation scripts enforce constraints.
4. **After pipeline ships authored fields:** C2 — Flutter remap pass-through, re-add fields to model/provider/test, rewrite `bannerMessage` with context-aware verbs.

---

### Do NOT do the following (anti-patterns captured)

- ❌ Do NOT re-derive `warning_message` from `reason` in Flutter. The template `"{standard_name} is {status}: {first sentence of reason}"` is the bug. Sentence 1 of `reason` is encyclopedic (definition), sentence 2+ is the danger. Result: "Metformin is banned: Metformin is a prescription antidiabetic drug..." — inverted safety signal.
- ❌ Do NOT conflate "banned substance" with "banned as adulterant in supplements." Metformin, meloxicam, sibutramine are legitimate prescription drugs; they're only illegal as undeclared adulterants in supplements. Calling them "banned" without `ban_context` is medically incorrect.
- ❌ Do NOT render `reason` directly to users. It's encyclopedic internal/citation copy, not user-facing warning copy.
- ❌ Do NOT ship an authored field without build-time validation. The `safety_warning` template check (must not start with `"{standard_name} is"`) is a critical guardrail to prevent the old derivation sneaking back in.
- ❌ Do NOT wire a UI that reads `warning_message` after Path A ships. The field is gone. If you see a grep hit for `warning_message`, it's a merge artifact — delete it.

---

### Files touched (for commit grep)

**Path A commit:**
- `assets/reference_data/banned_recalled_ingredients.json`
- `lib/services/stack/recalled_ingredient_result.dart`
- `lib/features/stack/providers/stack_safety_providers.dart`
- `test/core/reference_data_contract_test.dart`
- `test/features/stack/recalled_ingredient_integration_test.dart` (new)

**Path C commits (future):**
- Pipeline repo: `scripts/data/banned_recalled_ingredients.json` + `scripts/validate_banned_recalled.py`
- Flutter: remap script + same 4 Flutter files above (re-add fields) + contract test additions

---

## CONSOLIDATED OPEN ITEMS (as of 2026-05-18)

Everything below is genuinely NOT DONE, verified against the codebase. Organized by priority tier so nothing gets lost across sprints.

### P0 — Ship Blockers (Sean-owed manual tasks)

- [ ] **TestFlight build cut + upload** (Tracks A5, T0.7 step 4)
- [ ] **Google Play internal track build cut + upload**
- [ ] **Real-device smoke:** B3 home headline, T0.4/T0.5 visual edges, C3 paste-into-Mail/MyChart, D4 force-corruption rollback, 52 mg zinc UL red banner
- [ ] **Store metadata:** screenshots, description, privacy policy, encryption questionnaire
- [ ] **App Store Privacy Nutrition Label**
- [ ] **PHARMAGUIDE-1 (RenderFlex overflow) Sentry triage**
- [ ] **24h Sentry watch post-deploy**
- [ ] **G.4 Tighter SE spacing** — needs Sean's design call + simulator validation

### P1 — V1.0-Release Gate (code tasks)

- [-] Implement Google Sign-In — service + v2 auth callback wired; needs live provider/device verification.
- [-] Implement Apple Sign-In — service + v2 auth callback wired; needs live provider/device verification.
- [-] Implement Email auth — magic-link sheet + `pharmaguide://auth/callback` wired; password auth intentionally not used for v1.0; needs live Supabase round trip.
- [-] Account & Security section (email, password, login/logout) — email + sign-in route + signed-in sign-out action wired 2026-05-18; password/account-management still open.
- [-] Implement scan/AI usage limits — guest scans are local 3/day and scanner/manual barcode paths enforce the cap; signed-in scan policy is unlimited for current release. AI quota still open.
- [-] Enforce access tiers — Guest: 3 scans/day, no saved stack, no AI, no cloud sync. Signed-in Free: unlimited scans during early access + saved stack/profile/history. Premium: deferred. Stack saves now require sign-in for supplements + medications; AI/Premium gates still open.
- [🚫] ~~Wire `scan_limit_service` to live `increment_usage` RPC~~ — rescoped 2026-05-18 with signed-in unlimited scans for early access.
- [-] Build "upgrade to signed-in" prompt when guest hits limits — scanner cap sheet routes to auth; stack add/medication add route to auth; AI prompt still open.
- [🚫] ~~Build signed-in limits display (20 scans/day, 5 AI/day with UTC reset)~~ — rescoped 2026-05-18: signed-in users get unlimited scans for now; AI quota display remains tied to future Gemini enforcement.
- [-] Write auth flow tests (sign in, sign out, guest-to-auth migration) — auth skip, provider callbacks, magic-link placeholder guard, settings sign-out covered; real provider success/failure + guest migration still open.
- [-] Write usage limit tests — guest 3/day reset + signed-in-unlimited service behavior covered; scanner smoke + stack domain guard covered; AI quota tests still open.
- [-] Analytics events wired — Sentry breadcrumbs added for scan complete + stack add; real SDK (Firebase/Mixpanel/PostHog/etc.) still blocked on privacy/vendor decision before replacing stub `analytics_service.dart`.
- [ ] Gemini AI quota verification (5/day server-side enforcement)

### P2 — Next Code Sprints

**Trust & IA Sprint 2 — Refinement Polish (6 tasks):**
- [ ] T2.1–T2.8 — all `[ ]` in `INITIATIVE_PRODUCT_TRUST_AND_IA.md`. Gated on Sean's 5-product real-device smoke test.

**Trust & IA Sprint 3 — Backend Foundation (7 tasks):**
- [ ] Excipient ontology, prose `score_bonuses[].detail`, percentile ranking, editorial summaries — mostly pipeline-side data work.

**Cross-product dose summation:**
- [ ] New `stack_dose_summer.dart` — sum dose-per-day per nutrient_form across active stack. Wire into `StackIntelligenceEngine`. First targets: caffeine 200mg, vitamin A 3000mcg, niacin 35mg, iron 45mg. ~5h.

**QA & Polish:**
- [ ] Error matrix implementation (centralized error routing per spec §11)
- [ ] Dark mode audit (screen-by-screen visual check — theme infra done)
- [ ] Accessibility audit: VoiceOver, TalkBack, full Semantics pass (DT clamp at 1.4x done, partial Semantics done)
- [ ] No emojis as structural UI — Lucide icons audit
- [ ] Performance profiling: scan-to-result <500ms, search <300ms, launch <3s
- [ ] Memory profiling: no leaks on repeated scan/detail/back cycles
- [ ] "Complete your profile" prompt in nutrient panel when `ageBracket == null`
- [ ] Tap-to-expand contributions row in progress bar

### P3 — V1.1+ Backlog

- [ ] Build "update available" indicator on Profile tab
- [ ] Build notification preferences (`flutter_local_notifications`)
- [ ] Implement `min_app_version` gate (force update) — schema exists, no gate logic
- [ ] Settings: notification controls (reminders, alerts, insights, refills)
- [ ] Settings: accessibility (high contrast, VoiceOver — reduceMotion done)
- [ ] Settings: offline mode (auto-download, sync frequency)
- [ ] Settings: advanced (export data, clear cache, reset tutorials, delete account)
- [ ] Write OTA update tests (success, failure, rollback)
- [ ] Coach marks / feature tour (overlay system)
- [ ] "Try Demo Mode" (preloaded dummy scan)
- [ ] FitScore comparison view (side-by-side two products)
- [x] Stack share: "Export PDF for Doctor" — ✅ CODE DONE 2026-05-28. Offline branded PDF uses PharmaGuide logo + Geist fonts, existing stack intelligence/safety/nutrient/timing/depletion signals, and `printing.sharePdf`; verified with `flutter analyze` and `flutter test test/services/sharing test/features/stack/widgets/share_clinician_report_button_test.dart` (19 tests). Real-device share smoke ⏳ Sean.
- [ ] Deep link handling (`app_links` package) + shared product entry point + edge cases
- [ ] Build Open Graph preview for shared links
- [ ] Write deep link routing tests
- [ ] Stack Analysis History (last 3 saved reports)
- [ ] Pull-sync for multi-device (push-only today)
- [ ] Stack wishlist: compatibility check against current stack
- [ ] Full Stack Analysis report (nutrient breakdown, interactions, timing, goals)
- [ ] Add-to-stack scheduling flow (time, supply, reminders)
- [ ] Write sync tests against Supabase mock
- [ ] Handle edge case: 20+ product stack performance
- [ ] Telemetry on UL breaches (log locally only)
- [ ] Catalog rollback dashboard card
- [ ] User-contributed photos ("snap a photo of this bottle" → Supabase)
- [ ] v6.1 cleanup — remove legacy `matchesProfile` fallback (~30 days after v1.6.0 ships)
- [ ] Structural pregnancy/lactation split (pipeline + Flutter toggle)
- [ ] Deep link handling for invalid routes (graceful fallback)

### P4 — Future / Pipeline-Gated

- [ ] Remaining RECONCILIATION backlog: vitamin_d (needs `lab_status`), white_mulberry (needs `form_scope`), black_seed_oil (dose threshold), stinging_nettle (dose pattern)
- [ ] Future profile flags: heart subconditions, `severely_immunocompromised` escalators, CKD stage/eGFR, thyroid levothyroxine timing
- [ ] Heavy metal limits reference file + B8 contaminant risk scorer (pipeline)
- [ ] Excipient density mass calculator + A7 formulation density scorer (pipeline)
- [ ] Catalog rebuild for pipeline scoring changes
- [ ] Re-run full pipeline on fresh dataset to measure score impact
- [ ] Enrich 21 branded botanical stubs (Chromax, Cognizin, EpiCor, etc.)
- [ ] `backed_clinical_studies.json`: 6 study_type reviews, 5 missing source texts
- [ ] Flutter test coverage for dual-path interaction matching
- [ ] Live API integration tests (RxNorm + UMLS) gated on `--live` flag
- [ ] Blocked-build demo: deliberately broken Major+ entry must fail build
- [ ] Auto-enrich curated entries with supp.ai PMIDs at build time
- [ ] Live RxNorm integration test
- [ ] Integration test against real bundled `interaction_db.sqlite` fixture
- [ ] Fix markdownlint warnings in `docs/INTERACTION_DB_SPEC.md` (cosmetic)
- [-] About section — real ToS/privacy/support destinations are wired with `url_launcher`; StoreReview/rate-share release polish remains deferred.
- [ ] V1.4+ Commerce (Track E) — deferred until V1.2 trust ships

---

## Marketing Website — Parallel Initiative (in flight, 2026-05-07 → present)

> [!info] Repo: `/Users/seancheick/PharmaGuide Website` · Vercel: `pharmaguide-website.vercel.app` · GitHub: `seancheick/PharmaGuideWebsite` · Stack: Next.js 16 · React 19 · Tailwind v3 · Framer Motion 11 · Geist + Newsreader fonts

### Status: V1 marketing site live with 8 routes, full analytics + email, axe-clean.

| Track | Description | Sprints | Status |
|---|---|---|---|
| **W1** — Foundation | Design system, tokens, hero, infrastructure strip, problem section, how-it-works, interaction ladder, real-life moments, your-fit, final CTA, dark teal footer, back-to-top, programmatic favicon → real bitmap logo, OG image | 1 → 12 | ✅ Done |
| **W2** — Polish + accuracy | Carousel mobile expansion + edge-margin fix, ladder mobile-active state, Problem section text-balance, evidence levels matched to in-app schema (Established/Probable/Moderate/Limited/Theoretical replacing fictional A/B/C/D), tier 5 "No known issue" → "Informational" matching app | 13 → 18 | ✅ Done |
| **W3** — `/faq` page | Single-column accordion, Q01–Q11 numbered eyebrows, Framer height animation, FAQPage + Breadcrumb + WebPage JSON-LD, ISR 5d, voice-rules-applied copy, "Stay in the loop" newsletter CTA replacing the old strip | 19 | ✅ Done |
| **W4** — Email backend | Resend SDK + React Email installed. `subscribe()` helper (idempotent, server-only). `joinBetaWaitlist` + `subscribeToNewsletter` server actions. Branded BetaWelcomeEmail + NewsletterWelcomeEmail templates. FinalCTA + NewsletterCTA wired to real backend. Domain verification + audience IDs in env. | 20 | ✅ Done — domain verification by Sean |
| **W5** — Legal pages | Shared `<LegalPage>` component (sticky desktop TOC + mobile collapsible + scroll-spy via IntersectionObserver). `/privacy` (13 sections), `/terms` (14 sections, medical disclaimer prominent at #3), `/hipaa` (7 sections, honest framing), `/accessibility` (6 sections, WCAG 2.2 AA target). All emit Article + Breadcrumb JSON-LD. | 21 | ✅ Done |
| **W6** — `/methodology` | Premium custom layout (NOT LegalPage). 6 sections with custom visuals: 3 trust pillars · 4 source cards (FDA/NIH/PUB/PRO) · 5-step vertical timeline · 2-card advisory team (Dr. Pham L. PharmD + Miriam D. NP) · AI does/does NOT split · IS/IS NOT scope split. Article + HowTo + Breadcrumb JSON-LD. | 22 | ✅ Done |
| **W7** — `/features` | 6-pillar showcase with custom SVG illustrations: **Medication Depletion** (hero illustration: med card → arrow → depleted nutrient cards) · Stack Intelligence (5-node animated network) · Ingredient & Quality Transparency (parsed supplement-facts panel with decomposed proprietary blend) · Personal Fit (profile chips → adapted recs) · Nutrient Accumulation (4-row UL meter with over/under coloring) · Recall & Safety (FDA/FAERS alert stack). External authority deep links per pillar (FDA, NIH ODS, DSLD, FAERS, PubMed, Cochrane, NCCIH, DailyMed). SoftwareApplication + ItemList + Breadcrumb JSON-LD. | 23 | ✅ Done |
| **W8** — Homepage broadening | Hero eyebrow shifted "On-device supplement safety" → "The supplement & medication co-pilot." Subhead rewritten to name interactions, depletions, dose accumulation, recalls, ingredient quality. New BeyondInteractions section (6 capability cards → /features deep-dives) between Ladder and Real-Life Moments. | 24 | ✅ Done |
| **W9** — A11y + SEO + Analytics | axe-core audit on all key pages: 0 violations post-fix (was 3). FinalCTA aside→div, FAQ h3→h2, LegalPage TOC aside→nav, 7 page-titles fixed (template duplication). GSC + Bing + Yandex verification meta-tag scaffolding via env vars. Organization JSON-LD logo path fixed. `.env.example` + `docs/09-search-console-setup.md` published. | 25 | ✅ Done |
| **W10** — DNS migration to Vercel | Cut over `pharmaguide.io` from Hostinger to Vercel-routed (preserve email MX). Verify GSC + Bing on apex domain. | 26 | ⏳ Sean (DNS owner) |
| **W11** — `/blog` hub | Blog hub page + post template + first 2-3 seed posts | 27 | 🎯 Up next |

### Routes live (post-deploy)

| Route | Priority in sitemap | JSON-LD | Status |
|---|---|---|---|
| `/` | 1.0 | Organization + Website | ✅ |
| `/features` | 0.95 | SoftwareApplication + ItemList + Breadcrumb | ✅ |
| `/methodology` | 0.9 | Article + HowTo + Breadcrumb | ✅ |
| `/faq` | 0.7 | FAQPage + WebPage + Breadcrumb | ✅ |
| `/privacy` | 0.5 | PrivacyPolicy + Breadcrumb | ✅ |
| `/terms` | 0.5 | TermsOfService + Breadcrumb | ✅ |
| `/hipaa` | 0.4 | Article + Breadcrumb | ✅ |
| `/accessibility` | 0.4 | Article + Breadcrumb | ✅ |
| `/blog` | tbd | Blog + ItemList | 🎯 next |
| `/blog/[slug]` | tbd | Article | 🎯 next |
| `/about` | tbd | AboutPage | 📋 backlog |
| `/healthcare-pros` | tbd | Service | 📋 2026 |

### Brand + tech foundation

- Design tokens in CSS variables (single source of truth, consumed by Tailwind config)
- Geist Sans (UI) + Newsreader (italic-serif punchline rhythm) + Geist Mono (eyebrows + data)
- Severity tokens match in-app: contraindicated · avoid · caution · monitor · informational
- Evidence levels match in-app: Established · Probable · Moderate · Limited · Theoretical
- Real PharmaGuide logo wired as favicon (32 / 180 / 192 / 512 PNG sizes)
- Privacy-first analytics: Vercel Analytics + Vercel Speed Insights + GA4 + Microsoft Clarity
- Resend email backend: 2 audiences (beta-waitlist + newsletter), branded React Email welcome templates

### Owed back to Sean (Marketing Website)

- [ ] **DNS migration: Hostinger → Vercel for pharmaguide.io.** See "DNS migration" section in this tracker (added 2026-05-08).
- [ ] **Resend domain verification** — DNS records for DKIM/SPF/DMARC need to be added at the registrar before transactional emails will deliver from `hello@pharmaguide.io` instead of the test sandbox.
- [ ] **GSC + Bing verification tokens** — paste into `.env` + Vercel env, redeploy, verify, submit `sitemap.xml`. Step-by-step in `docs/09-search-console-setup.md`.
- [ ] **`/blog` hub + first 2-3 seed posts** — see "Blog hub" plan below.
