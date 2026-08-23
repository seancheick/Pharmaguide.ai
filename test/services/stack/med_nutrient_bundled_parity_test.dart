// Cross-repo parity pin (B1.2 #3). The bundled medication-depletions artifact
// must match the pipeline-generated output. The pipeline pins the SAME
// content_hash (build_artifact(source)._metadata.content_hash) in its own test
// — two identical pins form the parity contract, so a STALE app asset OR a
// DRIFTED pipeline source fails a pin. This is the drift-gate fixture-parity
// pattern applied across the two repos, and it makes "the checked-in Flutter
// fallback exactly matches generated output" an automatic check.
//
// When the pipeline source legitimately changes: regenerate the app asset via
// `build_medication_depletions_artifact.py`, then update BOTH pins to the new
// hash (this one and the pipeline's `test_medication_depletions_artifact.py`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// content_hash = sha256 over the clinical entries (not the release stamp).
// MUST equal the pipeline test's pinned value.
// Repinned 2026-07-27: final B1 clinical-content sign-off; warfarin/prednisone
// scope narrowing, OCP-B6 suppression, pregnancy-only vitamin-K rejection,
// evidence-aligned copy, and machine-recorded review dispositions.
// Repinned again 2026-07-27 (B1 release correction): the metformin/B12 record's
// consumer "From food" copy no longer implies universal supplementation — it
// names food sources and routes to testing, matching that record's own
// risk-based recommendation.
// Repinned for the fail-closed B1.1 candidate delta: four suppressed records
// received evidence-aligned proposed copy and current sources, but remain
// hidden pending a separate licensed-pharmacist review.
// Repinned for the B1 closure correction: eleven active records now require
// exact-copy delta review (including the furosemide/thiamine monitoring tip),
// and record provenance distinguishes the AI evidence audit from the
// PharmaGuide Clinical Team's exact-fingerprint approval.
// Repinned 2026-07-30 for the bounded Clinical Team delta response: exact
// levothyroxine/calcium and orlistat/vitamin-A copy plus the requested
// acid-suppression/iron and SSRI/sodium evidence revisions.
// Repinned 2026-08-09 to complete the batch-01 repin. dsld_clean 0546d8b3
// ("land batch-01 watch-block removal, park copy softening") removed the
// proposed metformin/B12 watch_threshold block and PARKED the consumer-copy
// softening, so the clinician-pinned "4–5 years" recommendation ships exactly.
// That commit deferred this app-side half until the batch-01 release; the
// catalog bundle in c2b5e68 shipped the new artifact first, leaving this pin
// as the stale half of the contract. The pipeline pins the same value in
// scripts/tests/test_medication_depletions_artifact.py (verified green), so
// both halves now agree again.
// Repinned 2026-08-23 after the export boundary became fail-closed: only
// records with verified citation review now publish, while the artifact
// metadata accounts for every withheld needs-revision or rejected record.
const _pinnedContentHash =
    'sha256:f85e11b5937602ae4ef0b9aad5c1eb812401050418749437aa6927763ecb8a14';

void main() {
  test('bundled artifact matches the pinned pipeline content_hash', () {
    final file = File('assets/reference_data/medication_depletions.json');
    expect(file.existsSync(), isTrue, reason: 'bundled artifact missing');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final meta = data['_metadata'] as Map<String, dynamic>;
    expect(
      meta['content_hash'],
      _pinnedContentHash,
      reason:
          'app asset stale or drifted from the pipeline source — '
          'regenerate via the pipeline generator and update both pins',
    );
    // The versioned metadata the app's activation gate depends on.
    expect(meta['minimum_runtime_contract'], isA<int>());
    expect(meta['schema_version'], isNotNull);
  });
}
