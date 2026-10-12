# AI-assistant sharing (ADR-009) — integrated, in PR — October 12, 2026

Plan: /Users/seancheick/.claude/plans/how-can-we-create-purring-beacon.md (revision 3, approved by Sean).
State: all lanes built, verified and integrated on branch `feat/ai-assistant-sharing`;
PR seancheick/Pharmaguide.ai#110 open against main. Pipeline PR #122 merged (catalog_search table +
publisher). Website PR seancheick/PharmaGuideWebsite#4 open (consent + connections pages). Lane
worktrees and branches removed after integration. Nothing else is pushed.

What landed (owners):
- AI brief: `lib/services/sharing/ai_brief_builder.dart` + `ai_share_scope.dart` + `clinician_report_data.dart`;
  `report_text.dart` owns report wording for the PDF and the brief; UI `ai_brief_preview_screen.dart`,
  `ai_share_scope_switches.dart`; release gate `test/release_gate/ai_brief_no_network_test.dart`.
- Consented snapshot (app): `lib/features/ai_share/*`, `ai_share_snapshot_client.dart` (the only caller of
  `ai-share-snapshot`, pinned by `no_health_in_supabase_test`), `ai_share_prefs_store.dart` (device-only).
- Servers: `supabase/functions/{mcp-public,mcp-personal,ai-share-snapshot}` over `_shared/{mcp_transport,
  rate_limiter,oauth_token,connection_gate,snapshot_crypto,catalog}.ts`; migrations `20261012*` (written,
  not applied; see `supabase/MIGRATION_HISTORY.md`); SQL suite `supabase/tests/ai_connector/` via
  `scripts/test_ai_connector_rls.sh`.
- Docs: ADR-009 accepted, ADR-010 proposed, AGENTS.md exception, `docs/security/ai-connector-threat-model.md`,
  `docs/spikes/2026-10-12-engine-service-spike.md` + `tool/engine_spike/`.

Evidence: `make check` on the integrated head → analyzer clean, 3,848 tests passed; `deno test
supabase/functions` → 197 passed; `scripts/test_ai_connector_rls.sh` → passed; website `pnpm test:ai-connector`
→ 12 passed, typecheck clean; simulator screenshots of the share option, brief preview, Profile row and
Connected AI assistants screen (session scratchpad).

Gates before the personal connector serves anyone (Sean, dashboard): enable OAuth Server (DCR staging only),
pre-register Claude / ChatGPT / Claude Code with exact callbacks, asymmetric JWT signing, `personal_mcp_audience`
+ token hook, apply `20261012*` migrations (and pipeline schema section 9 before the next sync), set
`AI_SHARE_SNAPSHOT_KEY_V1` for `ai-share-snapshot` and `mcp-personal`, confirm no other `pgrst.db_pre_request`;
then the S1–S3, S5, S10 staging checks in `supabase/functions/mcp-personal/README.md`.

Decisions owed to Sean: public server withholds condition/medication/pregnancy-tagged warnings (stated as a
limitation); whether the phone's share is sufficient consent for `get_my_stack_snapshot`; ADR-010 refactor
investment; final connected-case privacy copy (three strings) + privacy policy / FTC HBNR review.

Next: merge #110 and #4 when CI is green; apply migrations on staging; run the staging gate; Phase 3 (Apple
Health import) after launch; Phase 4 per ADR-010 once accepted.
