#!/usr/bin/env bash
# Increment the +N build number in pubspec.yaml.
#
# pubspec's `version: <name>+<build>` is the single source for both iOS
# CFBundleVersion ($(FLUTTER_BUILD_NUMBER)) and Android versionCode. App Store
# Connect / Play require a unique, increasing build number per upload, so this
# bumps +N -> +(N+1). The version NAME (e.g. 1.0.0) is left untouched.
#
# Usage:  bump_build_number.sh [path/to/pubspec.yaml]   (default: repo pubspec)
set -euo pipefail
cd "$(dirname "$0")/.."
file="${1:-pubspec.yaml}"

line="$(grep -E '^version: ' "$file" | head -1)"   # e.g. "version: 1.0.0+7"
name="${line#version: }"; name="${name%+*}"          # "1.0.0"
cur="${line##*+}"                                     # "7"

if ! [[ "$cur" =~ ^[0-9]+$ ]]; then
  echo "bump_build_number: could not parse a +N build number from '$line'" >&2
  exit 1
fi

next=$((cur + 1))
# -i.bak works on both BSD (macOS) and GNU sed; remove the backup after.
sed -i.bak "s|^version: .*|version: ${name}+${next}|" "$file" && rm -f "$file.bak"
echo "build number: +${cur} -> +${next}  (${file})"
