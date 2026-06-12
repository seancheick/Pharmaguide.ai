// manifest_check.js — k6 load test for the export_manifest version check.
//
// This is the request every app launch makes to decide whether a catalog
// OTA is available. It must stay fast under fleet-wide cold-start spikes.
//
// Usage:
//   SUPABASE_URL=https://<project>.supabase.co \
//   SUPABASE_ANON_KEY=<anon key> \
//   k6 run scripts/bench/k6/manifest_check.js
//
// WARNING: running this against production consumes Supabase quota/egress.
// Prefer a staging project or an off-peak window. See k6/README.md.

import http from 'k6/http';
import { check } from 'k6';

export const options = {
  stages: [
    // Ramp to 1000 VUs over 10 minutes, hold briefly, ramp down.
    { duration: '10m', target: 1000 },
    { duration: '2m', target: 1000 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE = __ENV.SUPABASE_URL;
const ANON = __ENV.SUPABASE_ANON_KEY;

export default function () {
  const url =
    `${BASE}/rest/v1/export_manifest` +
    `?select=db_version&is_current=eq.true&limit=1`;
  const res = http.get(url, {
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${ANON}`,
      Accept: 'application/json',
    },
    tags: { name: 'manifest_check' },
  });
  check(res, {
    'status 200': (r) => r.status === 200,
    'has db_version': (r) => r.body && r.body.includes('db_version'),
  });
}
