# Pipeline Score Explanation and Identity Integrity Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct label-to-canonical identity conflicts before any v4 route scores them, preserve label-native display names/forms, and emit scorer-owned facts that explain the public pillars.

**Architecture:** Add one pure identity-integrity module that extracts line-level label evidence, resolves a disposition, and owns the deterministic label-fidelity normalization. Integrate it at the ingredient-quality boundary so all v4 routes consume the same repaired or rejected rows. Add a release audit over enriched outputs, then add a separate score-explanation adapter that converts existing module metadata into versioned public facts without changing scoring math.

**Tech Stack:** Python 3.13, pytest 9 through `scripts/test.sh`, existing v4 scorer/export pipeline.

**Repository target:** Execute every path and command in this plan from the isolated pipeline worktree at `/Users/seancheick/.config/superpowers/worktrees/dsld_clean/score-explanation-identity`. The plan file lives in the Flutter repository only so both halves share one reviewed handoff; none of the `scripts/...` paths refer to the Flutter checkout.

---

### Task 1: Pure label identity and fidelity contract

**Files:**
- Create: `scripts/identity_integrity.py`
- Create: `scripts/tests/test_identity_integrity.py`

- [ ] **Step 1: Write failing tests for the disposition contract**

Cover `clean`, `repaired`, `taxonomy_only`, `identity_conflict`, and `missing_display_label`. Include the Nature Made shape where the supplied DHA taxonomy conflicts with structured line evidence `EPA (Eicosapentaenoic Acid)` and the form says `as Ethyl Esters`; the result must be `repaired`, canonical `epa`, display name `EPA`, display form `as Ethyl Esters`.

```python
def test_structured_epa_label_repairs_conflicting_dha_taxonomy():
    decision = resolve_identity(
        row={
            "raw_source_text": "Docosahexaenoic Acid Ethyl Ester",
            "ingredientGroup": "EPA (Eicosapentaenoic Acid)",
            "forms": [{"prefix": "as", "name": "Ethyl Esters"}],
        },
        supplied_canonical_id="dha",
        resolve_candidate=fake_resolver,
    )
    assert decision.disposition == "repaired"
    assert decision.canonical_id == "epa"
    assert decision.label_display_name == "EPA"
    assert decision.label_display_form == "as Ethyl Esters"
```

- [ ] **Step 2: Run the new tests and verify RED**

Run: `scripts/test.sh fast scripts/tests/test_identity_integrity.py`

Expected: FAIL because `identity_integrity` does not exist.

- [ ] **Step 3: Implement the minimal pure module**

Implement:

- `normalize_label_display(value)` with the exact approved order: remove Unicode trademark glyphs, NFKC, remove parenthesized TM/R/SM case-insensitively, collapse to one ASCII space, trim.
- `extract_label_evidence(row)` reading label-native name, structured `ingredientGroup`, `label_nutrient_context`, `alternateNames`, and line-level form fields only. Product marketing text is excluded.
- `IdentityDecision` with disposition, source/display fields, canonical before/after, evidence, scoreability, and rationale.
- `resolve_identity(...)` where unambiguous structured line evidence outranks taxonomy/UNII, multiple structured canonicals become a conflict, weak/no direct identity becomes `taxonomy_only`, and no displayable label becomes `missing_display_label`.
- A single `is_identity_scoreable(disposition)` helper.

- [ ] **Step 4: Run the tests and verify GREEN**

Run: `scripts/test.sh fast scripts/tests/test_identity_integrity.py`

Expected: PASS.

Run: `source scripts/python_env.sh && "$PG_PYTHON" -m py_compile scripts/identity_integrity.py`

