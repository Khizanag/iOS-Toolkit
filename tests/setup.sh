#!/bin/sh
# setup-machine.sh: identity and hooks scoped to one directory, reruns, dry
# run, and uninstall.
set -eu
cd "$(dirname "$0")/.."
toolkit=$(pwd -P)
. tests/lib.sh
sandbox_git

root="$SANDBOX/personal"
inside="$root/app"
outside="$SANDBOX/elsewhere/app"
mkdir -p "$inside" "$outside"
git -C "$inside" init --quiet
git -C "$outside" init --quiet
include_file="$XDG_CONFIG_HOME/git/ios-toolkit.gitconfig"

run_setup() {
    status=0
    output=$(GIT_EMAIL=me@example.com GIT_NAME="Me" sh scripts/setup-machine.sh --root "$root" ${1+"$@"} 2>&1) \
        || status=$?
}

include_entries() {
    git config --global --get-regexp '^includeif\.' || true
}

run_setup --dry-run
expect_success "dry run succeeds" "$status" "$output"
expect_contains "dry run shows the hooks path" "$toolkit/hooks" "$output"
expect_no_file "dry run writes no include file" "$include_file"
expect_empty "dry run leaves the global config alone" "$(include_entries)"

run_setup
expect_success "install succeeds" "$status" "$output"
expect_equal "repos under the root commit as GIT_EMAIL" me@example.com "$(git -C "$inside" config user.email)"
expect_equal "repos under the root use GIT_NAME" Me "$(git -C "$inside" config user.name)"
expect_equal "repos under the root use the toolkit hooks" "$toolkit/hooks" "$(git -C "$inside" config core.hooksPath)"
expect_equal "repos under the root expect GIT_EMAIL" me@example.com "$(git -C "$inside" config ios-toolkit.expectedEmail)"
expect_equal "repos elsewhere keep the global identity" test@example.com "$(git -C "$outside" config user.email)"
expect_empty "repos elsewhere get no hooks path" "$(git -C "$outside" config core.hooksPath || true)"

run_setup
expect_equal "a rerun keeps one includeIf entry" 1 "$(include_entries | wc -l | tr -d ' ')"

status=0
output=$(sh scripts/setup-machine.sh --root "$root" 2>&1) || status=$?
expect_failure "install without GIT_EMAIL fails" "$status" "$output"

status=0
output=$(GIT_EMAIL=me@example.com sh scripts/setup-machine.sh --root "$SANDBOX/missing" 2>&1) || status=$?
expect_failure "a missing root fails" "$status" "$output"

run_setup --uninstall
expect_success "uninstall succeeds" "$status" "$output"
expect_no_file "uninstall removes the include file" "$include_file"
expect_empty "uninstall removes the includeIf entry" "$(include_entries)"
expect_empty "repos under the root lose the hooks path" "$(git -C "$inside" config core.hooksPath || true)"

finish
