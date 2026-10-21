# Current handoff — score dropdowns show one reason and one key fact, October 20

Sean decided on 2026-10-20 that each pillar dropdown shows the pipeline's one-sentence reason and at most one key fact. Branch claude/score-explanation-cleanup, which pairs with pipeline branch claude/score-explanation-cleanup-915b07 (schema 2 `audience` on pillar facts). The earlier child-UL handoff is closed: PR129 merged at ef8d5566, and the pipeline's PR169 merged at 22d7b8ffd.

Owner: lib/core/scoring/v4_pillars.dart::_parseFacts reads only schema-2 facts with `audience: "consumer"`, keeping the first one; a schema-1 blob yields no facts, so the pillar shows its reason only. lib/core/components/pg_score_breakdown_card.dart no longer renders _PillarReceipt ("How these points add up") or fact `detail`. score_breakdown_section.dart no longer prepends the app scope paragraphs (kFormulationScope was deleted; kFormulaQualityChecksScope stays for pg_trust_receipts_sheet). The "= N/100" sum line stays. V4PillarValue.receipt is still parsed for dose_v41_receipt_parity_test. Will NOT create an app-side fact selector or recompute anything.

Validation: flutter analyze clean; 1,092 focused tests (scoring, components, product_detail) and the full flutter test (3,967) pass. The fixture test/fixtures/pipeline/dose_v41_pillars.json was regenerated from pipeline 0cfc37195 real output; scores and receipts are byte-equal to the old fixture.

Next: CI on the PR, then merge after the pipeline PR. The installed app reads only schema 1, so a schema-2 catalog shows reasons plus its old receipt rows until this build ships. The bundle only changes after Sean's Score-only run and the release gates. No IPA or catalog import from here.
