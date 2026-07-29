# PharmaGuide Beta-User Audit — 2026-07-29

Audited `main` @ `d812ed1`, bundled assets as shipped (catalog `2026.07.25.003719`,
interaction DB `1.0.9`). Every claim below was verified against current source,
the current bundled SQLite, or a test run — not against prior audit reports or
memory. Where a prior memory said otherwise, the memory is marked stale.

---

## Adversarial follow-up — Codex, 2026-07-29

Claude's core finding was correct: the previous recall join used record IDs as
ingredient IDs and could not match the shipped asset. Independent checks
against the bundled SQLite and JSON confirmed:

- 13,271 bundled products;
- 107 products with the pipeline-authored banned-substance flag;
- 0 products with the recall flag in the current catalog;
- 82 of the 107 flagged products can be named through a hard-banned authored
  common name;
- 0 unflagged products match that restricted hard-banned name set.

The follow-up also found and fixed gaps in Claude's implementation:

1. Claude introduced a worker provider that returned `(report, incomplete)` and
   a second compatibility provider that discarded `incomplete`. The Stack
   recall banner hedged, while Home and the clinician path could still diagnose
   the same empty report as clean. The report now owns its `incomplete` state
   and every surface consumes that single object.
2. Missing product rows, malformed/empty recall data, and per-product hydration
   failures now mark the scan incomplete. They no longer disappear as clean
   misses.
3. Pipeline `has_banned_substance` and `has_recalled_ingredient` are no longer
   collapsed into the same `BANNED` sentence. Banned substances match authored
   ingredient names; recalled products match authored product names. Unnamed
   flags retain accurate generic copy.
4. A banned product whose substance cannot be named now remains classified as
   banned in Stack Intelligence and clinician output; it no longer degrades to
   a generic recall.
5. Home and Stack now share one unavailable/error fallback. Home can no longer
   show green “No data yet” while Stack says the safety analysis failed.
6. Missing dose blobs now mark dose-dependent pair checks incomplete instead
   of evaluating a partial subtotal as a confident clear.
7. The accidental catalog commit `5c5364c` was reverted. It reused interaction
   DB version `1.0.9` for different bytes and broke the storage-alignment gate.
   The clinical/runtime assets are again byte-identical to `main`.
8. Interaction and recall banners now label partial results even when they also
   contain a known finding. Previously the banner showed the finding but hid
   that other products or checks had not been analyzed.

Verification after the follow-up: `flutter analyze lib test` clean and the full
Flutter suite **2,705 passing**.

---

## A. Executive summary

| | Count |
|---|---|
| Total findings | 27 |
| Safety-critical | 3 |
| High | 6 |
| Medium | 11 |
| Low / cleanup | 7 |
| **Confirmed defects** | **21** |
| Suspected (not independently verified) | 6 |
| False alarms disproved during the audit | 3 |
| Blocked (needs pipeline repo or device) | 4 |

