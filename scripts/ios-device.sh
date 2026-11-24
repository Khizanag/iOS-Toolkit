#!/bin/sh
# ios-device.sh — build an app and put it on a phone (and its Watch), over a cable or Wi-Fi.
#
# Run it through the app's Scripts/device.sh. It reads, from the app:
#   Scripts/gate.conf    PROJECT, SCHEME, DEVELOPER_DIR, and the DEVICE_* keys below
#                        (an app without a gate sets PROJECT and SCHEME in its Scripts/device.sh)
#   Scripts/device.conf  TEAM=<team id> DEVICE=<hardware UDID> BUNDLE_ID=<bundle id> [WATCH=<UDID>]
#                        Personal, so gitignored. DEVICE_CONF points at another file, for a
#                        second phone. UDIDs come from `xcrun devicectl list devices`.
#
# App keys, in Scripts/gate.conf:
#   DEVICE_BUNDLE_SETTING  the build setting BUNDLE_ID goes into (default <SCHEME>_BUNDLE_ID, upper case)
#   DEVICE_APP             the product's name, for its .app (default SCHEME)
#   DEVICE_OPTIMIZE=1      a Debug build compiles optimised, keeping DEBUG, so the phone feels the real
#                          app; OPTIMIZE=0 at run time keeps it plain, for a debugger
#   DEVICE_ENTITLEMENTS    entitlements to sign with instead of the project's, such as a free team's
#                          without App Groups; NO_ENTITLEMENTS=0 at run time keeps the project's
#   DEVICE_PREPARE         a command run in the app's root before the build
#   DEVICE_VERIFY          a command run after it with APP_PATH set; failing stops the install
#   DEVICE_WATCH_APP       the Watch app inside the .app (Watch/MyWatch.app), installed when WATCH is set
#
# Run time: CONFIGURATION=Debug|Release (Release by default); DEVICE_WAIT seconds to wait for the
# phone to come online (120); --no-launch.
#
# The build targets any iOS device and devicectl installs it: over Wi-Fi, xcodebuild can miss a
# phone devicectl already reaches, and a phone the team has registered needs nothing from the build.
set -eu

die() { echo "✗ $1" >&2; exit "${2:-1}"; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this inside the app's repository" 64
cd "$root"

# The wrapper's PROJECT and SCHEME win over Scripts/gate.conf.
wanted_project=${PROJECT:-} wanted_scheme=${SCHEME:-}
[ -f Scripts/gate.conf ] && . ./Scripts/gate.conf
PROJECT=${wanted_project:-${PROJECT:-}} SCHEME=${wanted_scheme:-${SCHEME:-}}
[ -n "$PROJECT" ] && [ -n "$SCHEME" ] || die "set PROJECT and SCHEME in Scripts/gate.conf or Scripts/device.sh" 64

conf=${DEVICE_CONF:-$root/Scripts/device.conf}
[ -f "$conf" ] || die "no $conf: add TEAM, DEVICE, and BUNDLE_ID (see the top of ios-device.sh)" 64
WATCH=""
. "$conf"
[ -n "${TEAM:-}" ] && [ -n "${DEVICE:-}" ] && [ -n "${BUNDLE_ID:-}" ] \
    || die "$conf must set TEAM, DEVICE, and BUNDLE_ID" 64

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# A git hook's repository would leak into package checkouts inside xcodebuild.
unset GIT_DIR GIT_INDEX_FILE

configuration=${CONFIGURATION:-Release}
setting=${DEVICE_BUNDLE_SETTING:-$(printf '%s' "$SCHEME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_BUNDLE_ID}
product=${DEVICE_APP:-$SCHEME}
derived="$root/.build/device"
log="$derived/build.log"
mkdir -p "$derived"

extra=""
if [ "$configuration" = Debug ] && [ "${DEVICE_OPTIMIZE:-0}" = 1 ] && [ "${OPTIMIZE:-1}" = 1 ]; then
    extra="SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule GCC_OPTIMIZATION_LEVEL=s"
fi
if [ -n "${DEVICE_ENTITLEMENTS:-}" ] && [ "${NO_ENTITLEMENTS:-1}" = 1 ]; then
    extra="$extra CODE_SIGN_ENTITLEMENTS=$root/$DEVICE_ENTITLEMENTS"
fi

if [ -n "${DEVICE_PREPARE:-}" ]; then
    echo "→ prepare"
    sh -c "$DEVICE_PREPARE" || die "prepare failed: $DEVICE_PREPARE"
fi

echo "→ build $SCHEME ($configuration) for $DEVICE"
# shellcheck disable=SC2086
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$configuration" \
    -destination "generic/platform=iOS" -derivedDataPath "$derived" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic "$setting=$BUNDLE_ID" $extra build >"$log" 2>&1; then
    grep -E "error:|Provisioning|limit" "$log" | sort -u | cut -c1-300 >&2 || true
    die "build failed — full log: $log"
fi

app="$derived/Build/Products/$configuration-iphoneos/$product.app"
[ -d "$app" ] || die "no $app after the build; set DEVICE_APP in Scripts/gate.conf"
built_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
[ "$built_id" = "$BUNDLE_ID" ] || die "built $built_id, expected $BUNDLE_ID — nothing installed"

if [ -n "${DEVICE_VERIFY:-}" ]; then
    APP_PATH="$app" sh -c "$DEVICE_VERIFY" || die "the build failed its check: $DEVICE_VERIFY"
fi

# Over Wi-Fi the phone drops in and out; wait for it rather than fail on the first look.
online() { xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -q " connected "; }
waited=0
until online || [ "$waited" -ge "${DEVICE_WAIT:-120}" ]; do
    [ "$waited" = 0 ] && echo "→ waiting for the phone: unlock it, on the Mac's Wi-Fi or a cable"
    sleep 5
    waited=$((waited + 5))
done

echo "→ install $app"
xcrun devicectl device install app --device "$DEVICE" "$app" >/dev/null \
    || die "couldn't reach the phone: unlock it, then run again"
if [ -n "$WATCH" ] && [ -n "${DEVICE_WATCH_APP:-}" ]; then
    echo "→ install on the Watch"
    xcrun devicectl device install app --device "$WATCH" "$app/$DEVICE_WATCH_APP" >/dev/null \
        || echo "  couldn't reach the Watch: keep it on its charger, unlocked, near the iPhone"
fi
if [ "${1:-}" != "--no-launch" ]; then
    echo "→ launch"
    xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null \
        || echo "  couldn't launch: unlock the phone and open it by hand"
fi
echo "✓ installed $BUNDLE_ID"
