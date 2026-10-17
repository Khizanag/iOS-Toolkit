#!/bin/sh
# ios-translations.sh and lib/xcstrings.py: the check syncs the catalogs with an
# export, then fails on missing, unreviewed, or stale strings in the shipped
# languages; merge validates every file before it writes any. xcodebuild is a
# fake on PATH; the fixture app is tests/fixtures/translations.
set -eu
cd "$(dirname "$0")/.."
toolkit=$(pwd -P)
. tests/lib.sh
sandbox_git

# -- fakes ---------------------------------------------------------------------
bin="$SANDBOX/bin"
mkdir -p "$bin"
calls="$SANDBOX/calls"
: >"$calls"
# An export writes every extracted key into the catalogs; FAKE_EXPORT_CATALOG
# stands in for one that found a new key.
cat >"$bin/xcodebuild" <<FAKE
#!/bin/sh
echo "xcodebuild \$*" >>"$calls"
[ -n "\${FAKE_EXPORT_CATALOG:-}" ] && cp "\$FAKE_EXPORT_CATALOG" App/Localizable.xcstrings
exit "\${FAKE_EXPORT_STATUS:-0}"
FAKE
chmod +x "$bin/xcodebuild"
PATH="$bin:$PATH"
export PATH

# -- the fixture app -----------------------------------------------------------
app="$SANDBOX/App"
cp -R tests/fixtures/translations "$app"
git -C "$app" init --quiet
git -C "$app" add .
git -C "$app" commit --quiet -m fixture
app=$(cd "$app" && pwd -P)
catalog="$app/App/Localizable.xcstrings"
l10n="$SANDBOX/l10n"

# Rewrites a catalog in Xcode's layout after a Python statement edits `strings`.
edit() {
    python3 - "$1" "$2" <<'PY'
import json, sys
path, statement = sys.argv[1], sys.argv[2]
catalog = json.load(open(path, encoding="utf-8"))
strings = catalog["strings"]
exec(statement)
text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
open(path, "w", encoding="utf-8").write(text + "\n")
PY
}

# Prints a Python expression over a JSON file: `data`, and a catalog's `strings`.
query() {
    python3 - "$1" "$2" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
strings = data.get("strings")
print(eval(sys.argv[2]))
PY
}

reset_app() {
    git -C "$app" checkout --quiet -- .
    git -C "$app" clean -fdq
    rm -rf "$l10n"
    mkdir -p "$l10n"
}

run() {
    : >"$calls"
    status=0
    output=$(cd "$app" && sh "$toolkit/scripts/ios-translations.sh" ${1+"$@"} 2>&1) || status=$?
}

reset_app

# -- check ---------------------------------------------------------------------
run check
expect_success "complete catalogs pass, skipping shouldTranslate=false and letterless keys" "$status" "$output"
expect_contains "in every language knownRegions ships" "every string translated into ka, pt-BR" "$output"
expect_contains "after an export syncs the catalogs" "-exportLocalizations -project App.xcodeproj" "$(cat "$calls")"
expect_contains "of the development region" "-exportLanguage en" "$(cat "$calls")"
expect_absent "into a scratch directory, never the repo" "-localizationPath $app" "$(cat "$calls")"

cp "$catalog" "$SANDBOX/exported.xcstrings"
edit "$SANDBOX/exported.xcstrings" 'strings["Round %lld"] = {}'
FAKE_EXPORT_CATALOG="$SANDBOX/exported.xcstrings"
export FAKE_EXPORT_CATALOG
run check
unset FAKE_EXPORT_CATALOG
expect_failure "a key the export adds is checked" "$status" "$output"
expect_contains "in every shipped language" "[ka] missing: Round %lld" "$output"
expect_contains "including region variants" "[pt-BR] missing: Round %lld" "$output"
expect_contains "with a total and the app's brief" "2 translation gap(s) in ka, pt-BR — see docs/TRANSLATION-BRIEF.md" "$output"
reset_app

edit "$catalog" 'strings["Start"]["localizations"]["ka"]["stringUnit"]["state"] = "needs_review"'
run check
expect_failure "a translation marked for review fails" "$status" "$output"
expect_contains "and says so" "[ka] needs review: Start" "$output"
reset_app

edit "$catalog" 'strings["%lld points"]["localizations"]["pt-BR"]["variations"]["plural"]["one"]["stringUnit"]["state"] = "new"'
run check
expect_failure "one untranslated plural form fails" "$status" "$output"
expect_contains "naming the key" "[pt-BR] untranslated: %lld points" "$output"
reset_app

edit "$catalog" 'strings["Start"]["localizations"]["ka"]["stringUnit"]["value"] = " "'
run check
expect_failure "a blank translation fails" "$status" "$output"
reset_app

edit "$catalog" 'strings["Open ${applicationName}"] = {"localizations": {
    "ka": {"stringSet": {"state": "translated", "values": ["${applicationName}-ის გახსნა"]}},
    "pt-BR": {"stringSet": {"state": "translated", "values": []}}}}'
run check
expect_contains "App Shortcut phrase sets count as translated" "[pt-BR] untranslated: Open \${applicationName}" "$output"
expect_absent "unless a set is empty" "[ka]" "$output"
reset_app

edit "$catalog" 'strings["Old title"] = {"extractionState": "stale"}'
run check
expect_failure "a stale key fails" "$status" "$output"
expect_contains "and is deleted, not translated" "stale, delete it: Old title" "$output"
reset_app

edit "$catalog" 'del strings["Start"]["localizations"]["pt-BR"]'
echo 'TRANSLATION_LANGUAGES=ka' >>"$app/Scripts/gate.conf"
run check
expect_success "TRANSLATION_LANGUAGES replaces knownRegions" "$status" "$output"
expect_contains "and is what gets checked" "every string translated into ka" "$output"
reset_app

