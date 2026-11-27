#!/bin/sh
# ios-device.sh: the build targets any iOS device and never a device id, devicectl installs and
# launches, and each app key (bundle setting, optimisation, entitlements, prepare, verify, Watch)
# does what it says. xcrun and xcodebuild are fakes on PATH.
set -eu
cd "$(dirname "$0")/.."
toolkit=$(pwd -P)
. tests/lib.sh
sandbox_git

# -- fakes ---------------------------------------------------------------------
bin="$SANDBOX/bin"
mkdir -p "$bin"
calls="$SANDBOX/calls"
cat >"$bin/xcrun" <<FAKE
#!/bin/sh
echo "xcrun \$*" >>"$calls"
case "\$*" in
    "devicectl list devices")
        state=connected; [ -n "\${FAKE_PAIRED:-}" ] && state="available (paired)"
        [ -n "\${FAKE_OFFLINE:-}" ] && state=unavailable
        echo "Phone   PHONE-UDID   \$state   iPhone 16 Pro Max (iPhone17,2)   physical " ;;
    "devicectl device install app"*) [ -z "\${FAKE_OFFLINE:-}" ] ;;
esac
FAKE
cat >"$bin/xcodebuild" <<FAKE
#!/bin/sh
echo "xcodebuild \$*" >>"$calls"
derived="" configuration="" scheme="" bundle=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -derivedDataPath) derived=\$2; shift ;;
        -configuration) configuration=\$2; shift ;;
        -scheme) scheme=\$2; shift ;;
        *_ID=*) bundle=\${1#*=} ;;
    esac
    shift
done
app="\$derived/Build/Products/\$configuration-iphoneos/\${FAKE_PRODUCT:-\$scheme}.app"
mkdir -p "\$app"
cat >"\$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>\${FAKE_BUNDLE:-\$bundle}</string></dict></plist>
PLIST
FAKE
chmod +x "$bin/xcrun" "$bin/xcodebuild"
PATH="$bin:$PATH"
export PATH

# -- an app --------------------------------------------------------------------
app="$SANDBOX/App"
mkdir -p "$app/Scripts"
git -C "$app" init --quiet
app=$(cd "$app" && pwd -P)
cat >"$app/Scripts/gate.conf" <<'CONF'
PROJECT=App.xcodeproj
SCHEME=App
CONF
cat >"$app/Scripts/device.conf" <<'CONF'
TEAM=TEAMID
DEVICE=PHONE-UDID
BUNDLE_ID=com.example.app.dev
CONF

# Settings go through env: macOS's sh keeps VAR=value set after a function call returns.
# FLAGS holds the script's own arguments.
run_device() {
    : >"$calls"
    status=0
    # shellcheck disable=SC2086
    output=$(cd "$app" && env DEVICE_WAIT=0 ${1+"$@"} sh "$toolkit/scripts/ios-device.sh" ${FLAGS:-} 2>&1) || status=$?
}

run_device
expect_success "a phone build installs" "$status" "$output"
expect_contains "the build targets any iOS device" "-destination generic/platform=iOS" "$(grep xcodebuild "$calls")"
expect_absent "the build never names the phone" "id=PHONE-UDID" "$(grep xcodebuild "$calls")"
expect_contains "the bundle id goes into <SCHEME>_BUNDLE_ID" "APP_BUNDLE_ID=com.example.app.dev" "$(grep xcodebuild "$calls")"
expect_contains "Release by default" "-configuration Release" "$(grep xcodebuild "$calls")"
expect_contains "devicectl installs on the phone" "devicectl device install app --device PHONE-UDID" "$(cat "$calls")"
expect_contains "and launches the app" "devicectl device process launch --device PHONE-UDID com.example.app.dev" "$(cat "$calls")"
expect_contains "it says what it installed" "✓ installed com.example.app.dev" "$output"

FLAGS=--no-launch run_device
FLAGS=""
expect_absent "--no-launch only installs" "process launch" "$(cat "$calls")"

cat >>"$app/Scripts/gate.conf" <<'CONF'
DEVICE_BUNDLE_SETTING=APP_ID
DEVICE_OPTIMIZE=1
DEVICE_ENTITLEMENTS=Scripts/free-team.entitlements
CONF
run_device CONFIGURATION=Debug
expect_contains "a named bundle setting takes the id" "APP_ID=com.example.app.dev" "$(grep xcodebuild "$calls")"
expect_contains "Debug builds compile optimised when the app asks" "SWIFT_OPTIMIZATION_LEVEL=-O" "$(grep xcodebuild "$calls")"
expect_contains "the app's entitlements replace the project's" "CODE_SIGN_ENTITLEMENTS=$app/Scripts/free-team.entitlements" "$(grep xcodebuild "$calls")"
run_device CONFIGURATION=Debug OPTIMIZE=0 NO_ENTITLEMENTS=0
expect_absent "OPTIMIZE=0 keeps Debug plain" "SWIFT_OPTIMIZATION_LEVEL" "$(grep xcodebuild "$calls")"
expect_absent "NO_ENTITLEMENTS=0 keeps the project's" "CODE_SIGN_ENTITLEMENTS" "$(grep xcodebuild "$calls")"
run_device
expect_absent "Release is never re-optimised" "SWIFT_OPTIMIZATION_LEVEL" "$(grep xcodebuild "$calls")"

run_device FAKE_BUNDLE=com.example.other
expect_failure "a different bundle id installs nothing" "$status" "$output"
expect_absent "nothing reaches the phone" "install app" "$(cat "$calls")"

cat >>"$app/Scripts/gate.conf" <<'CONF'
DEVICE_PREPARE='echo prepared >"$PWD/prepared"'
DEVICE_VERIFY='[ -f "$APP_PATH/Info.plist" ]'
CONF
run_device
expect_success "prepare and verify hooks run" "$status" "$output"
expect_file "prepare runs in the app's root" "$app/prepared"
echo "DEVICE_VERIFY=false" >>"$app/Scripts/gate.conf"
run_device
expect_failure "a failing check stops the install" "$status" "$output"
expect_absent "before anything is installed" "install app" "$(cat "$calls")"
sed -i '' '/DEVICE_VERIFY=false/d' "$app/Scripts/gate.conf"

echo "WATCH=WATCH-UDID" >>"$app/Scripts/device.conf"
echo "DEVICE_WATCH_APP=Watch/AppWatch.app" >>"$app/Scripts/gate.conf"
run_device
expect_contains "a Watch gets its app" "devicectl device install app --device WATCH-UDID $app/.build/device/Build/Products/Release-iphoneos/App.app/Watch/AppWatch.app" "$(cat "$calls")"

run_device FAKE_PAIRED=1 DEVICE_WAIT=30
expect_success "a phone reachable over Wi-Fi but not yet tunnelled installs" "$status" "$output"
expect_absent "without waiting for it to list as connected" "waiting for the phone" "$output"

run_device FAKE_OFFLINE=1
expect_failure "a phone that never comes online fails" "$status" "$output"
expect_contains "and says how to bring it back" "unlock it" "$output"

rm "$app/Scripts/device.conf"
run_device
expect_failure "no device.conf is a usage error" "$status" "$output"
expect_contains "and names what it needs" "TEAM, DEVICE, and BUNDLE_ID" "$output"

# An app without a gate names its project in its own Scripts/device.sh.
bare="$SANDBOX/Bare"
mkdir -p "$bare/Scripts"
git -C "$bare" init --quiet
bare=$(cd "$bare" && pwd -P)
printf 'TEAM=T\nDEVICE=PHONE-UDID\nBUNDLE_ID=com.example.bare\n' >"$bare/Scripts/device.conf"
status=0
output=$(cd "$bare" && DEVICE_WAIT=0 PROJECT=Bare.xcodeproj SCHEME=Bare sh "$toolkit/scripts/ios-device.sh" 2>&1) || status=$?
expect_success "PROJECT and SCHEME can come from the wrapper" "$status" "$output"

finish
