# Submission names and outcome notifications — 2026-09-11

One existing submission service, one push sender, unchanged identity/review/scoring authority.

- Your Contributions shows catalog brand + product name when the catalog record is available, with UPC secondary.
- An owner can give an unresolved submission a private display name. It is not verified identity and never enters matching, approval, or scoring.
- Lock-screen copy distinguishes approved, published, new photos needed, and not accepted. No product name or reviewer prose is sent. Delayed deliveries read current submission state.
- Notifications remain per submission; no count-digest scheduler was added.

## Deployment

Both additive naming migrations were applied. The second corrects the first function's void response to the existing backend's required boolean acknowledgement. Keep both migrations: the first was already applied, so history must not be rewritten.

`review-product-submissions` version 17 is active. The migration dry-run reports the remote database is up to date. No historical notification was deliberately replayed; actual phone delivery has not been demonstrated in this change.

## Verification and remaining release work

- 74 focused Flutter tests passed; analyzer clean.
- 103 SQL harness cases passed, including authenticated-owner isolation, invalid labels, unchanged identity/review, and a true save acknowledgement.
- 8 push-builder tests passed; review function type-check passed.
- Full app check: 3,528 passed, one failure in `quick_check_catalog_interaction_test.dart:190`. The bundled catalog contains zero products tagged vinpocetine, while the existing gate requires a positive count. No catalog, interaction logic, or release test was changed in this task.

The app source is not a phone deployment. Resolve the catalog release gate and verify the bundled data before building/installing a new phone release. UI behavior has widget coverage, not a new physical-device visual inspection.

Next: diagnose the catalog gate against the canonical pipeline output (do not invent a product or weaken a clinical assertion), finish the held product reviews, then build from a committed hash through the documented build path.
