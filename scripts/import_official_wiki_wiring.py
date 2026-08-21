#!/usr/bin/env python3
import argparse
import hashlib
import html
import json
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://barotraumagame.com/baro-wiki/api.php"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "CSharp" / "Client" / "Data" / "WiringDatabase.Generated.cs"
CACHE = Path(tempfile.gettempdir()) / "just-enough-baro-wiring-wiki-v1"
CACHE_MAX_AGE_SECONDS = 15 * 60

# Pages that deliberately document multiple wire-compatible prefab variants.
# Secondary infoboxes such as ammunition loaders are not aliases: they appear
# on turret pages but do not expose the turret's ConnectionPanel.
PREFAB_VARIANT_ALIASES = {
    "aliendoorshatches": {"aliendoor", "alienhatch"},
    "alienterminal": {"alienterminal_new", "alienterminal2"},
    "battery": {"battery", "shuttlebattery"},
    "depthcharge": {"depthchargetube"},
    "dockinghatchport": {"dockingport", "dockinghatch"},
    "doorshatches": {"door", "hatch"},
    "engines": {"engine", "largeengine", "shuttleengine"},
    "fabricatordeconstructor": {"fabricator", "deconstructor"},
    "navigationterminal": {"navterminal", "shuttlenavterminal"},
    "nuclearreactor": {"reactor1", "outpostreactor"},
    "oxygengenerator": {"oxygenerator", "shuttleoxygenerator", "outpostoxygenerator"},
    "periscope": {"periscope", "blankperiscope"},
    "pumps": {"pump", "smallpump"},
}

# Still published by the consolidated component page and used by older vanilla
# content, while the current individual page calls the same prefab powcomponent.
PREFAB_COMPATIBILITY_ALIASES = {
    # Current vanilla variants that expose the same (or a strict subset of the
    # same) connections as the canonical panel documented by the wiki. Runtime
    # rendering only enriches pins actually declared by the selected prefab.
    "aliendoorheavy": "aliendoorshatches",
    "aliendoorsmall": "aliendoorshatches",
    "aliendoorsmallwbuttons": "aliendoorshatches",
    "aliendoorwbuttons": "aliendoorshatches",
    "alienhatchheavy": "aliendoorshatches",
    "alienhatchsmall": "aliendoorshatches",
    "alienhatchsmallwbuttons": "aliendoorshatches",
    "alienhatchwbuttons": "aliendoorshatches",
    "endruinheavydoorhorizontal": "aliendoorshatches",
    "endruinheavydoorvertical": "aliendoorshatches",
    "guardianpodtrap": "guardianpod",
    "alienlightcomponent": "lightcomponent",
    "doorwbuttons": "doorshatches",
    "doorwbuttonswrecked": "doorshatches",
    "doorwrecked": "doorshatches",
    "hatchwbuttons": "doorshatches",
    "hatchwbuttonswrecked": "doorshatches",
    "hatchwrecked": "doorshatches",
    "smalldoor": "doorshatches",
    "windoweddoor": "doorshatches",
    "windoweddoorwbuttons": "doorshatches",
    "windoweddoorwbuttonswrecked": "doorshatches",
    "windoweddoorwrecked": "doorshatches",
    "dockinghatchwrecked": "dockinghatchport",
    "dockingportwrecked": "dockinghatchport",
    "emergencylight": "lightcomponent",
    "lamp": "lightcomponent",
    "lightcomponent90": "lightcomponent",
    "lightcomponentround": "lightcomponent",
    "lightfluorescentl01": "lightcomponent",
    "lightfluorescentl01wrecked": "lightcomponent",
    "lightfluorescentl02": "lightcomponent",
    "lightfluorescentl02wrecked": "lightcomponent",
    "lightfluorescentm01": "lightcomponent",
    "lightfluorescentm01wrecked": "lightcomponent",
    "lightfluorescentm02": "lightcomponent",
    "lightfluorescentm02wrecked": "lightcomponent",
    "lightfluorescentm03": "lightcomponent",
    "lightfluorescentm03wrecked": "lightcomponent",
    "lightfluorescentm04": "lightcomponent",
    "lightfluorescentm04wrecked": "lightcomponent",
    "lighthalogenm04": "lightcomponent",
    "lighthalogenm04wrecked": "lightcomponent",
    "lighthalogenmm01": "lightcomponent",
    "lighthalogenmm01wrecked": "lightcomponent",
    "lighthalogenmm02": "lightcomponent",
    "lighthalogenmm02wrecked": "lightcomponent",
    "lighthalogenmm03": "lightcomponent",
    "lighthalogenmm03wrecked": "lightcomponent",
    "lightleds01": "lightcomponent",
    "lightleds01wrecked": "lightcomponent",
    "streetlight": "lightcomponent",
    "junctionboxtutorial": "junctionbox",
    "outpostterminal": "terminal",
    "railguncontroller": "periscope",
    "rearrailguncontroller": "periscope",
    "railgunloadersmall": "railgunloader",
    "timeddetonator": "detonator",
    # Older official spelling retained for compatibility.
    "exponentationcomponent": "exponentiationcomponent",
}


