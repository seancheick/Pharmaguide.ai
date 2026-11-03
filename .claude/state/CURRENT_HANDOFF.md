# A2 + A3: one release generation, rollback, signing — 2026-11-03

Branch `claude/sharp-mayer-5d6e53`, app PR #178. Decision record: ADR-012 in `knowledge/architecture-decisions.md`.
Pipeline: PharmaGuide_Pipeline #336 merged as `eab3a334`; follow-up #341 merged as `0c897b8ec`.

## State
- All independent-review fixes are on #178, each with a test that failed first. main `120d0008` is merged in.
- Migration `supabase/migrations/20261103130000_signed_release_manifest.sql` is NOT applied to production.
  Rehearsal is committed: `scripts/test_release_rehearsal.sh <pipeline repo>`, 53/53 on PostgREST 14.5. Storage is faked.
- No key is bundled (`_kProductionReleaseKeys` is empty), so public builds stay catalog-only. Remote rules are
  tested, not publicly enabled. `scripts/config/remote_rules_gate.json` stays closed. Enabling needs Sean, after A9.
- Public-build move re-proved at `df9e9215` on iPhone 17 Pro Max iOS 26.5 `5CFF10CF`: upgrade plus kills at six
  points. Keyed device rows ran before the review fixes and were not rerun. Phone restored and shut down.
  Logs and screenshots: `a2-device/` in the session's shared notes folder.

## Owed
1. Integrator merges #178. #181 rebases on #178.
2. Sean: apply the migration; first production key; remote rules after A9.
3. Sean: copy for a notice naming a blocked-version correction; whether the publisher should refuse a rules-only
   correction that a schema 2 catalog can't show.
4. CodeRabbit on #178 (limit hit, requested again). #341 reviewed; both comments fixed in `e1f8d4327`.
5. Not tested: physical device, Android, release mode, real Storage.

## Known limits
- A root catalog that stays unreadable forever keeps the app on its unavailable screen, like kept release folders.
- Review finding 7, not changed: a failed stack-blob fetch makes `activate` clear the assembly holding the moved
  catalog, so the next check re-downloads 66 MB. Blobs are stored before the pointer swap; a crash there is a cache
  miss, not wrong data. Proposed fix: publish the validated folder before fetching stack data.

## Lane
Shared owners touched: `lib/main.dart`, `database_providers.dart`, `sync_service.dart`, ADR log,
`scripts/verify_native_app.py`. Root catalog files in Documents are gone after first launch on this branch.
