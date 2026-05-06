# Profile-gate evaluator fixture (Dart side of the drift contract)

`profile_gate_test_cases.json` is a **byte-identical copy** of the
authoritative fixture in the pipeline repo:

```
dsld_clean/scripts/data/profile_gate_test_cases.json
```

Both Dart and Python evaluators must produce identical
`(fires, severity)` output for every case. This is the v6.0 ADR's
drift-prevention contract.

## Re-sync

When the pipeline updates the fixture, copy the new file in:

```bash
cp /Users/seancheick/Downloads/dsld_clean/scripts/data/profile_gate_test_cases.json \
   /Users/seancheick/PharmaGuide\ ai/test/fixtures/profile_gate/

# Verify checksums match
shasum -a 256 /Users/seancheick/Downloads/dsld_clean/scripts/data/profile_gate_test_cases.json \
              /Users/seancheick/PharmaGuide\ ai/test/fixtures/profile_gate/profile_gate_test_cases.json
```

The drift-contract test
(`test/services/warnings/profile_gate_evaluator_test.dart`) compares this
file's SHA-256 against the pipeline repo's copy and fails if they
diverge — preventing silent drift between the two implementations.
