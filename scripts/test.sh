#!/bin/sh
# Runs every test suite; exits non-zero if any fails.
set -eu
cd "$(dirname "$0")/.."

status=0
for suite in tests/swiftlint.sh tests/hooks.sh tests/setup.sh; do
    printf '\n== %s\n' "$suite"
    sh "$suite" || status=1
done
exit "$status"
