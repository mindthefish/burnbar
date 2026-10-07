#!/bin/bash
# Creates a verified, notarized zip; does not publish or install the app.
# Required: BURNBAR_VERSION, BURNBAR_BUILD, CODESIGN_IDENTITY (Developer ID
# Application certificate name), NOTARY_KEYCHAIN_PROFILE (existing local profile).
# Usage: Scripts/release-app.sh [output-directory]; BURNBAR_ARCH defaults universal.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "error: $*" >&2; exit 1; }
: "${BURNBAR_VERSION:?set BURNBAR_VERSION}"
: "${BURNBAR_BUILD:?set BURNBAR_BUILD}"
: "${CODESIGN_IDENTITY:?set CODESIGN_IDENTITY}"
: "${NOTARY_KEYCHAIN_PROFILE:?set NOTARY_KEYCHAIN_PROFILE}"
[[ "$BURNBAR_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "invalid BURNBAR_VERSION"
[[ "$BURNBAR_BUILD" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "invalid BURNBAR_BUILD"
case "$CODESIGN_IDENTITY" in 'Developer ID Application: '*) ;; *) fail "use a Developer ID Application certificate name" ;; esac
output_dir="${1:-$repo_root/.build/releases}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
archive="$output_dir/Burnbar-$BURNBAR_VERSION-$BURNBAR_BUILD.zip"
[ ! -e "$archive" ] || fail "release archive already exists: $archive"
staging="$(mktemp -d "$output_dir/.Burnbar-release.XXXXXX")"
cleanup() { rm -rf -- "$staging"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
BURNBAR_ARCH="${BURNBAR_ARCH:-universal}" BURNBAR_HARDENED_RUNTIME=1 \
    "$repo_root/Scripts/build-app.sh" "$staging"
app="$staging/Burnbar.app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/submission.zip"
xcrun notarytool submit "$staging/submission.zip" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait --output-format json > "$staging/notary-result.json"
status="$(plutil -extract status raw -o - "$staging/notary-result.json")"
[ "$status" = Accepted ] || fail "notarization status: $status"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/release.zip"
mkdir "$staging/extracted"
ditto -x -k "$staging/release.zip" "$staging/extracted"
codesign --verify --deep --strict "$staging/extracted/Burnbar.app"
xcrun stapler validate "$staging/extracted/Burnbar.app"
mv -- "$staging/release.zip" "$archive"
echo "release ready: $archive"
