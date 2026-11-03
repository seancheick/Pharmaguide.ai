# A2 + A3: one release generation, rollback, signing — 2026-11-03

Goal: build ADR-012 (app) and publish rules with the catalog (pipeline PR). Remote rules stay off for public builds until A9 and a production key.

Owner: lib/services/catalog_swap.dart, catalog_updater_service.dart, lib/data/supabase/sync_service.dart, lib/data/providers/database_providers.dart, lib/main.dart bootstrap — evidence: read 2026-11-03. No owner for pointer, folders, signed manifest: searched lib for release_sequence, blocked_versions, active.json (zero hits).
New files: lib/services/release_store.dart, lib/services/release_manifest.dart. New dependency: cryptography (Ed25519).
Will NOT create: feature-flag framework, a second manifest table, stored results.
Shared owners touched: AGENTS-listed export contract (export_manifest columns), supabase/migrations (new migration, NOT applied to production).
Pipeline branch: claude/a2-release-manifest in /Users/seancheick/Downloads/dsld_clean_wt/a2-release-manifest. a4-finish owns scripts/rule_change_gate.py and its release_full.sh line; agreed by message.
Simulator: a5-finish holds the QA simulator; agree a slot before device checks.

Status lives in the plan's Status tracker (A3 and A2 rows).
