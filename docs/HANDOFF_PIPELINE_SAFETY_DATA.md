# Handoff: Pipeline Safety Data — Authored Warnings + Invariants Audit

**Date:** 2026-04-16
**From:** PharmaGuide Flutter (Sprint 27.6 Path A shipped) → Pipeline repo (`/Users/seancheick/Downloads/dsld_clean/`)
**Audience:** Pipeline maintainer (the person who owns `scripts/data/*.json` and `build_*.py`)
**Status:** Flutter Path A complete and landing. Pipeline Path C + invariants audit is the next sprint, owned upstream.

---

## TL;DR

Today the Flutter app **dropped every `warning_message` string** from the bundled recall asset because an audit found the derived strings were medically incorrect for ~30–40 of 139 entries. The derivation template was `"{standard_name} is {status}: {first sentence of reason}"`, which inverted the safety signal for prescription drugs used as undeclared adulterants (metformin, meloxicam, sibutramine, sildenafil, tadalafil) and produced useless encyclopedic blurbs for everything else.

The Flutter UI now composes the banner from structured fields only (`statusLabel + productName + commonNames`). No derived medical copy anywhere.

The fix is **upstream, not Flutter-side.** The pipeline should author three new fields per entry with safety-team review, and the Flutter asset remap should pass them through verbatim. Details in "Path C Spec" below.

While the door is open, there are **six other silent-break footguns** in the pipeline→Flutter safety path that need an audit pass in the same sprint. They're listed at the bottom — each one is a silent-failure risk (no crash, no log, just missing warnings). Do NOT ship Path C without auditing them.

Good catch today: the core Flutter issue was that a single derived template string was driving user-facing medical warnings with no authoring review. That class of footgun is the #1 thing to eliminate from this data layer.

---

## What Shipped Today (Flutter — Sprint 27.6 Path A)

### Files changed

| # | File | Change |
|---|---|---|
| 1 | `assets/reference_data/banned_recalled_ingredients.json` | Stripped `warning_message` from all 139 entries via `jq`. Updated `_metadata.migration_note` to explain the Sprint 27.6 removal and point to this handoff. |
| 2 | `lib/services/stack/recalled_ingredient_result.dart` | Removed `final String warningMessage` field, removed `required this.warningMessage` constructor arg, added comment explaining Path C replacement plan (`safety_warning` + `safety_warning_one_liner` + `ban_context`). |
| 3 | `lib/features/stack/providers/stack_safety_providers.dart` | Removed `warningMessage` read + pass-through at ingredient-alert construction. Switched `ReferenceDataRepository` instantiation from `new` → `ref.watch(referenceDataRepositoryProvider)` so integration tests can inject canned payloads. |
| 4 | `test/core/reference_data_contract_test.dart` | Replaced positive `containsPair('warning_message', ...)` with a negative assertion `expect(first.containsKey('warning_message'), isFalse)` that will fail loud if a future remap silently re-derives the field. |
| 5 | `test/features/stack/recalled_ingredient_integration_test.dart` (**new**) | 3 tests: positive match (`sibutramine`), negative match (`vitamin_d`), case-insensitive match (`SIBUTRAMINE` → `sibutramine`). Uses in-memory DBs + fake repo, no asset load. |

### Test counts

- 452/452 passing (449 before + 3 new integration tests)
- `flutter analyze` clean
- `flutter test` green

### What the banner looks like now

**Before (Flutter-derived warning_message):**
> ⚠️ BANNED — "Citrus Fit 1200" contains sibutramine. Sibutramine is banned: Sibutramine (Meridia) was an FDA-approved prescription weight-loss drug (serotonin-norepinephrine reuptake inhibitor) that FDA withdrew from the US market in October 2010 after a large cardiovascular outcomes trial

**After (structured fields only):**
> ⚠️ BANNED — "Citrus Fit 1200" contains sibutramine

The post-Path-A banner is shorter and safer but gives the user less "why" context. That gap is exactly what Path C fills — a proper authored `safety_warning_one_liner` like:

