# Current handoff — Product-detail clarity and responsive score batch

Date: 2026-10-25
Branch: `codex/product-detail-clarity`
Baseline: `802edbb6`

Goal: repair the user-observed product-detail hierarchy and narrow score wrapping through reusable owners, while keeping actionable safety prominent. The paired pipeline branch owns ingredient structure and score-explanation truth. Sean will run the pipeline later; no catalog rebuild, import, release, or publication belongs to this lane.

Owner Check:
- Score layout: `lib/core/components/pg_score_line.dart::PGScoreLine`.
- Personal summary: `lib/core/components/pg_review_before_use_card.dart::PGReviewBeforeUseCard` and `review_before_use_section.dart`.
- Coverage display: existing `mapped_coverage`/ledger consumer in product-detail gating; no new calculator or field.
- Research pairs: `lib/services/stack/research_pair_lookup.dart::ResearchPairLookup.lookupForProduct`.
- Additive projection: `tradeoffs_section.dart`, bounded by the existing inactive-ingredient detail list.
- Will NOT create: a second score, safety verdict, coverage state, profile state, or parallel card family.

Implemented commits:
- `465ace1c` makes prominent score layouts stack the tier below the score, compacts clean profile and Good-to-Know rows, removes proprietary-blend disclosure from global Analysis Coverage, and filters same-product research pairs.
- `c2b487b8` compacts long additive summaries only when the detailed inactive-ingredient list is present, so names are never discarded without a drill-down source.

Safety/accessibility invariants:
- Warning and danger personal rows still auto-expand; only clean `No known concerns` summaries start compact and remain tappable for profile details/editing.
- Proprietary-blend limitations remain visible in ingredient and score content but no longer falsely label a fully mapped product as globally partial.
- Compact and prominent score variants preserve score/tier semantics while preventing narrow-card word wrapping.

Verification: focused widget/helper suites pass; the additive follow-up suite passed 29 tests. Exact-head `make check` passed with a clean analyzer and all 4,021 tests. Three adversarial passes found and closed four edge classes; the final cumulative review reports no actionable findings and independently reran the seven focused classification cases. Exact-head CI and connected-device visual acceptance remain before claiming integration. Apple-silicon simulator build is blocked by existing ML Kit transitive libraries missing arm64 slices for the iOS 26+ simulator; use the connected physical iPhone if available and record the result.
