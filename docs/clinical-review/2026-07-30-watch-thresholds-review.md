# Clinical Review: Depletion Watch Thresholds (Round 1)

**Date drafted:** 2026-07-30
**Drafted by:** research draft (AI) — evidence verified against PubMed
**Decision needed:** Yes / No per row
**Status:** All three ship as `proposed` and are **inert**. Nothing below is
visible to any user until a reviewer changes `watch_review_status` to
`approved`. A release gate enforces this.

---

## What a threshold does

When a medication has been tracked in the app for longer than its threshold,
that depletion card gains one line — "Tracked here for about N years" — and its
existing monitoring tip is shown with more emphasis. **No notification is sent.**
No new claim is made; the card's clinical copy is unchanged.

The threshold answers only: *has enough time passed that this is worth
revisiting?* It never changes severity, evidence level, or advice.

## What was deliberately NOT drafted

77 of 80 entries have **no** threshold proposed. 42 of them say "long-term" in
their copy, which is not a duration — turning it into a number would be
inventing clinical timing. Only entries whose **own already-cited sources**
state a specific exposure period were drafted.

---

## Row 1 — `DEP_ANTACIDS_IRON` → **730 days (2 years)**

**Evidence (already on this entry):** Lam 2017, *Gastroenterology*
(PMID 27890768, [DOI](https://doi.org/10.1053/j.gastro.2016.11.023)).
Acid-suppressant use for ≥2 years was associated with subsequent iron
deficiency: PPI adjusted OR **2.49** (95% CI 2.35–2.64); H2RA OR **1.58**
(95% CI 1.46–1.71). 77,046 cases vs 389,314 controls.

**Why 730:** the study stratified on a ≥2-year supply. The threshold is that
exposure period, not an extrapolation.

**Decision:** ☐ Yes  ☐ No  ☐ Different value: ______

---

## Row 2 — `DEP_ANTACIDS_VITAMINB12` → **730 days (2 years)**

**Evidence (already on this entry):** Lam 2013, *JAMA*
(PMID 24327038, [DOI](https://doi.org/10.1001/jama.2013.280490)).
A ≥2-year supply of PPIs was associated with incident B12 deficiency
(OR **1.65**, 95% CI 1.58–1.73); ≥2 years of H2RAs OR **1.25** (95% CI
1.17–1.34). 25,956 cases vs 184,199 controls.

**Why 730:** same stratification boundary as the source.

**Decision:** ☐ Yes  ☐ No  ☐ Different value: ______

---

## Row 3 — `DEP_METFORMIN_VITAMINB12` → **1460 days (4 years)**

**Evidence (already on this entry):** de Jager 2010, *BMJ*
(PMID 20488910, [DOI](https://doi.org/10.1136/bmj.c2181)) — a 4.3-year
randomised placebo-controlled trial (n=390) in which metformin raised the
absolute risk of B12 deficiency by **7.2 percentage points** (NNH 13.8 per
4.3 years). The entry's own reviewed recommendation already reads "especially
after about **4–5 years**."

**Why 1460:** the lower bound of the window this entry already states, matched
to the trial duration on its own source list.

**⚠ Reviewer decision worth making explicitly:** Ting 2006, *Arch Intern Med*
(PMID 17030830, [DOI](https://doi.org/10.1001/archinte.166.18.1975)) found an
adjusted OR of **2.39** (95% CI 1.46–3.91) at **≥3 years** versus <3 years.
That supports an earlier trigger of 1095 days. It was **not** used here because
it is not currently on this entry, and the drafting rule is that a threshold may
only cite sources the entry already carries. If the team prefers the earlier
trigger, add Ting 2006 to the entry's sources first, then set 1095.

**Decision:** ☐ Yes (1460)  ☐ Yes, earlier (1095 + add Ting 2006)  ☐ No

---

## How to record a decision

For each approved row, in `dsld_clean/scripts/data/medication_depletions.json`:

```json
"watch_review_status": "approved",
"watch_approver": "<reviewer name>"
```

The release gate rejects an `approved` row that names no approver — an approval
with no attributable reviewer is not an approval. Rejected rows should be set to
`"rejected"` rather than deleted, so the decision stays on the record.

After editing, re-run the pipeline sync; the content hash pin in both repos must
be updated in the same commit (this is the intended cross-repo tripwire).

## Provenance

`watch_proposed_by: claude_research_draft` is recorded on every drafted row and
is deliberately distinct from `watch_approver`. The draft is not a review.