def request(parameters):
    url = API + "?" + urllib.parse.urlencode(parameters)
    cache_path = CACHE / (hashlib.sha256(url.encode("utf-8")).hexdigest() + ".json")
    if cache_path.exists() and time.time() - cache_path.stat().st_mtime <= CACHE_MAX_AGE_SECONDS:
        try:
            return json.loads(cache_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass
    request_object = urllib.request.Request(
        url,
        headers={"User-Agent": "JustEnoughBaro/1.0 (offline wiki data importer)"},
    )
    attempts = 4
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request_object, timeout=60) as response:
                payload = response.read()
            parsed = json.loads(payload)
            CACHE.mkdir(parents=True, exist_ok=True)
            temporary = cache_path.with_suffix(".tmp")
            temporary.write_bytes(payload)
            temporary.replace(cache_path)
            return parsed
        except (
            TimeoutError,
            ConnectionError,
            json.JSONDecodeError,
            urllib.error.URLError,
        ):
            if attempt + 1 == attempts:
                raise
            time.sleep(2**attempt)


def clean(fragment):
    value = re.sub(r"<[^>]+>", " ", fragment, flags=re.S)
    return " ".join(html.unescape(value).split())


def normalize_key(value):
    return re.sub(r"[^a-z0-9]", "", value.lower())


def connection_panel_sections(page_html):
    """Split a page into each outer ConnectionPanel table.

    Several official item pages document more than one prefab. Turret pages,
    for example, contain independent panels for the weapon and its loader. The
    inner tables use names such as ``connectionpanel-table1``; only the exact
    ``connectionpanel`` class starts a new panel section.
    """
    openings = []
    for match in re.finditer(r"<table\b([^>]*)>", page_html, re.I | re.S):
        class_attribute = re.search(
            r"\bclass\s*=\s*(['\"])(.*?)\1", match.group(1), re.I | re.S
        )
        if class_attribute is None:
            continue
        if "connectionpanel" in class_attribute.group(2).split():
            openings.append(match.start())
    return [
        page_html[start : openings[index + 1] if index + 1 < len(openings) else len(page_html)]
        for index, start in enumerate(openings)
    ]


def connection_panel_title(section, fallback):
    heading = re.search(
        r"<th\b[^>]*>.*?Connection\s+Panel.*?\bfor\s*<b\b[^>]*>(.*?)</b>",
        section,
        re.I | re.S,
    )
    return clean(heading.group(1)) if heading is not None else fallback


def table(page_html, class_name):
    """Return a ConnectionPanel subtable even when MediaWiki adds attributes.

    The template adds inline styles to one-sided panels. Matching the entire
    opening tag meant those panels (Button, Lever, detectors, and others) were
    silently skipped by the old importer.
    """
    for opening in re.finditer(r"<table\b([^>]*)>", page_html, re.I | re.S):
        attributes = opening.group(1)
        class_attribute = re.search(
            r"\bclass\s*=\s*(['\"])(.*?)\1", attributes, re.I | re.S
        )
        if class_attribute is None:
            continue
        classes = class_attribute.group(2).split()
        if class_name not in classes:
            continue
        closing_index = page_html.find("</table>", opening.end())
        if closing_index >= 0:
            return page_html[opening.end() : closing_index]
    return ""


def label_rows(table_html):
    labels = []
    for row in re.findall(r"<tr\b[^>]*>(.*?)</tr>", table_html, re.I | re.S):
        if not re.search(
            r"\bclass\s*=\s*(['\"])[^'\"]*connectionpanel-(?:red|blue)label[^'\"]*\1",
            row,
            re.I | re.S,
        ):
            continue
        label = re.search(r"<b\b[^>]*>(.*?)</b>", row, re.I | re.S)
        if label is not None:
            labels.append(clean(label.group(1)))
    return labels


