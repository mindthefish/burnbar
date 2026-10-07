#!/bin/bash
# Exercises destructive failure paths with an isolated, credential-free toolchain.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/burnbar-build-test.XXXXXX")"
test_root="$(cd "$test_root" && pwd -P)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/binary" "$test_root/install"
printf 'new binary\n' > "$test_root/binary/Burnbar"
chmod +x "$test_root/binary/Burnbar"
export TEST_ROOT="$test_root" TEST_INSTALL_DIR="$test_root/install"

cat > "$test_root/bin/tool" <<'STUB'
#!/bin/bash
set -euo pipefail
tool="$(basename "$0")"
echo "$tool $*" >> "$TEST_ROOT/tools.log"
case "$tool" in
    swift)
        if [ "$1" = build ]; then
            [ "${TEST_FAIL:-}" != build ] || exit 1
            case " $* " in *' --show-bin-path '*) echo "$TEST_ROOT/binary" ;; esac
        else
            mkdir -p "$2/Assets/AppIcon.iconset"
        fi
        ;;
    iconutil) while [ "$1" != -o ]; do shift; done; printf 'icon\n' > "$2" ;;
    security)
        [ "${TEST_FAIL:-}" != identity ] || exit 0
        echo ' 1) ABCDEF0123456789ABCDEF0123456789ABCDEF01 "Developer ID Application: Fixture (TEST)"'
        ;;
    codesign)
        if [ "$1" = --force ]; then
            [ "${TEST_FAIL:-}" != signing ] || exit 1
        elif [ "${TEST_FAIL:-}" = staged_verify ]; then
            exit 1
        elif [ "${TEST_FAIL:-}" = installed_verify ] && [ "${!#}" = "$TEST_INSTALL_DIR/Burnbar.app" ]; then
            exit 1
        elif [ "${TEST_FAIL:-}" = installed_signal ] && [ "${!#}" = "$TEST_INSTALL_DIR/Burnbar.app" ]; then
            kill -TERM "$PPID"
        fi
        ;;
    cp) [ "${TEST_FAIL:-}" != copy ] || exit 1; exec /bin/cp "$@" ;;
    mv)
        source="$1"
        if [ "$source" = -- ]; then source="$2"; fi
        case "$source" in
            */.Burnbar-build.*/Burnbar.app)
                [ "${TEST_FAIL:-}" != install ] || exit 1
                ;;
        esac
        exec /bin/mv "$@"
        ;;
    lipo)
        if [ "$1" = -create ]; then
            [ "$4" = -output ]
            /bin/cp "$2" "$5"
        else
            [ "$#" = 3 ] && [ "$2" = -verify_arch ]
            case "$3" in arm64|x86_64) ;; *) exit 1 ;; esac
            [ -f "$1" ]
        fi
        ;;
    xcrun)
        if [ "$1" = notarytool ]; then
            echo "{\"status\":\"${TEST_NOTARY_STATUS:-Accepted}\"}"
        fi
        ;;
    spctl) ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$test_root/bin/tool"
for tool in swift iconutil security codesign cp mv lipo xcrun spctl; do
    ln -s tool "$test_root/bin/$tool"
done
export PATH="$test_root/bin:$PATH"
unset CODESIGN_IDENTITY BURNBAR_VERSION BURNBAR_BUILD BURNBAR_ARCH BURNBAR_HARDENED_RUNTIME

assert_old_app() {
    [ "$(cat "$TEST_INSTALL_DIR/Burnbar.app/original")" = 'working app' ]
    [ "$(find "$TEST_INSTALL_DIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1 ]
}
reset_old_app() {
    rm -rf -- "$TEST_INSTALL_DIR/Burnbar.app"
    mkdir "$TEST_INSTALL_DIR/Burnbar.app"
    printf 'working app\n' > "$TEST_INSTALL_DIR/Burnbar.app/original"
}
for failure in build copy signing staged_verify install installed_verify installed_signal; do
    reset_old_app
    if TEST_FAIL="$failure" "$repo_root/Scripts/build-app.sh" "$TEST_INSTALL_DIR" > "$test_root/output.log" 2>&1; then
        echo "error: $failure unexpectedly succeeded" >&2
        exit 1
    fi
    assert_old_app
    echo "passed: $failure preserves the working app and cleans staging"
