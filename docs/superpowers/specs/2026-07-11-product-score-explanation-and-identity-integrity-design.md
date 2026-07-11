# Product Score Explanation and Identity Integrity

**Status:** Approved for implementation on 2026-07-11

## Problem

The Product Detail page exposes six v4 score pillars, but does not explain
them in terms of the product that was scored. Formulation and Dose currently
offer a generic `See details` action that scrolls to Active Ingredients. That
list describes individual ingredients, not the product-level rubric, so it
cannot answer why a product earned its pillar score.

The current Nature Made One Per Day Fish Oil 1200 mg detail blob (`dsld_id`
`179681`) makes the risk concrete:

- score: `63.6/100`
- formulation: `13.9/20`
- dose: `8.7/20`
- evidence: `10/20`
- transparency: `14/15`
- verification: `7/15`
- safety hygiene: `10/10`

The blob correctly says that its dose falls short of the rubric's working-dose
range and that its form is reasonable but not premium. The UI then shows bare
`Good` chips for individual ethyl-ester rows, which appears to contradict the
score.

The same product has a data-correctness fault. Its 360 mg label row contains
the direct label evidence `EPA` / `Eicosapentaenoic Acid`, but it reaches the
final blob as a DHA row because upstream structured taxonomy supplied a DHA
identity. The result is two DHA rows. This is not a one-SKU display fix: a
conflicting identity must never silently enter safety, dose, evidence, or
scoring logic for any scoring module.

## Goals

1. Let a shopper understand every score pillar without leaving the score card.
2. Separate ingredient-level form/dose labels from product-level score pillars.
3. Keep score explanations pipeline-authored; Flutter must never infer why a
   score is low or reimplement score math.
4. Eliminate generic and dead pillar links.
5. Correct EPA/DHA identity at the pipeline root and guard every active
   ingredient against equivalent source-to-canonical conflicts.
6. Apply the identity guard before every v4 module consumes ingredients,
   including multi/prenatal, omega, probiotic, sports, B-complex,
   fiber/digestive, immune support, and generic routes.
7. Make the ingredient name and form shown to shoppers faithfully traceable to
   the product label, even when an internal canonical identity is repaired.

## Non-goals

- Change the v4 scoring policy or score thresholds in this work.
- Claim a personal clinical need from a product-level dose score.
- Manufacture detailed explanations where the scorer has no verified input.
- Patch a single catalog record while leaving the identity conflict path open.

## Product Experience

### Chosen interaction: evidence in each pillar

The score card remains the explanation surface.

1. The card header contains a visible `How scoring works` action. It opens the
   existing trust-receipts sheet; the duplicated bottom-of-page trust row is
   removed.
2. All pillars are collapsed initially. The card acts as a single-open mobile
   accordion: opening one pillar closes the previously open pillar.
3. An open pillar renders, in order: the verified reason, zero or more
   pipeline facts, then an optional named destination action.
4. Where the pipeline provides score facts, the expansion shows those facts in
   plain language. For example, the omega dose expansion can show `EPA + DHA
   per day: 660 mg/day` and state that the value is a product-rubric input,
   not a personal recommendation.
5. A pillar links elsewhere only when the destination is specific and present:
   `View clinical evidence`, `View certifications`, or `View label details`.
   Formulation and Dose never scroll to Active Ingredients. There is no generic
   `See details` label.
6. Empty or stale explanation detail degrades to the pipeline's existing
   one-line pillar reason. It never receives app-generated score rationale.

### Visual language

Pillar status is a quality explanation, not a safety warning. A single shared
Dart presentation utility will classify the displayed fraction as:

| Fraction of pillar maximum | Label | Treatment |
| --- | --- | --- |
| `>= 85%` | Strong | dark teal |
| `>= 60% and < 85%` | Mixed | amber/neutral |
| `< 60%` | Limited | amber/neutral |

The label accompanies the score, so color is not the sole signal. In the
example, Formulation at `13.9/20` is `Mixed`, not success-green; it has
meaningful trade-offs but is not presented as unsafe or defective. The utility
will be shared by the Product Detail and Compare surfaces.

Ingredient chips become explicit:

- `Excellent form`, `Good form`, `Fair form`, `Poor form`
- `Low dose`, `High dose`, `Dose not disclosed`

`High dose` retains its existing safety meaning (above an applicable upper
limit). The absence of a dose chip is not displayed as a positive dose verdict.
The Active Ingredients heading gains an accessible explanation that form chips
describe a single ingredient, while the score evaluates the whole formula.

## Score-Explanation Contract

`quality_pillars_v4` remains the single public score payload. The existing
`score`, `max`, and pipeline-authored `reason` fields stay authoritative.

Each pillar can additionally carry this optional, versioned display payload:

