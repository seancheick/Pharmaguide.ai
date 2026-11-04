#!/usr/bin/env bash
# A store build with no alert-feed key could never verify a feed: it would show no
# alert from the feed, and no all-clear, until the next app update. TestFlight may
# go without one, for testing before the key exists.
set -euo pipefail

source_file="${1:-lib/services/release_manifest.dart}"

if [[ "${PHARMAGUIDE_IOS_DISTRIBUTION:-}" == "testflight" ]]; then
  exit 0
fi

# Looks at the map itself, so its formatting and any comment inside can't pass as
# a key. A key is a quoted ID with a 32-byte public key in hex.
python3 - "$source_file" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
found = re.search(r"_kProductionAlertFeedKeys\s*=[^{;]*\{(.*?)\}\s*;", source, re.DOTALL)
if not found:
    sys.exit(f"error: can't find _kProductionAlertFeedKeys in {sys.argv[1]}")
body = re.sub(r"/\*.*?\*/|//[^\n]*", "", found.group(1), flags=re.DOTALL)
if not re.search(r"""['"][A-Za-z0-9._-]+['"]\s*:\s*['"][0-9a-fA-F]{64}['"]""", body):
    sys.exit(
        "error: this store build has no safety-alert feed key.\n"
        "Pin the public key first: docs/RELEASE_SIGNING_RUNBOOK.md in the pipeline repo."
    )
PY
