# Label Truth and Trust Architecture Design

**Date:** 2026-07-19
**Status:** Approved for implementation

## Problem

PharmaGuide currently presents a scoring-shaped ingredient list as though it
were a transcription of the physical label. This causes visible omissions,
flattened hierarchy, duplicate-looking nutrient rows, and contradictions
between ingredient tiles, detail sheets, and score explanations. A user holding
the bottle cannot reliably distinguish what the manufacturer printed, what
PharmaGuide interpreted, and what entered the score.

## Product Contract

Product detail has three explicit layers:

1. **Label truth** reproduces every meaningful source-label line in printed
   order and hierarchy, including totals, constituents, parentheticals,
   proprietary blends, and other ingredients.
2. **PharmaGuide interpretation** records normalized identity, form, lineage,
   and source provenance without replacing the visible label identity.
3. **Analysis** states which rows affected scoring and why other visible rows
   were excluded or shown only as context.

The score core remains unchanged except where its existing consumer explanation
does not describe the signals that actually produced the score.

## Canonical Label Ledger

The pipeline `display_ingredients` ledger is the display source of truth. Every
meaningful row receives:

- `label_display_name`, `label_display_form`, and exact dose text;
- `label_order`, `nested_depth`, `parent_label`, and `raw_source_path`;
- `score_included` and `is_label_context`;
- an explicit display disposition: `scored`, `label_context`, `other_ingredient`,
  `interpreted`, or `needs_review`;
- form disclosure, assessment, and integrity states;
- `identity_integrity_state`: `clean`, `repaired`, `taxonomy_only`,
  `identity_conflict`, or `missing_display_label`;
- a stable fingerprint used for formula-version comparison.

The scoring ingredient list remains a separate input. Display rows may never be
fed back into dose, safety, or score calculations merely because they are shown.
Any score-included row with unresolved `identity_conflict` or
`missing_display_label` blocks score publication for that product. Suppressing a
row-level claim is not sufficient because the published aggregate score would
still imply confidence in a disputed identity.

Intentionally omitted source rows are recorded separately in the top-level
`label_ledger_omissions` audit list with `raw_source_path`, `raw_source_text`,
and a closed-set `omission_reason`. Omitted rows never masquerade as displayed
ledger rows and never enter scoring.

The top-level `label_source_rows` list is the reconciliation inventory for all
supported source-label sections. Each occurrence carries its stable
`raw_source_path`, literal `raw_source_text`, and `source_section`; every path
must resolve to either `display_ingredients` or `label_ledger_omissions`.

Display completeness is summarized in the separate top-level
`label_ledger_audit` object—not the scoring-confidence field named
`label_completeness`. It contains `support_status`, `source_structure`,
`meaningful_source_rows`, `displayed_rows`, `omitted_rows`,
`completeness_percentage`, and `completeness_status`. Unsupported structures
use a null percentage and `unavailable`; they never claim completeness.

## Label Rendering

The default section is **What the label lists**. It preserves ledger order and
uses indentation for hierarchy. It does not regroup or sort by scoring utility.
An optional **Analysis** filter may reduce the list to score-relevant rows, but
the default always mirrors the label.

Examples:

```text
Fish Oil                                      2,400 mg
  Total Omega-3 Fatty Acids                     720 mg
    EPA (Eicosapentaenoic Acid)                 360 mg
    DHA (Docosahexaenoic Acid)                  240 mg
    Other Omega-3 Fatty Acids                   120 mg
```

```text
Folate                               665 mcg DFE
  (400 mcg folic acid)
```

Totals and equivalent/component amounts are displayed once with lineage and are
not double counted. Count badges count logical label rows, never headers or
decorative widgets.

## Form State Contract

`unknown` is not user-facing. Form presentation uses:

- `assessed`: a disclosed form is mapped and may show Excellent/Good/Fair/Poor;
- `not_disclosed`: the form is applicable but absent from the source label and
  renders **Form not disclosed**;
- `listed_not_assessed`: exact form text exists but has no assessment and
  renders **Form listed · not yet assessed**;
- `not_applicable`: no form badge or form block;
- `needs_review`: stale, malformed, conflicting, or impossible contract;
  renders **Data needs review** and suppresses quality claims.

Invariant: a non-empty source-label form paired with `not_disclosed` is a
release-blocking integrity failure. Ingredient rows and explanation sheets use
one normalized presentation model.

## Confidence and Evidence

Three concepts remain separate:

- **Label completeness:** meaningful ledger rows displayed / meaningful source
  rows.
- **Analysis coverage:** scoring candidates mapped / eligible scoring
  candidates. Existing `mapped_coverage` belongs here.
- **Product match:** confidence that the catalog record represents the user's
  bottle, based on UPC/source/version/status metadata.

The UI uses **Label match** and **Analysis coverage**, never the laboratory term
“Label Accuracy.”

The existing `mapped_coverage` rename is presentation-only; it does not change
the scoring or safety contract. PharmaGuide never displays `safe`, a green
all-clear, or equivalent safe-sounding copy when `mapped_coverage < 0.3`.

