# PharmaGuide

Flutter app for supplement identification, product-quality explanations and
source-backed interaction findings. The pipeline computes product assessments;
the app renders them and evaluates personal context through its existing engine.
A quality score is not a personal safety verdict. Never describe a product as safe.

## Supported commands

This is the canonical app command guide. Run commands from the Flutter repository
(`/Users/seancheick/PharmaGuide ai` on Sean's Mac). `make help` lists current targets.
Use the Make targets for running and building: they supply the required Supabase,
Sentry and Google configuration from the local `.env`. Do not paste credentials
into documentation or bypass the shared builder with raw Flutter build commands.

| Task | Command | What it does |
| --- | --- | --- |
| Run on a connected device | `make run` | Hydrate the pinned interaction DB, then launch |
| Run on iOS simulator | `make run-ios` | Same launch configuration, iOS target |
| Run on Android emulator | `make run-android` | Same launch configuration, Android target |
| Build an IPA for TestFlight | `PHARMAGUIDE_IOS_DISTRIBUTION=testflight make build-ios` | Signed export tagged as TestFlight; no upload |
| Build an IPA for App Store distribution | `make build-ios` | Signed export tagged as production; no upload |
| Build Android AAB | `make build-android` | Release app bundle |
| Check local catalog/storage alignment | `make verify-bundle` | Core checksum and remote detail samples; no publication |
| Check Supabase connectivity | `make verify-supabase` | Read-only authentication settings probe |
| Analyze and test | `make check` | Full app source validation |
| Run tests | `make test` | Full Flutter test suite |
| Generate models/database code | `make gen` | Existing code-generation owner |
| Show all current commands | `make help` | Includes developer and maintenance targets |

`make build-ios` remains the single iOS build target. The distribution setting
changes the Sentry environment, not the product UI or scoring. Both channels use
`scripts/build_ios_release.sh`, which reserves the next build number, keeps the
About-screen version synchronized, checks release identity, archives, signs and
exports. An unsuccessful export keeps its reserved number for the next attempt.

The exported package is `build/ios/ipa/pharmaguide.ipa`. Upload that fresh file
through Transporter yourself, then install the processed build through TestFlight.
A successful catalog release or Git push does not produce a new IPA.

### Normal release sequence

1. Merge and push the reviewed app changes.
2. Complete the separately authorized pipeline/catalog release if data changed.
3. Confirm the imported app bundle and source validation, then run `make verify-bundle`.
4. Run the TestFlight build command above. Inspect the exported version and
   packaged catalog/interaction/reference checksums; do not reuse an old IPA.
5. Commit and push the reserved build-number changes.
6. Upload through Transporter; phone acceptance belongs to the tester.

See the pipeline's [operator runbook](../Downloads/dsld_clean/scripts/PIPELINE_OPERATIONS_README.md)
for Clean/Enrich/Score, optional pre-checks, publication, retries and maintenance.
Those commands run in the pipeline repo, not here. The online copy is in
[PharmaGuide_Pipeline](https://github.com/seancheick/PharmaGuide_Pipeline/blob/main/scripts/PIPELINE_OPERATIONS_README.md).

### Developer-only tools

`make run-v2`, `make run-v2-ios` and `make run-v2-android` open the existing
developer gallery through `DEV_ROUTE`. They are still supported previews, not
release modes. `make v2-audit` runs the design-system audit.

The old per-screen UI-toggle launch/build targets have been removed because the
app no longer reads their flags. Historical design notes are not build instructions.
Do not restore retired commands or invent a new build variant to enable current UI.

## Setup and architecture

Use the repository's Flutter/Dart SDK constraints, Xcode for iOS and Android tooling
for Android. Configure a local `.env` with the existing Makefile's Supabase, Sentry
and Google client settings; this repository does not ship an `.env.example`.
Install dependencies with `flutter pub get`, hydrate the pinned interaction data
with `make hydrate-interaction-db`, and run `make gen` before first local validation.

- `lib/`: Riverpod/GoRouter screens, data readers and existing personal-context engine.
- `assets/db/pharmaguide_core.db`: committed read-only catalog, replaceable through OTA.
- `assets/db/interaction_db.sqlite`: checksum-pinned build-time hydration asset.
- `user_data.db`: separate writable local profile/stack/cache, untouched by catalog OTA.
- `assets/db/export_manifest.json` and reference manifests: actual versions and digests.
- `tool/interaction_db.release.json`: immutable interaction asset pin.

Product quality uses six pipeline-owned pillars: Formulation, Dose, Evidence,
Transparency, Verification and Safety/Hygiene. Product safety and assessment
completeness remain independent. The app never recomputes the pipeline score.
See [AGENTS.md](AGENTS.md) for ownership, privacy and validation requirements, and
[knowledge/pipeline-reference.md](knowledge/pipeline-reference.md) for the data contract.

PharmaGuide provides educational information and does not replace clinical advice.
