Clearly fake safety-alert data for tests and the simulator notice screenshot. Never publish it.
`interaction_rule_feed.json` is the output of the pipeline's `build_safety_alerts.stage()` over the
fake records in its `scripts/tests/fixtures/safety_alerts/`, so both repos test the same bytes.
