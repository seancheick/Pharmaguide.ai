// catalog_download.js — k6 test for concurrent catalog OTA downloads.
//
// Simulates a fleet-wide OTA event: 200 clients simultaneously downloading
// the full pharmaguide_core.db snapshot from Supabase Storage at
//   pharmaguide/v{DB_VERSION}/pharmaguide_core.db
// (path contract: lib/data/supabase/supabase_contract.dart coreDbPath).
//
// Measures throughput (bytes/s via data_received) and error rate.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_ANON_KEY=... DB_VERSION=2026.06.10.020350 \
//   k6 run scripts/bench/k6/catalog_download.js
//
// WARNING: each iteration downloads the FULL catalog file (tens of MB).
// 200 VUs against production will burn significant Supabase egress in
// minutes. Run against staging, or off-peak with a reduced duration.

import http from 'k6/http';
import { check } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const bytesDownloaded = new Counter('catalog_bytes_downloaded');
const downloadErrors = new Rate('catalog_download_errors');

export const options = {
  scenarios: {
    ota_burst: {
      executor: 'constant-vus',
      vus: 200,
      duration: '5m',
    },
  },
  thresholds: {
    catalog_download_errors: ['rate<0.02'],
    http_req_failed: ['rate<0.02'],
  },
  // Discard bodies after measuring to avoid holding 200 catalogs in memory.
  discardResponseBodies: false,
};

const BASE = __ENV.SUPABASE_URL;
const ANON = __ENV.SUPABASE_ANON_KEY;
const VERSION = __ENV.DB_VERSION;

if (!VERSION) {
  throw new Error('DB_VERSION env var is required (e.g. from export_manifest db_version)');
}

const url =
  `${BASE}/storage/v1/object/authenticated/pharmaguide/` +
  `v${VERSION}/pharmaguide_core.db`;

export default function () {
  const res = http.get(url, {
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${ANON}`,
    },
    tags: { name: 'catalog_download' },
    responseType: 'binary',
    timeout: '300s',
  });
  const ok = check(res, {
    'status 200': (r) => r.status === 200,
    'body non-empty': (r) => r.body && r.body.byteLength > 0,
  });
  downloadErrors.add(!ok);
  if (res.body) {
    bytesDownloaded.add(res.body.byteLength);
  }
}

// Throughput: divide catalog_bytes_downloaded by test duration, or read
// k6's built-in data_received rate in the end-of-test summary.
