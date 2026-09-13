# Changelog

Every release of iOS-Toolkit. Apps pin exact tags; the bump rules live in [README.md](README.md#versioning).

## v1.1.0

- `.github/workflows/ios-ci.yml`: reusable CI with lint, `swift test`, and xcodebuild jobs, configured by inputs instead of copied between repos.
- The lint job installs the exact SwiftLint release the base pins instead of whatever Homebrew currently serves, so a Homebrew update cannot fail a repo that has not moved.
- `tests/workflow.sh` keeps that pin equal to `swiftlint_version` and fails on a floating action or runner image.

## v1.0.0

- `swiftlint/base.yml`: thresholds, 18 opt-in rules, and 17 custom rules consolidated from the per-app configs, with SwiftLint pinned to 0.65.1.
- Relaxations already used by two or more apps, now in the base: `type_name` allows `ID`, and `no_navigation_destination` skips `SearchView.swift`.
- Machine-wide hooks: identity, signing-team, and staged-file SwiftLint checks before each commit, with pass-through to repo-local hooks.
- `scripts/setup-machine.sh` installs the hooks for every repo under one directory.
