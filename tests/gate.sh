#!/bin/sh
# ios-gate.sh and lib/simulator.sh: simulators resolve to one exact UDID, the
# build happens once, tests run without rebuilding, and warnings or failures
# stop the gate. xcrun, xcodebuild and swiftlint are fakes on PATH.
set -eu
cd "$(dirname "$0")/.."
toolkit=$(pwd -P)
. tests/lib.sh
sandbox_git

# -- fakes ---------------------------------------------------------------------
bin="$SANDBOX/bin"
mkdir -p "$bin"
calls="$SANDBOX/calls"
: >"$calls"
cat >"$bin/xcrun" <<FAKE
#!/bin/sh
if [ "\$1 \$2 \$3 \$4" = "simctl list devices available" ]; then cat "$toolkit/tests/fixtures/simctl-devices.txt"; exit 0; fi
if [ "\$1 \$2" = "simctl create" ]; then echo "xcrun \$*" >>"$calls"; echo "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"; exit 0; fi
echo "xcrun \$*" >>"$calls"
FAKE
cat >"$bin/xcodebuild" <<FAKE
#!/bin/sh
echo "xcodebuild \$*" >>"$calls"
case "\$*" in
    *build-for-testing*)
        echo "/Applications/Xcode.app/SDKs/StoreKitTest.h:34:32: warning: deprecated in the SDK itself"
        [ -n "\${FAKE_WARNING:-}" ] && echo "\$(pwd -P)/App/View.swift:1:1: warning: unused"
        echo "** TEST BUILD SUCCEEDED **" ;;
    *test-without-building*) echo "✔ Test run with 3 tests in 1 suite passed"; exit "\${FAKE_TEST_STATUS:-0}" ;;
esac
FAKE
cat >"$bin/swiftlint" <<FAKE
#!/bin/sh
echo "swiftlint \$*" >>"$calls"
exit "\${FAKE_LINT_STATUS:-0}"
FAKE
chmod +x "$bin/xcrun" "$bin/xcodebuild" "$bin/swiftlint"
PATH="$bin:$PATH"
export PATH

# -- simulator resolution ------------------------------------------------------
. scripts/lib/simulator.sh
expect_equal "exact name on a named runtime" \
    DCACD159-DEDE-4394-8134-47E09DF35A11 "$(resolve_simulator "iPhone 17 Pro" 26.5)"
expect_equal "no runtime picks the newest that has the device" \
    11111111-2222-3333-4444-555555555555 "$(resolve_simulator "iPhone 17 Pro" "")"
expect_equal "a name with a suffix is a different device" \
    CD45D5C3-C9FF-4F7F-8D9D-C6C3E79C8B11 "$(resolve_simulator "iPhone 17 Pro (iOS 27)" 27.0)"
expect_empty "a missing device resolves to nothing" "$(resolve_simulator "iPhone 99" 26.5)"
expect_empty "non-iOS runtimes are ignored" "$(resolve_simulator "iPhone 17 Pro" 27.1)"

# -- the gate ------------------------------------------------------------------
app="$SANDBOX/App"
mkdir -p "$app/Scripts"
git -C "$app" init --quiet
app=$(cd "$app" && pwd -P)
cat >"$app/Scripts/gate.conf" <<'CONF'
PROJECT=App.xcodeproj
SCHEME=App
UNIT_TESTS=AppTests
UI_TESTS=AppUITests
DEVICE_NAME="iPhone 17 Pro"
DEVICE_OS=26.5
CONF

run_gate() {
    : >"$calls"
    status=0
    output=$(cd "$app" && sh "$toolkit/scripts/ios-gate.sh" ${1+"$@"} 2>&1) || status=$?
}

run_gate
expect_success "a clean gate passes" "$status" "$output"
expect_absent "warnings inside the SDK are not the app's" "StoreKitTest.h" "$output"
expect_contains "the simulator is booted by UDID" "simctl bootstatus DCACD159-DEDE-4394-8134-47E09DF35A11" "$(cat "$calls")"
expect_contains "the build is addressed by UDID" "-destination id=DCACD159-DEDE-4394-8134-47E09DF35A11" "$(grep build-for-testing "$calls")"
expect_absent "no destination is ever addressed by name" "name=" "$(cat "$calls")"
expect_contains "tests run without rebuilding" "test-without-building" "$(cat "$calls")"
expect_contains "a failure never waits on simctl diagnose" "-collect-test-diagnostics never" "$(grep test-without-building "$calls")"
expect_contains "unit tests run by default" "-only-testing:AppTests" "$(grep test-without-building "$calls")"
expect_absent "UI tests wait for --full" "AppUITests" "$(grep test-without-building "$calls")"
expect_contains "builds stay in the repo's own folder" "-derivedDataPath $app/.build/gate" "$(grep build-for-testing "$calls")"

run_gate --full
expect_contains "--full adds the UI tests" "-only-testing:AppUITests" "$(grep test-without-building "$calls")"

run_gate -only-testing:AppTests/Suite
expect_contains "explicit tests replace the defaults" "-only-testing:AppTests/Suite" "$(grep test-without-building "$calls")"
expect_absent "explicit tests drop the default target" "-only-testing:AppTests " "$(grep test-without-building "$calls") "

run_gate --os 25.0
expect_failure "an unknown simulator stops the gate" "$status" "$output"
expect_contains "and says which one" "no available simulator named" "$output"

sed -i '' 's/^DEVICE_NAME=.*/DEVICE_NAME="App Gate"/' "$app/Scripts/gate.conf"
echo 'DEVICE_TYPE="iPhone 17 Pro"' >>"$app/Scripts/gate.conf"
run_gate
expect_success "a missing per-app simulator is created" "$status" "$output"
expect_contains "with the model and runtime asked for" "simctl create App Gate iPhone 17 Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5" "$(cat "$calls")"
expect_contains "and the gate runs on it" "id=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" "$(grep build-for-testing "$calls")"
sed -i '' '/^DEVICE_TYPE=/d; s/^DEVICE_NAME=.*/DEVICE_NAME="iPhone 17 Pro"/' "$app/Scripts/gate.conf"

FAKE_WARNING=1 run_gate
expect_failure "a compiler warning fails the gate" "$status" "$output"

FAKE_TEST_STATUS=65 run_gate
expect_failure "a failing test fails the gate" "$status" "$output"

FAKE_LINT_STATUS=2 run_gate
expect_failure "a lint violation fails the gate" "$status" "$output"
expect_absent "and nothing is built after it" "build-for-testing" "$(cat "$calls")"

printf '#!/bin/sh\nexit 3\n' >"$app/Scripts/check.sh"
chmod +x "$app/Scripts/check.sh"
echo 'CHECKS="Scripts/check.sh"' >>"$app/Scripts/gate.conf"
run_gate
expect_failure "a failing extra check fails the gate" "$status" "$output"

rm "$app/Scripts/gate.conf"
run_gate
expect_failure "a repo without gate.conf is refused" "$status" "$output"

finish
