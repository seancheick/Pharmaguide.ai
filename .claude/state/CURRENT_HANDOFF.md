# Current handoff — early release compatibility, October 15

Lane codex/release-compatibility: Sean authorized fixing late release failures and repetition, without a pipeline or deployment. Owner: scripts/import_catalog_artifact.sh schema arrays and catalog_schema_supported/interaction_schema_user_version; existing scripts/tests/test_import_catalog_artifact.py CI harness. Will NOT create a second schema policy, new catalog field, app calculation or publisher.

The importer supports --check-compatibility C I before requiring artifacts/tools, sharing exactly the same lookups with actual import. Current2.5.0/4.0.0 passes; unknown catalog/interaction versions and missing arguments fail. Pipeline companion invokes it before full pipeline-only processing and publishing preflight; actual new-artifact import still runs before upload.

11 importer tests pass in30.7s; one explicitly private-candidate test remains opt-in skipped (existing). Bash syntax and real producer compatibility pass. No catalog/bundle/phone changes. CI and PR integration pending; no final pipeline go-ahead. Scoring Step4 remains independently owned in pipeline Claude lane; user runs corpus only after completed source integration and readiness. Production personal/snapshot remains disabled; WorkOS staging-only request sent with explicit approval, activation/retest pending.
