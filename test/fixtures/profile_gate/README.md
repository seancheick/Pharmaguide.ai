# Profile-gate evaluator fixture (Dart side of the drift contract)

`profile_gate_test_cases.json` is a **byte-identical copy** of the
authoritative fixture in the pipeline repo:

```
dsld_clean/scripts/data/profile_gate_test_cases.json
```

Both the Dart and Python profile_gate evaluators must produce identical
`(fires, severity)` output for every case. This is the v6.0 ADR's
drift-prevention contract.

## How drift is caught

Two independent guards, one per repo, both pinned to the **same** SHA-256:

- **This repo** — `test/services/warnings/profile_gate_fixture_sync_test.dart`
  hashes this vendored copy and asserts it equals the pinned canonical hash.
  `profile_gate_evaluator_test.dart` then proves the Dart evaluator agrees
  with every case in it.
- **Pipeline repo** — `scripts/tests/test_profile_gate_fixture_sync.py` pins
  the identical hash against the canonical file, and
  `test_profile_gate_contract.py` proves the Python evaluator agrees.

Because both pins hold the same value, the fixture cannot change in either
repo without a visible, reviewed pin bump in **both** — that lockstep is the
actual cross-repo parity contract. (An earlier version of this README claimed
`profile_gate_evaluator_test.dart` itself SHA-256-compared against the pipeline
copy. It never did; the pinned-hash tests above are what actually enforce it.)

## Re-syncing the fixture (when you intend to change it)

1. Edit the canonical file in the pipeline repo.
2. Recompute the hash:
   ```bash
   shasum -a 256 /Users/seancheick/Downloads/dsld_clean/scripts/data/profile_gate_test_cases.json
   ```
3. Copy it into this repo:
   ```bash
   cp /Users/seancheick/Downloads/dsld_clean/scripts/data/profile_gate_test_cases.json \
      "/Users/seancheick/PharmaGuide ai/test/fixtures/profile_gate/"
   ```
4. Update `PINNED_SHA256` in the pipeline test **and** `pinnedSha256` in this
   repo's `profile_gate_fixture_sync_test.dart` to the new hash.
5. Run both test suites; both fixture-sync tests must go green.
