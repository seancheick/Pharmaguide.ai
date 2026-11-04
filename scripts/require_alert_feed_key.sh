#!/usr/bin/env bash
# A store build with no alert-feed key could never verify a feed: it would show no
# alert from the feed, and no all-clear, until the next app update. TestFlight may
# go without one, for testing before the key exists.
set -euo pipefail

source_file="${1:-lib/services/release_manifest.dart}"

if [[ "${PHARMAGUIDE_IOS_DISTRIBUTION:-}" == "testflight" ]]; then
  exit 0
fi
if ! grep -q '_kProductionAlertFeedKeys = {' "$source_file"; then
  echo "error: can't find _kProductionAlertFeedKeys in $source_file" >&2
  exit 1
fi
if grep -q '_kProductionAlertFeedKeys = {};' "$source_file"; then
  echo "error: this store build has no safety-alert feed key." >&2
  echo "Pin the public key first: docs/RELEASE_SIGNING_RUNBOOK.md in the pipeline repo." >&2
  exit 1
fi
