#!/bin/sh
# Routes every git repo under one directory through this toolkit's hooks and
# one identity, using a single includeIf block in the global git config.
set -eu

usage() {
    cat <<'EOF'
Usage: GIT_EMAIL=<email> [GIT_NAME=<name>] setup-machine.sh [--root <dir>] [--dry-run | --uninstall]

Every repository under <dir> (default: ~/Developer/Khizanag) gets:
  core.hooksPath              this toolkit's hooks/
  user.email, user.name       GIT_EMAIL, GIT_NAME
  ios-toolkit.expectedEmail   GIT_EMAIL, checked by the pre-commit hook

Repositories outside <dir> are untouched.
EOF
}

root="$HOME/Developer/Khizanag"
mode=install
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || { usage >&2; exit 64; }
            root=$2
            shift 2
            ;;
        --dry-run | --uninstall)
            mode=${1#--}
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

[ -d "$root" ] || { echo "setup-machine: $root is not a directory" >&2; exit 1; }
root=$(cd "$root" && pwd -P)
toolkit_dir=$(cd "$(dirname "$0")/.." && pwd -P)
include_section="includeIf.gitdir/i:$root/"
include_file="${XDG_CONFIG_HOME:-$HOME/.config}/git/ios-toolkit.gitconfig"

if [ "$mode" = uninstall ]; then
    git config --global --remove-section "$include_section" 2>/dev/null || true
    rm -f "$include_file"
    echo "Removed the ios-toolkit git config for $root/"
    exit 0
fi

email=${GIT_EMAIL:-}
[ -n "$email" ] || { echo "setup-machine: GIT_EMAIL is required" >&2; exit 1; }

if [ "$mode" = dry-run ]; then
    echo "Would write $include_file with:"
    echo "  user.email = $email"
    [ -z "${GIT_NAME:-}" ] || echo "  user.name = $GIT_NAME"
    echo "  core.hooksPath = $toolkit_dir/hooks"
    echo "  ios-toolkit.expectedEmail = $email"
    echo "Would set in the global git config:"
    echo "  $include_section.path = $include_file"
    exit 0
fi

mkdir -p "$(dirname "$include_file")"
rm -f "$include_file"
git config --file "$include_file" user.email "$email"
if [ -n "${GIT_NAME:-}" ]; then
    git config --file "$include_file" user.name "$GIT_NAME"
fi
git config --file "$include_file" core.hooksPath "$toolkit_dir/hooks"
git config --file "$include_file" ios-toolkit.expectedEmail "$email"
git config --global --replace-all "$include_section.path" "$include_file"
echo "Repos under $root/ now commit as $email through $toolkit_dir/hooks"
