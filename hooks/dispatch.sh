#!/bin/sh
# Every client hook in this directory is a symlink to this file. With
# core.hooksPath set, git ignores .git/hooks, so each run ends by handing over
# to the repository's own hook of the same name.
set -eu

hook_name=$(basename "$0")
hooks_dir=$(cd "$(dirname "$0")" && pwd -P)

if [ "$hook_name" = pre-commit ]; then
    . "$hooks_dir/lib/pre-commit-checks.sh"
    run_pre_commit_checks
fi

git_common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
repo_hook="$git_common_dir/hooks/$hook_name"
if [ -x "$repo_hook" ] && ! [ "$repo_hook" -ef "$hooks_dir/dispatch.sh" ]; then
    exec "$repo_hook" ${1+"$@"}
fi