```json
{
  "explanation": {
    "schema_version": 1,
    "facts": [
      {
        "id": "epa_dha_per_day",
        "label": "EPA + DHA per day",
        "value_display": "660 mg/day",
        "detail": "This total is used by the omega dose rubric."
      }
    ]
  }
}
```

Rules:

- `reason` is the only summary sentence. It is not duplicated in
  `explanation`.
- `facts` are emitted only from the scorer's actual module inputs. Flutter
  renders `label`, `value_display`, and optional `detail` verbatim.
- `facts` may be empty. An unknown fact is omitted, never estimated.
- The pipeline must validate the schema and ensure each fact is tied to a
  score input or verified evidence signal.
- Navigation remains an app concern, but labels and eligibility live in one
  shared v4-pillar destination map. Evidence maps to `View clinical evidence`,
  verification maps to `View certifications`, and transparency maps to `View
  label details`. The action renders only when its keyed destination is present
  on the page. Formulation, Dose, and Safety Hygiene have no destination action.
  No screen creates an ad hoc action label or destination.
- Existing `v4_score_explanation` (top strengths and drags) remains backward
  compatible. The chosen card does not need it to calculate a second
  "biggest opportunity" summary.

The exporter builds these facts from the scorer's module breakdown. Omega is
the first detailed producer because it can emit verified EPA/DHA daily totals
and form facts. Every v4 module still emits the existing consumer-ready reason;
other module-specific facts are introduced only after their input provenance is
explicit. This covers every module without fabricating a generic explanation.

## Identity Integrity Contract

### Source precedence

The cleaner establishes a per-row explicit identity from high-specificity label
evidence before a canonical identity is made scoreable. Sources include the
row's raw label text, structured nutrient context, and direct line-level
`Form`/`Alt. Name` evidence. Generic product marketing and parent-blend text do
not qualify.

For a single unambiguous explicit identity, the cleaner repairs a conflicting
taxonomy/UNII assignment and preserves an audit trail containing the original
value, source evidence, and resolution rule. For conflicting high-specificity
signals, it sets an identity-conflict state rather than choosing silently.

When no high-specificity label identity is available, a row is marked
`taxonomy_only`. It may remain scoreable only when its canonical ID, standard
name, and form/UNII mapping agree under the existing confidence contract. It
cannot be repaired from weak context. The release audit records the status and
its count; a disagreement among those structured sources is an unresolved
conflict. This preserves valid label rows that do not disclose a specific
chemical identity without turning taxonomy into an unchecked override.

### Label-fidelity contract

The final artifact carries two deliberately separate representations for every
active row:

- `label_display_name` and `label_display_form` are label-derived display
  fields. They are the source of the ingredient name and form shown in the
  primary product UI.
- `canonical_id` and `standard_name` are internal identity fields used for
  scoring, safety, evidence, nutrient aggregation, and navigation. They never
  replace the primary label text merely because they are more normalized.

The artifact also retains the literal `source_label_name` and, when present,
`source_label_form` from the parsed label evidence. The only permitted
primary-display transformations run in this exact order: remove the Unicode
trademark glyphs `™`, `®`, and `℠`; apply Unicode NFKC normalization; remove
case-insensitive parenthesized trademark markers `(TM)`, `(R)`, and `(SM)`;
then collapse whitespace to one ASCII space and trim. The release audit applies
this exact same algorithm to each source/display pair and requires equality.
No other punctuation, token, abbreviation, case, word order, chemical identity,
source, or form may change. The pipeline must not expand an abbreviation into a
different-looking chemical name or synthesize a form that the label did not
disclose. A verified mapping may appear in a secondary detail as
`Also known as ...`, but it is never the row title and never obscures the label
wording.

Fresh release artifacts must have a non-empty, displayable literal
`source_label_name` for every active row. A `taxonomy_only` row can remain
scoreable only when it still has that literal display name and the structured
identity sources agree under the existing confidence contract. A row with no
such name is unscoreable, cannot drive product claims, and fails the release
audit. Cached or development blobs use the existing explicit `Identity needs
review` fallback; they never substitute an internal canonical name.

For example, when the label says `EPA (as Ethyl Esters)`, the primary row must
say `EPA` with `as Ethyl Esters` as its form. The corrected canonical identity
may be `epa` and its standard name may be `Eicosapentaenoic Acid`, but neither
may replace that label-first presentation. The analogous DHA row remains DHA.

Every scorable active row must retain the source label key and the display
derivation method in its audit trail. Existing display-fidelity checks for
branded tokens and plant parts remain, but are extended to reject
canonical-identity substitution rather than only obvious string collapse.

An unresolved conflict:

- cannot be scoreable;
- cannot drive safety, interaction, evidence, nutrient aggregation, or module
  routing;
