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
const _pinnedContentHash =
    'sha256:180a7380a03f20066103030d496124ee9a5e1c8e65167da095b627ace36f7f98';

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
