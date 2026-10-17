"""String Catalog logic for ios-translations.sh: check, dump, and merge.

Run from the repo root (ios-translations.sh does). The catalogs are the repo's
tracked *.xcstrings. Shipped languages are the project's knownRegions minus its
developmentRegion and Base, unless --languages names them. Written for the
Python 3.9 that ships with Xcode: no third-party modules.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

# Format placeholders, compared without their positions: `%2$@` counts as `%@`.
TOKEN = re.compile(r"%(?:\d+\$)?(?:\.\d+)?(lld|llu|ld|lu|lf|d|i|u|@|f)|%%|\$\{[A-Za-z]+\}")
COUNT = re.compile(r"%(?:\d+\$)?(?:lld|llu|ld|lu|d|i|u)")
PLURAL_CATEGORIES = {"zero", "one", "two", "few", "many", "other"}
SHOWN = 30


def tokens(text):
    return sorted(
        match.group(0) if match.group(0).startswith(("%%", "${")) else "%" + match.group(1)
        for match in TOKEN.finditer(text)
    )


def needs_translation(key, entry):
    """Keys marked shouldTranslate=false, and keys with no letters once the
    placeholders are gone ("42", "%lld%%"), never need a translation."""
    if entry.get("shouldTranslate") is False:
        return False
    return bool(re.search(r"[A-Za-z]", TOKEN.sub("", key)))


UNIT_KINDS = ("stringUnit", "stringSet")


def string_units(node):
    """Every unit under a localization: a stringUnit, or the stringSet App Shortcut
    phrases use, whether plain or under plural, device, or substitution variations."""
    if isinstance(node, dict):
        units = [node[kind] for kind in UNIT_KINDS if isinstance(node.get(kind), dict)]
        for key, value in node.items():
            if key not in UNIT_KINDS:
                units += string_units(value)
        return units
    if isinstance(node, list):
        return [unit for item in node for unit in string_units(item)]
    return []


def is_blank(unit):
    texts = unit.get("values") if "values" in unit else [unit.get("value", "")]
    return not texts or any(not str(text).strip() for text in texts)


def gap(localization):
    """Why a language's localization of a key cannot ship, or None when it can."""
    units = string_units(localization) if localization is not None else []
    if not units:
        return "missing"
    states = {unit.get("state") for unit in units}
    if "needs_review" in states:
        return "needs review"
    if states != {"translated"} or any(is_blank(unit) for unit in units):
        return "untranslated"
    return None


# MARK: - Inputs
def shipped_languages(project, override):
    if override.split():
        return override.split()
    if not project:
        sys.exit("✗ set PROJECT in Scripts/gate.conf, or TRANSLATION_LANGUAGES")
    pbxproj = pathlib.Path(project) / "project.pbxproj"
    try:
        text = pbxproj.read_text(encoding="utf-8")
    except OSError as error:
        sys.exit(f"✗ cannot read {pbxproj}: {error.strerror}")
    regions = re.search(r"\bknownRegions = \(([^)]*)\);", text)
    if not regions:
        sys.exit(f"✗ {pbxproj} has no knownRegions")
    development = re.search(r"\bdevelopmentRegion = \"?([^\";]+)\"?;", text)
    skipped = {"Base", development.group(1) if development else "en"}
    names = (name.strip().strip('"') for name in regions.group(1).split(","))
    return [name for name in names if name and name not in skipped]


def tracked_catalogs():
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.xcstrings"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout.decode("utf-8")
    catalogs = []
    for name in sorted(filter(None, listed.split("\0"))):
        path = pathlib.Path(name)
        if not path.is_file():
            continue
        try:
            catalogs.append((path, json.loads(path.read_text(encoding="utf-8"))))
        except ValueError as error:
            sys.exit(f"✗ {path} is not valid JSON: {error}")
    return catalogs


def write_catalog(path, catalog):
    """Xcode's own layout — sorted keys, two-space indent, `" : "` — so a merge
    adds no noise to the next export's diff."""
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    path.write_text(text + "\n", encoding="utf-8")


def catalog_gaps(catalogs, languages):
    gaps = []
    for path, catalog in catalogs:
        source = catalog.get("sourceLanguage", "en")
        for key, entry in sorted(catalog.get("strings", {}).items()):
            if entry.get("extractionState") == "stale":
                gaps.append((path, None, "stale, delete it", key))
                continue
            if not needs_translation(key, entry):
                continue
            localizations = entry.get("localizations", {})
            for language in languages:
                problem = gap(localizations.get(language)) if language != source else None
                if problem:
                    gaps.append((path, language, problem, key))
    return gaps


# MARK: - Commands
def check(arguments):
    languages = shipped_languages(arguments.project, arguments.languages)
    catalogs = tracked_catalogs()
    if not catalogs:
        sys.exit("✗ no tracked .xcstrings files to check")
    if not languages:
        print("✓ nothing to check: the project ships no language besides its development region")
        return 0
    gaps = catalog_gaps(catalogs, languages)
    if not gaps:
        print(f"✓ every string translated into {', '.join(languages)}")
        return 0
    for path, language, problem, key in gaps[:SHOWN]:
        print(f"  {path}: {f'[{language}] ' if language else ''}{problem}: {key}", file=sys.stderr)
    if len(gaps) > SHOWN:
        print(f"  … and {len(gaps) - SHOWN} more", file=sys.stderr)
    brief = arguments.brief
    pointer = f"see {brief}" if brief and pathlib.Path(brief).is_file() else "translate, then run ios-translations.sh merge"
    print(f"✗ {len(gaps)} translation gap(s) in {', '.join(languages)} — {pointer}", file=sys.stderr)
    return 1