Expected: no output and exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/identity_integrity.py scripts/tests/test_identity_integrity.py
git commit -m "feat(identity): define label-first integrity contract"
```

### Task 2: Enricher integration before scoreability

**Files:**
- Modify: `scripts/enrich_supplements_v3.py`
- Modify: `scripts/tests/test_scorable_classification.py`

- [ ] **Step 1: Add failing enrichment regressions**

Add a complete active-row fixture for the 360 mg EPA / 300 mg DHA case. Assert:

- the 360 mg row is canonical `epa`, not `dha`;
- label display remains `EPA` / `as Ethyl Esters`;
- the 300 mg row remains `dha`;
- unresolved high-specificity conflicts are absent from `ingredients_scorable`;
- every active IQD row has exactly one identity disposition and source label key.

- [ ] **Step 2: Verify RED with the pinned runner**

Run: `scripts/test.sh fast scripts/tests/test_scorable_classification.py -k identity_integrity`

Expected: FAIL on missing disposition and incorrect canonical.

- [ ] **Step 3: Integrate the resolver at the IQD boundary**

In `_collect_ingredient_quality_data`:

- resolve label identity before `_build_quality_entry` is finalized;
- when `repaired`, rerun the existing IQM matcher with the approved label identity/form so canonical ID, standard name, form ID, and bio score all come from one match;
- stamp `source_label_key`, literal/display name/form, identity disposition, original canonical, evidence, and resolution rationale;
- set conflict/missing-label rows non-scoreable and route them to skipped diagnostics;
- project repaired identity metadata back to the matching `activeIngredients` row before downstream taxonomy, interaction, and v4 work runs;
- keep `ingredients`, `ingredients_scorable`, and `ingredients_skipped` as references to the same stamped row objects so no copy can drift.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
scripts/test.sh fast scripts/tests/test_scorable_classification.py -k identity_integrity
source scripts/python_env.sh && "$PG_PYTHON" -m py_compile scripts/enrich_supplements_v3.py
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/enrich_supplements_v3.py scripts/tests/test_scorable_classification.py
git commit -m "fix(identity): resolve label conflicts before scoring"
```

### Task 3: Strict scoring-input identity guard

**Files:**
- Modify: `scripts/scoring_input_contract.py`
- Modify: `scripts/tests/test_scoring_input_contract.py`

- [ ] **Step 1: Add failing strict-contract tests**

Reject `identity_conflict` and `missing_display_label` even if a malformed upstream row still says `scoreable_identity=true`. Require a valid disposition in strict mode while retaining an old-batch compatibility path only when strict mode is explicitly disabled.

- [ ] **Step 2: Verify RED**

Run: `scripts/test.sh fast scripts/tests/test_scoring_input_contract.py -k identity_integrity`

Expected: FAIL because the shared contract still accepts the malformed row.

- [ ] **Step 3: Implement the shared guard**

Use the disposition vocabulary and `is_identity_scoreable` helper from `identity_integrity.py`; do not copy the status list into this module.

- [ ] **Step 4: Verify GREEN and compile**

```bash
scripts/test.sh fast scripts/tests/test_scoring_input_contract.py
source scripts/python_env.sh && "$PG_PYTHON" -m py_compile scripts/scoring_input_contract.py
```

- [ ] **Step 5: Commit**

```bash
git add scripts/scoring_input_contract.py scripts/tests/test_scoring_input_contract.py
git commit -m "fix(scoring): reject unresolved ingredient identity"
```

### Task 4: Module-agnostic identity release audit

**Files:**
- Create: `scripts/audit_identity_integrity.py`
- Create: `scripts/tests/test_audit_identity_integrity.py`
- Modify: `scripts/release_full.sh`

- [ ] **Step 1: Write failing audit and release-wiring tests**

The audit must emit one disposition record for every active row, including clean rows. Tests must derive expected modules from `scoring_v4.router.VALID_CLASSES`, fail when a route fixture lacks dispositions, fail on conflict/missing display, and pass repaired/clean/permitted taxonomy-only rows.

- [ ] **Step 2: Verify RED**

Run: `scripts/test.sh fast scripts/tests/test_audit_identity_integrity.py`

Expected: FAIL because the audit does not exist.

- [ ] **Step 3: Implement the audit CLI**

Scan canonical enriched-output paths, classify each product through `class_for_product`, and write a deterministic summary containing product ID, route, source path, literal label fields, supplied/final canonical, disposition, scoreability, and rationale. Exit non-zero for unresolved conflicts, missing display labels, canonical mismatch after repair, or missing dispositions. Registry-wide route coverage is enforced by the test inventory; a targeted runtime batch is not required to contain every possible route.

- [ ] **Step 4: Wire the strict gate before final DB assembly**

Add a `run_strict_gate "active identity integrity" ...` call inside the branch that is about to assemble a newer final DB. It scans the enriched outputs that triggered assembly; an auto-skipped release with only an already-gated `dist/` artifact does not fail because an old products directory is absent. Tests must not trigger enrichment or the full release.

- [ ] **Step 5: Run focused tests and shell syntax validation**

```bash
scripts/test.sh fast scripts/tests/test_audit_identity_integrity.py
source scripts/python_env.sh && "$PG_PYTHON" -m py_compile scripts/audit_identity_integrity.py
bash -n scripts/release_full.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/audit_identity_integrity.py scripts/tests/test_audit_identity_integrity.py scripts/release_full.sh
git commit -m "feat(release): gate active identity integrity"
```

### Task 5: Label-native final blob export