> "Sibutramine is an FDA-withdrawn prescription weight-loss drug. If your supplement contains it, stop and consult a doctor — serious cardiovascular risk."

That string is authored by a clinician, not derived from an encyclopedic definition. That's the whole point.

---

## Why — the audit findings (with real examples)

These are real strings that were rendering in the app until today. Every one was produced by the derivation template `"{standard_name} is {recall_status}: {reason.split('. ')[0]}"`.

### 1. ADULTERANT_METFORMIN — inverted safety signal (most dangerous)

**Old derived warning_message:**
> "Metformin is banned: Metformin is a prescription antidiabetic drug (biguanide class) that lowers blood glucose by reducing hepatic glucose production"

**Why it's wrong:** Metformin is NOT banned as a medication. It's a first-line, FDA-approved prescription drug that ~85 million people worldwide take daily. It's only flagged in this dataset as an *undeclared adulterant in supplements* (e.g., diabetes-marketed herbal formulas that spike product with real metformin without disclosure).

A patient on prescribed metformin reads this banner in our app and believes their medication was just banned. That's clinical chaos. A provider sees their patient's app flagging metformin as banned and loses trust in the product. The `recall_status: banned` applies to *the undeclared-adulterant context*, not *the molecule in prescribing*.

Same pattern breaks meloxicam, sibutramine, sildenafil, tadalafil, phenolphthalein — every entry where `canonical_id` starts with `adulterant_` or names a prescription drug.

### 2. ADULTERANT_MELOXICAM — same failure mode

**Old derived:**
> "Meloxicam is banned: Meloxicam (Mobic) is a prescription NSAID selective for COX-2, used for arthritis pain"

Reads as "Mobic is banned." Mobic is not banned. It is prescribed daily.

### 3. BANNED_ADD_ORANGE_B — useless blurb

**Old derived:**
> "Orange B is watchlist: Synthetic orange dye"

No user learns anything from "is watchlist: Synthetic orange dye." They already see the ingredient name. The derivation adds zero signal and cannot be actioned.

### 4. BANNED_EPHEDRA — buries the lead

**Old derived:**
> "Ephedra is banned: Ephedra (ma huang, Ephedra sinica) alkaloids — primarily ephedrine and pseudoephedrine — are potent sympathomimetics that stimulate the cardiovascular system and central nervous system"

Reads as a pharmacology textbook intro. What the user actually needs to know — "FDA banned ephedra in 2004 after 155 deaths, most from cardiovascular events" — is nowhere. The reason field has it in sentence 3. The template only took sentence 1.

### 5. BANNED_DMAA — encyclopedic, not a warning

**Old derived:**
> "DMAA is banned: DMAA (1,3-dimethylamylamine) is a synthetic aliphatic amine marketed falsely as derived from geranium oil"

Tells the user what DMAA is, not what it does to them. The clinical signal — "DMAA raises blood pressure acutely, linked to strokes and cardiac arrests in otherwise-healthy users, FDA enforcement since 2012" — is absent.

### Root cause

The derivation template assumed `reason[0]` (first sentence of `reason`) was a warning sentence. It is not — it's an encyclopedic definition. The two are structurally different types of text. No Flutter-side template can bridge that gap safely. **Medical-grade user-facing text must be authored, not derived.**

---

## Path C Spec — what the pipeline needs to implement

### Field 1: `ban_context` (enum, required)

Disambiguates the overloaded `status: banned`. Current `status` conflates four real-world cases. They must be separable for safe UI copy.

| Value | Meaning | Example canonical_ids |
|---|---|---|
| `substance` | The molecule itself is controlled / illegal in the US as a substance. | `banned_dmaa`, `banned_ephedra`, `banned_phenibut`, `banned_bmpea` |
| `adulterant_in_supplements` | The molecule is a legitimate prescription drug (or elsewhere-controlled) that has been found undeclared in supplements. Using it as prescribed is fine. | `adulterant_metformin`, `adulterant_meloxicam`, `adulterant_sildenafil`, `adulterant_tadalafil`, `adulterant_phenolphthalein` |
| `watchlist` | FDA warning-letters issued but no formal ban. Evidence of harm accumulating. | `banned_add_octopamine`, `banned_add_orange_b`, `banned_add_deterenol` |
| `export_restricted` | Restricted in specific jurisdictions (EU, Canada, AU) but not US. | (none currently — reserved) |