def tooltip_rows(table_html):
    """Keep blank tooltip rows so descriptions stay paired with their pins."""
    tooltips = []
    for row in re.findall(r"<tr\b[^>]*>(.*?)</tr>", table_html, re.I | re.S):
        tooltip = re.search(
            r"<div\b[^>]*\bclass\s*=\s*(['\"])[^'\"]*\bcp-tooltip\b[^'\"]*\1[^>]*>(.*?)</div>",
            row,
            re.I | re.S,
        )
        if tooltip is not None:
            tooltips.append(clean(tooltip.group(2)))
            continue
        # Empty descriptions are rendered as a normal 36 px tooltip row with
        # no cp-tooltip div. Ten-pixel rows are only visual separators.
        if re.search(
            r"<td\b[^>]*\bstyle\s*=\s*(['\"])[^'\"]*\bheight\s*:\s*36px\b[^'\"]*\1",
            row,
            re.I | re.S,
        ):
            tooltips.append("")
    return tooltips


def extract_side(page_html, label_table, tooltip_table, direction, source):
    labels = label_rows(table(page_html, label_table))
    tooltips = tooltip_rows(table(page_html, tooltip_table))
    if len(labels) != len(tooltips):
        raise ValueError(
            f"{source}: {direction} panel has {len(labels)} labels but "
            f"{len(tooltips)} tooltip rows"
        )
    return [
        {"name": label, "direction": direction, "tooltip": tooltip}
        for label, tooltip in zip(labels, tooltips)
    ]


def summary(page_html):
    quote = re.search(r"<blockquote>\s*<p>(.*?)</p>\s*</blockquote>", page_html, re.S)
    if quote:
        return clean(quote.group(1)).strip().strip('"“”').strip()
    return ""


def prefab_identifiers(page_html):
    """Read every Technical -> Identifier value published for a panel page."""
    identifiers = []
    seen = set()
    for row in re.findall(r"<tr\b[^>]*>(.*?)</tr>", page_html, re.I | re.S):
        cells = re.findall(r"<t[dh]\b[^>]*>(.*?)</t[dh]>", row, re.I | re.S)
        if len(cells) < 2 or clean(cells[0]).lower() != "identifier":
            continue
        for identifier in re.findall(r"[a-z0-9_.:-]+", clean(cells[1]).lower()):
            if identifier not in seen:
                seen.add(identifier)
                identifiers.append(identifier)
    return identifiers


def embedded_pages():
    pages = []
    continuation = {}
    while True:
        response = request(
            {
                "action": "query",
                "list": "embeddedin",
                "eititle": "Template:Connection panel",
                "einamespace": 0,
                "eilimit": 500,
                "format": "json",
                **continuation,
            }
        )
        pages.extend(response.get("query", {}).get("embeddedin", []))
        continuation = response.get("continue")
        if continuation is None:
            return pages


def parsed_html(title):
    return request(
        {"action": "parse", "page": title, "prop": "text", "format": "json"}
    ).get("parse", {}).get("text", {}).get("*", "")


