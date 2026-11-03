Clearly fake safety-alert data for tests and the simulator notice screenshot. Never publish it.
`interaction_rule_base_feed.json` (what `feed_path` names) and `interaction_rule_feed.json` (the
superset `manifest.extended_feed` names) are the output of the pipeline's
`build_safety_alerts.stage()` over the fake records in its `scripts/tests/fixtures/safety_alerts/`,
so both repos test the same bytes.
