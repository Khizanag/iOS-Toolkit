#!/bin/sh
# ios-translations.sh — String Catalog tooling for an iOS app: the gate's
# translation check, plus the dump and merge steps of a translation pass.
#
# Runs anywhere inside the app's repo. Scripts/gate.conf supplies PROJECT and,
# optionally:
#   TRANSLATION_LANGUAGES="de ja"  replaces the shipped languages read from the
#                                  project's knownRegions (minus the development
#                                  region and Base)
#   TRANSLATION_BRIEF=docs/…       where a failed check points (default:
#                                  docs/TRANSLATION-BRIEF.md)
#
# The catalogs are the repo's tracked *.xcstrings. A plain build never adds new
# keys to them, so `check` exports first: new keys land in the catalogs, and in
# the diff, before the check reads them.
set -eu

usage() {
    cat <<'USAGE'
Usage: ios-translations.sh check
       ios-translations.sh dump <source.json> [--missing]
       ios-translations.sh merge <dir> [LANG ...]

  check   sync the catalogs, then fail on any key that is missing a shipped
          language, needs review, or is stale
  dump    write every key translators need, with its English text, comment,
          and a plural flag; --missing keeps only keys some language lacks
  merge   validate <dir>/<LANG>.json (every file but source.json when no LANG
          is named), then merge them; one invalid entry merges nothing
USAGE
}

die() { printf '✗ %s\n' "$1" >&2; exit "${2:-1}"; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository" 64
PROJECT="" TRANSLATION_LANGUAGES="" TRANSLATION_BRIEF="docs/TRANSLATION-BRIEF.md"
if [ -f "$root/Scripts/gate.conf" ]; then
    # shellcheck disable=SC1091
    . "$root/Scripts/gate.conf"
fi
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export DEVELOPER_DIR
catalogs="$(cd "$(dirname "$0")" && pwd -P)/lib/xcstrings.py"
cd "$root"

# Exports the development language into a scratch directory; the side effect
# that matters is Xcode writing every extracted key into the catalogs.
sync_catalogs() {
    [ -f "$PROJECT/project.pbxproj" ] || die "no $PROJECT/project.pbxproj in $root" 64
    region=$(sed -n 's/^[[:space:]]*developmentRegion = "\{0,1\}\([^";]*\)"\{0,1\};.*/\1/p' "$PROJECT/project.pbxproj" | head -n 1)
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    xcodebuild -exportLocalizations -project "$PROJECT" -localizationPath "$scratch/export" \
        -exportLanguage "${region:-en}" -scmProvider system >"$scratch/export.log" 2>&1 \
        || { tail -n 20 "$scratch/export.log" >&2; die "could not sync the String Catalogs (xcodebuild -exportLocalizations)"; }
}

[ $# -gt 0 ] || { usage >&2; exit 64; }
command=$1
shift
case "$command" in
    check)
        [ -n "$PROJECT" ] || die "Scripts/gate.conf must set PROJECT" 64
        sync_catalogs
        status=0
        python3 "$catalogs" --project "$PROJECT" --languages "$TRANSLATION_LANGUAGES" \
            check --brief "$TRANSLATION_BRIEF" || status=$?
        exit "$status"
        ;;
    dump | merge)
        exec python3 "$catalogs" --project "$PROJECT" --languages "$TRANSLATION_LANGUAGES" "$command" ${1+"$@"}
        ;;
    -h | --help) usage ;;
    *) usage >&2; exit 64 ;;
esac