def import_records():
    records = {}
    for page in embedded_pages():
        title = page["title"]
        if "(Legacy)" in title or title == "Wiring Components":
            continue
        page_html = parsed_html(title)
        page_summary = summary(page_html)
        page_identifiers = prefab_identifiers(page_html)
        sections = connection_panel_sections(page_html)
        for section_index, section in enumerate(sections):
            panel_title = connection_panel_title(section, title)
            source = f"{title}#{panel_title}"
            pins = extract_side(
                section,
                "connectionpanel-table1",
                "connectionpanel-table2",
                "input",
                source,
            )
            pins += extract_side(
                section,
                "connectionpanel-table3",
                "connectionpanel-table4",
                "output",
                source,
            )
            if not pins and not (page_summary and section_index == 0):
                continue

            key = normalize_key(panel_title)
            exact_identifiers = [
                identifier
                for identifier in page_identifiers
                if normalize_key(identifier) == key
            ]
            # Prefer identifiers that name this exact panel. A page can have a
            # secondary item infobox without a second panel (both turret
            # hardpoint pages mention ``blankloader``), so assigning every
            # identifier from a single-panel page would create false aliases.
            # A sole non-matching identifier is safe and covers renamed pages
            # such as RegEx Find Component -> regexcomponent.
            associated_identifiers = (
                exact_identifiers
                if exact_identifiers
                else page_identifiers
                if len(page_identifiers) == 1
                else []
            )
            candidate = {
                "title": panel_title,
                "summary": page_summary if section_index == 0 else "",
                "pins": pins,
                "identifiers": associated_identifiers,
                "page_identifiers": page_identifiers,
            }
            previous = records.get(key)
            if previous is None or sum(pin["tooltip"] != "" for pin in pins) > sum(
                pin["tooltip"] != "" for pin in previous.get("pins", [])
            ):
                records[key] = candidate

    # The consolidated page contains authoritative tooltips for several
    # components whose individual pages have blank tooltip rows.
    consolidated = parsed_html("Wiring Components")
    sections = re.split(r"(?=<h2>)", consolidated)
    for section in sections:
        heading = re.search(
            r'<span\b[^>]*\bclass="[^"]*\bmw-headline\b[^"]*"[^>]*\bid="([^"]+)"',
            section,
        )
        if heading is None:
            continue
        title = clean(heading.group(1).replace("_", " "))
        pins = extract_side(
            section,
            "connectionpanel-table1",
            "connectionpanel-table2",
            "input",
            f"Wiring Components#{title}",
        )
        pins += extract_side(
            section,
            "connectionpanel-table3",
            "connectionpanel-table4",
            "output",
            f"Wiring Components#{title}",
        )
        section_summary = summary(section)
        if pins or section_summary:
            key = normalize_key(title)
            previous = records.get(key, {})
            described_pins = sum(pin["tooltip"] != "" for pin in pins)
            previous_described_pins = sum(
                pin["tooltip"] != "" for pin in previous.get("pins", [])
            )
            records[key] = {
                "title": title,
                "summary": section_summary or previous.get("summary", ""),
                "pins": pins
                if described_pins > previous_described_pins
                else previous.get("pins", pins),
                "identifiers": previous.get("identifiers", []),
                "page_identifiers": previous.get("page_identifiers", []),
            }
    return records


def csharp_string(value):
    return json.dumps(value, ensure_ascii=False)


def alias_map(records):
    aliases = {}
    for key, record in records.items():
        published = set(record.get("identifiers", []))
        page_published = set(record.get("page_identifiers", published))
        configured = PREFAB_VARIANT_ALIASES.get(key)
        if configured is not None:
            missing = configured - page_published
            if missing:
                raise ValueError(
                    f"{record['title']}: configured prefab aliases are no longer "
                    f"published by the wiki: {sorted(missing)}"
                )
            selected = published | configured
        else:
            selected = published

        for identifier in selected:
            alias = normalize_key(identifier)
            if alias and alias != key:
                previous = aliases.get(alias)
                if previous is not None and previous != key:
                    raise ValueError(
                        f"Prefab identifier alias {identifier!r} maps to both "
                        f"{previous!r} and {key!r}"
                    )
                aliases[alias] = key
    for alias, key in PREFAB_COMPATIBILITY_ALIASES.items():
        if key not in records:
            raise ValueError(f"Compatibility alias {alias!r} has no panel {key!r}")
        aliases[normalize_key(alias)] = key
    return aliases


