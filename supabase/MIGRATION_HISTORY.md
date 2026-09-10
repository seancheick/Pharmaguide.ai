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
