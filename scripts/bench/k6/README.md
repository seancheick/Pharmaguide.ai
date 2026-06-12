# k6 Load Tests — Supabase endpoints

> **WARNING — these tests hit real Supabase infrastructure.**
> Every request consumes project egress, storage bandwidth, and API quota.
> `catalog_download.js` in particular downloads the full ~40 MB catalog per
> iteration at 200 VUs — that is gigabytes of egress per minute.
> **Run against a staging Supabase project, or production only off-peak
> with reduced VUs/duration.** Never point these at production casually.

Secrets are passed by environment variable **name** only — source them from
your shell or `.env` tooling. Never hardcode or paste values:

- `SUPABASE_URL` — project base URL
- `SUPABASE_ANON_KEY` — anon key (apikey + bearer headers)
- `BLOB_SHA` — sha256 of a detail blob (blob_fetch only)
- `MODE` — `authed` | `public` (blob_fetch only)
- `DB_VERSION` — catalog version from `export_manifest` (catalog_download only)

Install k6: `brew install k6`

## manifest_check.js

The per-launch OTA version check:
`GET /rest/v1/export_manifest?select=db_version&is_current=eq.true&limit=1`

Ramps 0 → 1000 VUs over 10 min, holds 2 min.
Thresholds: `http_req_duration p(95) < 300ms`, error rate < 1%.

```bash
SUPABASE_URL=... SUPABASE_ANON_KEY=... k6 run scripts/bench/k6/manifest_check.js
```

## blob_fetch.js

Detail blob fetch, comparing the authenticated endpoint
(`/storage/v1/object/authenticated/pharmaguide/shared/details/sha256/{prefix}/{sha}.json`,
apikey + authorization headers) against the public endpoint
(`/storage/v1/object/public/...`). Run twice and diff the summaries:

```bash
SUPABASE_URL=... SUPABASE_ANON_KEY=... BLOB_SHA=<sha256> MODE=authed \
  k6 run scripts/bench/k6/blob_fetch.js
SUPABASE_URL=... BLOB_SHA=<sha256> MODE=public \
  k6 run scripts/bench/k6/blob_fetch.js
```

## catalog_download.js

Fleet OTA simulation: 200 constant VUs downloading
`/storage/v1/object/authenticated/pharmaguide/v{DB_VERSION}/pharmaguide_core.db`
for 5 minutes. Reports throughput (`catalog_bytes_downloaded`,
`data_received`) and error rate (`catalog_download_errors`, threshold < 2%).

```bash
SUPABASE_URL=... SUPABASE_ANON_KEY=... DB_VERSION=<from export_manifest> \
  k6 run scripts/bench/k6/catalog_download.js
```

## Local baselines for context

The on-device query benchmark (`../query_bench.sh`, run 2026-06-11 against
the bundled 9,270-product catalog) puts every hot local query under ~23 ms
(most under 10 ms) — see `../README.md` for the full table. Network paths
tested here are the dominant latency contributors in real usage, which is
why the manifest check carries a hard `p(95) < 300ms` threshold.
