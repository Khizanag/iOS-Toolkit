#!/bin/sh
# ios-freshness.sh: the check fails on an old project format, old String Catalogs, an
# old SwiftLint base, or an old TestingLab requirement; fix brings all four up and the
# check passes; what only Xcode or a person can do is reported, never failed. The
# installed Xcode is a fake on PATH; the app and its sibling clones live in a sandbox.
set -eu
cd "$(dirname "$0")/.."
toolkit=$(pwd -P)
. tests/lib.sh
sandbox_git

# -- fakes ---------------------------------------------------------------------
bin="$SANDBOX/bin"
mkdir -p "$bin"
cat >"$bin/xcodebuild" <<'FAKE'
#!/bin/sh
[ "$1" = -version ] || exit 2
printf 'Xcode %s\nBuild version 27B52\n' "${FAKE_XCODE:-27.2}"
FAKE
chmod +x "$bin/xcodebuild"
PATH="$bin:$PATH"
export PATH
newest_toolkit=$(git -C "$toolkit" tag --list 'v*' --sort=-v:refname | head -n 1)

# -- the app and its siblings ----------------------------------------------------
workspace="$SANDBOX/apps"
app="$workspace/App"
mkdir -p "$app/Scripts" "$app/App.xcodeproj" "$app/App" "$workspace/TestingLab-iOS" "$workspace/iOS-Constitution"
printf 'PROJECT=App.xcodeproj\n' >"$app/Scripts/gate.conf"
cat >"$app/App.xcodeproj/project.pbxproj" <<'PBX'
// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 77;
	objects = {
		AA /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastUpgradeCheck = 1640;
			};
			compatibilityVersion = "Xcode 16.0";
			mainGroup = BB;
			preferredProjectObjectVersion = 77;
		};
		CC /* XCRemoteSwiftPackageReference "TestingLab-iOS" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/Khizanag/TestingLab-iOS";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 1.0.0;
			};
		};
	};
	rootObject = AA;
}
PBX
printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n  },\n  "version" : "1.0"\n}\n' >"$app/App/Localizable.xcstrings"
printf 'parent_config: https://raw.githubusercontent.com/Khizanag/iOS-Toolkit/v0.9.0/swiftlint/base.yml\n' >"$app/.swiftlint.yml"
printf '## Constitution\n\nConforms as of the 2026-01-01 entry.\n' >"$app/CLAUDE.md"
printf '# Changelog\n\n## 2026-02-01\n\n- Amended article 1.\n' >"$workspace/iOS-Constitution/CHANGELOG.md"
git -C "$workspace/TestingLab-iOS" init --quiet
git -C "$workspace/TestingLab-iOS" commit --quiet --allow-empty -m lab
git -C "$workspace/TestingLab-iOS" tag v1.2.0
git -C "$app" init --quiet
git -C "$app" add .
git -C "$app" commit --quiet -m fixture
app=$(cd "$app" && pwd -P)
pbxproj="$app/App.xcodeproj/project.pbxproj"

run() {
    status=0
    output=$(cd "$app" && sh "$toolkit/scripts/ios-freshness.sh" ${1+"$@"} 2>&1) || status=$?
}

# -- check -----------------------------------------------------------------------
run
expect_failure "an app behind the installed Xcode fails the check" "$status" "$output"
expect_contains "it names the project format" "objectVersion 77; Xcode 27.2 writes 110" "$output"
expect_contains "it names the catalog format" "aren't in Xcode 27.2's format (version 1.1)" "$output"
expect_contains "it names the SwiftLint base" "pinned to v0.9.0" "$output"
expect_contains "it names the TestingLab requirement" "requirement is 1.0.0; its newest release is 1.2.0" "$output"
expect_contains "it points at the fix" "ios-freshness.sh fix" "$output"
expect_contains "recommended settings are reported" "Update to Recommended Settings" "$output"
expect_contains "a newer constitution is reported" "amended 2026-02-01" "$output"

# -- fix -------------------------------------------------------------------------
run fix
expect_success "fix brings the app up to date" "$status" "$output"
expect_contains "objectVersion moves to Xcode 27's" "objectVersion = 110;" "$(cat "$pbxproj")"
expect_contains "so does preferredProjectObjectVersion" "preferredProjectObjectVersion = 110;" "$(cat "$pbxproj")"
expect_absent "the old compatibilityVersion goes" "compatibilityVersion" "$(cat "$pbxproj")"
expect_contains "the catalog moves to 1.1" '"version" : "1.1"' "$(cat "$app/App/Localizable.xcstrings")"
expect_contains "the SwiftLint base moves to the newest tag" "iOS-Toolkit/$newest_toolkit/swiftlint" "$(cat "$app/.swiftlint.yml")"
expect_contains "TestingLab moves to its newest release" "minimumVersion = 1.2.0;" "$(cat "$pbxproj")"
expect_contains "LastUpgradeCheck is left to Xcode" "LastUpgradeCheck = 1640;" "$(cat "$pbxproj")"

run
expect_success "after fix the check passes" "$status" "$output"
expect_contains "and says so" "up to date with Xcode 27.2" "$output"

# -- an Xcode that isn't there ------------------------------------------------------
FAKE_XCODE=""
export FAKE_XCODE
cat >"$bin/xcodebuild" <<'FAKE'
#!/bin/sh
exit 1
FAKE
run
expect_failure "a missing Xcode stops the check" "$status" "$output"
expect_contains "and names the Xcode it looked for" "no Xcode at DEVELOPER_DIR=" "$output"
cat >"$bin/xcodebuild" <<'FAKE'
#!/bin/sh
[ "$1" = -version ] || exit 2
printf 'Xcode %s\nBuild version 27B52\n' "${FAKE_XCODE:-27.2}"
FAKE
unset FAKE_XCODE

# -- an Xcode the toolkit doesn't know yet -----------------------------------------
FAKE_XCODE=28.0
export FAKE_XCODE
run
expect_failure "an unknown Xcode stops the check" "$status" "$output"
expect_contains "and asks for its row" "Xcode 28.0 is newer than iOS-Toolkit knows" "$output"
unset FAKE_XCODE

finish
