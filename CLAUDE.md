# CLAUDE.md — ios-toolkit

Build-time tooling that personal iOS apps reference by release tag. Nothing here is linked into an app.

## Rules

- `scripts/test.sh` passes before every commit. It needs the SwiftLint version `swiftlint/base.yml` pins.
- Every custom rule in `swiftlint/base.yml` has a fixture directory at `tests/fixtures/base/violations/<rule>/`; the suite fails otherwise. `tests/fixtures/base/clean/` stays violation-free.
- `swiftlint/base.yml` sets no paths. Apps own `included` and `excluded`.
- Hooks and scripts are POSIX `sh` with no dependencies beyond git and SwiftLint. macOS runs `/bin/sh` as bash 3.2, so write `${1+"$@"}` instead of a bare `"$@"` under `set -u`.
- Every file directly under `hooks/` except `dispatch.sh` is a symlink to `dispatch.sh`.
- The repo is public. Never name a private repository, an employer, a signing team, or a personal email address.
- A change that can fail a previously passing app is a major release. Record every tag in `CHANGELOG.md`.

## Release

```bash
scripts/test.sh
git tag vX.Y.Z
git push origin vX.Y.Z
```

Apps adopt a release by changing the tag in their `parent_config` URL.