The Flutter copy rule (once we ship it) is:

- `substance` → "stop and consult a doctor"
- `adulterant_in_supplements` → "if your **supplement** contains it, stop and consult a doctor — this does NOT apply to the medication when prescribed"
- `watchlist` → "emerging concern — FDA has issued warning letters"
- `export_restricted` → "restricted outside the US"

### Field 2: `safety_warning` (string, ≤200 chars, required)

One or two sentences, authored. User-facing. Medical-grade.

**Validator rules (enforce at build time in the pipeline):**
- MUST NOT start with `"{standard_name} is "` (this catches any accidental re-derivation from the old template)
- MUST NOT start with `"<name> is a prescription"`, `"<name> is a synthetic"`, `"<name> is an FDA"` — these were the old encyclopedic openers
- Length: 50 ≤ len ≤ 200
- MUST contain at least one verb that describes user action OR risk (one of: `stop`, `avoid`, `consult`, `risk`, `linked`, `caused`, `associated with`)
- For `ban_context: adulterant_in_supplements`: MUST contain a phrase matching the pattern `(in|within|found in|as an adulterant in).{0,40}(supplement|product|dietary)` — this is the clinical safety guardrail.

### Field 3: `safety_warning_one_liner` (string, ≤80 chars, required)

The banner form. Exactly one short sentence. What appears in-app on the stack safety card.

**Validator rules:**
- MUST NOT start with `"{standard_name} is "`
- Length: 20 ≤ len ≤ 80
- MUST end with `.` or `!`
- MUST NOT contain semicolons (too complex for a banner)

### Example entries (author these, paste into `scripts/data/banned_recalled_ingredients.json`)

```json
{
  "id": "adulterant_metformin",
  "standard_name": "Metformin (as undeclared adulterant)",
  "status": "banned",
  "ban_context": "adulterant_in_supplements",
  "safety_warning": "Metformin is a prescription diabetes drug. When found undeclared in supplements, it can cause dangerous blood sugar drops. If your supplement lists it or has tested positive, stop and talk to your doctor. This does not apply to metformin prescribed by a physician.",
  "safety_warning_one_liner": "Prescription drug spiked into supplements — stop the supplement, keep your prescription.",
  "reason": "Metformin is a prescription antidiabetic drug...",
  "..."
}

{
  "id": "banned_ephedra",
  "standard_name": "Ephedra (ma huang)",
  "status": "banned",
  "ban_context": "substance",
  "safety_warning": "FDA banned ephedra in dietary supplements in 2004 after it was linked to strokes, heart attacks, and over 155 deaths — many in otherwise-healthy users. Stop and consult a doctor.",
  "safety_warning_one_liner": "FDA-banned stimulant linked to strokes and heart attacks. Stop immediately.",
  "reason": "Ephedra (ma huang, Ephedra sinica) alkaloids...",
  "..."
}

{
  "id": "banned_dmaa",
  "standard_name": "DMAA (1,3-dimethylamylamine)",
  "status": "banned",
  "ban_context": "substance",
  "safety_warning": "DMAA is an unapproved synthetic stimulant that raises blood pressure acutely and has been linked to strokes and cardiac arrests in healthy users. FDA has pursued enforcement since 2012. Stop and consult a doctor.",
  "safety_warning_one_liner": "Unapproved stimulant linked to strokes and cardiac arrests. Stop immediately.",
  "reason": "DMAA (1,3-dimethylamylamine) is a synthetic aliphatic amine...",
  "..."
}

{
  "id": "banned_add_orange_b",
  "standard_name": "Orange B",
  "status": "watchlist",
  "ban_context": "watchlist",
  "safety_warning": "Orange B is a synthetic dye approved by FDA only for hot dog and sausage casings — not for dietary supplements. Its presence in a supplement indicates undisclosed colorant use and possible mislabeling.",
  "safety_warning_one_liner": "Synthetic dye not approved for supplements — possible mislabeling.",
  "reason": "Synthetic orange dye...",
  "..."
}
```

