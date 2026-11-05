#!/bin/sh
# ios-screens.sh: settings are applied as asked and always put back, and the sheet
# holds what the tests named, not what Xcode recorded. xcrun and xcodebuild are
# fakes on PATH; the contact sheet runs for real.
set -eu
cd "$(dirname "$0")/.."
toolkit=$(pwd -P)
. tests/lib.sh
sandbox_git

real_swift=$(command -v swift)

# -- a real contact sheet ------------------------------------------------------
pixels="$SANDBOX/pixels"
mkdir -p "$pixels"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' | base64 -D >"$pixels/shot.png"
cp "$pixels/shot.png" "$pixels/A.png"
cp "$pixels/shot.png" "$pixels/B.png"
cp "$pixels/shot.png" "$pixels/C.png"
cat >"$pixels/manifest.json" <<'JSON'
[{"attachments": [
  {"exportedFileName": "B.png", "suggestedHumanReadableName": "02-question_0_6E594E27-06ED-42FE-B7F4-7E591507D93F.png"},
  {"exportedFileName": "A.png", "suggestedHumanReadableName": "01-home_0_3E04B275-A757-4F15-B982-E3333F3D6F76.png"},
  {"exportedFileName": "C.png", "suggestedHumanReadableName": "App Screenshot_0_6E594E27-06ED-42FE-B7F4-7E591507D93F.png"},
  {"exportedFileName": "D.mp4", "suggestedHumanReadableName": "Screen Recording.mp4"}
]}]
JSON
sheet="$SANDBOX/sheet"
mkdir -p "$sheet"
status=0
output=$("$real_swift" scripts/lib/contact-sheet.swift "$pixels" "$sheet" 2>&1) || status=$?
expect_success "the contact sheet builds" "$status" "$output"
expect_contains "and counts what the tests named" "2 screenshots" "$output"
expect_success "it writes a sheet" "$([ -s "$sheet/sheet-1.jpg" ] && echo 0 || echo 1)" "$output"
expect_success "under the test's name" "$([ -s "$sheet/01-home.png" ] && echo 0 || echo 1)" "$(ls "$sheet")"
expect_absent "and leaves out what Xcode recorded" "App Screenshot" "$(ls "$sheet")"

empty="$SANDBOX/empty"
mkdir -p "$empty"
printf '[{"attachments": [{"exportedFileName": "C.png", "suggestedHumanReadableName": "App Screenshot_0.png"}]}]' >"$empty/manifest.json"
status=0
output=$("$real_swift" scripts/lib/contact-sheet.swift "$empty" "$sheet" 2>&1) || status=$?
expect_failure "no named screenshots is an error" "$status" "$output"
expect_contains "that says so" "kept no named screenshots" "$output"

# -- fakes ---------------------------------------------------------------------
bin="$SANDBOX/bin"
mkdir -p "$bin"
calls="$SANDBOX/calls"
cat >"$bin/xcrun" <<FAKE
#!/bin/sh
if [ "\$1 \$2 \$3 \$4" = "simctl list devices available" ]; then cat "$toolkit/tests/fixtures/simctl-devices.txt"; exit 0; fi
echo "xcrun \$*" >>"$calls"
case "\$*" in
    "simctl ui "*" appearance") echo light ;;
    "simctl ui "*" content_size") echo large ;;
    "simctl ui "*" increase_contrast") echo disabled ;;
    "xcresulttool export attachments"*)
        [ -n "\${FAKE_NO_RESULT:-}" ] && exit 1
        shift 3
        while [ \$# -gt 0 ]; do
            [ "\$1" = "--output-path" ] && mkdir -p "\$2"
            shift
        done ;;
    swift*) [ -n "\${FAKE_SHEET_STATUS:-}" ] && exit "\$FAKE_SHEET_STATUS"; echo "  sheet" ;;
