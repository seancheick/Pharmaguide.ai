# Personal connector production acceptance — October 23, 2026

Goal: finish controlled production WorkOS/phone/Codex acceptance, then report activation readiness accurately. Public personal reads/uploads remain disabled. User authorized production server credential, migration, validated merges and completed-branch cleanup.

Owner: existing mcp-personal verifier/handler/repositories, SQL pairing/revocation/snapshot, website verified-user authorization and privacy owners. Evidence: current code, source matrix, owner tests and hosted receipts. Will NOT create a second issuer, data/sync/clinical brain or persisted permission contract.

Integrated: app PR138 main f393e00; runtime candidate5cb49ecd passed full CI40055271502 and combined97Deno; d6c2796 followup documentation only. App clean and completed branches removed. Website PR10/11 main3672756, exact CI passed and public policy pages verified. Primary website/pipeline unrelated dirty lanes preserved.

Verified: hosted two-account26 assertions (real Supabase sessions/RLS/RPC, WorkOS identity injected at boundary); staging real OAuth/phone/Codex lifecycle, automatic update/optout, oldrefresh denial and unexpired-token disconnect denial; snapshot purge and physical browser-to-app return passed. Production deletion19 assertions passed using actual deployed HTTP retry after providerfailure injection; same-environment WorkOS identity create/lookup/delete, all fixtures cleaned. Account-deletion migration20261024023658 applied with approval.

Production: billing unlocked; approved replacement server key stored Supabase and Vercel sensitive production env. Issuer https://capable-square-94.authkit.app; client client_01M5NXSNSESQFXNCBNPA547059 PKCE thirdparty; exact callback http://127.0.0.1:3199/callback/S6tE1k6DOX3Z. DCR/CIMD off. External sign-in https://pharmaguide.io/oauth/authorize. Canonical resource remains existing Supabase mcp-personal URL. Deployed mcp-personal/ai-share-snapshot/delete-account from f393e00; metadata productionissuer verified, normal personal/snapshot503 verified.

Security credential handling: first newly generated key was exposed in a tool result and immediately expired before use; replacement never printed. Temporary private key files retained only until serverconfiguration finishes, then delete. No key in receipt or repo.

Remaining: Vercel configuration deployment readback; exact-user bounded qualification of production OAuth+phone+Codex while public access stays off. pairing_flutter owns temporary external MCP wrapper using canonical factory and exact user/client/issuer/expiry, denies data until exactconnection+consent pinned; workos_website owns bounded verified-user rollout exception while global pairingflagfalse; plan_review independently reviews; parent integrates/deploys/tests. No claim of production onboarding from local callback probes. New grant action requires user confirmation when ready.

Receipts: ~/pg_quality/personal_phone_approval_20261023/production_readiness_20261024.json, workos-production-configuration.json, hosted_two_account_isolation_20261024.json, hosted_production_account_deletion_20261024.json. S9 bounded adultDTC source/technical review complete with published notices and incident tabletop, not legal certification. Provider timeout ambiguity requires operator identity-metadata reconciliation; local access remains blocked.