cp "$catalog" "$app/App/Draft.xcstrings"
edit "$app/App/Draft.xcstrings" 'del strings["Start"]["localizations"]["ka"]'
run check
expect_success "an untracked catalog is not checked" "$status" "$output"
reset_app

echo 'TRANSLATION_BRIEF=docs/missing.md' >>"$app/Scripts/gate.conf"
edit "$catalog" 'del strings["Start"]["localizations"]["ka"]'
run check
expect_contains "without a brief, a failure points at merge" "then run ios-translations.sh merge" "$output"
reset_app

FAKE_EXPORT_STATUS=70
export FAKE_EXPORT_STATUS
run check
unset FAKE_EXPORT_STATUS
expect_failure "a failed export fails the check" "$status" "$output"
expect_contains "and says what failed" "could not sync the String Catalogs" "$output"

sed -i '' '/^PROJECT=/d' "$app/Scripts/gate.conf"
run check
expect_failure "a gate.conf without PROJECT is refused" "$status" "$output"
reset_app

# -- dump ----------------------------------------------------------------------
run dump "$SANDBOX/source.json"
expect_success "dump writes the translator's source" "$status" "$output"
expect_equal "with every translatable key, and no others" \
    "['%lld points', 'CFBundleDisplayName', 'Start', 'Team %@']" "$(query "$SANDBOX/source.json" 'sorted(data)')"
expect_equal "each with its English text and comment" \
    "Starts the game." "$(query "$SANDBOX/source.json" 'data["Start"]["comment"]')"
expect_equal "and a plural flag for counts" \
    "True False" "$(query "$SANDBOX/source.json" '"%s %s" % (data["%lld points"]["plural"], data["Start"]["plural"])')"

edit "$catalog" 'del strings["Start"]["localizations"]["ka"]'
run dump "$SANDBOX/missing.json" --missing
expect_equal "--missing keeps the keys a language lacks, and names it" \
    "{'Start': ['ka']}" "$(query "$SANDBOX/missing.json" '{key: value["missing"] for key, value in data.items()}')"
reset_app

# -- merge ---------------------------------------------------------------------
cat >"$l10n/ka.json" <<'JSON'
{"Start": "დავიწყოთ", "Team %@": "%1$@ გუნდი", "%lld points": {"one": "%lld ქულა", "other": "%lld ქულა"}}
JSON
run merge "$l10n"
expect_success "a valid file merges" "$status" "$output"
expect_equal "into the catalog that has each key" \
    "დავიწყოთ translated" "$(query "$catalog" '"%s %s" % (strings["Start"]["localizations"]["ka"]["stringUnit"]["value"], strings["Start"]["localizations"]["ka"]["stringUnit"]["state"])')"
expect_equal "plural objects become plural variations" \
    "['one', 'other']" "$(query "$catalog" 'sorted(strings["%lld points"]["localizations"]["ka"]["variations"]["plural"])')"
expect_contains "positional placeholders match their plain form" "App/Localizable.xcstrings: 3 merged" "$output"
expect_equal "and the catalog keeps Xcode's layout" "$(cat "$catalog")" \
    "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : ")))' "$catalog")"
reset_app

cat >"$l10n/ka.json" <<'JSON'
{"Start": "დავიწყოთ", "Team %@": "გუნდი"}
JSON
run merge "$l10n"
expect_failure "a dropped placeholder is refused" "$status" "$output"
expect_contains "with the reason" "placeholders differ from the key for 'Team %@'" "$output"
expect_contains "and nothing is merged" "nothing merged" "$output"
expect_empty "not even the valid entries" "$(git -C "$app" status --porcelain)"
reset_app

printf '{"Start": ""}\n' >"$l10n/ka.json"
run merge "$l10n"
expect_contains "an empty translation is refused" "empty translation for 'Start'" "$output"
reset_app

printf '{"Strat": "დავიწყოთ"}\n' >"$l10n/ka.json"
run merge "$l10n"
expect_contains "a key no catalog has is refused" "no catalog has the key 'Strat'" "$output"
reset_app

printf '{"%%lld points": {"one": "%%lld ქულა"}}\n' >"$l10n/ka.json"
run merge "$l10n"
expect_contains "a plural without 'other' is refused" "has no 'other'" "$output"
reset_app

edit "$catalog" 'strings["Open ${applicationName}"] = {}'
printf '{"Open ${applicationName}": ["${applicationName}-ის გახსნა", "${applicationName}-ში შესვლა"]}\n' >"$l10n/ka.json"
run merge "$l10n"
expect_equal "a list of phrases becomes an App Shortcuts phrase set" \
    "2" "$(query "$catalog" 'len(strings["Open ${applicationName}"]["localizations"]["ka"]["stringSet"]["values"])')"
printf '{"Open ${applicationName}": ["გახსნა"]}\n' >"$l10n/ka.json"
run merge "$l10n"
expect_contains "and every phrase keeps the parameters" "placeholders differ from the key" "$output"
reset_app

edit "$catalog" 'strings["%lld rounds"] = {}'
printf '{"%%lld rounds": {"one": "%%lld round", "other": "%%lld rounds"}}\n' >"$l10n/en.json"
run merge "$l10n" en
expect_success "en.json gives the source language its plural forms" "$status" "$output"
expect_equal "as plural variations" \
    "%lld round" "$(query "$catalog" 'strings["%lld rounds"]["localizations"]["en"]["variations"]["plural"]["one"]["stringUnit"]["value"]')"
reset_app

finish
