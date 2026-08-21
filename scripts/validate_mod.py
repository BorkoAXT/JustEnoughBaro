#!/usr/bin/env python3
"""Offline structural validation for the C# JEB package."""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise RuntimeError(message)


def validate_xml() -> None:
    paths = [
        ROOT / "ModConfig.xml",
        ROOT / "filelist.xml",
        ROOT / "Config/SettingsClient.xml",
        ROOT / "CSharp/JustEnoughBaro.Client.csproj",
        *sorted((ROOT / "Texts").glob("*.xml")),
    ]
    for path in paths:
        ET.parse(path)

    mod = ET.parse(ROOT / "ModConfig.xml").getroot()
    assemblies = mod.findall("Assembly")
    if len(assemblies) != 1:
        fail(f"ModConfig must load exactly one Assembly, found {len(assemblies)}")
    if mod.findall("Lua"):
        fail("ModConfig still loads Lua")
    assembly = assemblies[0]
    expected = {
        "Folder": "%ModDir%/CSharp/Client",
        "Target": "Client",
        "IsScript": "true",
        "UseInternalAccessName": "true",
    }
    for key, value in expected.items():
        if assembly.get(key) != value:
            fail(f"Assembly {key} must be {value!r}")


def validate_json() -> None:
    creature_path = ROOT / "Data/creature_wiki.json"
    creature = json.loads(creature_path.read_text(encoding="utf-8"))
    if len(creature) < 50:
        fail(f"Expected at least 50 creature records, found {len(creature)}")
    for identifier, entry in creature.items():
        if not identifier or not isinstance(entry, dict):
            fail("Malformed creature record")
        for field in ("title", "description", "image", "url"):
            if not isinstance(entry.get(field), str):
                fail(f"Creature {identifier!r} has an invalid {field}")

    curated = json.loads((ROOT / "Data/curated_knowledge.json").read_text(encoding="utf-8"))
    if curated.get("schemaVersion") != 1:
        fail("Unsupported curated knowledge schema")
    if len(curated.get("professions", {})) != 6:
        fail("Curated profession count changed unexpectedly")
    if len(curated.get("submarines", {})) != 16:
        fail("Curated submarine count changed unexpectedly")


def localization_packs(source: str) -> dict[str, list[str]]:
    names = (("en", "EnglishPack"), ("ru", "RussianPack"), ("pt", "PortuguesePack"))
    markers: list[tuple[str, int]] = []
    for language, method in names:
        match = re.search(
            rf"private static Dictionary<string, string> {method}\(\)", source
        )
        if match is None:
            fail(f"Missing localization method {method}")
        markers.append((language, match.start()))

    packs: dict[str, list[str]] = {}
    for index, (language, start) in enumerate(markers):
        end = markers[index + 1][1] if index + 1 < len(markers) else len(source)
        packs[language] = re.findall(r'\["([^"]+)"\]\s*=', source[start:end])
    return packs


def validate_localization() -> None:
    path = ROOT / "CSharp/Client/Core/JebLocalization.cs"
    source = path.read_text(encoding="utf-8")
    packs = localization_packs(source)
    canonical = set(packs["en"])
    for language, keys in packs.items():
        if len(keys) != len(set(keys)):
            fail(f"Duplicate keys in {language} localization")
        missing = canonical - set(keys)
        extra = set(keys) - canonical
        if missing or extra:
            fail(f"Localization mismatch for {language}: missing={sorted(missing)}, extra={sorted(extra)}")

    used: set[str] = set()
    for csharp in (ROOT / "CSharp/Client").rglob("*.cs"):
        if csharp == path:
            continue
        text = csharp.read_text(encoding="utf-8")
        for key in re.findall(r'L\.(?:Get|F)\("([^"]+)"', text):
            if not key.endswith("."):
                used.add(key)
    missing_used = used - canonical
    if missing_used:
        fail(f"C# uses untranslated literal keys: {sorted(missing_used)}")


def validate_wiring() -> None:
    source = (ROOT / "CSharp/Client/Data/WiringDatabase.Generated.cs").read_text(
        encoding="utf-8"
    )
    panels = len(re.findall(r"new WiringPanelInfo\s*$", source, re.MULTILINE))
    pins = len(re.findall(r"new WiringPin \{", source))
    aliases = len(re.findall(r'^            \[".*"\] = ".*",$', source, re.MULTILINE))
    if (panels, pins, aliases) != (101, 422, 95):
        fail(
            "Unexpected wiring dataset counts: "
            f"panels={panels}, pins={pins}, aliases={aliases}"
        )


def validate_no_lua() -> None:
    lua_files = sorted(ROOT.rglob("*.lua"))
    if lua_files:
        fail("Lua files remain: " + ", ".join(str(path.relative_to(ROOT)) for path in lua_files))


def main() -> int:
    validate_xml()
    validate_json()
    validate_localization()
    validate_wiring()
    validate_no_lua()
    print("JEB validation passed: C# package, XML/JSON, localization, and wiring data are consistent.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ET.ParseError, RuntimeError) as exception:
        print(f"validation failed: {exception}", file=sys.stderr)
        raise SystemExit(1)
