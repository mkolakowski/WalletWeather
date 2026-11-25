#!/usr/bin/env python3
"""Turns one run of the simulator walk into a summary (Plans/ios-ui-review.md, #345).

    Scripts/ui-report.py build/ui-review/<run>     writes report.md and report.json there
    Scripts/ui-report.py                            the latest run
    Scripts/ui-report.py --sheets [<run>]           also draw contact sheets under <run>/sheets

It reads each configuration's walk.json (apps/ios/UITests writes them) and:

- folds the same finding seen on several screens and configurations into one,
  with where it was seen and a picture to look at;
- sets aside what UITests/Known.json says is already judged (a check being
  wrong about something, or a choice Matthew made), so a run only raises
  what's new;
- compares screens with each other, which no single screen can show: left
  margins, title bars, how amounts and dates are written, words that mean the
  same thing, and (in an .iso configuration) dates that ignore the setting;
- adds the source check's report when the run folder holds one (source.json,
  from `WW_UI_SOURCE_REPORT=<run>/source.json swift test --filter UISourceTests`).

Python 3 from the system; nothing to install.
"""
import collections
import fnmatch
import json
import pathlib
import re
import sys

IOS = pathlib.Path(__file__).resolve().parent.parent
LEVELS = {"bug": 0, "slip": 1, "note": 2}

# Words that mean the same thing. A screen using one while another uses the
# other is worth a look; which one is right is Matthew's call.
TERMS = [
    ["Delete", "Remove", "Erase", "Clear"],
    ["Sign out", "Log out", "Disconnect"],
    ["Sign in", "Log in", "Login"],
    ["Cancel", "Close", "Dismiss", "Done", "OK"],
    ["can't", "cannot", "can’t", "Couldn't", "Could not", "Unable to"],
    ["Edit", "Change"],
    ["Add", "New", "Create"],
    ["Try again", "Retry"],
    ["Save", "Apply", "Update"],
    ["Turn on", "Enable", "Switch on"],
    ["Choose", "Select", "Pick"],
    ["transaction", "line", "entry"],
    ["bill", "recurring", "repeating"],
    ["’", "'"],
    ["…", "..."],
]

MONTHS = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"


def fold_key(text):
    """A label with its numbers taken out, so "$4,794.98" and "$18,500.00" fold together."""
    text = re.sub(r"\d[\d,]*(\.\d+)?", "#", text)
    return re.sub(r"\b(%s)[a-z]*\b" % MONTHS, "Mon", text)[:80]


def load_known():
    path = IOS / "UITests" / "Known.json"
    if not path.exists():
        return []
    return json.loads(path.read_text()).get("known", [])


def known_for(finding, known):
    for entry in known:
        if entry.get("check") not in (None, "*", finding["check"]):
            continue
        if not fnmatch.fnmatch(finding["screen"], entry.get("screen", "*")):
            continue
        if entry.get("label") and not re.search(entry["label"], finding["label"]):
            continue
        if entry.get("config") and not fnmatch.fnmatch(finding["config"], entry["config"]):
            continue
        return entry
    return None


def write_sheets(run, walks):
    """Contact sheets under <run>/sheets: each screen across a device's looks and text sizes
    (<screen>.<device>.looks.jpg), down its length (<screen>.<configuration>.long.jpg), and every
    screen's first picture eight to a sheet (overview.<configuration>.<n>.jpg)."""
    import subprocess
    sheets = []

    def rows_of(cells, height):
        rows, row, width = [], [], 0
        for cell in cells:
            if row and width + cell["width"] * height / cell["height"] > 1900:
                rows.append(row)
                row, width = [], 0
            row.append({"path": cell["path"], "label": cell["label"]})
            width += cell["width"] * height / cell["height"]
        return rows + ([row] if row else [])

    screens = collections.OrderedDict()
    for config, walk in walks.items():
        for screen in walk["screens"]:
            screens.setdefault(screen["name"], collections.OrderedDict())[config] = screen
    for name, by_config in screens.items():
        devices = collections.OrderedDict()
        for config, screen in by_config.items():
            if not screen["captures"]:
                continue
            devices.setdefault(config.split(".")[0], []).append((config, screen))
            if len(screen["captures"]) > 1:
                window = screen["captures"][0]["measures"]["window"]
                cells = [{"path": str(run / config / c["file"]), "label": c["part"], "width": window[2], "height": window[3]} for c in screen["captures"][:6]]
                height = 760 if window[3] > window[2] * 1.2 else 560
                sheets.append({"out": str(run / "sheets" / f"{name}.{config}.long.jpg"), "height": height, "rows": rows_of(cells, height)})
        for device, entries in devices.items():
            window = entries[0][1]["captures"][0]["measures"]["window"]
            cells = [{"path": str(run / config / screen["captures"][0]["file"]), "label": config.split(".", 1)[1], "width": window[2], "height": window[3]}
                     for config, screen in entries]
            height = 760 if window[3] > window[2] * 1.2 else 560
            sheets.append({"out": str(run / "sheets" / f"{name}.{device}.looks.jpg"), "height": height, "rows": rows_of(cells, height)})
    # Every screen's first picture, eight to a sheet: is each screen what its name says?
    for config, walk in walks.items():
        cells = []
        for screen in walk["screens"]:
            if screen["captures"]:
                window = screen["captures"][0]["measures"]["window"]
                cells.append({"path": str(run / config / screen["captures"][0]["file"]), "label": screen["name"], "width": window[2], "height": window[3]})
        if not cells:
            continue
        tall = cells[0]["height"] > cells[0]["width"] * 1.2
        height, per_row, per_sheet = (600, 4, 8) if tall else (420, 2, 6)
        for number in range(0, len(cells), per_sheet):
            group = cells[number:number + per_sheet]
            rows = [[{"path": c["path"], "label": c["label"]} for c in group[i:i + per_row]] for i in range(0, len(group), per_row)]
            sheets.append({"out": str(run / "sheets" / f"overview.{config}.{number // per_sheet + 1:02d}.jpg"), "height": height, "rows": rows})
    manifest = run / "sheets.json"
    manifest.write_text(json.dumps(sheets))
    subprocess.run(["swift", str(IOS / "Scripts" / "ui-sheet.swift"), str(manifest)], check=False)