Evidence copy reconciles scopes. Strong evidence for one ingredient does not
imply strong evidence for the full formula or exact product. Formulation copy
names actual signals such as form disclosure and EPA+DHA concentration rather
than inferring cheap forms from a low pillar band.

## Product Version and Source Label

Product detail surfaces source, source record ID, UPC when present, catalog
version, label/formula fingerprint, source/update date when present, and
reformulation/off-market status. The existing bottle image remains the hero.
A separate **View source label** surface appears next to the label ledger.

Formula history is generated only from real catalog snapshots or source records
sharing a defensible lineage key. The app never fabricates dates or claims that
two similar names are versions of the same formula. When no history exists, it
says so.

## Mismatch Reporting

The label section includes **Doesn't match your bottle?** Authenticated users
may submit structured product-label mismatch reports. Reports contain product
record identifiers, catalog/fingerprint metadata, mismatch categories, and up
to three explicitly selected product-label photos (front, Supplement Facts,
Other Ingredients). They contain no profile, medications, conditions,
allergies, stack, or health notes.

Photos use a private Supabase Storage bucket. Client policies are owner-scoped;
reviewers access reports and signed photo URLs only through a service-role/admin
backend, never through a broader client policy. Report rows use RLS and
immutable ownership. Users see upload state and can retry. Authentication is
required for in-app reports and all attachments. Unauthenticated users see
**Sign in to report a mismatch**; PharmaGuide exposes no unauthenticated
submission channel. Reports never overwrite catalog data automatically.

## Telemetry and Operations

Trust telemetry uses the existing consent-gated local AnalyticsService. Events
contain only allowlisted state/category/count values and never raw UPCs, product
names, health data, label text, or photos. Required metrics include source-label
opens, analysis-filter use, form-state distribution, review-state encounters,
and mismatch submission outcomes.

Pipeline release audits block:

- source form present but form state `not_disclosed`;
- any score-included row with `identity_integrity_state = identity_conflict`;
- any active row with `identity_integrity_state = missing_display_label`;
- any product whose score-publication state is blocked by an identity-integrity
  failure;
- meaningful source row missing from the display ledger without an allowed
  omission reason;
- duplicate parent/component display without lineage;
- label completeness below 100% for supported label archetypes;
- unresolved `needs_review` rows presented with dose/form/safety claims.

Allowed omission reasons are a closed set:
`nutrition_fact_not_applicable`, `decorative_or_header_text`,
`duplicate_source_line`, `empty_source_text`, and
`unsupported_source_structure`. Only the first four may coexist with 100%
label completeness. `unsupported_source_structure` makes completeness
unavailable, queues the product for review, and forbids a completeness claim.

The first supported archetypes are flat Supplement Facts; vitamin/mineral
panels; omega parent/component totals; folate DFE/equivalent amounts; elemental
mineral/source-compound pairs; proprietary blends; botanicals with plant
part/extract text; probiotics with strain/CFU text; and Other Ingredients.
Unrecognized multi-column panels, packet-combination panels, and malformed
structures use `unsupported_source_structure` until explicitly supported.

The operations dashboard reports label completeness, display dispositions,
form-state rates, integrity failures, and formula-history coverage by category
and brand.

## Accessibility and Performance

All statuses have text and Semantics labels; color is supplementary. Nested rows
announce hierarchy and score participation. Large ledgers render lazily and keep
44-point targets. The default view prioritizes identity and label match above
deep score content.

## Delivery Phases

### P0 — Stop Trust Regressions

- make the canonical ledger the default ingredient display and preserve source
  hierarchy, parentheticals, order, doses, and logical counts;
- enforce identity-integrity and low-analysis-coverage publication gates;
- ship the minimum blocking pipeline audits for missing label rows, invalid
  form states, identity conflicts, and unsupported completeness claims;
- unify row/sheet form presentation, including **Form not disclosed** and
  **Data needs review**, without hiding disclosed-but-unmapped forms;
- remove duplicate warnings and reconcile evidence/formulation explanations
  with the signals that produced their pillars.

### P1 — Make Product Identity Verifiable

- add Label match, source-label access, source/version/fingerprint metadata,
  and defensible formula history;
- add Label/Analysis filters, accessible hierarchy semantics, and performant
  rendering for large ledgers;
- distinguish label completeness, analysis coverage, and product match in both
  copy and data contracts.

### P2 — Close the Feedback and Operations Loop

- add authenticated structured mismatch reports, private photo upload, retry,
  owner RLS, and service-role reviewer access;
- add consent-gated trust telemetry with strict privacy allowlists;
- extend the P0 audits with operational dashboards and trend reporting for
  completeness, form states, integrity failures, mismatch outcomes, and
  formula-history coverage.

## Verification

Canary fixtures cover omega hierarchy, folate DFE equivalence, elemental salts,
proprietary blends, botanicals, probiotics, disclosed-unmapped forms,
not-disclosed forms, stale contracts, reformulated products, and other
ingredients. Tests lock row/sheet parity, logical counts, semantics, source
label actions, privacy allowlists, RLS policies, and release-audit failures.
