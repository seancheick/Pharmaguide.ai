// blob_fetch.js — k6 test comparing authed vs public detail-blob fetches.
//
// The app fetches product detail blobs from Supabase Storage at
//   shared/details/sha256/{first-2-chars}/{sha}.json
// This script measures the latency difference between the authenticated
// object endpoint and the public object endpoint for the same blob.
//
// Usage (authed):
//   SUPABASE_URL=... SUPABASE_ANON_KEY=... \
//   BLOB_SHA=<64-char sha256> MODE=authed \
//   k6 run scripts/bench/k6/blob_fetch.js
//
// Usage (public):
//   SUPABASE_URL=... BLOB_SHA=<sha> MODE=public \
//   k6 run scripts/bench/k6/blob_fetch.js
//
// WARNING: consumes Supabase storage egress. Use staging or off-peak.

import http from 'k6/http';
import { check } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 50 },
    { duration: '3m', target: 50 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE = __ENV.SUPABASE_URL;
const ANON = __ENV.SUPABASE_ANON_KEY;
const SHA = __ENV.BLOB_SHA; // full sha256 hex of the blob
const MODE = (__ENV.MODE || 'authed').toLowerCase(); // 'authed' | 'public'

if (!SHA) {
  throw new Error('BLOB_SHA env var is required (sha256 of a detail blob)');
}

const prefix = SHA.slice(0, 2);
const objectPath = `pharmaguide/shared/details/sha256/${prefix}/${SHA}.json`;

export default function () {
  let res;
  if (MODE === 'public') {
    res = http.get(`${BASE}/storage/v1/object/public/${objectPath}`, {
      tags: { name: 'blob_fetch_public' },
    });
  } else {
    res = http.get(`${BASE}/storage/v1/object/authenticated/${objectPath}`, {
      headers: {
        apikey: ANON,
        Authorization: `Bearer ${ANON}`,
      },
      tags: { name: 'blob_fetch_authed' },
    });
  }
  check(res, {
    'status 200': (r) => r.status === 200,
    'is json': (r) =>
      (r.headers['Content-Type'] || '').includes('json') ||
      (r.body && r.body.startsWith('{')),
  });
}