def render_csharp(records):
    aliases = alias_map(records)
    lines = [
        "// <auto-generated />",
        "// Generated from the official Barotrauma Wiki ConnectionPanel tables by",
        "// scripts/import_official_wiki_wiring.py. Blank descriptions are blank upstream.",
        "#nullable enable",
        "",
        "using System;",
        "using System.Collections.Generic;",
        "using System.Text;",
        "",
        "namespace JustEnoughBaro;",
        "",
        "internal static class WiringDatabase",
        "{",
        "    private static readonly IReadOnlyDictionary<string, WiringPanelInfo> panels = CreatePanels();",
        "    private static readonly IReadOnlyDictionary<string, string> aliases = CreateAliases();",
        "",
        "    public static IReadOnlyDictionary<string, WiringPanelInfo> Panels => panels;",
        "    public static IReadOnlyDictionary<string, string> Aliases => aliases;",
        "",
        "    public static bool TryGet(string? prefabIdentifier, string? displayName, out WiringPanelInfo panel)",
        "    {",
        "        if (TryGet(prefabIdentifier, out panel)) { return true; }",
        "        return TryGet(displayName, out panel);",
        "    }",
        "",
        "    public static bool TryGet(string? value, out WiringPanelInfo panel)",
        "    {",
        "        string key = NormalizeKey(value);",
        "        if (panels.TryGetValue(key, out WiringPanelInfo? exact))",
        "        {",
        "            panel = exact;",
        "            return true;",
        "        }",
        "        if (aliases.TryGetValue(key, out string? target) && panels.TryGetValue(target, out WiringPanelInfo? aliased))",
        "        {",
        "            panel = aliased;",
        "            return true;",
        "        }",
        "        panel = null!;",
        "        return false;",
        "    }",
        "",
        "    public static WiringPin? MatchPin(WiringPanelInfo panel, string pinName)",
        "    {",
        "        return MatchPin(panel, pinName, null);",
        "    }",
        "",
        "    public static WiringPin? MatchPin(WiringPanelInfo panel, string pinName, string? direction)",
        "    {",
        "        string key = NormalizeKey(pinName);",
        "        foreach (WiringPin pin in panel.Pins)",
        "        {",
        "            if (NormalizeKey(pin.Name) != key) { continue; }",
        "            if (string.IsNullOrWhiteSpace(direction) || string.Equals(pin.Direction, direction, StringComparison.OrdinalIgnoreCase))",
        "            {",
        "                return pin;",
        "            }",
        "        }",
        "        return null;",
        "    }",
        "",
        "    public static string NormalizeKey(string? value)",
        "    {",
        "        if (string.IsNullOrWhiteSpace(value)) { return string.Empty; }",
        "        StringBuilder result = new StringBuilder(value.Length);",
        "        foreach (char character in value)",
        "        {",
        "            if (character is >= 'A' and <= 'Z') { result.Append((char)(character + 32)); }",
        "            else if ((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')) { result.Append(character); }",
        "        }",
        "        return result.ToString();",
        "    }",
        "",
        "    private static IReadOnlyDictionary<string, WiringPanelInfo> CreatePanels()",
        "    {",
        "        return new Dictionary<string, WiringPanelInfo>(StringComparer.OrdinalIgnoreCase)",
        "        {",
    ]
    for key in sorted(records):
        record = records[key]
        lines.append(f"            [{csharp_string(key)}] = new WiringPanelInfo")
        lines.append("            {")
        lines.append(f"                Key = {csharp_string(key)},")
        lines.append(f"                Title = {csharp_string(record['title'])},")
        lines.append(
            f"                Summary = {csharp_string(record.get('summary', ''))},"
        )
        lines.append("                Pins = new WiringPin[]")
        lines.append("                {")
        for pin in record["pins"]:
            lines.append(
                "                    new WiringPin { Name = %s, Direction = %s, Description = %s },"
                % tuple(
                    csharp_string(pin[field])
                    for field in ("name", "direction", "tooltip")
                )
            )
        lines.append("                }")
        lines.append("            },")
    lines.extend(
        [
            "        };",
            "    }",
            "",
            "    private static IReadOnlyDictionary<string, string> CreateAliases()",
            "    {",
            "        return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)",
            "        {",
        ]
    )
    for alias, key in sorted(aliases.items()):
        lines.append(f"            [{csharp_string(alias)}] = {csharp_string(key)},")
    lines.extend(["        };", "    }", "}"])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Generate C# data from official Barotrauma ConnectionPanel tables."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the checked-in C# dataset differs from the wiki",
    )
    parser.add_argument("--output", type=Path, default=OUTPUT)
    arguments = parser.parse_args()

    records = import_records()
    generated = render_csharp(records)
    if arguments.check:
        current = (
            arguments.output.read_text(encoding="utf-8")
            if arguments.output.exists()
            else ""
        )
        if current != generated:
            print(f"Wiring dataset is stale: {arguments.output}", file=sys.stderr)
            return 1
    else:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(generated, encoding="utf-8")

    pin_count = sum(len(record["pins"]) for record in records.values())
    described_count = sum(
        pin["tooltip"] != ""
        for record in records.values()
        for pin in record["pins"]
    )
    print(
        f"Imported {len(records)} official connection panels with {pin_count} pins "
        f"({described_count} described, {len(alias_map(records))} identifier aliases) "
        f"into {arguments.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
