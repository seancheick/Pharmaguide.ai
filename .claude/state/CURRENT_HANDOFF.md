# Current handoff — fresh IPA and command cleanup, October 17

Sean authorized a fresh signed IPA and removal of stale commands. Transporter/TestFlight upload remains Sean's task. No corpus pipeline, catalog republication or clinical change. App baseline: 8d4bfb1d; qualified candidate edd2b236, PR126 merged as 053e9784b6c4faca12aa156ef3845a7e1239e804. Pipeline documentation PR153 merged as 1a06a3ca0.

Owner: Makefile::build-ios and help; scripts/build_ios_release.sh and prepare_ios_build_number.sh; scripts/verify_bundle.dart; existing README/AGENTS, preflight/hydration tests and CI. Evidence: actual Make recipes, complete lib flag-reader search, real Make fixtures and packaged IPA digests. Will NOT create a build variant, command registry, publisher, scoring owner, clinical policy or public field.

## Fresh package — complete

`build/ios/ipa/pharmaguide.ipa`: version 1.0.0 (22), catalog 2026.10.15.235610 with 15,426 products. Built using `PHARMAGUIDE_IOS_DISTRIBUTION=testflight make build-ios`. Strict deep code-sign verification passes; get-task-allow=false, team SVBYWES848. All 42 checked catalog/interaction/reference assets inside the signed package match local files byte-for-byte. SHA256: 905dc932f828f26b8930b711cdd279e9a13ca50b4ba757e52fa94a4ae382eaba. Sean subsequently confirmed uploading build 22 through Transporter; Apple processing was not independently checked. No agent upload. Receipts: pipeline reports/ipa_build_20261017/.

Bundle verification passes core checksum and 20 remote valid JSON samples. Build-number reservation and About synchronization: 9 tests pass. Version changes are limited to pubspec.yaml and lib/core/utils/app_version.dart, committed as 6bc5de4b. Current app features and data are unchanged from the qualified source; subsequent command/docs changes require no IPA rebuild.

## Command cleanup — implemented and reviewed

Removed nine obsolete per-screen UI-toggle targets after proving no lib readers. Preserved live DEV_ROUTE gallery commands and the design audit. Fixed make help showing input filenames instead of target names and excluding names containing digits. Fail-first regressions reproduced both classes; final command/preflight checks 10 pass, hydration checks 19 pass. The command fixture tests actual Make behavior for TestFlight and production, hydration ordering and required configuration; it now runs in CI.

Canonical app commands: README.md (Supported commands). Canonical pipeline/release/retry/stage/optional-precheck/IPA handoff: pipeline scripts/PIPELINE_OPERATIONS_README.md. Agent instructions link these owners. Seven past design records are marked historical, not operating runbooks. Plain make build-ios retains production configuration; the explicit distribution setting selects TestFlight. No default-channel change. Independent fresh review found no actionable issues.

CI39046878614 on edd2b236 passed. PR126 is merged and candidate containment in origin/main is verified. The own local/remote temporary branch was removed. Later handoff changes are documentation-only; no duplicate broad checkpoint or IPA rebuild is required. Sean already uploaded build 22; next is his phone acceptance after Apple processing. No further upload or pipeline run by the agent.

## Disk audit — read-only

About 108 GiB free. ~/pg_quality uses 57 GiB, including 18 GiB in mapped_coverage_169_20261012; ~/.cache/uv uses 12 GiB. SHA-256 comparison proves 5,083,206,656 logical bytes / 30,853 duplicate files across that audit's candidate_before_xos and candidate_build22 final_db_output/dist mirrors. Preserve their differing export manifests and two unique reports per mirror. These old audit folder names are not today's IPA. No files were deleted. Detailed keep/candidate list: pipeline reports/ipa_build_20261017/disk-audit.md. Preserve build22 IPA/archive/debug symbols, raw labels/photos, clinical sources and other agents' worktrees.