- remains visible with its literal label text and an integrity diagnostic;
- causes the release identity audit to fail until reviewed or resolved.

This policy applies to all active ingredients, not a hardcoded EPA/DHA list.
EPA/DHA is the first regression fixture because its source conflict is known and
material to the omega module.

The release gate prevents an unresolved conflict from reaching users. As a
defense-in-depth fallback for a cached or development blob, Flutter renders the
literal label with `Identity needs review`, omits form/dose/safety claims, and
does not show a product-quality score derived from that row.

### EPA/DHA expected result

For `179681`, the final active rows must be:

- primary display `EPA` with form `as Ethyl Esters`, 360 mg, canonical `epa`
- primary display `DHA` with its label-derived form, 300 mg, canonical `dha`

The 1,200 mg fish-oil parent remains a source/form row and is not added to the
EPA+DHA dose total. Safety and score calculations consume the corrected
canonical rows.

### Release audit

The pipeline gains an identity audit over all enriched artifacts. It emits one
disposition for every active row: `clean`, `repaired`, `taxonomy_only`,
`identity_conflict`, or `missing_display_label`. Each entry records product ID,
source path, literal label name/form, explicit identity signal, supplied
canonical identity, resolution, and whether the row remained scoreable. The
release gate fails for an unresolved conflict, a missing display label, or a
resolved row whose canonical identity does not match the approved label
evidence.

The audit is module-agnostic; the v4 scorer's completeness and routing gates
then consume only conflict-free identities. This prevents the same source error
from contaminating multi/prenatal or any other scoring route.

The authoritative coverage inventory is the v4 scorer's module-routing
registry, not a hand-maintained test list. Release tests enumerate every active
route from that registry, including the generic fallback, and require an audit
disposition for every active row presented to each route. Adding a new scorer
route therefore cannot bypass identity resolution or label-fidelity checks.

## Implementation Boundaries

### Flutter

- Extend the shared v4 pillar parser/model to parse optional explanation facts
  and the shared visual status.
- Update the score card to present labeled state, expanded reason/facts, and
  named destination actions.
- Remove Formulation/Dose-to-ingredients callbacks and the duplicate trust
  footer.
- Make ingredient form chip labels explicit through the existing shared label
  helper; do not duplicate strings in the tile.
- Keep the app tolerant of old blobs that lack explanation facts.

### Pipeline

- Add a score-explanation adapter at the export boundary, sourced from v4
  module breakdowns, and validate its schema.
- Add identity-evidence extraction and conflict resolution before scorable
  active rows are finalized.
- Add a release audit/gate that scans all enriched artifacts and prevents
  unresolved canonical conflicts from shipping.
- Preserve raw source evidence and resolution metadata for audits; do not hide
  a conflict by changing a display string alone.

## Verification

### Pipeline

- EPA/DHA fixture: 360 mg direct EPA context resolves to `epa`; 300 mg DHA
  resolves to `dha`; their primary display names and forms retain the literal
  label terminology; total is 660 mg without counting 1,200 mg fish oil.
- Label-fidelity fixture: a repaired canonical identity cannot change the
  shopper-facing name or form, and only the permitted reversible display
  cleanup is allowed.
- Missing-label fixture: a fresh active row without a literal displayable label
  is unscoreable and fails release; a cached row shows the explicit fallback
  rather than a canonical substitute.
- Contradictory high-specificity identity fixture: row is unscoreable and the
  audit fails rather than guessing.
- Regression tests derive every v4 route from the scorer registry, require a
  `clean`, `repaired`, or permitted `taxonomy_only` disposition for every active
  row, and verify a conflict cannot reach module routing or score inputs.
- Score-explanation tests assert every emitted fact is sourced from the
  corresponding module input and all existing reason strings remain consumer
  ready.
- Full enriched-artifact identity audit passes before release.

### Flutter

- Six-pillar card renders explicit state labels and in-place reasons/facts.
- Formulation and Dose have no generic scroll action.
- Named evidence/certification/label actions appear only when their target
  exists.
- Old blobs render safely with the one-line reason only.
- Form chip labels include `form`; dose chips retain their existing semantic
  meaning.
- Widget tests cover narrow mobile width, accessibility labels, and no
  color-only status communication.
- Run focused tests, the full `flutter analyze`, and the applicable Flutter
  test suite before commit.

## Rollout

1. Implement and test pipeline changes against targeted fixtures and the
   current artifact audit; do not run a full release in this task.
2. Implement and test Flutter against both fresh and legacy blob fixtures.
3. Rebuild catalog and interaction artifacts in one user-run release after
   both repositories pass their targeted gates.
4. Verify the exact beta-user product plus representative multi, probiotic,
   generic, and safety-gated product paths on simulator before publishing.