def main():
    make_sheets = "--sheets" in sys.argv
    sys.argv = [a for a in sys.argv if a != "--sheets"]
    if len(sys.argv) > 1:
        run = pathlib.Path(sys.argv[1]).resolve()
    else:
        runs = sorted(p for p in (IOS / "build" / "ui-review").glob("*/") if p.is_dir())
        if not runs:
            sys.exit("ui-report: no runs in build/ui-review")
        run = runs[-1]
    walks = {}
    for folder in sorted(p for p in run.iterdir() if p.is_dir()):
        walk, use = folder / "walk.json", folder / "use.json"
        if walk.exists():
            walks[folder.name] = json.loads(walk.read_text())
        if use.exists():   # the flows of a :deep configuration, filed as screens called use-…
            flows = json.loads(use.read_text())
            if folder.name in walks:
                walks[folder.name]["screens"] += flows["screens"]
            else:
                walks[folder.name] = flows
    if not walks:
        sys.exit(f"ui-report: no walk.json under {run}")
    meta = json.loads((run / "run.json").read_text()) if (run / "run.json").exists() else {}
    known = load_known()

    # Every finding, flat.
    findings = []
    captures = []   # (config, screen, capture)
    for config, walk in walks.items():
        for screen in walk["screens"]:
            if screen["name"] == "self-test":
                continue
            top = screen["captures"][0]["file"] if screen["captures"] else ""
            for finding in screen["findings"]:
                findings.append(dict(finding, config=config, screen=screen["name"], part="top", file=top))
            for capture in screen["captures"]:
                captures.append((config, screen["name"], capture))
                for finding in capture["findings"]:
                    findings.append(dict(finding, config=config, screen=screen["name"], part=capture["part"], file=capture["file"]))
            for check, why in screen.get("expected", {}).items():
                known.append({"check": check, "screen": screen["name"], "why": why})

    # Dates that ignore the setting: in an .iso configuration every day should read 2026-11-12.
    for config, screen, capture in captures:
        if not config.endswith(".iso"):
            continue
        for text in capture["measures"]["strings"]:
            if len(text) > 90:
                continue   # a row read out as one; its parts are listed too
            if re.search(r"\b(%s)[a-z]*\.? \d{1,2}\b|\b\d{1,2}/\d{1,2}\b" % MONTHS, text) and not re.search(r"\d{4}-\d{2}-\d{2}", text):
                findings.append({"check": "date-ignores-setting", "level": "slip", "label": text[:120], "frame": [],
                                 "detail": "Dates & display is set to 2026-11-12, and this still reads another way.",
                                 "config": config, "screen": screen, "part": capture["part"], "file": capture["file"]})

    # Fold: one line per (check, label), with everywhere it was seen.
    folded = collections.OrderedDict()
    set_aside = collections.OrderedDict()
    for finding in findings:
        entry = known_for(finding, known)
        target = set_aside if entry else folded
        key = (finding["check"], fold_key(finding["label"]))
        item = target.setdefault(key, {"check": finding["check"], "level": finding["level"], "label": finding["label"],
                                       "detail": finding["detail"], "seen": [], "why": entry.get("why") if entry else None})
        if LEVELS.get(finding["level"], 3) < LEVELS.get(item["level"], 3):
            item["level"] = finding["level"]
        item["seen"].append({"config": finding["config"], "screen": finding["screen"], "part": finding["part"],
                             "file": f'{finding["config"]}/{finding["file"]}', "frame": finding["frame"]})
    items = sorted(folded.values(), key=lambda i: (LEVELS.get(i["level"], 3), i["check"], -len(i["seen"])))

    # Comparing screens: the first picture of each, in the first configuration of each device.
    compare = {}
    devices = collections.OrderedDict()
    for config in walks:
        devices.setdefault(config.split(".")[0], config)
    for device, config in devices.items():
        rows = []
        for screen in walks[config]["screens"]:
            if screen["name"] == "self-test" or screen["name"].startswith("use-") or not screen["captures"]:
                continue
            m = screen["captures"][0]["measures"]
            rows.append({"screen": screen["name"], "leftMargin": m["leftMargin"], "bar": m["navigationBarHeight"], "title": m["title"],
                         "tabBar": m["tabBar"], "amounts": m["amountStyles"], "dates": m["dateStyles"], "seconds": screen["seconds"],
                         "open": screen.get("timings", {}).get("open")})
        margins = collections.Counter(r["leftMargin"] for r in rows)
        bars = collections.Counter(r["bar"] for r in rows)
        compare[device] = {"config": config, "rows": rows, "margins": dict(margins.most_common()), "bars": dict(bars.most_common())}

    # Words: which screens use which of a group.
    strings = collections.defaultdict(set)
    for config, screen, capture in captures:
        for text in capture["measures"]["strings"]:
            if len(text) <= 90:
                strings[text].add(screen)
    words = []
    for group in TERMS:
        uses = {}
        for term in group:
            pattern = re.escape(term) if len(term) <= 3 and not term.isalpha() else r"(?<![A-Za-z])" + re.escape(term) + r"(?![A-Za-z])"
            hits = {text: sorted(screens) for text, screens in strings.items() if re.search(pattern, text)}
            if hits:
                uses[term] = {"count": len(hits), "examples": sorted(hits.items(), key=lambda kv: len(kv[0]))[:6]}
        if len(uses) > 1:
            words.append(uses)

    source = json.loads((run / "source.json").read_text()) if (run / "source.json").exists() else None

    # Crash reports the walk collected: what stopped, and the first frames with a name.
    crashes = []
    for path in sorted((run / "crashes").glob("*.ips")) if (run / "crashes").exists() else []:
        try:
            head, body = path.read_text().split("\n", 1)
            crash = json.loads(body)
            thread = next(t for t in crash["threads"] if t.get("triggered"))
            images = crash["usedImages"]
            frames = [f'{images[f["imageIndex"]].get("name", "?")}: {f.get("symbol", "?")[:120]}' for f in thread["frames"][:14]]
            crashes.append({"file": path.name, "at": crash.get("captureTime", ""), "exception": crash.get("exception", {}).get("type", ""),
                            "signal": crash.get("exception", {}).get("signal", ""), "frames": frames})
        except (ValueError, KeyError, StopIteration):
            crashes.append({"file": path.name, "at": "", "exception": "(couldn't read it)", "signal": "", "frames": []})

    report = {"run": run.name, "meta": meta, "configs": {c: {k: w[k] for k in w if k != "screens"} | {
        "screens": len(w["screens"]), "pictures": sum(len(s["captures"]) for s in w["screens"]),
        "seconds": round(sum(s["seconds"] for s in w["screens"]))} for c, w in walks.items()},
        "findings": items, "setAside": list(set_aside.values()), "crashes": crashes, "compare": compare, "words": words,
        "strings": {text: sorted(screens) for text, screens in sorted(strings.items())},
        "source": source and {"rules": source["rules"], "slips": source["slips"], "survey": {k: v for k, v in source["survey"].items() if k != "strings"}}}
    (run / "report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False))

    # The summary a person, or Claude, reads first.
    out = [f"# UI walk: {run.name}", ""]
    if meta:
        out.append(f'iOS {meta.get("version")} at {meta.get("commit")}'
                   + (f' (+{meta["uncommitted"]} uncommitted files)' if meta.get("uncommitted") else "")
                   + f', started {meta.get("started")}, mode {meta.get("mode")}.')
        out.append("")
    out += ["| Configuration | Screens | Pictures | Minutes |", "| --- | --- | --- | --- |"]
    for config, info in report["configs"].items():
        out.append(f'| {config} | {info["screens"]} | {info["pictures"]} | {info["seconds"] / 60:.1f} |')
    broken = [c for c, w in walks.items() if not any(s["name"] == "self-test" for s in w["screens"])]
    out.append("")

    if crashes:
        out += ["## Crashes", ""]
        seen_frames = set()
        for crash in crashes:
            key = tuple(crash["frames"][:6])
            out.append(f'- `crashes/{crash["file"]}` at {crash["at"][:19]}: {crash["exception"]} ({crash["signal"]})' + (" — the same as above" if key in seen_frames else ""))
            if key not in seen_frames:
                out += [f"    - {frame}" for frame in crash["frames"]]
            seen_frames.add(key)
        out.append("")

    by_check = collections.OrderedDict()
    for item in items:
        by_check.setdefault(item["check"], []).append(item)
    out += ["## Findings by check", "", "| Check | Level | Different findings | Times seen |", "| --- | --- | --- | --- |"]
    for check, group in by_check.items():
        out.append(f'| {check} | {group[0]["level"]} | {len(group)} | {sum(len(i["seen"]) for i in group)} |')
    out.append(f'\nSet aside as already judged (UITests/Known.json): {len(set_aside)} findings.')
    out.append("")
    for check, group in by_check.items():
        out += [f"### {check}", "", group[0]["detail"] if len({i["detail"] for i in group}) == 1 else "", ""]
        for item in group[:40]:
            screens = collections.OrderedDict()
            for seen in item["seen"]:
                screens.setdefault(seen["screen"], []).append(seen["config"].split(".")[0] + "." + ".".join(seen["config"].split(".")[1:]))
            where = "; ".join(f'{screen} ({len(set(configs))} cfg)' for screen, configs in list(screens.items())[:5])
            more = f" and {len(screens) - 5} more screens" if len(screens) > 5 else ""
            first = item["seen"][0]
            detail = "" if len({i["detail"] for i in group}) == 1 else f' — {item["detail"][:160]}'
            out.append(f'- **{item["label"][:90] or "(no label)"}**{detail} · {where}{more} · `{first["file"]}` {first["frame"]}')
        if len(group) > 40:
            out.append(f"- … and {len(group) - 40} more (report.json has them all)")
        out.append("")

    out += ["## Comparing screens", ""]
    for device, data in compare.items():
        out += [f'### {device} ({data["config"]})', "",
                f'Left margins (points: screens): {data["margins"]}', f'Title bar heights (points: screens): {data["bars"]}', ""]
        common = max(data["margins"], key=data["margins"].get) if data["margins"] else None
        odd = [r for r in data["rows"] if r["leftMargin"] != common]
        if odd:
            out.append("Screens off the usual left margin: " + ", ".join(f'{r["screen"]} ({r["leftMargin"]:.0f})' for r in odd))
        slow = sorted((r for r in data["rows"] if (r["open"] or 0) > 12), key=lambda r: -r["open"])
        if slow:
            out.append("Slow to open and settle (seconds): " + ", ".join(f'{r["screen"]} ({r["open"]})' for r in slow[:8]))
        mixes = collections.Counter(tuple(r["amounts"]) for r in data["rows"] if r["amounts"])
        out.append(f"How amounts are written (styles: screens): {dict(mixes)}")
        dates = collections.Counter(tuple(r["dates"]) for r in data["rows"] if r["dates"])
        out.append(f"How dates are written (styles: screens): {dict(dates)}")
        out.append("")
    if words:
        out += ["## Words that mean the same thing", ""]
        for uses in words:
            out.append("- " + " / ".join(f'**{term}** ×{use["count"]} (e.g. "{use["examples"][0][0][:50]}" on {use["examples"][0][1][0]})' for term, use in uses.items()))
        out.append("")
    if source:
        out += ["## The source check", "", "| Rule | Slips | Why |", "| --- | --- | --- |"]
        for rule in source["rules"]:
            if rule["count"]:
                out.append(f'| {rule["id"]} | {rule["count"]} | {rule["why"]} |')
        survey = source["survey"]
        out += ["", f'Corner radii in use: {dict(sorted(survey["cornerRadius"].items(), key=lambda kv: -kv[1]))}',
                f'Spacings: {dict(sorted(survey["spacing"].items(), key=lambda kv: -kv[1]))}',
                f'Paddings: {dict(sorted(survey["padding"].items(), key=lambda kv: -kv[1]))}',
                f'Type styles: {dict(sorted(survey["fonts"].items(), key=lambda kv: -kv[1]))}', ""]
    if broken:
        out += ["## Heads-up", "", "No self-test in: " + ", ".join(broken) + " (run with --only, or the walk stopped early).", ""]
    (run / "report.md").write_text("\n".join(out) + "\n")
    if make_sheets:
        write_sheets(run, walks)
    levels = collections.Counter(i["level"] for i in items)
    print(f'ui-report: {len(items)} different findings ({levels.get("bug", 0)} bugs, {levels.get("slip", 0)} slips, {levels.get("note", 0)} notes), '
          f'{len(set_aside)} set aside; {run / "report.md"}')


if __name__ == "__main__":
    main()