**Fixed and merged-ready this pass:** 3 of the 3 safety-critical findings, in
[PR #66](https://github.com/seancheick/Pharmaguide.ai/pull/66). Full suite 2,705
passing, `flutter analyze lib test` clean.

The unifying defect: **three separate surfaces converted "we could not check"
into "we found nothing."** That is the single most dangerous failure mode a
safety app has, because the user cannot tell the two apart, and neither can
their clinician.

### False alarms — disproved, do not chase

1. **`evidence_level` all-NULL in the interaction DB.** Prior memory says all 150
   rules ship NULL evidence. **Now false**: 145/145 populated
   (`established` 55, `probable` 46, `moderate` 42, `theoretical` 2), and all
   four map correctly onto `EvidenceLevel` wireIds. Memory is stale.
2. **`allergen_summary` empty for all products.** Prior memory says 0 populated.
   **Now false**: 3,472/3,472 products with `has_allergen_risks = 1` carry a
   populated summary. Fixed upstream; memory is stale.
3. **`top_warnings` ships plain strings that the parser drops.** **Now false**:
   all 23,304 entries across 7,803 products are structured objects.
   `parseTopWarnings` handles them. The *real* `top_warnings` issue is different
   and is filed as M-3 below.

---

## B. Reproduction matrix

Severity key: **SC** safety-critical · **H** high · **M** medium · **L** low.
Confidence: **confirmed** = I reproduced or read the code path myself;
**reported** = surfaced by a sub-audit and not independently re-verified.

### SC-1 — Clinician report prints an all-clear when the checks failed ✅ FIXED

| | |
|---|---|
| Repro | Any stack; force `StackSafetyReport.checksIncomplete = true` (interaction DB unavailable, med-class bridge throws, or any safety subsystem fails), then tap Share clinician report. |
| Expected | The PDF states the checks did not complete. |
| Actual | PDF printed `Interactions flagged: 0`, `Nutrient warnings: 0`, and `No stack warnings in the current snapshot.` |
| Screen | Clinician PDF (`share_clinician_report_button` → `ClinicianPdfBuilder`) |
| File | `lib/services/sharing/clinician_pdf_builder.dart:21-36` (params), `:239`, `:263` |
| Impact | A prescriber reads a patient-generated document asserting zero interactions when zero checks ran. The app hedges on the same object (`stack_safety_details_sheet.dart:48,138` — *"This is not an all-clear"*); the document did not. The flag's own docstring (`stack_safety_report.dart:48-51`) says the UI must hedge. |
| Confidence | **confirmed** — RED test showed the literal string in the PDF byte stream |
| Owner | App (fixed, PR #66) |

### SC-2 — Stack nutrient totals were a silent partial sum ✅ FIXED

| | |
|---|---|
| Repro | Stack of 5 supplements, airplane mode with a cold detail-blob cache (or any product whose blob 404s). Open Stack → Nutrient totals. |
| Expected | Totals hedge that items were excluded. |
| Actual | Products whose product row or blob failed were dropped with no signal; the panel presented the remaining sum as the user's intake **and ran upper-limit comparisons against it**. |
| Screen | Stack → Nutrient accumulation panel |
| File | `lib/features/stack/providers/stack_nutrient_providers.dart` (the `continue` arms) |
| Impact | A UL comparison drawn from an under-report can read "within limit" when the true total is not. `stack_safety_providers.dart:355-378` already tracked exactly this condition (`coverageIncomplete`) for the interaction half — the nutrient half never reported it. |
| Confidence | **confirmed** |
| Owner | App (fixed, PR #66) |

### SC-3 — Upper-limit panel vanished on error ✅ FIXED

| | |
|---|---|
| Repro | Make `stackNutrientStatusesProvider` throw (reference data unreadable). Open Stack. |
| Expected | An explicit "totals unavailable" state. |
| Actual | `error: (_, __) => const SizedBox.shrink()` — the panel disappeared. |
| Screen | Stack → Nutrient accumulation panel |
| File | `lib/features/stack/widgets/nutrient_accumulation_panel.dart:44` |
| Impact | On the one surface whose job is upper-limit safety, empty space reads as "no UL concerns." **The existing test asserted `findsNothing`, so it locked the defect in.** |
| Confidence | **confirmed** |
| Owner | App (fixed, PR #66) |

### H-1 — `DSI_VITE_ANTICOAG` fires a hard "not recommended" at any vitamin E dose

| | |
|---|---|
| Repro | Profile with an anticoagulant (or warfarin in stack). Open any multivitamin containing ~30 IU vitamin E. |
| Expected | No hard warning — the rule's own advice is a ≤400 IU/day ceiling the user is far below. |
| Actual | Rule has `severity = avoid`, `materiality = presence`. `Severity.isHard` → `computeFitDisplay` → `FitHidden` → **"Not recommended for your profile"**, fit tier suppressed entirely. Management copy reads *"Limit vitamin E to ≤400 IU/day when taking anticoagulants."* |
| Screen | Product detail → Profile Relevance; hero verdict |
| File | Curated data: `interactions` row `DSI_VITE_ANTICOAG` (evidence `probable`) |
| Impact | Hard false positive on an extremely common combination. Copy implies a numeric threshold was evaluated; none was. |
| Confidence | **confirmed** (DB row + code path read) |
| Owner | **Pipeline / clinical curation** — one entry at a time, with evidence. Do not batch. |

### H-2 — Eleven more presence-materiality rules carry threshold prose

Same class as H-1 at lower severity. `SSI_ZINC_COPPER` (caution) — *"copper alongside
zinc supplementation exceeding 25 mg/day"* — fires at any zinc dose.
`DSI_PPI_B12` (caution) — *"Long-term PPI users (>2 years)"* — duration never
evaluated. `DSI_THYROID_TURMERIC` (monitor) — *"if starting high-dose curcumin."*
12 rules total match `materiality='presence'` AND dose/duration prose.
**Confidence: confirmed. Owner: pipeline curation.**

### H-3 — Medications show a green "Matched for interaction checks" with zero rule coverage

| | |
|---|---|
| Repro | Add **levodopa** (also duloxetine, gabapentin, montelukast, divalproex, ezetimibe). Open Stack. |
| Expected | An honest "matching limited" state. |
| Actual | Green `V2Colors.safe` badge: *"Matched for interaction checks — RxNorm ingredient identity and reviewed medication groups are available for matching."* |
| Root cause | `medication_identity_status.dart:45-48` computes `complete` from `drugClassIds`, which is the persisted **union** of curated `class:*` ids and uncurated RxClass runtime slugs. A med with only RxClass slugs matches zero curated classes but still reads `complete`. |
| File | `lib/services/medications/medication_identity_status.dart:45-48`; rendered `lib/features/stack/v2/stack_v2_screen.dart:1239-1245` |
| Impact | The app affirmatively tells the user matching is available when no rule can fire. |
| Confidence | **confirmed** (both files read) |
| Fix direction | Compute status from curated coverage (∩ `drug_class_map`) ∪ direct-RxCUI rule hit, not from the merged list. |

### H-4 — Detail-blob fetch failure is indistinguishable from "no blob exists"

`detail_blob_service.dart:83-85` swallows every failure (network, timeout, 5xx,
malformed JSON) into `null`; `detail_blob_provider` also returns `null` when the
product simply declares no blob. The provider therefore **never throws for a
network failure**, which makes `blobError` at
`product_detail_v2_connected.dart:387` — and the `!blobError` arm of
`shouldShowDeepDive` — dead code for that entire failure class. Deep-dive renders
on a null blob (empty ingredients card, no hedge) while the hero verdict and
score still render confidently from the core DB. Blob-authored profile advisories
silently vanish. **Confirmed. Owner: app.**

### H-5 — Interaction DB `min_app_version` is parsed and never enforced

Stored at `interaction_database.dart:455` → field `:68`; **zero consumers**.
`onUpgrade` is an empty no-op (`:116`). The catalog, by contrast, *is* gated
(`sync_service.dart:631` `enforceCatalogVersionGate` → `CatalogVersionGateException`).
Low risk today (bundled declares `1.0.0`) but the interaction-DB OTA path can
load a bundle the reader cannot correctly interpret. **Confirmed. Owner: app.**

### H-6 — Clinician report flattens "good to know" into WARNINGS at true severity

`clinician_pdf_builder.dart:254,278-286,321` renders every signal into one
`Warnings` section in an amber box using `signal.clinicalSeverity.label`.
`consumerDisposition` is never read. Because
`clinical_signal_envelope.dart:144-166` deliberately keeps the **true** severity
for ranking while pinning food advisories to `goodToKnow` for placement, a note
the app shows under a calm "Good to know" heading prints to the clinician as
**"Not recommended: X × Y"**. **Reported, high confidence. Owner: app.**

### Medium

- **M-1** — `hero_verdict_provider.dart:180` parses severity with
  `orElse: () => Severity.safe` — fail-**open** in a safety path. Violates the
  codebase's own stated rule (`severity.dart:165`: *"NEVER to a higher tier and
  NEVER to `safe`"*) and contradicts `safety_check_sheet.dart:176`
  (`orElse: () => Severity.caution`). Live shipped `top_warnings` vocabulary is
  `avoid`/`contraindicated` (in-enum) plus `low`/`moderate`/`high`/`warning`/
  `critical` (not in enum → collapse to `safe`); 5,185 products have
  all-out-of-enum severities. **Latent, not live**: today's unknown tokens are
  the additive/dose-safety scale and genuinely should not gate the hero. But a
  renamed or new hard token would vanish silently, with no telemetry. One-line
  fix + test. **Confirmed.**
- **M-2** — `stack_ul_checker.dart:176-185`: displayed `pctOfUl` prefers
  `verdict.pctUl` while `_classify` uses the recompute. `_mostSevereVerdict` can
  merge `overUl=false` with `pctUl=250`, yielding a **green row labeled
  "250% UL"**. **Confirmed by code read; no live example found.**
- **M-3** — `top_warnings` is consumed *only* by the blocked banner
  (`parseTopWarnings` has one caller, `:607`). Non-blocked products render no
  static warnings offline, and the payload's `message` field — which
  `FINAL_EXPORT_SCHEMA_V1.md:880` says is for display — reaches no surface.
  This is the **open architectural decision** from prior work: retire the field,
  or route it through the same warning presenter. Rows lack profile-gate
  metadata, so rendering them raw would over-warn. **Confirmed. Needs a decision.**
- **M-4** — Anonymous/unmatched-age UL falls back to `highest_ul`, the **least**
  restrictive demographic ceiling (`stack_ul_checker.dart:371`). Under-warns
  users without a profile and any user whose age bracket has no row.
- **M-5** — `aggregate()` calls `putIfAbsent` *before* the exclusion check, so a
  nutrient whose every row is excluded still produces a `NutrientTotal` with
  `totalAmount = 0.0`, empty unit, and no contributions — rendering as **"0"**
  and not tappable. Exactly the misleading zero the audit targets.
- **M-6** — Split-total UL false negative (needs pipeline data check). Totals key
  on `canonical_id`; `_rdaAliases` maps `vitamin_d2`/`d3` → `vitamin_d` **only
  for reference lookup, not for aggregation**. If the pipeline ever emits distinct
  canonical ids for D2/D3, K1/K2, or folate/folic acid, they become separate rows
  each compared against the same UL. Verify `nutrient_group_id` is always populated.
- **M-7** — Clinician PDF silently truncates: `.take(10)` nutrients, `.take(8)`
  timing, `.take(8)` depletions, with no "+N more".
- **M-8** — Two evidence vocabularies in one PDF: "Strong Evidence" (`:326`) vs
  "Established" (`:653-658`).
- **M-9** — Medication identity status (`partial`/`unresolved`) never reaches the
  PDF, so an unmatched med silently contributes nothing to the findings.
- **M-10** — Provenance rows *vanish* on fetch failure rather than saying
  "unknown" (`clinician_pdf_builder.dart:205-216` + button `:83-107`).
- **M-11** — Share-sheet cancel is indistinguishable from success; no test.

### Low / cleanup

**L-1** `clinician_report_builder.dart` (markdown) has **no production caller**
yet carries the suite's strongest assertions — dead path, misleading coverage.
**L-2** Seven `InteractionWarning` fields parsed and never rendered, each with a
docstring claiming UI consumption. **L-3** `InteractionWarning.fromJson` drops the
`type` discriminator. **L-4** `AnalyticsService` is entirely write-only — no flush
path, default off. **L-5** `countLiveInteractions()` dead outside tests.
**L-6** Empty `onUpgrade` in core + interaction DBs. **L-7** `Tier: Solid` printed
in the PDF with no "not a clinical assessment" qualifier (while `qualityScore` is
correctly withheld and test-locked).

---

## C. Drift map

| Clinical concept | Representations | SSOT | Status |
|---|---|---|---|
| Checks-did-not-run | `StackSafetyReport.checksIncomplete/coverageIncomplete` → app sheet → banner → **PDF** | `StackSafetyReport` | PDF was not derived from it — **fixed PR #66** |
| Partial nutrient totals | safety provider tracked it; nutrient provider did not | `StackSafetyReport.coverageIncomplete` | **fixed PR #66** — nutrient provider now feeds it |
| Severity | pipeline `severity` → `Severity` enum → `top_warnings` low/moderate/high/critical scale | `Severity` enum | **Two vocabularies.** Additive/dose scale silently collapses to `safe` (M-1) |
| Evidence grading | `interactions.evidence_level` → `EvidenceLevel` → app label → PDF label ×2 | `EvidenceLevel` | Wire mapping clean; **PDF renders two label sets** (M-8) |
| Consumer disposition | `ConsumerDisposition` → app "Needs attention"/"Good to know" → PDF | `ClinicalSignalEnvelope` | **PDF ignores it** (H-6) |
| Medication identity | curated `drug_class_map` ∪ RxClass runtime slugs → `drugClassesCol` → status badge | `drug_class_map` | **Merged at persistence, so the badge cannot tell them apart** (H-3) |
| UL eligibility | `skip_ul_check`, `ul_gate_eligible`, `over_ul`, `pct_ul` | pipeline row | Honored by aggregator, dose_safety, tradeoffs; display/tier can still disagree (M-2) |
| Static warnings | `top_warnings` (core DB) vs structured blob warnings | blob | `top_warnings` reaches only the blocked banner (M-3) |
| Version gating | catalog gated; interaction DB not | — | **Asymmetric** (H-5) |

---

## D. Dead code & silent failures

Swallowed without telemetry: `detail_blob_service.dart:83`,
`fit_score_provider.dart:87,96`, `personalized_warnings_provider.dart:41,65`
(the same `on UnimplementedError → return const []` idiom the file's own comment
at `:92-104` documents as a removed hazard), `stack_dose_summer.dart:132` (whose
twin at `warnings_pipeline.dart:116` *does* report).

Vanish-on-error UI: `stack_v2_screen.dart:2210,2240`.

Write-only / dead: `AnalyticsService` buffer, `clinician_report_builder.dart`,
`countLiveInteractions()`, `agent1_drug_class`/`agent2_drug_class` columns,
seven `InteractionWarning` fields, `min_app_version` on the interaction DB.

Tests that did not exercise production behavior: the nutrient panel's
`'error state collapses silently'` (asserted the defect — **rewritten**); PDF
builder tests are 100% synthetic with no `checksIncomplete` case (**added**);
`clinician_report_builder_test.dart` covers a dead path.

---

## E. Regression suite added (all red before, green after)

`test/services/sharing/clinician_pdf_builder_test.dart`
— checks-incomplete states it rather than an all-clear
— coverage-incomplete states it rather than an all-clear
— no bare zero interaction count when checks failed

`test/features/stack/widgets/nutrient_accumulation_panel_test.dart`
— error says totals unavailable, never blank *(replaces the defect-locking test)*
— partial totals carry a hedge above the numbers
— complete totals carry no hedge
— every-item-skipped says so rather than hiding

`test/features/stack/providers/recalled_ingredients_incomplete_test.dart`
and `recalled_ingredient_integration_test.dart`
— one report carries findings and completeness to every consumer
— missing hydration and malformed data hedge rather than clear
— banned and recalled flags retain distinct copy and classification

`test/features/stack/providers/safety_check_for_add_medication_test.dart`
— missing dose context prevents a confident clear

`test/features/stack/v2/stack_health_fallback_display_test.dart`
— Home and Stack share the same non-green error fallback

`test/features/stack/widgets/stack_safety_banner_test.dart`
— known findings retain an explicit partial-results hedge when another check
or product label could not be analyzed

---

## F. Verification run

- `flutter analyze lib test` → **No issues found**
- `flutter test` → **2,705 passing**
- Asset checksums recomputed independently: interaction DB
  `b3595104…605b0` and catalog `ef5fa6a8…3de3bf` both match their manifests;
  `integrity_check ok`; row counts match manifest counts; **no LFS pointer shipped**.

---

## G. Not covered — be explicit about the gaps

- **Timing conflict reconciliation (Part 5)** — not exercised. The service and
  card exist and PR `953f204` made timing product-aware, but I did not test
  fat-soluble + ALA, iron + calcium, or zinc + copper for mutually incompatible
  instructions.
- **Device runtime (Part 8)** — airplane mode, kill-during-hydration, corrupt or
  partial SQLite, old `user_data.db` migration, low memory, storage permission
  were traced statically only.
- **Byte-exact artifact regeneration (Part 7)** — requires the `dsld_clean`
  pipeline repo; only the shipped artifacts were verified.
- **OCR / barcode / manual entry (Part 2)** — not exercised.

---

## H. Working-tree note

The catalog/interaction bundle commit that appeared during this audit was
reverted because it changed immutable bytes without a new interaction release
version and failed bundle-to-storage alignment. No catalog, interaction DB, or
medication-depletion artifact differs from `main`. The unrelated local
`CLAUDE.md` edit remains deliberately excluded from PR #66.