def dump(arguments):
    languages = shipped_languages(arguments.project, arguments.languages) if arguments.missing else []
    entries = {}
    for path, catalog in tracked_catalogs():
        source = catalog.get("sourceLanguage", "en")
        for key, entry in catalog.get("strings", {}).items():
            if entry.get("extractionState") == "stale" or not needs_translation(key, entry):
                continue
            localizations = entry.get("localizations", {})
            missing = [language for language in languages if language != source and gap(localizations.get(language))]
            if arguments.missing and not missing:
                continue
            source_localization = localizations.get(source, {})
            item = {
                "english": source_localization.get("stringUnit", {}).get("value", key),
                "comment": entry.get("comment", ""),
                "plural": bool(COUNT.search(key)) or "variations" in source_localization,
            }
            phrases = source_localization.get("stringSet", {}).get("values")
            if phrases:
                item["phrases"] = phrases
            if arguments.missing:
                item["missing"] = missing
            entries[key] = item
    output = pathlib.Path(arguments.output)
    output.write_text(json.dumps(entries, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"✓ {len(entries)} keys → {output}")
    return 0


def validate(language, key, value, known):
    if key not in known:
        return [f"{language}: no catalog has the key {key!r}"]
    problems = []
    if isinstance(value, dict):
        unknown = sorted(set(value) - PLURAL_CATEGORIES)
        if unknown:
            problems.append(f"{language}: not plural categories {unknown} for {key!r}")
        if "other" not in value:
            problems.append(f"{language}: the plural for {key!r} has no 'other'")
        texts = list(value.values())
    elif isinstance(value, list):
        texts = value or [""]
    else:
        texts = [value]
    expected = tokens(key)
    for text in texts:
        if not isinstance(text, str) or not text.strip():
            problems.append(f"{language}: empty translation for {key!r}")
        elif tokens(text) != expected:
            problems.append(f"{language}: placeholders differ from the key for {key!r}: {text!r}")
    return problems


def localization(value):
    """A string, a plural object of CLDR categories, or a list of App Shortcut phrases."""
    def unit(text):
        return {"stringUnit": {"state": "translated", "value": text}}

    if isinstance(value, dict):
        return {"variations": {"plural": {category: unit(text) for category, text in value.items()}}}
    if isinstance(value, list):
        return {"stringSet": {"state": "translated", "values": value}}
    return unit(value)


def load_translations(directory, languages, known):
    translations = {}
    problems = []
    for language in languages:
        path = directory / f"{language}.json"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            problems.append(f"{path}: {error}")
            continue
        if not isinstance(data, dict):
            problems.append(f"{path}: expected one JSON object keyed by the English key")
            continue
        for key, value in data.items():
            problems += validate(language, key, value, known)
        translations[language] = data
    return translations, problems


def merge(arguments):
    directory = pathlib.Path(arguments.directory)
    languages = arguments.language or sorted(path.stem for path in directory.glob("*.json") if path.stem != "source")
    if not languages:
        sys.exit(f"✗ no <LANG>.json files in {directory}")
    catalogs = tracked_catalogs()
    known = {key for _, catalog in catalogs for key in catalog.get("strings", {})}
    translations, problems = load_translations(directory, languages, known)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        print(f"✗ {len(problems)} problem(s); nothing merged", file=sys.stderr)
        return 1
    for path, catalog in catalogs:
        merged = 0
        for key, entry in catalog.get("strings", {}).items():
            if entry.get("shouldTranslate") is False:
                continue
            for language, data in translations.items():
                if key in data:
                    entry.setdefault("localizations", {})[language] = localization(data[key])
                    merged += 1
        if merged:
            write_catalog(path, catalog)
        remaining = len(catalog_gaps([(path, catalog)], [lang for lang in languages if lang != catalog.get("sourceLanguage", "en")]))
        print(f"✓ {path}: {merged} merged" + (f", {remaining} gap(s) left" if remaining else ""))
    return 0


def main():
    parser = argparse.ArgumentParser(prog="ios-translations.sh", description=__doc__.splitlines()[0])
    parser.add_argument("--project", default="", help="the .xcodeproj whose knownRegions are the shipped languages")
    parser.add_argument("--languages", default="", help="space-separated languages that replace knownRegions")
    commands = parser.add_subparsers(dest="command", required=True)
    check_command = commands.add_parser("check", help="fail on any key missing a shipped language, needing review, or stale")
    check_command.add_argument("--brief", default="", help="the translation brief a failure points to")
    check_command.set_defaults(run=check)
    dump_command = commands.add_parser("dump", help="write every key translators need, as JSON")
    dump_command.add_argument("output")
    dump_command.add_argument("--missing", action="store_true", help="only keys some shipped language lacks")
    dump_command.set_defaults(run=dump)
    merge_command = commands.add_parser("merge", help="validate <dir>/<LANG>.json files, then merge them")
    merge_command.add_argument("directory")
    merge_command.add_argument("language", nargs="*")
    merge_command.set_defaults(run=merge)
    arguments = parser.parse_args()
    return arguments.run(arguments)


if __name__ == "__main__":
    sys.exit(main())
