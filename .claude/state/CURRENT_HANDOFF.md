# Active — pre-beta launch gates, October 21

Goal: show the existing Analysis Coverage caveat beside the pipeline result, add real-product safety/stack acceptance, and remove unused numeric FitScore arithmetic while preserving categorical personal relevance.

Owned app files: product-detail v2 composition and focused tests; FitScore result/service/constants where the dead-code proof requires; real pipeline fixture and release-gate tests; engine-spike closure list. Pipeline changes live in the sibling pipeline worktree.

Baseline: app `origin/main` at `9b49a4c1`; bundled catalog `2026.10.21.140823` remains preserved. The primary app checkout is untouched. The ignored interaction DB and environment were copied only to validate this worktree. No IPA/TestFlight upload or catalog import ran here.

Owner Check:
- Owner: `label_confidence_section.dart::buildLabelConfidenceSection` and existing `mappedCoverage` reader. The product screen now mounts that existing surface directly below the hero when it has a coverage/label signal.
- Owner: `fit_score_service.dart::_buildAssessment` plus `FitScoreResult.state/reasons/maxRelevantSeverity/mappedCoverage`. Removed numeric `scoreFit20`, E2c penalty and `maxPossible`; retained the categorical profile result and the existing warning pipeline.
- Owner: existing warning, Quick Check, stack interaction and nutrient aggregation services. The new tests consume pipeline-authored blobs; they do not author clinical policy.
- Will NOT create: a second safety evaluator, coverage field/calculator, personal score, interaction engine, or nutrient aggregator.

Implemented:
- A low-coverage product retains the pipeline score/verdict in the hero while the existing Analysis Coverage card states the limitation below it.
- Deleted the unused E2c numeric penalty calculator, numeric FitScore fields and dependent closure entry. No live references remain.
- Added a frozen `candidate_v5` real-product fixture and end-to-end cases for pregnancy/breastfeeding + St. John's wort, pregnancy + sage, kidney disease + magnesium, no-data, controls, duplicate magnesium totals, and exact levothyroxine/calcium plus calcium/iron Quick Check paths.

Validation:
- Final affected Flutter slice before the broad gate: 252 passed.
- `make check`: analyzer clean and 3,962 tests passed.
- Refreshed `candidate_v5` fixture tests: 10 passed.
- Engine spike harness: 5 passed; actual VM/AOT/dart2js/Deno/Node build and byte-identical parity passed; all 28 live engine files compile.
- `make verify-bundle`: PASS on preserved catalog `2026.10.21.140823` (20 sampled blobs, HTTP 200 and valid JSON). This verifies the old bundle only; rebuilt parity remains open.
- Dead-reference census for `scoreFit20|maxPossible|e2cPenalty|E2cMedicalCalculator|e2c_medical|.e2c`: zero live references.
- `git diff --check` clean before commit.

Next unchecked item: commit the final candidate, obtain fresh independent review and exact-head CI, integrate after green. After Sean's required producer rerun, import and validate the rebuilt catalog, run release gates and complete the Flutter release flow.
