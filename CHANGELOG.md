# Changelog

Every release of iOS-Toolkit. Apps pin exact tags; the bump rules live in [README.md](README.md#versioning).

## v1.2.1

- `ios-gate.sh` summarizes only test results and compiler errors; app log lines that contain "error:" stay in the log file.

## v1.2.0

- `scripts/ios-gate.sh`: the local release gate for apps without paid CI. Strict lint, one warning-free `build-for-testing`, then `test-without-building`, configured per app by `Scripts/gate.conf`. A mid-sized app goes from about ten minutes to under twenty seconds.
- Simulators are resolved to an exact UDID and booted once (`scripts/lib/simulator.sh`). A `name=` destination had made `xcodebuild` boot a crash-looping simulator on another runtime.
- Tests run with `-collect-test-diagnostics never`, so a run no longer waits up to ten minutes on `simctl diagnose`, which also booted every shut-down simulator.
- `DEVICE_TYPE` creates a per-app gate simulator on first use, so parallel sessions stop sharing one device's state.
- Only warnings in the app's own sources fail the gate; SDK-header deprecations do not.

## v1.1.0

- `.github/workflows/ios-ci.yml`: reusable CI with lint, `swift test`, and xcodebuild jobs, configured by inputs instead of copied between repos.
- The lint job installs the exact SwiftLint release the base pins instead of whatever Homebrew currently serves, so a Homebrew update cannot fail a repo that has not moved.
- `tests/workflow.sh` keeps that pin equal to `swiftlint_version` and fails on a floating action or runner image.

## v1.0.0

- `swiftlint/base.yml`: thresholds, 18 opt-in rules, and 17 custom rules consolidated from the per-app configs, with SwiftLint pinned to 0.65.1.
- Relaxations already used by two or more apps, now in the base: `type_name` allows `ID`, and `no_navigation_destination` skips `SearchView.swift`.
- Machine-wide hooks: identity, signing-team, and staged-file SwiftLint checks before each commit, with pass-through to repo-local hooks.
- `scripts/setup-machine.sh` installs the hooks for every repo under one directory.
