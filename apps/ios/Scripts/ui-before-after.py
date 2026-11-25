#!/usr/bin/env python3
"""Writes the iOS before-and-after page from the sets of pictures (#352).

    Scripts/ui-before-after.py            compares each set with the one before it and writes the page
    Scripts/ui-before-after.py --check A B   compares two sets and prints what differs (no page)

A set is build/ui-sets/<version>-<build>/ (Scripts/ui-snapshot.sh takes one):
set.json and a picture of the top of every screen, per configuration. The
page is written from the sets and the repo's history and nothing else: no
clock, no order that depends on the disk. The same sets give the same page,
byte for byte.

It writes the page's content and the pictures it shows under
build/artifact/ (the WalletWeather artifact's folder, #351) and wraps it
with the artifact-page skill's script. Publishing is Claude's step.
"""
import html
import json
import pathlib
import re
import shutil
import subprocess
import sys

IOS = pathlib.Path(__file__).resolve().parent.parent
REPO = IOS.parent.parent
SETS = IOS / "build" / "ui-sets"
OUT = IOS / "build" / "artifact"
SLUG = "ios-before-after"
KEEP = 6   # pairs on the page; older ones stay on the screenshots branch
DEVICES = {"iphone": "iPhone 17", "duo-open": "iPhone Duo, open on its side", "duo-closed": "iPhone Duo, closed"}
esc = html.escape


def load_sets():
    sets = []
    for path in SETS.glob("*/set.json"):
        info = json.loads(path.read_text())
        info["folder"] = path.parent
        sets.append(info)
    return sorted(sets, key=lambda s: (s["build"], s["label"]))


def pictures(a_set):
    return {f"{p.parent.name}/{p.stem}": p for p in sorted(a_set["folder"].glob("*/*.jpg"))}


def compare(before, after):
    """What differs between two sets. Kept beside the later set, so it's worked out once."""
    kept = after["folder"] / f'compare.{before["label"]}.json'
    old, new = pictures(before), pictures(after)
    both = sorted(set(old) & set(new))
    if not kept.exists():
        pairs = after["folder"] / "pairs.json"
        pairs.write_text(json.dumps([{"name": n, "before": str(old[n]), "after": str(new[n])} for n in both]))
        subprocess.run(["swift", str(IOS / "Scripts" / "ui-compare.swift"), str(pairs), str(kept)], check=True, capture_output=True)
        pairs.unlink()
    verdicts = json.loads(kept.read_text())
    return {"verdicts": verdicts, "same": [v["name"] for v in verdicts if not v["changed"]],
            "changed": [v for v in verdicts if v["changed"]], "added": sorted(set(new) - set(old)), "gone": sorted(set(old) - set(new))}


def what_went_in(before, after):
    """The iOS commits between two sets, oldest first, from the repo's own history."""
    log = subprocess.run(["git", "-C", str(REPO), "log", "--reverse", "--format=%h\t%s", f'{before["commit"]}..{after["commit"]}', "--", "apps/ios"],
                         capture_output=True, text=True).stdout
    lines = []
    for row in log.splitlines():
        sha, _, subject = row.partition("\t")
        if subject.startswith("iOS "):
            lines.append((sha, subject))
    return lines


def name_of(key):
    config, screen = key.split("/")
    device = DEVICES.get(config.split(".")[0], config.split(".")[0])
    words = screen.replace("-", " ")
    return words[0].upper() + words[1:], device


def linked(subject):
    return re.sub(r"#(\d+)", r'<a href="https://github.com/mkolakowski/WalletWeather/issues/\1">#\1</a>', esc(subject))


STYLE = """<style>
.ba-sum td:first-child { font-family: var(--mono); white-space: nowrap; }
.ba-count { font: 0.9rem var(--mono); color: var(--soft); }
.ba-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; align-items: start; }
.ba-pair figure { margin: 0; min-width: 0; display: flex; flex-direction: column; gap: 4px; }
.ba-pair figcaption { font: 600 0.72rem var(--mono); letter-spacing: 0.06em; color: var(--soft); }
.ba-shot { position: relative; line-height: 0; border: 1px solid var(--rule); border-radius: 8px; overflow: hidden; }
.ba-shot img { width: 100%; height: auto; display: block; }
.ba-shot i { position: absolute; border: 2px solid #ff9f0a; border-radius: 4px; box-shadow: 0 0 0 1px rgba(0,0,0,0.35); pointer-events: none; }
.ba-screen { background: var(--panel); border: 1px solid var(--rule); border-radius: 10px; padding: 14px; display: flex; flex-direction: column; gap: 10px; }
.ba-screen header { display: flex; flex-wrap: wrap; gap: 4px 12px; align-items: baseline; }
.ba-screen header span { color: var(--soft); font-size: 0.88rem; }
.ba-wide .ba-pair { grid-template-columns: 1fr; }
</style>
"""