### Authoring process

- Drafting: pipeline maintainer + one clinical advisor (MD, PharmD, or RDN with regulatory background).
- Review: safety-team sign-off on each of the 139 entries before merging — track in a checklist file like `scripts/data/safety_warning_review_checklist.md`.
- Budget: ~15 min/entry × 139 = ~35 hours. Batch by `ban_context` category (all adulterants together, all substances together) — copy patterns repeat.
- Non-goal: do NOT auto-generate these with an LLM. An LLM can draft for human review but must not ship unreviewed. This is the whole lesson from today.

### Build-time validator

Add to `scripts/` (e.g. `validate_banned_recalled.py`) and wire into CI:

```python
BAD_OPENERS_PATTERN = re.compile(
    r"^[A-Z][a-z_]+ is (a |an |the )?(prescription|synthetic|FDA)",
    re.IGNORECASE,
)

def validate_entry(e):
    errors = []
    sw = e["safety_warning"]
    if sw.startswith(f"{e['standard_name']} is "):
        errors.append("safety_warning starts with derivation template")
    if BAD_OPENERS_PATTERN.match(sw):
        errors.append("safety_warning uses encyclopedic opener")
    if not (50 <= len(sw) <= 200):
        errors.append(f"safety_warning length {len(sw)} outside [50, 200]")
    if not any(v in sw.lower() for v in ("stop", "avoid", "consult", "risk", "linked", "caused", "associated")):
        errors.append("safety_warning has no risk/action verb")
    if e["ban_context"] == "adulterant_in_supplements":
        if not re.search(r"(in|within|found in|as an adulterant in).{0,40}(supplement|product|dietary)", sw):
            errors.append("adulterant entry missing 'in supplement' clinical guardrail")

    one = e["safety_warning_one_liner"]
    if one.startswith(f"{e['standard_name']} is "):
        errors.append("one_liner starts with derivation template")
    if not (20 <= len(one) <= 80):
        errors.append(f"one_liner length {len(one)} outside [20, 80]")
    if not one.endswith((".", "!")):
        errors.append("one_liner missing terminal punctuation")
    if ";" in one:
        errors.append("one_liner contains semicolon")

    if e["ban_context"] not in ("substance", "adulterant_in_supplements", "watchlist", "export_restricted"):
        errors.append(f"invalid ban_context: {e['ban_context']}")

    return errors
```

Fail the build on any entry with errors. No soft warnings. This is the contract.

### Remap to Flutter

Once the pipeline ships these fields, the Flutter-side remap script should pass them through verbatim (no derivation):

| Pipeline field | Flutter asset field |
|---|---|
| `ban_context` | `ban_context` (new) |
| `safety_warning` | `safety_warning` (new) |
| `safety_warning_one_liner` | `safety_warning_one_liner` (new) |

The Flutter `RecalledIngredientAlert` model gains three fields, `bannerMessage` uses `safety_warning_one_liner` verbatim, and a new `detailMessage` getter returns `safety_warning`. No string composition on the Flutter side.

When this ships, the Flutter contract test **must flip back** to a positive assertion AND keep the negative assertion for `warning_message`:

```dart
// Path C landed — assert new fields present
expect(first, containsPair('safety_warning', isA<String>()));
expect(first, containsPair('safety_warning_one_liner', isA<String>()));
expect(first, containsPair('ban_context', isA<String>()));

// Keep the negative assertion — the removed field must NEVER come back
expect(first.containsKey('warning_message'), isFalse,
    reason: 'Old derived field must not reappear — see Sprint 27.6.');
```

