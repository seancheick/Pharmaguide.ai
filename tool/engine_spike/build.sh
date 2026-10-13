#!/usr/bin/env bash
# Engine portability spike: build + run the unchanged lib/ engine three ways
# (Dart VM, AOT native exe, dart2js under Deno and Node) and diff the findings.
# Run from the repo root after `flutter pub get`, using the reviewed fixtures.
# Never refresh fixtures or the reviewed golden as part of verification.
set -euo pipefail
DART="${DART:-$HOME/Development/flutter/bin/dart}"
SPIKE=tool/engine_spike
B=$SPIKE/.build
PKG="--packages=$B/package_config.json"
ENTRY=$SPIKE/bin/engine_spike.dart
case "$(uname -s)" in
  Darwin) TIME_FLAG=-l ;;
  Linux) TIME_FLAG=-v ;;
  *) echo "Unsupported timing platform" >&2; exit 1 ;;
esac

for runtime in deno node; do
  command -v "$runtime" >/dev/null || { echo "Required runtime missing: $runtime" >&2; exit 1; }
done
python3 $SPIKE/make_overlay.py

findings() { grep -o '{"pre_add".*' "$1" | head -1; }
timing()   { grep -o 'TIMING .*' "$1" | head -1; }
cpu()      { grep -Ei 'real|elapsed|maximum resident' "$1" | tr -s ' ' | tr '\n' ' '; }

echo "== Dart VM (JIT)"
"$DART" run $PKG "$ENTRY" > "$B/vm.out" 2>&1
findings "$B/vm.out" > "$B/vm.json"
python3 -m json.tool "$B/vm.json" > "$B/vm.golden.json"
python3 - "$B/vm.json" "$SPIKE/golden/spike_findings.json" <<'PY'
import json, sys
with open(sys.argv[1]) as actual, open(sys.argv[2]) as expected:
    if json.load(actual) != json.load(expected):
        sys.exit('VM differs from reviewed golden; review .build/vm.golden.json. Golden was not changed.')
PY
timing "$B/vm.out"

echo "== AOT native (dart compile exe)"
"$DART" compile exe $PKG "$ENTRY" -o "$B/engine_spike.exe" > "$B/exe.compile.log" 2>&1
ls -l "$B/engine_spike.exe" | awk '{print "exe bytes", $5}'
/usr/bin/time "$TIME_FLAG" "$B/engine_spike.exe" > "$B/exe.out" 2> "$B/exe.time"
findings "$B/exe.out" > "$B/exe.json"
timing "$B/exe.out"; cpu "$B/exe.time"; echo

echo "== dart2js -O2"
"$DART" compile js -O2 $PKG "$ENTRY" -o "$B/engine_spike.js" > "$B/js.compile.log" 2>&1
ls -l "$B/engine_spike.js" | awk '{print "js bytes", $5}'
gzip -9 -c "$B/engine_spike.js" | wc -c | awk '{print "js gzip bytes", $1}'

if command -v deno >/dev/null; then
  echo "-- Deno $(deno --version | head -1)"
  /usr/bin/time "$TIME_FLAG" deno run --quiet "$B/engine_spike.js" > "$B/deno.out" 2> "$B/deno.time"
  findings "$B/deno.out" > "$B/deno.json"
  timing "$B/deno.out"; cpu "$B/deno.time"; echo
fi
if command -v node >/dev/null; then
  echo "-- Node $(node --version)"
  /usr/bin/time "$TIME_FLAG" node -e "globalThis.self = globalThis; require('$PWD/$B/engine_spike.js')" > "$B/node.out" 2> "$B/node.time"
  findings "$B/node.out" > "$B/node.json"
  timing "$B/node.out"; cpu "$B/node.time"; echo
fi

echo "== Full-closure probe (imports all 29 engine files; compile-only)"
"$DART" compile js -O2 $PKG $SPIKE/bin/closure_probe.dart -o "$B/closure_probe.js" > "$B/probe.js.log" 2>&1
echo "probe js: compiled"
"$DART" compile exe $PKG $SPIKE/bin/closure_probe.dart -o "$B/closure_probe.exe" > "$B/probe.exe.log" 2>&1
echo "probe exe: compiled"

echo "== Parity (canonical findings JSON must be byte-identical)"
for f in exe deno node; do
  [ -s "$B/$f.json" ] || { echo "$f: MISSING" >&2; exit 1; }
  if cmp -s "$B/vm.json" "$B/$f.json"; then echo "$f == vm"; else echo "$f DIFFERS from vm" >&2; exit 1; fi
done
