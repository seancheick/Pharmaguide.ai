#!/usr/bin/env bash
# Reserve the next iOS build number without skipping numbers after a failed IPA
# export. The latest successfully exported IPA is the source of truth.
set -euo pipefail

cd "$(dirname "$0")/.."

pubspec="${1:-pubspec.yaml}"
# The build number is compiled into the app as well, for the About screen. It
# is a copy of pubspec's, and the step that reserves a build owns both copies:
# reserving only one is how a hand-edited pubspec left them disagreeing.
app_version="$(dirname "$pubspec")/lib/core/utils/app_version.dart"
ipa="${PHARMAGUIDE_IOS_IPA_PATH:-build/ios/ipa/pharmaguide.ipa}"

if ! grep -qE '^const int kAppBuildNumber = [0-9]+;$' "$app_version" 2>/dev/null; then
  echo "prepare_ios_build_number: no 'const int kAppBuildNumber = <n>;' in $app_version" >&2
  exit 1
fi
version_line="$(grep -E '^version: ' "$pubspec" | head -1)"

if [[ ! "$version_line" =~ ^version:\ ([^+[:space:]]+)\+([0-9]+)$ ]]; then
  echo "prepare_ios_build_number: could not parse 'version: <name>+<build>' from '$version_line'" >&2
  exit 1
fi

version_name="${BASH_REMATCH[1]}"
current_build="${BASH_REMATCH[2]}"
latest_successful_build="${PHARMAGUIDE_LATEST_IPA_BUILD:-}"

if [[ -z "$latest_successful_build" ]]; then
  if [[ -f "$ipa" ]]; then
    latest_successful_build="$(
      unzip -p "$ipa" Payload/Runner.app/Info.plist |
        python3 -c '
import plistlib
import sys

print(plistlib.loads(sys.stdin.buffer.read())["CFBundleVersion"])
'
    )"
  else
    latest_successful_build=0
  fi
fi

if [[ ! "$latest_successful_build" =~ ^[0-9]+$ ]]; then
  echo "prepare_ios_build_number: latest successful IPA build is not an integer: '$latest_successful_build'" >&2
  exit 1
fi

target_build="$current_build"
if ((current_build <= latest_successful_build)); then
  target_build=$((latest_successful_build + 1))
fi

if ((target_build != current_build)); then
  sed -i.bak \
    "s|^version: .*|version: ${version_name}+${target_build}|" \
    "$pubspec"
  rm -f "$pubspec.bak"
  echo "iOS build number reserved: +${current_build} -> +${target_build}"
else
  echo "iOS build number +${current_build} is already reserved; reusing it"
fi

# Written every time, not only on a bump: a reused build must still leave the
# compiled copy saying the same number.
sed -i.bak \
  "s|^const int kAppBuildNumber = [0-9]*;$|const int kAppBuildNumber = ${target_build};|" \
  "$app_version"
rm -f "$app_version.bak"
if ! grep -qx "const int kAppBuildNumber = ${target_build};" "$app_version"; then
  echo "prepare_ios_build_number: could not write kAppBuildNumber = ${target_build}" >&2
  exit 1
fi
