# Migration history

## Remote-only stamps recorded before this repo tracked them

These eight versions exist in `supabase_migrations.schema_migrations` on the
linked project and have **no file here**. They are apply-time stamps written by
the Supabase MCP `apply_migration` tool and the dashboard SQL editor, which
record the moment a statement ran rather than the version of the file it came
from. The schema changes they made are real and are still in production.

| Stamp | Applied (UTC) |
|---|---|
| 20260415204654 | 2026-04-15 20:46:54 |
| 20260513053047 | 2026-05-13 05:30:47 |
| 20260710210008 | 2026-07-10 21:00:08 |
| 20260711022522 | 2026-07-11 02:25:22 |
| 20260813232301 | 2026-08-13 23:23:01 |
| 20260813233125 | 2026-08-13 23:31:25 |
| 20260814163344 | 2026-08-14 16:33:44 |
| 20260814164213 | 2026-08-14 16:42:13 |

They were reconciled on 2026-09-10: the stamps were marked reverted so that
`db push` stops treating the tracked files as pending, and the five files below
were marked applied because production demonstrably already contains what they
create. **Nothing was deleted from the database and no schema changed** — this
table is the record moving out of a bookkeeping table and into the repository,
so that removing the duplicate rows does not erase the fact that they ran.

### Why the five files were safe to mark applied

Each was verified against a schema dump of the live project, not inferred:

| File | Evidence in production |
|---|---|
| `20260411000000_user_stacks.sql` | table `user_stacks` exists |
| `20260614000000_user_stacks_id_text.sql` | `user_stacks.id` is `text` |
| `20260614000100_user_stacks_phi_backstops.sql` | all four `users_can_*` policies exist |
| `20260813233000_public_share_snapshots.sql` | table `public_share_snapshots` exists |
| `20260814090000_secure_public_share_snapshots.sql` | only `service_role` holds a grant on it |

### Why three files were renamed

`20260411_`, `20260614_` and a second `20260614_` carried eight-digit prefixes.
Supabase versions are `YYYYMMDDHHMMSS`, so those could never be recorded in the
history table at all, and two files sharing `20260614` is why `supabase db reset`
has never worked in this repository. They now carry valid versions on the dates
they already claimed.

## The rule that caused this

`apply_migration` and the dashboard stamp apply-time versions. A file applied
that way is invisible to `db push`, which then treats it as pending and would
**replay** it — harmless for `IF NOT EXISTS` DDL, destructive for a migration
that drops and recreates a table. After any such apply, reconcile the stamp to
the file version with `supabase migration repair`, or apply through `db push` in
the first place.

## Connector migrations and remote status

### Pipeline-owned remote stamp (2026-10-13)

| Stamp | Applied | Note |
|---|---|---|
| 20261012234615 | 2026-10-12 23:46 UTC | pipeline-owned: `catalog_search_release_projection` (section 9 of the pipeline's `scripts/sql/supabase_schema.sql`, PharmaGuide_Pipeline#122). No file here by design; marked reverted on 2026-10-13 so `db push` stops treating it as missing. Schema unchanged. |

| File | Written | Status |
|---|---|---|
| `20261012120000_ai_connector_restrictive_rls.sql` | 2026-10-12 | applied to omayamxacvacrnvdvzhr on 2026-10-13 via `supabase db push` — S1 restrictive `client_id` policies on the user tables and `storage.objects`; guard in the app's seven SECURITY DEFINER RPCs |
| `20261012120100_ai_connections.sql` | 2026-10-12 | applied to omayamxacvacrnvdvzhr on 2026-10-13 via `supabase db push` — `ai_connections`, `mcp_access_log` (S10, S7, S5) |
| `20261012120200_custom_access_token_hook.sql` | 2026-10-12 | applied to omayamxacvacrnvdvzhr on 2026-10-13 via `supabase db push` — S2 token hook and `ai_connector_config`; after applying, set `personal_mcp_audience` and enable the hook in Authentication → Hooks |
| `20261012130000_ai_share_snapshots.sql` | 2026-10-12 | applied to omayamxacvacrnvdvzhr on 2026-10-13 via `supabase db push` — ADR-009 Phase 2 `ai_share_snapshots` (ciphertext only, no plaintext column, service role only), `purge_expired_ai_share_snapshots()` scheduled every 15 min with pg_cron (manual: `SELECT * FROM public.purge_expired_ai_share_snapshots();`). Before deploying `ai-share-snapshot`, set the function secret `AI_SHARE_SNAPSHOT_KEY_V1` (base64 of 32 random bytes, e.g. `openssl rand -base64 32`) for both `ai-share-snapshot` and `mcp-personal` |
| `20261012130100_pgrst_reject_ai_assistant_tokens.sql` | 2026-10-12 | applied to omayamxacvacrnvdvzhr on 2026-10-13 via `supabase db push` — S1 project-wide: `ALTER ROLE authenticator SET pgrst.db_pre_request` so PostgREST refuses any request whose claims carry `client_id`; covers the 23 privileged functions without a per-function guard. Check no other `pgrst.db_pre_request` is set on the project first (`SELECT setconfig FROM pg_db_role_setting WHERE setrole = 'authenticator'::regrole;`) |
| `20261012130200_ai_connections_display_fields.sql` | 2026-10-12 | applied to omayamxacvacrnvdvzhr on 2026-10-13 via `supabase db push` — S3/S4 `ai_connections.client_name`, `callback_host` (nullable, ≤ 200), written by the website consent route |

For future replays, apply with `supabase db push` in timestamp order and only after
`scripts/test_ai_connector_rls.sh` passes. The first one re-creates the seven
RPCs from their current definitions. A later migration that redefines one of
them must keep its `PERFORM public.reject_oauth_client_request();` line; the
test fails if it does not.

## October13 authorization containment

Applied with Sean's approval, in this order, to `omayamxacvacrnvdvzhr`:

| File | Status |
|---|---|
| `20261013165631_ai_connection_session_binding.sql` | Applied; service-role-only session-binding RPC verified (authenticated execute=false, service_role=true). |
| `20261013171928_ai_connector_deny_unbound_oauth.sql` | Applied; existing hook refuses assistant issuance/refresh and preserves ordinary app-session claims. |

`mcp-personal`, `ai-share-snapshot` and `mcp-public` were deployed from merged containment source.
Personal reads and snapshot POST return503; authenticated deletion stays available. Production
DCR=false was applied through the Management API and read back. These are containment receipts,
not personal-connector activation. No WorkOS migration or self-hosted issuer prototype was applied.
