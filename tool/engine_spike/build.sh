#!/usr/bin/env bash
# Engine portability spike: build + run the unchanged lib/ engine three ways
# (Dart VM, AOT native exe, dart2js under Deno and Node) and diff the findings.
# Run from the repo root after `flutter pub get` and extract_fixtures.sh.
set -euo pipefail
DART="${DART:-$HOME/Development/flutter/bin/dart}"
SPIKE=tool/engine_spike
B=$SPIKE/.build
PKG="--packages=$B/package_config.json"
ENTRY=$SPIKE/bin/engine_spike.dart

python3 $SPIKE/make_overlay.py

findings() { grep -o '{"pre_add".*' "$1" | head -1; }
timing()   { grep -o 'TIMING .*' "$1" | head -1; }
cpu()      { grep -E 'real|maximum resident' "$1" | tr -s ' ' | tr '\n' ' '; }

echo "== Dart VM (JIT)"
"$DART" run $PKG "$ENTRY" > "$B/vm.out" 2>&1
findings "$B/vm.out" > "$B/vm.json"
mkdir -p $SPIKE/golden
python3 -m json.tool "$B/vm.json" > $SPIKE/golden/spike_findings.json
timing "$B/vm.out"

echo "== AOT native (dart compile exe)"
"$DART" compile exe $PKG "$ENTRY" -o "$B/engine_spike.exe" > "$B/exe.compile.log" 2>&1
ls -l "$B/engine_spike.exe" | awk '{print "exe bytes", $5}'
/usr/bin/time -l "$B/engine_spike.exe" > "$B/exe.out" 2> "$B/exe.time"
findings "$B/exe.out" > "$B/exe.json"
timing "$B/exe.out"; cpu "$B/exe.time"; echo

echo "== dart2js -O2"
"$DART" compile js -O2 $PKG "$ENTRY" -o "$B/engine_spike.js" > "$B/js.compile.log" 2>&1
ls -l "$B/engine_spike.js" | awk '{print "js bytes", $5}'
gzip -9 -c "$B/engine_spike.js" | wc -c | awk '{print "js gzip bytes", $1}'

if command -v deno >/dev/null; then
  echo "-- Deno $(deno --version | head -1)"
  /usr/bin/time -l deno run --quiet "$B/engine_spike.js" > "$B/deno.out" 2> "$B/deno.time"
  findings "$B/deno.out" > "$B/deno.json"
  timing "$B/deno.out"; cpu "$B/deno.time"; echo
fi
if command -v node >/dev/null; then
  echo "-- Node $(node --version)"
  /usr/bin/time -l node -e "globalThis.self = globalThis; require('$PWD/$B/engine_spike.js')" > "$B/node.out" 2> "$B/node.time"
  findings "$B/node.out" > "$B/node.json"
  timing "$B/node.out"; cpu "$B/node.time"; echo
fi

echo "== Full-closure probe (imports all 29 engine files; compile-only)"
"$DART" compile js -O2 $PKG $SPIKE/bin/closure_probe.dart -o "$B/closure_probe.js" > "$B/probe.js.log" 2>&1 && echo "probe js: compiled"
"$DART" compile exe $PKG $SPIKE/bin/closure_probe.dart -o "$B/closure_probe.exe" > "$B/probe.exe.log" 2>&1 && echo "probe exe: compiled"

echo "== Parity (canonical findings JSON must be byte-identical)"
for f in exe deno node; do
  [ -s "$B/$f.json" ] || { echo "$f: MISSING"; continue; }
  if cmp -s "$B/vm.json" "$B/$f.json"; then echo "$f == vm"; else echo "$f DIFFERS from vm"; fi
done