esac
exit 0
FAKE
cat >"$bin/xcodebuild" <<FAKE
#!/bin/sh
echo "xcodebuild \$*" >>"$calls"
echo "App/Model.swift:33: Precondition failed: two right answers"
echo "** TEST SUCCEEDED **"
exit "\${FAKE_TEST_STATUS:-0}"
FAKE
chmod +x "$bin/xcrun" "$bin/xcodebuild"
PATH="$bin:$PATH"
export PATH

app="$SANDBOX/App"
mkdir -p "$app/Scripts"
git -C "$app" init --quiet
app=$(cd "$app" && pwd -P)
cat >"$app/Scripts/gate.conf" <<'CONF'
PROJECT=App.xcodeproj
SCHEME=App
DEVICE_NAME="iPhone 17 Pro"
DEVICE_OS=26.5
SCREENS_TESTS="AppUITests/EveryScreen"
CONF

run_screens() {
    : >"$calls"
    status=0
    output=$(cd "$app" && sh "$toolkit/scripts/ios-screens.sh" ${1+"$@"} 2>&1) || status=$?
}

udid=DCACD159-DEDE-4394-8134-47E09DF35A11

# -- the run -------------------------------------------------------------------
run_screens
expect_success "a clean run passes" "$status" "$output"
expect_contains "it runs SCREENS_TESTS" "-only-testing:AppUITests/EveryScreen" "$(grep "xcodebuild test" "$calls")"
expect_contains "addressed by UDID" "-destination id=$udid" "$(grep "xcodebuild test" "$calls")"
expect_absent "plain, it sets nothing" "appearance dark" "$(cat "$calls")"
expect_contains "and says where the sheet is" "✓ $app/.build/screens/" "$output"
expect_contains "and passes the crash cause on" "Precondition failed" "$output"

run_screens -only-testing:AppUITests/Other
expect_contains "explicit tests replace the defaults" "-only-testing:AppUITests/Other" "$(grep "xcodebuild test" "$calls")"
expect_absent "and drop SCREENS_TESTS" "EveryScreen" "$(grep "xcodebuild test" "$calls")"

run_screens --a11y
expect_contains "--a11y turns on Dark Mode" "simctl ui $udid appearance dark" "$(cat "$calls")"
expect_contains "the largest text" "content_size accessibility-extra-extra-extra-large" "$(cat "$calls")"
expect_contains "Increase Contrast" "increase_contrast enabled" "$(cat "$calls")"
expect_contains "Reduce Motion" "ReduceMotionEnabled -bool true" "$(cat "$calls")"
expect_contains "and Reduce Transparency" "EnhancedBackgroundContrastEnabled -bool true" "$(cat "$calls")"
expect_contains "then puts the appearance back" "simctl ui $udid appearance light" "$(cat "$calls")"
expect_contains "the text size" "simctl ui $udid content_size large" "$(cat "$calls")"
expect_contains "contrast" "simctl ui $udid increase_contrast disabled" "$(cat "$calls")"
expect_contains "and the reduce settings" "ReduceMotionEnabled -bool false" "$(cat "$calls")"

FAKE_TEST_STATUS=65 run_screens --ax5
expect_failure "failing tests fail the run" "$status" "$output"
expect_contains "and still make the sheet, which may show why" "xcrun swift" "$(cat "$calls")"
expect_contains "and still put the settings back" "simctl ui $udid content_size large" "$(cat "$calls")"
unset FAKE_TEST_STATUS

FAKE_NO_RESULT=1 FAKE_TEST_STATUS=65 run_screens --dark
expect_failure "no results at all fails the run" "$status" "$output"
expect_contains "and still puts the settings back" "simctl ui $udid appearance light" "$(cat "$calls")"
unset FAKE_NO_RESULT FAKE_TEST_STATUS

sed -i '' '/^SCREENS_TESTS=/d' "$app/Scripts/gate.conf"
run_screens
expect_failure "no tests named is refused" "$status" "$output"
expect_contains "with what to do" "SCREENS_TESTS" "$output"

run_screens --nonsense
expect_failure "an unknown flag is refused" "$status" "$output"

rm "$app/Scripts/gate.conf"
run_screens
expect_failure "a repo without gate.conf is refused" "$status" "$output"

finish
