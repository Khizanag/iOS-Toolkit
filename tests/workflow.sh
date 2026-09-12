#!/bin/sh
# The reusable CI workflow: its SwiftLint pin tracks the base config, and
# nothing it depends on floats.
set -eu
cd "$(dirname "$0")/.."
. tests/lib.sh

workflow=.github/workflows/ios-ci.yml

base_version=$(sed -n 's/^swiftlint_version: *//p' swiftlint/base.yml)
workflow_version=$(sed -n 's/^ *SWIFTLINT_VERSION: *//p' "$workflow")
expect_equal "the workflow installs the SwiftLint version base.yml pins" "$base_version" "$workflow_version"

unpinned=$(grep -nE "^[[:space:]]*(- )?uses:" "$workflow" .github/workflows/test.yml | grep -vE "@v[0-9]+" || true)
expect_empty "every action is pinned to a major version" "$unpinned"

floating=$(grep -nE "runs-on:.*latest" "$workflow" .github/workflows/test.yml || true)
expect_empty "no job runs on a floating runner image" "$floating"

finish