---

## Other Silent-Break Footguns to Audit (same sprint)

Every one of these is a "no crash, no log, just wrong" failure mode. Flutter has no way to detect them at build time without pipeline-side invariants. All six should be audited in the same sprint as Path C because the cost of the audit once is small and the cost of a silent regression in production is medical-grade.

### A. `contains_*` hazard flags — derivation provenance unclear

The export schema has boolean flags like `contains_stimulants`, `contains_sedatives`, `contains_blood_thinners`, `contains_omega3`, `contains_probiotics`, `contains_collagen`, `contains_adaptogens`, `contains_nootropics`.

**Questions the pipeline dev should answer:**

1. What is the source-of-truth list for each flag? (e.g., what makes an ingredient "a stimulant" vs "a nootropic"?) Is it a keyword list? A cross-reference against IQM tags? A manual mapping?
2. Where is the list versioned? (if keyword list, which file; if IQM join, which tag column)
3. What happens when a new ingredient appears in DSLD that matches no list? Silent `false`, or error?
4. Are the flags recomputed on every pipeline run, or cached? If cached, what invalidates?
5. For safety-relevant flags (`contains_blood_thinners`, `contains_stimulants`): is the list curated or auto-derived? Curated is required for these — auto-derived is a silent-safety risk.
6. Is there a gold-standard test set (e.g., 20 known-stimulant products, 20 known-non-stimulant) in the pipeline test suite that would fail if the derivation regressed?

**Required:** a short section in the pipeline README listing, per flag, the source list, file path, test set, and owner. If auto-derived, add a test that fails on any known-false-positive or known-false-negative.

### B. `has_recalled_ingredient` — computation + rebuild guarantee

The `has_recalled_ingredient` integer flag on `products_core` is what makes the stack safety check fast (pre-joined).

**Questions:**

1. Where in the pipeline is this computed? (Expected: build_final_db.py or equivalent, iterating every product and checking `key_ingredient_tags` intersection with recall canonical_ids.)
2. Is it recomputed on every full rebuild, or only when the recall list changes?
3. What happens if the recall list gets a new canonical_id between builds? The flag goes stale. Is there a CI check that asserts "every canonical_id in recall list appears on at least one product with `has_recalled_ingredient = 1`"?
4. Is the intersection case-insensitive? (Flutter side is — lowercased in `canonicalIdsForProduct`. Pipeline must match or 12 uppercase-tag products silently slip through.)
5. If a product's `key_ingredient_tags` JSON is malformed / empty string / null, does the flag default to 0 (correct) or skip the row (hiding the error)?

**Required:** a test in the pipeline that:
- Asserts the flag is recomputed from `key_ingredient_tags` on every run (not carried over from prior DB).
- Asserts case-insensitive match (build a test product with `["SIBUTRAMINE"]`, confirm flag = 1).
- Asserts every active recall canonical_id matches ≥1 product OR is explicitly marked `no_active_occurrences: true` in the recall list.

### C. Canonical-ID invariants (lowercase + cross-reference integrity)

Today's integration test `case-insensitive canonical_id match` guards the Flutter side. The pipeline side needs the same guarantee.

**Invariants to enforce:**

1. Every `canonical_id` in `banned_recalled_ingredients.json` is lowercase (`[a-z0-9_]+`). Build fails otherwise.
2. Every `key_ingredient_tags` entry in `products_core` is lowercase before export.
3. Every `common_names[]` string is lowercase (or consistently-cased — pick one, enforce).
4. No whitespace in canonical_ids.
5. Cross-reference: every `synergy_cluster.ingredients[]` canonical_id either exists in IQM `canonical_id` OR is flagged in `_metadata.orphan_ingredients`. Orphans are allowed, but unknown orphans break synergy matching silently.

**Required:** a pipeline validator that fails on any canonical_id violating the lowercase/whitespace rule. Run it on every `scripts/data/*.json` that has canonical_ids.

### D. Top-level key stability — the "direct-copy" failure mode

