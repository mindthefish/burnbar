#!/bin/bash
# Usage: Scripts/build-app.sh [install-directory]
# BURNBAR_VERSION=0.1.0 BURNBAR_BUILD=1 BURNBAR_ARCH=native|universal|arm64|x86_64
# CODESIGN_IDENTITY defaults to ad-hoc (-). An explicit certificate must exist.
# BURNBAR_HARDENED_RUNTIME=1 enables the runtime and timestamp for release signing.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_dir="${1:-/Applications}"
version="${BURNBAR_VERSION:-0.1.0}"
build="${BURNBAR_BUILD:-1}"
architecture="${BURNBAR_ARCH:-native}"
identity="${CODESIGN_IDENTITY--}"
runtime="${BURNBAR_HARDENED_RUNTIME:-0}"

fail() { echo "error: $*" >&2; exit 1; }
[[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "invalid BURNBAR_VERSION"
[[ "$build" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "invalid BURNBAR_BUILD"
case "$architecture" in native|universal|arm64|x86_64) ;; *) fail "invalid BURNBAR_ARCH" ;; esac
case "$runtime" in 0|1) ;; *) fail "BURNBAR_HARDENED_RUNTIME must be 0 or 1" ;; esac
[ -n "$identity" ] || fail "CODESIGN_IDENTITY must not be empty"
if [ "$identity" != "-" ]; then
    identities="$(security find-identity -v -p codesigning)"
    if [[ "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
        echo "$identities" | grep -Fi -- " $identity " >/dev/null || fail "signing identity not found"
    else
        echo "$identities" | grep -F -- "\"$identity\"" >/dev/null || fail "signing identity not found"
    fi
elif [ "$runtime" = 1 ]; then
    fail "hardened release signing requires a certificate"
fi
[ -d "$install_dir" ] && [ -w "$install_dir" ] || fail "$install_dir must be an existing writable directory"
install_dir="$(cd "$install_dir" && pwd)"
app_bundle="$install_dir/Burnbar.app"
[ ! -L "$app_bundle" ] || fail "refusing to replace a symbolic-link app bundle"
[ ! -e "$app_bundle" ] || [ -d "$app_bundle" ] || fail "existing app bundle is not a directory"

# All bundle mutations stay on one filesystem. Only the task-owned directory is
# removed by cleanup; an old app is retained until the installed app verifies.
staging="$(mktemp -d "$install_dir/.Burnbar-build.XXXXXX")"
staged_app="$staging/Burnbar.app"
backup="$staging/previous.app"
installed=0
completed=0
lock_owned=0
cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ "$completed" = 0 ]; then
        if [ "$installed" = 1 ] && ! rm -rf -- "$app_bundle"; then
            echo "error: cleanup failed; original app preserved at $backup" >&2
            exit 1
        fi
        if [ -d "$backup" ]; then
            if ! mv -- "$backup" "$app_bundle"; then
                echo "error: rollback failed; original app preserved at $backup" >&2
                exit 1
            fi
        fi
    fi
    rm -rf -- "$staging"
    if [ "$lock_owned" = 1 ]; then rmdir "$install_dir/.Burnbar-install.lock"; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$install_dir/.Burnbar-install.lock" || fail "another installation is in progress (or an interrupted installation left .Burnbar-install.lock)"
lock_owned=1

cd "$repo_root"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$staging/Assets"
build_binary() {
    arch="$1"
    scratch="$repo_root/.build/app-$arch"
    args=(--scratch-path "$scratch" -c release --product Burnbar)
    if [ "$arch" != native ]; then args+=(--arch "$arch"); fi
    swift build "${args[@]}"
    binary_dir="$(swift build "${args[@]}" --show-bin-path)"
    cp -- "$binary_dir/Burnbar" "$staging/Burnbar-$arch"
}
if [ "$architecture" = universal ]; then
    build_binary arm64
    build_binary x86_64
    lipo -create "$staging/Burnbar-arm64" "$staging/Burnbar-x86_64" -output "$staged_app/Contents/MacOS/Burnbar"
    for arch in arm64 x86_64; do
        lipo "$staged_app/Contents/MacOS/Burnbar" -verify_arch "$arch"
    done
else
    build_binary "$architecture"
    cp -- "$staging/Burnbar-$architecture" "$staged_app/Contents/MacOS/Burnbar"
fi
swift Scripts/make-icon.swift "$staging"
iconutil -c icns "$staging/Assets/AppIcon.iconset" -o "$staged_app/Contents/Resources/AppIcon.icns"
if [ -f "$repo_root/LICENSE" ]; then cp -- "$repo_root/LICENSE" "$staged_app/Contents/Resources/LICENSE"; fi

cat > "$staged_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Burnbar</string>
    <key>CFBundleDisplayName</key><string>Burnbar</string>
    <key>CFBundleExecutable</key><string>Burnbar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.mindthefish.burnbar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$staged_app/Contents/Info.plist"
sign_args=(--force --sign "$identity")
if [ "$runtime" = 1 ]; then sign_args+=(--options runtime --timestamp); fi
codesign "${sign_args[@]}" "$staged_app"
codesign --verify --deep --strict "$staged_app"

if [ -e "$app_bundle" ]; then mv -- "$app_bundle" "$backup"; fi
installed=1
mv -- "$staged_app" "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
completed=1
echo "installed: $app_bundle (version $version, build $build, $architecture; signed with: $identity)"
