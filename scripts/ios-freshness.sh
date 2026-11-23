#!/bin/sh
# ios-freshness.sh — keeps an iOS app on the newest infrastructure:
#
#   project format   the newest Xcode format the installed Xcode writes (objectVersion)
#   String Catalogs  the newest catalog format the installed Xcode writes ("version")
#   SwiftLint base   .swiftlint.yml's parent_config pinned to this toolkit's newest tag
#   TestingLab       the package requirement at TestingLab's newest tag (sibling clone)
#
# and reports, without failing, what only a person can bring up to date:
#
#   recommended settings   LastUpgradeCheck older than the installed Xcode: open the
#                          project in Xcode and accept "Update to Recommended Settings"
#   constitution           CLAUDE.md "Conforms as of" older than the newest amendment in
#                          the sibling iOS-Constitution clone: review and catch up
#
# Usage:
#   ios-freshness.sh          check; exits 1 when anything a script can fix is behind
#   ios-freshness.sh fix      rewrites what is behind, then checks again
#
# Reads PROJECT from the app's Scripts/gate.conf. ios-gate.sh runs the check first,
# unless gate.conf sets FRESHNESS=0 (for an archived app that no longer moves).
set -eu

say() { printf '→ %s\n' "$1"; }
die() { printf '✗ %s\n' "$1" >&2; exit "${2:-1}"; }

mode=${1:-check}
case "$mode" in
    check | fix) ;;
    -h | --help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "usage: ios-freshness.sh [check|fix]" 64 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository" 64
PROJECT=""
[ -f "$root/Scripts/gate.conf" ] && . "$root/Scripts/gate.conf"
[ -n "$PROJECT" ] || die "Scripts/gate.conf sets no PROJECT" 64
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export DEVELOPER_DIR
toolkit=$(cd "$(dirname "$0")/.." && pwd -P)
catalogs="$toolkit/scripts/lib/xcstrings.py"
cd "$root"
pbxproj="$PROJECT/project.pbxproj"
[ -f "$pbxproj" ] || die "no $pbxproj" 64

# -- what "newest" means for the installed Xcode ---------------------------------
# One row per Xcode major. A new Xcode stops every gate here until its row exists:
# in Xcode, set a project's File inspector → Project Format to the newest entry, and
# copy the objectVersion it writes and the "version" a catalog it saves gets.
xcode=$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9.]*\).*/\1/p' | head -n 1)
[ -n "$xcode" ] || die "no Xcode at DEVELOPER_DIR=$DEVELOPER_DIR: point it at the installed, newest Xcode"
case "${xcode%%.*}" in
    27) object_version=110 catalog_version=1.1 ;;
    *) die "Xcode $xcode is newer than iOS-Toolkit knows: add its project and catalog format to ios-freshness.sh" ;;
esac
upgrade_check=$(printf '%s\n' "$xcode" | awk -F. '{ printf "%d%d%d", $1, $2 + 0, $3 + 0 }')

behind=0
note() { printf '  %s\n' "$1"; }
lag() { behind=1; printf '  ✗ %s\n' "$1"; }

# -- project format ----------------------------------------------------------------
current=$(sed -n 's/^[[:space:]]*objectVersion = \([0-9]*\);.*/\1/p' "$pbxproj" | head -n 1)
if [ "$current" != "$object_version" ]; then
    if [ "$mode" = fix ]; then
        sed -i '' \
            -e "s/^\([[:space:]]*objectVersion = \)[0-9]*;/\1$object_version;/" \
            -e "s/^\([[:space:]]*preferredProjectObjectVersion = \)[0-9]*;/\1$object_version;/" \
            -e '/^[[:space:]]*compatibilityVersion = "[^"]*";/d' \
            "$pbxproj"
        grep -q "preferredProjectObjectVersion" "$pbxproj" \
            || sed -i '' "s/^\([[:space:]]*\)mainGroup = /\1preferredProjectObjectVersion = $object_version;\\
\1mainGroup = /" "$pbxproj"
        note "project format $current → $object_version (Xcode ${xcode%%.*})"
    else
        lag "project format is objectVersion $current; Xcode $xcode writes $object_version"
    fi
