# Export fidelity integration
Goal: preserve explicit pipeline nutrient-analysis decisions in the app. No pipeline, release, IPA or publication.
Owner: lib/services/health/product_health_facts.dart::_extractNutrients — evidence: fit_score_provider consumes healthFacts.nutrients; explicit empty analyzed_ingredients previously fell back to raw compound mass. Will NOT create a converter, nutrient identity owner or safety policy.
Baseline origin/main 8d0b9b0b. Branch codex/export-fidelity, paired pipeline codex/export-fidelity-integration.
Change: an explicitly present analyzed_ingredients field is authoritative even empty; genuinely legacy blobs lacking the field retain fallback. Ingredient display rows remain intact.
Validation: fail-first empty-analysis regression reproduced; 75 focused ProductHealthFacts/stack UL tests passed. make gen completed using preserved local interaction DB. Final CI and review pending; no catalog/release readiness claimed.
Evidence: /Users/seancheick/pg_quality/export_fidelity_integration_20261021/.
Next: complete paired candidate validation, CI, merge and preserve evidence before branch/worktree cleanup.
