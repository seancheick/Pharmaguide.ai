#!/usr/bin/env bash
# Build a release IPA and verify that the exported artifact matches the build
# number reserved in pubspec.yaml. If Flutter archives successfully but does not
# export an IPA, retry the export with Xcode provisioning updates enabled.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="${PHARMAGUIDE_IOS_BUILD_ROOT:-$(cd "$script_dir/.." && pwd)}"
flutter_bin="${1:?usage: build_ios_release.sh <flutter-binary> [flutter-options...]}"
shift

cd "$repo_root"

pubspec="$repo_root/pubspec.yaml"
ipa="$repo_root/build/ios/ipa/pharmaguide.ipa"
archive="$repo_root/build/ios/archive/Runner.xcarchive"
export_options="$script_dir/../ios/ExportOptions.plist"
xcodebuild_bin="${PHARMAGUIDE_XCODEBUILD_BIN:-xcodebuild}"

PHARMAGUIDE_IOS_IPA_PATH="$ipa" \
  bash "$script_dir/prepare_ios_build_number.sh" "$pubspec"

version_line="$(grep -E '^version: ' "$pubspec" | head -1)"
expected_build="${version_line##*+}"

ipa_build_number() {
  local candidate="$1"
  [[ -f "$candidate" ]] || return 1
  unzip -p "$candidate" Payload/Runner.app/Info.plist |
    plutil -extract CFBundleVersion raw -o - -
}

matching_ipa_exists() {
  local actual_build
  actual_build="$(ipa_build_number "$ipa" 2>/dev/null || true)"
  [[ "$actual_build" == "$expected_build" ]]
}

plutil -lint "$export_options" >/dev/null

if ! "$flutter_bin" build ipa "$@" \
  --export-options-plist="$export_options" \
  --release; then
  echo "Flutter did not finish the IPA export; checking the archive fallback." >&2
fi

if ! matching_ipa_exists; then
  archive_info="$archive/Info.plist"
  archive_build=""
  if [[ -f "$archive_info" ]]; then
    archive_build="$(
      plutil -extract ApplicationProperties.CFBundleVersion \
        raw -o - "$archive_info" 2>/dev/null || true
    )"
  fi

  if [[ "$archive_build" == "$expected_build" ]]; then
    export_dir="$(mktemp -d "${TMPDIR:-/tmp}/pharmaguide-ios-export.XXXXXX")"
    trap 'rm -rf "$export_dir"' EXIT

    if "$xcodebuild_bin" -exportArchive \
      -archivePath "$archive" \
      -exportPath "$export_dir" \
      -exportOptionsPlist "$export_options" \
      -allowProvisioningUpdates; then
      shopt -s nullglob
      exported_ipas=("$export_dir"/*.ipa)
      shopt -u nullglob
      if ((${#exported_ipas[@]} == 1)); then
        mkdir -p "$(dirname "$ipa")"
        cp "${exported_ipas[0]}" "$ipa"
      fi
    fi
  fi
fi

if ! matching_ipa_exists; then
  echo "build_ios_release: no App Store IPA matching reserved build +${expected_build} was exported" >&2
  echo "The build number remains reserved and will be reused on the next attempt." >&2
  exit 1
fi

echo "App Store IPA ready: build +${expected_build} at $ipa"
