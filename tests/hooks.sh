#!/bin/sh
# Pre-commit behaviour, checked through real commits in throwaway repos.
set -eu
cd "$(dirname "$0")/.."
toolkit=$(pwd -P)
. tests/lib.sh
sandbox_git

mkdir -p "$SANDBOX/shared" "$SANDBOX/shared-old"
cp swiftlint/base.yml "$SANDBOX/shared/base.yml"
sed 's/^swiftlint_version: .*/swiftlint_version: 0.0.1/' swiftlint/base.yml >"$SANDBOX/shared-old/base.yml"

link_view='import SwiftUI

struct LinkView: View {
    var body: some View {
        NavigationLink("Next") {
            Text("Destination")
        }
    }
}'

new_repo() {
    repo="$SANDBOX/repos/$1"
    mkdir -p "$repo"
    git -C "$repo" init --quiet
    git -C "$repo" config core.hooksPath "$toolkit/hooks"
    git -C "$repo" config ios-toolkit.expectedEmail test@example.com
    printf '%s\n' "$repo"
}

new_lint_repo() {
    repo=$(new_repo "$1")
    mkdir -p "$repo/Sources"
    printf 'parent_config: ../../%s/base.yml\n\nincluded:\n  - Sources\n' "${2:-shared}" >"$repo/.swiftlint.yml"
    git -C "$repo" add .swiftlint.yml
    printf '%s\n' "$repo"
}

stage_file() {
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" >"$1/$2"
    git -C "$1" add "$2"
}

try_commit() {
    status=0
    output=$(git -C "$1" commit --quiet -m "$2" 2>&1) || status=$?
}

echo "swiftlint"
repo=$(new_lint_repo lint)
stage_file "$repo" Sources/Greeting.swift 'let greeting = "Hello"'
try_commit "$repo" "Add greeting"
expect_success "clean staged Swift commits" "$status" "$output"

stage_file "$repo" Sources/LinkView.swift "$link_view"
try_commit "$repo" "Add link view"
expect_failure "a violation in a staged file blocks" "$status" "$output"
expect_contains "the block names the rule" "(no_navigation_link)" "$output"

git -C "$repo" commit --quiet --no-verify -m "Add debt"
stage_file "$repo" Sources/Farewell.swift 'let farewell = "Bye"'
try_commit "$repo" "Add farewell"
expect_success "debt in files outside the commit does not block" "$status" "$output"

stage_file "$repo" Sources/LinkView.swift "// Touched
$link_view"
try_commit "$repo" "Touch link view"
expect_failure "a staged file with old debt blocks until it is clean" "$status" "$output"
git -C "$repo" reset --quiet --hard

repo=$(new_lint_repo scope)
stage_file "$repo" Sources/Greeting.swift 'let greeting = "Hello"'
stage_file "$repo" Scripts/Tool.swift "$link_view"
try_commit "$repo" "Add greeting and tool"
expect_success "files outside included are not linted" "$status" "$output"

repo=$(new_lint_repo empty)
stage_file "$repo" Scripts/Tool.swift "$link_view"
try_commit "$repo" "Add tool"
expect_success "a repo with nothing to lint yet commits" "$status" "$output"

repo=$(new_lint_repo missing)
stage_file "$repo" Sources/Value.swift 'let value = 1'
status=0
output=$(IOS_TOOLKIT_SWIFTLINT=/nonexistent/swiftlint git -C "$repo" commit --quiet -m "Add value" 2>&1) || status=$?
expect_failure "a missing SwiftLint blocks" "$status" "$output"
expect_contains "the block says how to install it" "brew install swiftlint" "$output"

repo=$(new_lint_repo pinned shared-old)
stage_file "$repo" Sources/Value.swift 'let value = 1'
try_commit "$repo" "Add value"
expect_failure "a SwiftLint version other than the pinned one blocks" "$status" "$output"
expect_contains "the block names the pinned version" "0.0.1" "$output"

echo "identity and signing"
repo=$(new_repo identity)
git -C "$repo" config user.email someone@example.com
stage_file "$repo" notes.txt "first"
try_commit "$repo" "Add notes"
expect_failure "a user.email other than the expected one blocks" "$status" "$output"
expect_contains "the block names the expected address" "test@example.com" "$output"
git -C "$repo" config --unset user.email
try_commit "$repo" "Add notes"
expect_success "the expected address commits" "$status" "$output"

stage_file "$repo" App.xcodeproj/project.pbxproj '				DEVELOPMENT_TEAM = ABCDE12345;'
try_commit "$repo" "Set team"
expect_failure "a staged DEVELOPMENT_TEAM blocks" "$status" "$output"
stage_file "$repo" App.xcodeproj/project.pbxproj '				"DEVELOPMENT_TEAM[sdk=iphoneos*]" = ABCDE12345;'
try_commit "$repo" "Set device team"
expect_failure "an SDK-scoped DEVELOPMENT_TEAM blocks" "$status" "$output"
stage_file "$repo" App.xcodeproj/project.pbxproj '				DEVELOPMENT_TEAM = "";'
try_commit "$repo" "Clear team"
expect_success "a blank DEVELOPMENT_TEAM commits" "$status" "$output"

echo "chaining"
repo=$(new_repo chain)
stage_file "$repo" LinkView.swift "$link_view"
try_commit "$repo" "Add link view"
expect_success "repos without .swiftlint.yml skip linting" "$status" "$output"

for hook in pre-commit post-commit; do
    printf '#!/bin/sh\ntouch "$(git rev-parse --git-dir)/%s-ran"\n' "$hook" >"$repo/.git/hooks/$hook"
    chmod +x "$repo/.git/hooks/$hook"
done
stage_file "$repo" notes.txt "chained"
try_commit "$repo" "Add notes"
expect_success "commits with repo-local hooks succeed" "$status" "$output"
expect_file "the repo's own pre-commit still runs" "$repo/.git/pre-commit-ran"
expect_file "the repo's own post-commit still runs" "$repo/.git/post-commit-ran"

printf '#!/bin/sh\necho "local hook says no" >&2\nexit 1\n' >"$repo/.git/hooks/pre-commit"
stage_file "$repo" notes.txt "blocked"
try_commit "$repo" "Change notes"
expect_failure "a failing repo-local hook still blocks" "$status" "$output"
expect_contains "the repo hook's message reaches the user" "local hook says no" "$output"

repo=$(new_repo loop)
ln -s "$toolkit/hooks/dispatch.sh" "$repo/.git/hooks/pre-commit"
stage_file "$repo" notes.txt "loop"
(sleep 20 && pkill -f "repos/loop/.git/hooks/pre-commit") &
watchdog=$!
try_commit "$repo" "Add notes"
{ kill "$watchdog" && wait "$watchdog"; } 2>/dev/null || true
expect_success "a repo hook linked back to the toolkit does not loop" "$status" "$output"

finish
