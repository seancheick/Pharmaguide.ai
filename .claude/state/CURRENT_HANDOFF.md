# WorkOS branding — completed October 24, 2026

Goal: finish existing production WorkOS logos, test real consent, and report the release boundary. Completed without activating personal access.

Owner: existing WorkOS Production Branding and PharmaGuide Codex Connect application; website src/app/icon1.png/icon.png; existing shared MCP server branding. Evidence: official WorkOS branding/OAuth docs, saved UI readback, image-load checks and real hosted consent screenshot. Will NOT create a brand registry, OAuth client, credential, clinical owner or access grant.

Saved: environment display name PharmaGuide; light/dark logo icons, full-logo fallbacks and favicons; existing Codex application light/dark logos. Exact client ID, callback and scopes preserved. Real provider consent loaded both 192×192 logos; the admin mock issuer letter was absent on the real hosted page. Cancelled before Allow access; no code/token exchange. Saved previews and actual consent proof: ~/pg_quality/workos_branding_20261024/.

Used the existing exact-account qualification window for the visual test (about 15 minutes); normal MCP reads/uploads remained hard-disabled throughout. Explicit global pairing=false preserved. All three temporary production keys removed. Cleanup deployment dpl_8nkwKR2BkXmYE51ytw17eBdDEBJD is READY with production aliases on unchanged website main2ce144eb. Temporary test deployment deleted. Post-check: active connections0, snapshots0, personal503 and snapshot503. No keys, tokens or health payloads logged.

Documentation-only source updates: existing public MCP README future-logo guide, personal README pointer, and the single threat-model execution register. Runtime unchanged; no new broad CI required. Full Markdown diff/references and git diff --check reviewed. Existing app mainf4abb166/history CI40110147051 and prior production qualification remain valid. Other lanes preserved.

Remaining release work: docs/security/ai-connector-threat-model.md::Production release boundary. Enforce/qualify rollout scope; close two independent real OAuth account flows and the still-unexpired old-access-after-reconnect test; prepare coordinated existing handler/upload/website/phone activation with candidate CI; obtain explicit launch authorization and run production smoke/rollback checks. No activation is authorized by this logo-only task.
