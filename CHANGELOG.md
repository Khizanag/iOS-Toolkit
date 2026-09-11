# Changelog

Every release of ios-toolkit. Apps pin exact tags; the bump rules live in [README.md](README.md#versioning).

## v1.0.0

- `swiftlint/base.yml`: thresholds, 18 opt-in rules, and 17 custom rules consolidated from the per-app configs, with SwiftLint pinned to 0.65.1.
- Relaxations already used by two or more apps, now in the base: `type_name` allows `ID`, and `no_navigation_destination` skips `SearchView.swift`.
- Machine-wide hooks: identity, signing-team, and staged-file SwiftLint checks before each commit, with pass-through to repo-local hooks.
- `scripts/setup-machine.sh` installs the hooks for every repo under one directory.