def page(sets):
    out = [STYLE, "<main>", "<h1>The iPhone app, before and after</h1>",
           '<p class="lede">One picture of the top of every screen is taken at each TestFlight upload, on an iPhone 17 and on the iPhone Duo open on its side, '
           "in the demo with the date pinned to 15 November 2026. Each set is compared with the one before it, and the screens that differ are shown here, "
           "the earlier build on the left, with the part that changed outlined. A script writes this page from the pictures; nobody chooses what's on it.</p>"]
    shots = OUT / SLUG
    if shots.exists():
        shutil.rmtree(shots)
    pairs = list(zip(sets, sets[1:]))[::-1][:KEEP]
    if not pairs:
        out.append(f'<p>One set so far ({esc(sets[0]["label"]) if sets else "none"}). The first comparison appears with the next upload.</p>')
    else:
        out.append('<div class="scroll"><table class="ba-sum"><thead><tr><th>Build</th><th>Changed</th><th>The same</th><th>New</th><th>What went in</th></tr></thead><tbody>')
        results = []
        for before, after in pairs:
            result = compare(before, after)
            went = what_went_in(before, after)
            results.append((before, after, result, went))
            out.append(f'<tr><td><a href="#b{after["build"]}">{esc(before["version"])} → {esc(after["version"])}</a></td><td>{len(result["changed"])}</td>'
                       f'<td>{len(result["same"])}</td><td>{len(result["added"])}</td><td>{"; ".join(linked(s) for _, s in went) or "nothing under apps/ios"}</td></tr>')
        out.append("</tbody></table></div>")
        for before, after, result, went in results:
            out.append(f'<h2 id="b{after["build"]}">{esc(before["version"])} → {esc(after["version"])}</h2>')
            out.append(f'<p class="ba-count">build {before["build"]} ({esc(before["commit"])}) → build {after["build"]} ({esc(after["commit"])}) · '
                       f'{len(result["changed"])} of {len(result["verdicts"])} pictures changed</p>')
            if went:
                out.append("<ul>" + "".join(f"<li>{linked(subject)}</li>" for _, subject in went) + "</ul>")
            if not result["changed"] and not result["added"]:
                out.append("<p>No screen the walk visits looks different. If something did change, it's on a screen or in a state the walk doesn't open yet: "
                           "add it to <code>apps/ios/UITests/Screens.swift</code>.</p>")
            for verdict in result["changed"]:
                title, device = name_of(verdict["name"])
                config, screen = verdict["name"].split("/")
                files = {}
                for side, a_set in (("before", before), ("after", after)):
                    target = shots / a_set["label"] / config / f"{screen}.jpg"
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(a_set["folder"] / config / f"{screen}.jpg", target)
                    files[side] = f'{SLUG}/{a_set["label"]}/{config}/{screen}.jpg'
                boxes = "".join(f'<i style="left:{b[0] * 100:.2f}%;top:{b[1] * 100:.2f}%;width:{b[2] * 100:.2f}%;height:{b[3] * 100:.2f}%"></i>' for b in verdict["boxes"])
                wide = " ba-wide" if config.startswith("duo-open") else ""
                note = f' · {esc(verdict["note"])}' if verdict["note"] else ""
                out.append(f'<article class="ba-screen{wide}"><header><h3>{esc(title)}</h3><span>{esc(device)} · {verdict["share"] * 100:.1f}% of the picture{note}</span></header>'
                           f'<div class="ba-pair"><figure><figcaption>BEFORE · {esc(before["version"])}</figcaption><div class="ba-shot"><img loading="lazy" alt="{esc(title)} in {esc(before["version"])}" src="{files["before"]}">{boxes}</div></figure>'
                           f'<figure><figcaption>AFTER · {esc(after["version"])}</figcaption><div class="ba-shot"><img loading="lazy" alt="{esc(title)} in {esc(after["version"])}" src="{files["after"]}">{boxes}</div></figure></div></article>')
            for key in result["added"]:
                title, device = name_of(key)
                config, screen = key.split("/")
                target = shots / after["label"] / config / f"{screen}.jpg"
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(after["folder"] / config / f"{screen}.jpg", target)
                out.append(f'<article class="ba-screen"><header><h3>{esc(title)}</h3><span>{esc(device)} · new in this build</span></header>'
                           f'<div class="ba-pair"><figure><figcaption>BEFORE</figcaption><p>Not in the earlier set.</p></figure>'
                           f'<figure><figcaption>AFTER · {esc(after["version"])}</figcaption><div class="ba-shot"><img loading="lazy" alt="{esc(title)}" src="{SLUG}/{after["label"]}/{config}/{screen}.jpg"></div></figure></div></article>')
            if result["gone"]:
                out.append("<p>No longer in the walk: " + ", ".join(esc(name_of(k)[0]) for k in result["gone"]) + ".</p>")
    out.append("</main>")
    OUT.mkdir(parents=True, exist_ok=True)
    body = OUT / f"{SLUG}.body.html"
    body.write_text("\n".join(out) + "\n")
    subprocess.run([sys.executable, str(REPO / ".claude" / "skills" / "artifact-page" / "scripts" / "pages.py"), "wrap", SLUG, str(body)], check=True)
    body.unlink()
    files = sorted(str(p.relative_to(OUT)) for p in shots.rglob("*.jpg")) if shots.exists() else []
    (OUT / f"{SLUG}.files.json").write_text(json.dumps(files, indent=1) + "\n")
    print(f"ui-before-after: {len(pairs)} comparison(s), {len(files)} pictures; publish {SLUG}.html and the files listed in {SLUG}.files.json")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--check":
        sets = {s["label"]: s for s in load_sets()}
        result = compare(sets[sys.argv[2]], sets[sys.argv[3]])
        for verdict in result["changed"]:
            print(f'  differs: {verdict["name"]} ({verdict["share"] * 100:.2f}%) {verdict["boxes"][:2]} {verdict["note"]}')
        print(f'ui-before-after: {len(result["changed"])} of {len(result["verdicts"])} differ between {sys.argv[2]} and {sys.argv[3]}')
        sys.exit(1 if result["changed"] else 0)
    page(load_sets())