**Files:**
- Modify: `scripts/build_final_db.py`
- Modify: `scripts/tests/test_build_final_db.py`
- Modify: `scripts/tests/test_label_fidelity_contract.py`

- [ ] **Step 1: Add failing export tests**

Assert `label_display_name` and `label_display_form` are emitted and drive `display_label` / `display_form_label`; canonical `standard_name` never replaces them. Assert the normalization equality contract and missing-label release failure. Lock the 179681 display to `EPA` plus `as Ethyl Esters` while canonical remains `epa`.

- [ ] **Step 2: Verify RED**

Run: `scripts/test.sh fast scripts/tests/test_build_final_db.py -k label_identity`

Expected: FAIL on absent fields or canonical substitution.

- [ ] **Step 3: Update the export seam**

Make `_compute_display_label` and `_compute_form_contract` prefer IQD's approved label-display fields. Emit literal source fields, disposition, source label key, identity rationale, and canonical-before-repair for auditability. Fail the export contract for conflict/missing-display rows rather than silently falling back to `standard_name`.

- [ ] **Step 4: Run focused fidelity tests**

```bash
scripts/test.sh fast scripts/tests/test_build_final_db.py -k "label_identity or omega3"
scripts/test.sh fast scripts/tests/test_label_fidelity_contract.py
source scripts/python_env.sh && "$PG_PYTHON" -m py_compile scripts/build_final_db.py
```

Expected: PASS, with artifact-backed tests still reported separately if no build fixture exists.

- [ ] **Step 5: Commit**

```bash
git add scripts/build_final_db.py scripts/tests/test_build_final_db.py scripts/tests/test_label_fidelity_contract.py
git commit -m "fix(export): preserve label-native ingredient identity"
```

### Task 6: Pipeline-authored pillar explanation facts

**Files:**
- Create: `scripts/scoring_v4/pillar_explanations.py`
- Create: `scripts/tests/test_v4_pillar_explanations.py`
- Modify: `scripts/scoring_v4/quality_score.py`

- [ ] **Step 1: Write failing explanation-contract tests**

For an omega result, assert:

- dose emits `epa_dha_per_day` from `dimensions.dose.metadata.per_day_mid_mg`;
- formulation emits the detected omega form from its own metadata;
- schema version is `1` and facts have stable IDs;
- absent inputs emit no fact;
- non-omega modules retain reason-only pillars;
- score/max/reason and total score are byte-for-byte unchanged.

- [ ] **Step 2: Verify RED**

Run: `scripts/test.sh fast scripts/tests/test_v4_pillar_explanations.py`

Expected: FAIL because the adapter does not exist.

- [ ] **Step 3: Implement the explanation adapter**

Build facts only from the module breakdown used by the scorer. Map internal omega form codes to consumer copy in this pipeline module, format quantities deterministically, omit unknowns, and attach optional `explanation` blocks after pillar arithmetic. Do not recalculate scores or generate "biggest opportunity" prose.

- [ ] **Step 4: Run focused and existing v4 tests**

```bash
scripts/test.sh fast scripts/tests/test_v4_pillar_explanations.py
scripts/test.sh fast scripts/tests/test_v4_quality_score.py scripts/tests/test_v4_pillar_contract_gate.py scripts/tests/test_v4_pillar_consumer_copy.py
source scripts/python_env.sh && "$PG_PYTHON" -m py_compile scripts/scoring_v4/pillar_explanations.py scripts/scoring_v4/quality_score.py
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/scoring_v4/pillar_explanations.py scripts/scoring_v4/quality_score.py scripts/tests/test_v4_pillar_explanations.py
git commit -m "feat(scoring): emit verified pillar explanation facts"
```

### Task 7: Pipeline regression verification

**Files:**
- Modify: `scripts/tests/test_audit_identity_integrity.py` only if a missing edge case is found

- [ ] **Step 1: Run the full fast suite**

Run: `scripts/test.sh fast`

Expected: all fast tests pass.

- [ ] **Step 2: Run the release test group without executing a release**

Run: `scripts/test.sh release`

Expected: all release gates pass or artifact-dependent tests explicitly report the missing targeted build. Do not run `release_full.sh`.

- [ ] **Step 3: Run a targeted 179681 fixture/build if source data is available**

Use the smallest existing brand/stage command that contains DSLD `179681`; do not run the whole corpus. Verify canonical EPA/DHA, 660 mg total, label-native display, pillar facts, and zero identity audit failures.

- [ ] **Step 4: Commit any test-only closeout**

```bash
git add scripts/tests/test_audit_identity_integrity.py
git commit -m "test(identity): close pipeline integrity regressions"
```
