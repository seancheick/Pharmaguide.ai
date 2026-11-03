# A2 + A3: one release generation, rollback, signing — 2026-11-03

Branch `claude/sharp-mayer-5d6e53`, app PR #178. Decision record: ADR-012 in `knowledge/architecture-decisions.md`.
Pipeline half: PharmaGuide_Pipeline PR #336, branch `claude/a2-release-manifest`. Merge #336 first.

## State
- Code, migration and tests are committed on both branches. Neither is merged.
- Migration `supabase/migrations/20261103130000_signed_release_manifest.sql` is NOT applied to production.
  Rehearsed 53/53 on a production-like schema, PostgREST 14.5 and 16.4, under its earlier name. Storage was faked.
- No key is bundled (`_kProductionReleaseKeys` is empty), so public builds stay catalog-only. Remote rules are
  tested, not publicly enabled. `scripts/config/remote_rules_gate.json` stays closed. Enabling needs Sean, after A9.
- Device proof finished on iPhone 17 Pro Max iOS 26.5 `5CFF10CF`, keyed debug simulator build. Phone restored from
  its backup and shut down. Evidence and screenshots: `a2-device/` in the session's shared notes folder.

## Owed
1. Sean: merge #336 then #178; apply the migration; first production key; remote rules after A9.
2. Sean: copy for a notice naming a blocked-version correction; whether the publisher should refuse a rules-only
   correction that a schema 2 catalog can't show.
3. Independent review of #178 (0 reviews) and of #336 since `cfb3ebf59`.
4. Not tested: physical device, Android, release mode, real Storage, first-launch move time without load.

## Found, not fixed here
A medication rule that exists only in the rules file is dropped on the product page: `class:*` ids in
`_interactionResultToWarning` against bare ids in the page's filter. On main too. Note:
`a2-device/medication-rule-dropped-on-product-page.md`. Proposed as its own task.

## Lane
Shared owners touched: `lib/main.dart`, `database_providers.dart`, `sync_service.dart`, ADR log,
`scripts/verify_native_app.py`. Root catalog files in Documents are gone after first launch on this branch.
