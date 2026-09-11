# Pre-commit checks, sourced by dispatch.sh. A failed check exits 1.

fail() {
    printf 'pre-commit: %s\n' "$1" >&2
    exit 1
}

run_pre_commit_checks() {
    cd "$(git rev-parse --show-toplevel)"
    check_identity
    check_development_team
    lint_staged_swift
}

check_identity() {
    expected=$(git config --get ios-toolkit.expectedEmail || true)
    [ -n "$expected" ] || return 0
    actual=$(git config --get user.email || true)
    [ "$actual" != "$expected" ] || return 0
    fail "user.email is '$actual', but repos here commit as '$expected'.
Fix: git config --local --unset user.email"
}

check_development_team() {
    added=$(git diff --cached -U0 -- '*.pbxproj' \
        | grep -E '^\+[[:space:]]*"?DEVELOPMENT_TEAM(\[[^]]*\])?"?[[:space:]]*=[[:space:]]*"?[A-Z0-9]{10}"?;' \
        || true)
    [ -n "$added" ] || return 0
    fail "a staged project file sets DEVELOPMENT_TEAM; commit it blank.
$added
Unstage that hunk: git restore --staged -p -- '*.pbxproj'"
}

find_swiftlint() {
    if [ -n "${IOS_TOOLKIT_SWIFTLINT:-}" ]; then
        [ -x "$IOS_TOOLKIT_SWIFTLINT" ] && printf '%s\n' "$IOS_TOOLKIT_SWIFTLINT"
        return
    fi
    # GUI git clients run hooks without the login shell's PATH.
    for candidate in "$(command -v swiftlint || true)" /opt/homebrew/bin/swiftlint /usr/local/bin/swiftlint; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

lint_staged_swift() {
    [ -f .swiftlint.yml ] || return 0
    staged=$(git -c core.quotePath=false diff --cached --name-only --diff-filter=ACMR -- '*.swift')
    [ -n "$staged" ] || return 0
    swiftlint=$(find_swiftlint) || fail "SwiftLint is not installed: brew install swiftlint"

    scratch=$(mktemp -d)
    # The whole repo is linted so included/excluded behave exactly as in CI;
    # findings are then narrowed to staged files, so debt elsewhere never blocks.
    status=0
    "$swiftlint" lint --strict --quiet --reporter xcode >"$scratch/out" 2>"$scratch/err" || status=$?

    root=$(pwd -P)
    # SwiftLint reports /tmp and /var paths without the /private prefix.
    case "$root" in
        /private/tmp/* | /private/var/*) root=${root#/private} ;;
    esac
    printf '%s\n' "$staged" | awk -v root="$root" '{ print root "/" $0 ":" }' >"$scratch/staged"
    findings=$(grep -F -f "$scratch/staged" "$scratch/out" || true)
    errors=$(cat "$scratch/err")
    linted_anything=$([ -s "$scratch/out" ] && echo yes || echo no)
    rm -rf "$scratch"

    case "$errors" in
        *"Currently running SwiftLint"*)
            fail "$errors
Install the pinned SwiftLint, or move this repo to a toolkit release that pins yours."
            ;;
        *"No lintable files found"*)
            return 0
            ;;
    esac
    [ -z "$findings" ] || fail "SwiftLint violations in staged files:
$findings"
    if [ "$status" -ne 0 ] && [ "$linted_anything" = no ]; then
        fail "SwiftLint could not lint this repo:
$errors"
    fi
}
