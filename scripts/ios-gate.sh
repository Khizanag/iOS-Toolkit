#!/bin/sh
# ios-gate.sh — the local release gate for an iOS app: strict lint, one
# warning-free build, then the tests without rebuilding. Apps call it from
# their pre-push hook in place of paid CI.
#
# Configuration lives in the app's Scripts/gate.conf (sourced as sh):
#   PROJECT=MyApp.xcodeproj      SCHEME=MyApp
#   UNIT_TESTS=MyAppTests        UI_TESTS=MyAppUITests     (optional)
#   DEVICE_NAME="iPhone 17 Pro"  DEVICE_OS=26.5            (empty = newest)
#   DEVICE_TYPE="iPhone 17 Pro"  (optional) create DEVICE_NAME as this model when
#                                missing — give each app its own gate simulator
#   CHECKS="Scripts/lint-copy.sh"                          (optional, run last)
#
# The simulator is resolved to its UDID and booted once; xcodebuild only ever
# sees `id=<UDID>`. A failing test does not trigger xcodebuild's diagnostics
# collection, which waits up to ten minutes on `simctl diagnose`; the result
# bundle already holds the failure. Builds go to <repo>/.build/gate so they stay warm between
# runs and never contend with Xcode's own DerivedData.
set -eu

usage() {
    cat <<'USAGE'
Usage: ios-gate.sh [--full] [--os <version>] [--device <name>] [-only-testing:<Target[/Suite]> ...]

  --full           also run UI_TESTS
  --os, --device   override DEVICE_OS / DEVICE_NAME from Scripts/gate.conf
  -only-testing:…  run just these tests (repeatable)
USAGE
}

say() { printf '→ %s\n' "$1"; }
die() { printf '✗ %s\n' "$1" >&2; exit "${2:-1}"; }
elapsed() { printf '  %ss\n' "$(( $(date +%s) - $1 ))"; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository" 64
conf="$root/Scripts/gate.conf"
[ -f "$conf" ] || die "no Scripts/gate.conf in $root" 64

PROJECT="" SCHEME="" UNIT_TESTS="" UI_TESTS="" DEVICE_NAME="iPhone 17 Pro" DEVICE_OS="" DEVICE_TYPE="" CHECKS=""
# shellcheck disable=SC1090
. "$conf"
[ -n "$PROJECT" ] && [ -n "$SCHEME" ] || die "Scripts/gate.conf must set PROJECT and SCHEME" 64

full=0
only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --full) full=1; shift ;;
        --os) [ $# -ge 2 ] || { usage >&2; exit 64; }; DEVICE_OS=$2; shift 2 ;;
        --device) [ $# -ge 2 ] || { usage >&2; exit 64; }; DEVICE_NAME=$2; shift 2 ;;
        -only-testing:*) only="$only $1"; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; exit 64 ;;
    esac
done
if [ -z "$only" ]; then
    [ -n "$UNIT_TESTS" ] && only="-only-testing:$UNIT_TESTS"
    [ "$full" = 1 ] && [ -n "$UI_TESTS" ] && only="$only -only-testing:$UI_TESTS"
fi

DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export DEVELOPER_DIR
script_dir=$(cd "$(dirname "$0")" && pwd -P)
. "$script_dir/lib/simulator.sh"

cd "$root"
derived="$root/.build/gate"
logs="$derived/Logs"
mkdir -p "$logs"
stamp=$(date +%Y%m%d-%H%M%S)

say "simulator: $DEVICE_NAME${DEVICE_OS:+ (iOS $DEVICE_OS)}"
udid=$(resolve_simulator "$DEVICE_NAME" "$DEVICE_OS")
if [ -z "$udid" ] && [ -n "$DEVICE_TYPE" ] && [ -n "$DEVICE_OS" ]; then
    udid=$(create_simulator "$DEVICE_NAME" "$DEVICE_TYPE" "$DEVICE_OS") || die "could not create simulator \"$DEVICE_NAME\""
    printf '  created %s\n' "$DEVICE_NAME"
fi
[ -n "$udid" ] || die "no available simulator named \"$DEVICE_NAME\"${DEVICE_OS:+ on iOS $DEVICE_OS} — see: xcrun simctl list devices available"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || die "simulator $udid did not boot"
printf '  %s\n' "$udid"

say "swiftlint --strict"
started=$(date +%s)
swiftlint lint --strict --quiet || die "lint failed"
elapsed "$started"

say "build for testing"
started=$(date +%s)
build_log="$logs/build-$stamp.log"
xcodebuild build-for-testing \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "id=$udid" -derivedDataPath "$derived" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO >"$build_log" 2>&1 \
    || { grep -E "error:" "$build_log" | sort -u | head -20 >&2; die "build failed — full log: $build_log"; }
# Only warnings in this repo's sources count. Tool chatter (appintentsmetadataprocessor)
# has no path, and SDK headers (StoreKitTest's own deprecations) are not ours to fix.
warnings=$(grep -F "$root/" "$build_log" | grep -F ": warning:" | sort -u || true)
[ -z "$warnings" ] || { printf '%s\n' "$warnings" >&2; die "build has warnings — full log: $build_log"; }
elapsed "$started"

if [ -n "$only" ]; then
    say "test$(printf '%s' "$only" | sed 's/^ */ /')"
    started=$(date +%s)
    test_log="$logs/test-$stamp.log"
    result="$derived/Results/$stamp.xcresult"
    # shellcheck disable=SC2086
    xcodebuild test-without-building \
        -project "$PROJECT" -scheme "$SCHEME" \
        -destination "id=$udid" -derivedDataPath "$derived" \
        -resultBundlePath "$result" -collect-test-diagnostics never \
        $only >"$test_log" 2>&1 || status=$?
    grep -E "Test run with|Executed [0-9]+ tests?|✘|error:|recorded an issue" "$test_log" | tail -20 || true
    [ "${status:-0}" = 0 ] || die "tests failed — log: $test_log · results: $result"
    printf '  results: %s\n' "$result"
    elapsed "$started"
fi

for check in $CHECKS; do
    say "$check"
    "$root/$check" || die "$check failed"
done

printf '✓ gate passed\n'