This is the class of bug the Flutter contract test was written for (Sprint 27.5). The recall list uses Flutter key `recalled_ingredients` while the pipeline output has `ingredients`. Synergy uses Flutter `clusters` vs pipeline `synergy_clusters`. Any contributor who "refreshes the asset" by copying the pipeline file in place silently wipes the feature — Flutter reads `data['recalled_ingredients']`, gets `null`, coalesces to `const []`, and 139 recall entries disappear.

**Required:**

1. Add a `_metadata.schema_version` and `_metadata.top_level_key` field to every `scripts/data/*.json` that Flutter bundles.
2. Document in the pipeline README the exact key-rename table between pipeline format and Flutter format.
3. Ship a `scripts/export_to_flutter.py` (or equivalent) that performs the remap, does NOT allow direct copy, and fails if the Flutter contract test file isn't present.
4. The Flutter contract test already asserts the pipeline key is NOT present — don't break that assertion by helpfully copying both keys.

### E. `bonus_points` authoring in `synergy_cluster.json`

Current state: 5 clusters have authored bonus_points; 53 are defaulted by evidence_tier (strong→2, moderate/limited→1). The user-facing impact is that every product with those 53 clusters gets the same bonus regardless of real synergy magnitude — D+K2 scores the same as a weak moderate-tier pair.

**Required:**

1. Pipeline side authors per-cluster `bonus_points` on the 53 defaulted clusters, with safety-team review (not as critical as recall warnings, but still material to the user-facing score).
2. Flag in `_metadata.migration_note` which clusters are authored vs defaulted. Today all 58 are marked ambiguously.
3. Contract test on Flutter side: assert that `bonus_points` is present on every cluster AND in range [0, 5] (sanity). Already exists; keep it.

### F. `regulatory_basis` in banned_recalled — also derived

Same hazard family as `warning_message`. Current `regulatory_basis` strings are derived from `jurisdictions[]` (e.g., "FDA — multiple enforcement actions"). Some are fine, some are too vague to be actionable.

**Required:**

1. Short audit (1-2 hours): read all 139 `regulatory_basis` strings, flag any that are too generic to be actionable.
2. Pipeline-side: add `regulatory_basis` as an authored field with a validator rule (must cite specific regulation or enforcement action, not just agency name).
3. Or: if vagueness is acceptable, document that explicitly in `_metadata`.

---

## Opportunistic Pass-Through (cheap wins while the door is open)

Two fields already exist upstream but are not in the Flutter asset. Adding them costs one line each in the remap and unlocks downstream features:

1. `legal_status_enum` (pipeline → Flutter as `legal_status`) — precise per-jurisdiction legal status. Lets Flutter eventually show "banned in US + EU" vs "banned in US only" without Flutter-side logic.
2. `references_structured` (pipeline → Flutter as `references[]`) — structured citations (PMID, FDA docket, NEJM citation). Today the Flutter app has no citation support on recall warnings — this unlocks a "Why is this flagged?" detail pane without any further pipeline work.

Do these in the same remap script as Path C. They're additive and free.

---

## Testing Invariants (patterns Flutter uses — pipeline should mirror)

These three patterns are the discipline that caught today's issue. The pipeline should adopt the same discipline for every asset it emits.

### Pattern 1: Contract test with positive AND negative assertion

For every top-level key the Flutter asset uses, assert:
- the Flutter key IS present
- the pipeline-source key is NOT present

Both sides of the assertion matter. The positive assertion catches accidental deletion. The negative assertion catches accidental direct-copy from pipeline source. See `test/core/reference_data_contract_test.dart` for the pattern.

### Pattern 2: Integration test with injected payload, not loaded asset

Flutter's new `test/features/stack/recalled_ingredient_integration_test.dart` proves the scan→flag path end-to-end without loading the real bundled asset. It:

- Boots in-memory `CoreDatabase` + `UserDatabase`
- Seeds one product row + one stack entry
- Overrides `referenceDataRepositoryProvider` with a `_FakeReferenceDataRepository` returning a canned 1-entry recall payload
- Asserts the provider future returns the violation