done
rm -rf -- "$TEST_INSTALL_DIR/Burnbar.app"
if TEST_FAIL=installed_verify "$repo_root/Scripts/build-app.sh" "$TEST_INSTALL_DIR" > "$test_root/output.log" 2>&1; then
    echo 'error: invalid first installation unexpectedly succeeded' >&2
    exit 1
fi
[ "$(find "$TEST_INSTALL_DIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 0 ]
echo 'passed: invalid first installation removes the new bundle and staging'
reset_old_app
if TEST_FAIL=identity CODESIGN_IDENTITY='Developer ID Application: Fixture (TEST)' \
    "$repo_root/Scripts/build-app.sh" "$TEST_INSTALL_DIR" > "$test_root/output.log" 2>&1; then
    echo 'error: missing requested identity unexpectedly succeeded' >&2
    exit 1
fi
assert_old_app
echo 'passed: missing requested identity fails without ad-hoc fallback'

BURNBAR_VERSION=2.3.4 BURNBAR_BUILD=42 BURNBAR_ARCH=universal \
    "$repo_root/Scripts/build-app.sh" "$TEST_INSTALL_DIR" > "$test_root/output.log" 2>&1
[ ! -e "$TEST_INSTALL_DIR/Burnbar.app/original" ]
[ "$(cat "$TEST_INSTALL_DIR/Burnbar.app/Contents/MacOS/Burnbar")" = 'new binary' ]
[ "$(plutil -extract CFBundleShortVersionString raw -o - "$TEST_INSTALL_DIR/Burnbar.app/Contents/Info.plist")" = 2.3.4 ]
[ "$(plutil -extract CFBundleVersion raw -o - "$TEST_INSTALL_DIR/Burnbar.app/Contents/Info.plist")" = 42 ]
grep -F -- '-verify_arch arm64' "$test_root/tools.log" >/dev/null
grep -F -- '-verify_arch x86_64' "$test_root/tools.log" >/dev/null
grep -F 'codesign --force --sign - ' "$test_root/tools.log" >/dev/null
echo 'passed: replacement, version/build metadata, universal build, ad-hoc default'

# Notarization is stubbed; ditto and plutil still verify archive/plist plumbing.
export BURNBAR_VERSION=2.3.4 BURNBAR_BUILD=42
export CODESIGN_IDENTITY='Developer ID Application: Fixture (TEST)'
export NOTARY_KEYCHAIN_PROFILE='test-profile-never-read'
if TEST_NOTARY_STATUS=Invalid "$repo_root/Scripts/release-app.sh" "$test_root/releases" > "$test_root/output.log" 2>&1; then
    echo 'error: rejected notarization unexpectedly succeeded' >&2
    exit 1
fi
[ ! -e "$test_root/releases/Burnbar-2.3.4-42.zip" ]
[ "$(find "$test_root/releases" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 0 ]
"$repo_root/Scripts/release-app.sh" "$test_root/releases" > "$test_root/output.log" 2>&1
[ -f "$test_root/releases/Burnbar-2.3.4-42.zip" ]
grep -F -- '--options runtime --timestamp' "$test_root/tools.log" >/dev/null
grep -F 'xcrun stapler staple' "$test_root/tools.log" >/dev/null
grep -F 'spctl --assess --type execute' "$test_root/tools.log" >/dev/null
if "$repo_root/Scripts/release-app.sh" "$test_root/releases" > "$test_root/output.log" 2>&1; then
    echo 'error: existing release archive unexpectedly overwritten' >&2
    exit 1
fi
echo 'passed: notarization rejection, hardened signing, stapling, zip verification, overwrite refusal'
