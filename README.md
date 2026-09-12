# ios-toolkit

Build-time tooling shared by my iOS apps: one SwiftLint base config, machine-wide git hooks, and the tests that keep both honest. Apps reference a tagged release instead of copying files, so a fix reaches every app through a one-line version bump.

## Contents

| Path | What it is |
| --- | --- |
| `swiftlint/base.yml` | Thresholds, 18 opt-in rules, 17 custom rules, and the pinned SwiftLint version |
| `hooks/` | Pre-commit checks, plus pass-through to repo-local hooks for every other client hook |
| `scripts/setup-machine.sh` | Routes every repo under one directory through `hooks/` |
| `tests/` | Rule fixtures, the config-inheritance contract, and hook and setup tests |

## Lint config

Point the app's `.swiftlint.yml` at a release tag and keep only app-specific settings there:

```yaml
parent_config: https://raw.githubusercontent.com/Khizanag/ios-toolkit/v1.0.0/swiftlint/base.yml

included:
  - MyApp
  - MyAppTests

excluded:
  - MyApp/Resource
```

Add `.swiftlint/RemoteConfigCache` to `.gitignore`. SwiftLint caches the base there after the first fetch, so linting keeps working offline, and appends the entry itself when it's missing.

How app settings combine with the base:

- **Rule lists add up.** `opt_in_rules`, `disabled_rules`, and `custom_rules` in the app join the base's.
- **`disabled_rules` wins.** Disabling a rule in the app turns it off even when the base opts in.
- **A same-name custom rule replaces the base definition.** Copy the rule and edit it, for example to widen `excluded`.
- **A rule configuration block replaces the base block.** Setting `identifier_name:` in the app drops every base setting for that rule, so copy the whole block before editing.
- **Paths stay in the app.** The base sets no `included` or `excluded`.

`tests/swiftlint.sh` checks each of these, so a SwiftLint upgrade that changes them fails CI.

The base pins `swiftlint_version`. Any other SwiftLint version fails `--strict`: install the pinned one, or move to a toolkit release that pins yours.

## Hooks

Install once per machine:

```bash
GIT_EMAIL="you@example.com" GIT_NAME="Your Name" scripts/setup-machine.sh
```

The script writes `~/.config/git/ios-toolkit.gitconfig` and adds one `includeIf` block to the global git config. Every repo under `~/Developer/Khizanag` then uses this toolkit's hooks and that identity. `--root <dir>` picks another directory; repos outside it are untouched. Preview with `--dry-run`, remove with `--uninstall`.

Pre-commit runs three checks:

1. **Identity.** `user.email` must match the configured address, which catches a stray repo-local override.
2. **Signing team.** Staged project files may not add a non-blank `DEVELOPMENT_TEAM`.
3. **SwiftLint**, in repos with a `.swiftlint.yml`. It lints the whole repo exactly as CI does, then reports only staged files: debt in untouched files never blocks, and a touched file must be clean.

Every hook then runs the repo's own `.git/hooks/<name>` when present, because `core.hooksPath` would otherwise silently disable it. SwiftLint reads the working tree, so a partially staged file is linted with its unstaged edits. `git commit --no-verify` skips everything.

## Shared CI

An app's whole workflow becomes one call, pinned to a release tag:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    uses: Khizanag/ios-toolkit/.github/workflows/ios-ci.yml@v1.1.0
    with:
      packages: '["Package/AppCore"]'
      xcodebuild: '[{"name":"Unit tests","scheme":"MyApp","project":"MyApp.xcodeproj","only":"MyAppTests"}]'
```

| Input | Default | What it does |
| --- | --- | --- |
| `lint` | `true` | Runs `swiftlint --strict` with the exact version the base pins |
| `lint-directory` | `.` | Where to lint from, when the config is not at the repo root |
| `packages` | `[]` | JSON array of package directories, one `swift test` job each |
| `xcodebuild` | `[]` | JSON array of jobs, each taking `name` and `scheme` plus optional `action`, `project`, `only`, and `directory` |

The lint job installs SwiftLint from the pinned release rather than Homebrew, so a new Homebrew build never breaks a repo mid-week. Jobs only one repo needs — a coverage badge, a script check — stay in that repo's workflow next to the call.

## Versioning

Apps pin exact tags; nothing upgrades on its own.

| Bump | When |
| --- | --- |
| Major | The release can fail an app that passed before: a new rule, a tighter threshold, a new blocking check, a SwiftLint version change |
| Minor | Additions that cannot fail an app: a relaxed rule, a new script, a new hook pass-through |
| Patch | Messages, docs, and fixes that change no outcome |

Every tag gets a `CHANGELOG.md` entry.

## Tests

```bash
scripts/test.sh
```

Needs git and the SwiftLint version `swiftlint/base.yml` pins. CI runs the same script on every push.

## License

MIT. See [LICENSE](LICENSE).