The advantage over loading the real asset: tests are deterministic regardless of data drift, fast (<50ms each), and focused on the match logic — if they fail, it's the match logic, not the data.

Pipeline side should do the same: every feature that reads `scripts/data/*.json` should have a unit test that injects a 1-3-entry fixture, not one that loads the production file. Production-file tests belong in a separate contract-test suite.

### Pattern 3: Case-insensitive match test

Always test the case-insensitive match path explicitly. It's the exact class of bug that would silently let 12 uppercase-tag products slip past a lowercase-keyed recall list. Flutter has a test for it now — pipeline should too.

---

## Cross-Repo Coordination Checklist

- [ ] Pipeline: land `ban_context` + `safety_warning` + `safety_warning_one_liner` in `scripts/data/banned_recalled_ingredients.json` with safety-team review on every entry.
- [ ] Pipeline: add `scripts/validate_banned_recalled.py` (rules above) and wire into CI.
- [ ] Pipeline: audit + author `contains_*` derivation source lists (see Footgun A).
- [ ] Pipeline: add `has_recalled_ingredient` rebuild + case-insensitive match test (Footgun B).
- [ ] Pipeline: enforce canonical_id lowercase invariant across all JSON files (Footgun C).
- [ ] Pipeline: add `_metadata.schema_version` + `_metadata.top_level_key` to every Flutter-bundled JSON (Footgun D).
- [ ] Pipeline: author remaining 53 `bonus_points` values in `synergy_cluster.json` (Footgun E).
- [ ] Pipeline: audit `regulatory_basis` accuracy (Footgun F).
- [ ] Pipeline: opportunistic pass-through of `legal_status_enum` + `references_structured`.
- [ ] Flutter: update remap script to consume new fields; flip contract test to positive assertion on `safety_warning_*` + keep negative on `warning_message`.
- [ ] Flutter: wire `safety_warning_one_liner` into `RecalledIngredientViolation.bannerMessage` verbatim; add `detailMessage` getter for `safety_warning`.
- [ ] Flutter: add integration test coverage for `ban_context` branching in banner copy.

---

## Reference paths

**Flutter repo** (`/Users/seancheick/PharmaGuide ai/`):

- `assets/reference_data/banned_recalled_ingredients.json` — bundled asset (post-Sprint 27.6 Path A)
- `lib/features/stack/providers/stack_safety_providers.dart` — consumer of `recalled_ingredients[]`, match logic around line 344
- `lib/services/stack/recalled_ingredient_result.dart` — model (`RecalledIngredientAlert`, `RecalledIngredientViolation`, `RecalledIngredientsReport`)
- `test/core/reference_data_contract_test.dart` — schema contract test
- `test/features/stack/recalled_ingredient_integration_test.dart` — scan→flag integration test
- `SPRINT_TRACKER.md` Sprint 27.6 section — full Path A + Path C plan

**Pipeline repo** (`/Users/seancheick/Downloads/dsld_clean/`):

- `scripts/data/banned_recalled_ingredients.json` — authoritative recall list (143 entries upstream, 139 after `match_mode == "active"` filter)
- `scripts/data/synergy_cluster.json` — authoritative synergy clusters
- `scripts/audit_banned_recalled_accuracy.py` — existing audit script (extend for Path C validator)
- `scripts/data/banned_recalled_accuracy_report.json` — latest audit output

---

## Why we're doing this now

A single derived template string was producing user-facing medical warnings for 139 ingredients with zero safety-team review. On an average day, that's a UX paper cut. On the day a user on prescribed metformin reads "Metformin is banned" and stops taking their diabetes medication, that's a clinical incident that ships from our repo.

This sprint closes the footgun — authored strings, validator-enforced, safety-team-reviewed, contract-tested. Six other footguns in the same data path get audited in the same pass so we don't have this conversation again in three months.

Good catch today. Ship Path C clean.
