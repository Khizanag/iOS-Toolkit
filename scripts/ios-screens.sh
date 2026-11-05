#!/bin/sh
# ios-screens.sh — see the app: runs UI tests on the gate's simulator, under whichever
# accessibility settings you ask for, and puts every screenshot they keep on a
# contact sheet. Layout bugs at large text sizes show up here and nowhere else.
#
# Configuration is the app's Scripts/gate.conf, plus:
#   SCREENS_TESTS="MyAppUITests/EveryScreenUITests"   (what -only-testing defaults to)
#
# A screenshot counts when its test keeps it under a name:
#   XCTAttachment(screenshot: …), .name = "01-home", .lifetime = .keepAlways
#
# The simulator's settings are put back on exit, whatever happened.
set -eu

usage() {
    cat <<'USAGE'
Usage: ios-screens.sh [--dark] [--ax5] [--contrast] [--reduce] [--a11y]
                      [--os <version>] [--device <name>] [-only-testing:<Target[/Suite]> ...]

  --dark       Dark Mode
  --ax5        the largest accessibility text size
  --contrast   Increase Contrast
  --reduce     Reduce Motion and Reduce Transparency
  --a11y       all four
  --os, --device   override DEVICE_OS / DEVICE_NAME from Scripts/gate.conf
USAGE
}

say() { printf '→ %s\n' "$1"; }
die() { printf '✗ %s\n' "$1" >&2; exit "${2:-1}"; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository" 64
conf="$root/Scripts/gate.conf"
[ -f "$conf" ] || die "no Scripts/gate.conf in $root" 64

PROJECT="" SCHEME="" UNIT_TESTS="" UI_TESTS="" DEVICE_NAME="iPhone 17 Pro" DEVICE_OS="" SCREENS_TESTS=""
# shellcheck disable=SC1090
. "$conf"
[ -n "$PROJECT" ] && [ -n "$SCHEME" ] || die "Scripts/gate.conf must set PROJECT and SCHEME" 64

dark=0 ax5=0 contrast=0 reduce=0 only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dark) dark=1; shift ;;
        --ax5) ax5=1; shift ;;
        --contrast) contrast=1; shift ;;
        --reduce) reduce=1; shift ;;
        --a11y) dark=1; ax5=1; contrast=1; reduce=1; shift ;;
        --os) [ $# -ge 2 ] || { usage >&2; exit 64; }; DEVICE_OS=$2; shift 2 ;;
        --device) [ $# -ge 2 ] || { usage >&2; exit 64; }; DEVICE_NAME=$2; shift 2 ;;
        -only-testing:*) only="$only $1"; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; exit 64 ;;
    esac
done
if [ -z "$only" ]; then
    for test in $SCREENS_TESTS; do
        only="$only -only-testing:$test"
    done
fi
[ -n "$only" ] || die "name the tests: SCREENS_TESTS in Scripts/gate.conf, or -only-testing:…" 64

DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export DEVELOPER_DIR
script_dir=$(cd "$(dirname "$0")" && pwd -P)
. "$script_dir/lib/simulator.sh"

cd "$root"
udid=$(resolve_simulator "$DEVICE_NAME" "$DEVICE_OS")
[ -n "$udid" ] || die "no available simulator named \"$DEVICE_NAME\"${DEVICE_OS:+ on iOS $DEVICE_OS} — see: xcrun simctl list devices available"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || die "simulator $udid did not boot"

# -- settings -----------------------------------------------------------------
accessibility_defaults="com.apple.Accessibility"
was_appearance=$(xcrun simctl ui "$udid" appearance 2>/dev/null || echo light)
was_size=$(xcrun simctl ui "$udid" content_size 2>/dev/null || echo large)
was_contrast=$(xcrun simctl ui "$udid" increase_contrast 2>/dev/null || echo disabled)

restore() {
    xcrun simctl ui "$udid" appearance "$was_appearance" >/dev/null 2>&1 || true
    xcrun simctl ui "$udid" content_size "$was_size" >/dev/null 2>&1 || true
    xcrun simctl ui "$udid" increase_contrast "$was_contrast" >/dev/null 2>&1 || true
    if [ "$reduce" = 1 ]; then
        xcrun simctl spawn "$udid" defaults write "$accessibility_defaults" ReduceMotionEnabled -bool false >/dev/null 2>&1 || true
        xcrun simctl spawn "$udid" defaults write "$accessibility_defaults" EnhancedBackgroundContrastEnabled -bool false >/dev/null 2>&1 || true
    fi
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$dark" = 1 ] && xcrun simctl ui "$udid" appearance dark
[ "$ax5" = 1 ] && xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large
[ "$contrast" = 1 ] && xcrun simctl ui "$udid" increase_contrast enabled
if [ "$reduce" = 1 ]; then
    xcrun simctl spawn "$udid" defaults write "$accessibility_defaults" ReduceMotionEnabled -bool true
    xcrun simctl spawn "$udid" defaults write "$accessibility_defaults" EnhancedBackgroundContrastEnabled -bool true
fi

# -- run ----------------------------------------------------------------------
derived="$root/.build/gate"
out="$root/.build/screens/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
say "$DEVICE_NAME:$only"
status=0
# shellcheck disable=SC2086
xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "id=$udid" -derivedDataPath "$derived" \
    -resultBundlePath "$out/result.xcresult" -collect-test-diagnostics never \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
    $only >"$out/test.log" 2>&1 || status=$?
grep -E "^([^ ]+:[0-9]+: )?(Fatal error|Precondition failed|Assertion failed)|^/[^ ]+:[0-9]+: error:|^\*\* TEST" "$out/test.log" | sort -u | tail -20 || true

# A failed run may still have kept the screenshot that shows why.
say "contact sheet"
xcrun xcresulttool export attachments --path "$out/result.xcresult" --output-path "$out/attachments" >/dev/null 2>&1 \
    || die "no attachments to export — log: $out/test.log"
xcrun swift "$script_dir/lib/contact-sheet.swift" "$out/attachments" "$out"
rm -rf "$out/attachments"

[ "$status" = 0 ] || die "tests failed — log: $out/test.log"
printf '✓ %s\n' "$out"