fi

last_upgrade=$(sed -n 's/^[[:space:]]*LastUpgradeCheck = \([0-9]*\);.*/\1/p' "$pbxproj" | head -n 1)
if [ "$mode" = check ] && [ -n "$last_upgrade" ] && [ "$last_upgrade" -lt "$upgrade_check" ]; then
    note "! recommended settings last applied by Xcode $last_upgrade: open the project in Xcode $xcode and accept Update to Recommended Settings"
fi

# -- String Catalogs -----------------------------------------------------------------
if [ "$mode" = fix ]; then
    python3 "$catalogs" upgrade "$catalog_version" | sed 's/^/  /'
elif ! python3 "$catalogs" upgrade "$catalog_version" --check >/dev/null; then
    lag "String Catalogs aren't in Xcode $xcode's format (version $catalog_version)"
fi

# -- SwiftLint base -------------------------------------------------------------------
newest_toolkit=$(git -C "$toolkit" tag --list 'v*' --sort=-v:refname | head -n 1)
if [ -f .swiftlint.yml ] && [ -n "$newest_toolkit" ]; then
    pinned=$(sed -n 's|.*iOS-Toolkit/\(v[0-9][0-9.]*\)/swiftlint/base.yml.*|\1|p' .swiftlint.yml | head -n 1)
    if [ -n "$pinned" ] && [ "$pinned" != "$newest_toolkit" ]; then
        if [ "$mode" = fix ]; then
            sed -i '' "s|iOS-Toolkit/$pinned/swiftlint|iOS-Toolkit/$newest_toolkit/swiftlint|" .swiftlint.yml
            note "SwiftLint base $pinned → $newest_toolkit"
        else
            lag "SwiftLint base pinned to $pinned; iOS-Toolkit's newest is $newest_toolkit"
        fi
    fi
fi

# -- TestingLab ------------------------------------------------------------------------
lab="$root/../TestingLab-iOS"
if grep -q 'TestingLab-iOS' "$pbxproj" && [ -d "$lab/.git" ]; then
    newest_lab=$(git -C "$lab" tag --list 'v*' --sort=-v:refname | head -n 1 | sed 's/^v//')
    required=$(awk '/TestingLab-iOS" \*\/ = \{/ { inside = 1 } inside && /minimumVersion/ { gsub(/[^0-9.]/, ""); print; exit }' "$pbxproj")
    if [ -n "$newest_lab" ] && [ -n "$required" ] && [ "$required" != "$newest_lab" ]; then
        if [ "$mode" = fix ]; then
            sed -i '' "/TestingLab-iOS\" \*\/ = {/,/};/ s/minimumVersion = [0-9.]*;/minimumVersion = $newest_lab;/" "$pbxproj"
            find "$PROJECT" -name Package.resolved -path '*swiftpm*' -exec rm -f {} +
            note "TestingLab $required → $newest_lab (Package.resolved removed; resolve again)"
        else
            lag "TestingLab requirement is $required; its newest release is $newest_lab"
        fi
    fi
fi

# -- iOS-Constitution -------------------------------------------------------------------
constitution="$root/../iOS-Constitution/CHANGELOG.md"
if [ "$mode" = check ] && [ -f CLAUDE.md ] && [ -f "$constitution" ]; then
    conforms=$(sed -n 's/.*[Cc]onforms as of the \([0-9-]*\) entry.*/\1/p' CLAUDE.md | head -n 1)
    newest_amendment=$(sed -n 's/^## \([0-9][0-9-]*\)$/\1/p' "$constitution" | head -n 1)
    if [ -n "$conforms" ] && [ -n "$newest_amendment" ] && [ "$conforms" \< "$newest_amendment" ]; then
        note "! iOS-Constitution amended $newest_amendment; the app conforms as of $conforms: review the CHANGELOG and catch up"
    fi
fi

if [ "$mode" = fix ]; then
    exec sh "$0" check
fi
[ "$behind" = 0 ] || die "infrastructure is behind — run: $toolkit/scripts/ios-freshness.sh fix"
printf '  up to date with Xcode %s\n' "$xcode"
