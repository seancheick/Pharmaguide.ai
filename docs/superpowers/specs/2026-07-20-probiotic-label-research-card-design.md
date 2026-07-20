# Probiotic Label and Research Card Design

**Status:** Approved by product owner on 2026-07-20

## Goal

Explain what a probiotic label discloses and what PharmaGuide can substantiate from its curated research without implying that an unmatched strain has no research or that the exact product was clinically tested.

## Consumer contract

- The canonical ingredient ledger remains the label source of truth.
- The card appears immediately after Ingredients for probiotic products.
- The headline states total CFU **per serving** and separates that aggregate from per-strain disclosure.
- The card says “named microorganisms” when a label row may lack a complete alphanumeric strain designation.
- A positive “Research match found” state requires exact-strain, human evidence that is clinician-verified and not rejected.
- An unmatched row says “No strain-specific research match in our database.” It never says “not clinically studied.”
- Formula-only, species-level, pending-review, rejected, and inactivated states have distinct copy.
- Evidence strength is always paired with its indication when available. It is not a formula-wide endorsement.
- Prebiotic and delivery features are visually separated from research status.
- The explanation states that a research match does not mean the exact product or dose was studied.

## Data contract

Each emitted `probiotic_detail.clinical_strains[]` row may include:

- `research_match_status`: `exact_strain`, `formula_only`, `species_level`, `pending_review`, or `rejected`
- `evidence_scope`: `strain_specific`, `formula_specific`, or `species_general`
- `review_status`: `clinician_verified` or `pending_review`
- `human_evidence`: boolean
- `clinical_support_level`: `high`, `moderate`, or `weak`
- `indication_primary`: label-safe indication text already authored in the clinical-strain source
- `source_urls`: deduplicated PubMed URLs
- `source_count`: number of source URLs

Legacy blobs without these fields receive conservative Flutter-side interpretation: no positive research state solely because a row exists in `clinical_strains`.

## Presentation

The card title is “Probiotic label & research” with a visible information action. The intro explains that effects may depend on the named microorganism, dose, and intended use. Summary text states total CFU per serving, named-microorganism count, verified research-match count, and aggregate/per-strain disclosure.

Rows use explicit status text instead of hollow circles. Positive status uses an 18–20 px verified icon plus text. Other states use neutral or caution text and do not rely on color. Research rows may open a detail sheet containing scope, indication, support level, disclosure context, and source links.

## Accessibility

- No status is conveyed by color alone.
- Card information and research rows have explicit semantic labels, roles, and 44 px minimum interactive targets.
- Abbreviations are announced as “colony-forming units.”
- Layout supports text scaling without fixed-height rows.

## Non-goals

- Do not alter probiotic scoring.
- Do not create new health claims or infer benefits from species names.
- Do not claim the exact product was studied unless a future product-specific contract explicitly proves that.
- Do not rebuild the catalog or run the release pipeline in this task.
