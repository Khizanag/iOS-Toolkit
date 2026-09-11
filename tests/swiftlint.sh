#!/bin/sh
# The base config: each custom rule fires on its fixture, clean code passes,
# and app configs combine with the base the way README.md describes.
set -eu
cd "$(dirname "$0")/.."
. tests/lib.sh

lint() {
    swiftlint lint --strict --quiet --no-cache --reporter xcode --config "$1" "$2" 2>&1 || true
}

findings_for() {
    printf '%s\n' "$1" | grep -F "/$2:" || true
}

custom_rules=$(awk '
    /^custom_rules:/ { inside = 1; next }
    inside && /^[^[:space:]#]/ { inside = 0 }
    inside && /^  [a-z_]+:[[:space:]]*$/ { sub(/^  /, ""); sub(/:.*/, ""); print }
' swiftlint/base.yml)

echo "custom rules"
for rule in $custom_rules; do
    fixture="tests/fixtures/base/violations/$rule"
    if [ -d "$fixture" ]; then
        expect_contains "$rule fires on its fixture" "($rule)" "$(lint tests/fixtures/base/.swiftlint.yml "$fixture")"
    else
        report_failure "$rule has a fixture" "missing $fixture"
    fi
done

for fixture in tests/fixtures/base/violations/*; do
    rule=$(basename "$fixture")
    printf '%s\n' "$custom_rules" | grep -qx "$rule" \
        || report_failure "fixture $rule matches a custom rule" "base.yml has no custom rule named $rule"
done

expect_empty "clean code passes" "$(lint tests/fixtures/base/.swiftlint.yml tests/fixtures/base/clean)"

echo "app config on top of the base"
output=$(lint tests/fixtures/override/.swiftlint.yml tests/fixtures/override)
expect_contains "base custom rules still apply" "(no_navigation_link)" "$(findings_for "$output" Links.swift)"
expect_contains "base opt-in rules still apply" "(empty_count)" "$(findings_for "$output" Count.swift)"
expect_contains "app opt-in rules add to the base" "(redundant_type_annotation)" "$(findings_for "$output" Annotation.swift)"
expect_contains "app custom rules add to the base" "(no_print)" "$(findings_for "$output" Debug.swift)"
expect_empty "a same-name app rule replaces the base definition" "$(findings_for "$output" LegacyRouter.swift)"
expect_empty "app disabled_rules turns off a base opt-in rule" "$(findings_for "$output" Unwrap.swift)"
expect_empty "app disabled_rules keeps the base's disabled rules" "$(findings_for "$output" Todo.swift)"
expect_contains "an app rule block replaces the base block" "(identifier_name)" "$(findings_for "$output" Names.swift)"

finish
