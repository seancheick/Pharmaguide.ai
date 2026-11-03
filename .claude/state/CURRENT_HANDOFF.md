# A2 + A3: one release generation, rollback, signing — 2026-11-03

Branch `claude/sharp-mayer-5d6e53`. Decision record: ADR-012 in `knowledge/architecture-decisions.md`.
Pipeline half: PharmaGuide_Pipeline PR #336, branch `claude/a2-release-manifest`.

## State
- App code, migration and tests are committed on this branch. Not merged.
- The migration `supabase/migrations/20261102120000_signed_release_manifest.sql` is NOT applied to production.
  It was run on a local Postgres with stubs for the submission functions; Docker was down.
- No key is bundled, so public builds stay catalog-only. Remote rules stay locked by
  `_kProductionReleaseKeys` being empty and the pipeline's `scripts/config/remote_rules_gate.json`.
  Enabling either needs Sean, after A9.

## Owed
1. Device check on PharmaGuide iOS 26 QA. A5 holds the simulator, then A4, then this branch; A5 messages when free.
   Back up the container, and note the Keychain (Supabase session) lives at device level and a container restore
   does not bring it back. Fake server: PostgREST `export_manifest`, Storage paths, 503 for auth.
   Prove on screen: changed rule with no app update, kill and relaunch mid-update, rollback through restart.
   Ready to run: `/private/tmp/claude-501/-Users-seancheick-PharmaGuide-ai--claude-worktrees-sharp-mayer-5d6e53/e8ac3806-8ab9-4ddb-9170-54b7eaed1d30/scratchpad/device/serve.py <port> <state.json> <real supabase url>` is the fake publisher, and
   `/private/tmp/claude-501/-Users-seancheick-PharmaGuide-ai--claude-worktrees-sharp-mayer-5d6e53/e8ac3806-8ab9-4ddb-9170-54b7eaed1d30/scratchpad/device/prepare.py <bundled rules> <sequence> <catalog version> <catalog file> --rules 1.0.16 "QA REMOTE RULE 1.0.16"`
   signs a release with the pipeline's own code and changes St. John's wort's pregnancy headline, which is the on-screen proof.
   Build with `make run-ios SUPABASE_URL=http://127.0.0.1:<port> PHARMAGUIDE_RELEASE_TEST_KEY_ID=qa-local PHARMAGUIDE_RELEASE_TEST_KEY=<public hex>`
   and a FLUTTER wrapper that picks the QA simulator (see memory `reference_simulator_walkthrough`).
2. Pipeline, after A4's `scripts/rule_change_gate.py` lands: call `check_rule_changes` when a manifest names rules.
3. Pipeline: `scripts/release_full.sh` still publishes unsigned; wire signing before the first keyed build ships.
4. Copy decision for Sean: a notice that names a blocked-version correction. Today it reuses the existing
   "Personalized checks are incomplete" and not-scored states, and adds no copy.

## Lane
Shared owners touched: `lib/main.dart`, `database_providers.dart`, `sync_service.dart`, ADR log,
`scripts/verify_native_app.py`. Root catalog files in Documents are gone after first launch on this branch.
