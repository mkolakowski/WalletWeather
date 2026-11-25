#!/usr/bin/env python3
"""Writes the WalletWeather artifact's pages that come straight from the repo (#353).

    repo_pages.py all          every page below
    repo_pages.py changelog    from CHANGELOG.md
    repo_pages.py roadmap      from ROADMAP.md
    repo_pages.py plans        from the Status table of each file in Plans/, and the phase issues' states
    repo_pages.py decisions    from docs/dev/decisions/
    repo_pages.py waiting      from the #338 checklist, each plan's Open questions and the open issues

Each page is written from the files as they stand (and, for plans and
waiting, from GitHub's issues as they stand) and from nothing else: no clock
in the text, no order that depends on the disk. The same commit gives the
same page. Each says which commit it was written from. Its entry in
pages.json loses its "stub" mark and takes the date its source last changed.
Publishing is Claude's step (the artifact-page skill).
"""
import html
import json
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pages as builder  # noqa: E402

REPO = builder.REPO
OUT = builder.OUT
GH = "https://github.com/mkolakowski/WalletWeather"
RELEASES_IN_FULL = 12
esc = html.escape


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True).stdout.strip()


def gh_json(*args):
    out = subprocess.run(["gh", *args, "--repo", "mkolakowski/WalletWeather"], capture_output=True, text=True, cwd=REPO)
    return json.loads(out.stdout) if out.returncode == 0 and out.stdout.strip() else None


# ---- A reader for the Markdown these files use --------------------------

def inline(text, base=""):
    """Bold, italics, code, strike-through, links and #123, on escaped text."""
    codes = []

    def keep(match):
        codes.append(f"<code>{esc(match.group(1))}</code>")
        return f"\x00{len(codes) - 1}\x00"
    text = re.sub(r"`([^`]+)`", keep, text)
    text = esc(text, quote=False)

    def link(match):
        label, url = match.group(1), match.group(2)
        if not re.match(r"[a-z]+:|#", url):
            url = f"{GH}/blob/main/{(pathlib.PurePosixPath(base) / url).as_posix()}" if base else f"{GH}/blob/main/{url}"
            url = re.sub(r"/[^/]+/\.\./", "/", url)
            url = re.sub(r"/[^/]+/\.\./", "/", url)
        return f'<a href="{esc(url)}">{label}</a>'
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text, flags=re.S)
    text = re.sub(r"~~(.+?)~~", r"<s>\1</s>", text, flags=re.S)
    text = re.sub(r"(?<![\w*])\*([^*\n]+?)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(r'(?<![\w&/">#])#(\d{1,4})\b', rf'<a href="{GH}/issues/\1">#\1</a>', text)
    return re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)


def markdown(text, base="", shift=0):
    """Headings, paragraphs, lists (one level of nesting), tables, quotes and rules.
    `shift` pushes headings down, so a file's `##` can sit under the page's own."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    lines = text.split("\n")
    out, i = [], 0

    def close_list(stack):
        while stack:
            out.append(f"</li></{stack.pop()}>")

    lists = []
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        item = re.match(r"^(\s*)([-*]|\d+\.) +(.*)$", line)
        if item:
            depth = 0 if len(item.group(1)) < 2 else 1
            tag = "ol" if item.group(2)[0].isdigit() else "ul"
            body = [item.group(3)]
            i += 1
            while i < len(lines) and lines[i].strip() and not re.match(r"^\s*([-*]|\d+\.) +", lines[i]) and not lines[i].startswith(("#", "|")):
                body.append(lines[i].strip())
                i += 1
            content = " ".join(body)
            box = re.match(r"^\[([ xX])\] +(.*)$", content)
            if box:
                content = ("☑ " if box.group(1) != " " else "☐ ") + box.group(2)
            if not lists:
                depth = 0
            while len(lists) > depth + 1:
                out.append(f"</li></{lists.pop()}>")
            if len(lists) == depth + 1:
                out.append("</li>")
            else:
                out.append(f"<{tag}>")
                lists.append(tag)
            out.append(f"<li>{inline(content, base)}")
            continue
        close_list(lists)
        heading = re.match(r"^(#{1,5}) +(.*)$", stripped)
        if heading:
            level = min(6, len(heading.group(1)) + shift)
            out.append(f"<h{level}>{inline(heading.group(2), base)}</h{level}>")
            i += 1
        elif stripped.startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            head = [c.strip() for c in stripped.strip("|").split("|")]
            rows = []
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            out.append('<div class="scroll"><table><thead><tr>' + "".join(f"<th>{inline(c, base)}</th>" for c in head) + "</tr></thead><tbody>"
                       + "".join("<tr>" + "".join(f"<td>{inline(c, base)}</td>" for c in row) + "</tr>" for row in rows) + "</tbody></table></div>")
        elif stripped.startswith(">"):
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip().lstrip("> "))
                i += 1
            out.append(f"<blockquote>{inline(' '.join(quote), base)}</blockquote>")
        elif re.match(r"^(-{3,}|={3,}|\*{3,})$", stripped):
            out.append("<hr>")
            i += 1
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r"^(#{1,5} |\s*([-*]|\d+\.) +|\||>)", lines[i]):
                para.append(lines[i].strip())
                i += 1
            out.append(f"<p>{inline(' '.join(para), base)}</p>")
    close_list(lists)
    return "\n".join(part for part in out if part is not None)


STYLE = """<style>
.rp-from { font: 0.8rem var(--mono); color: var(--soft); }
.rp main h3, main h3 { margin-top: 10px; }
main h4 { font: 600 0.9rem var(--sans); margin: 8px 0 0; color: var(--soft); }
main s { color: var(--soft); }
main blockquote { margin: 0; padding-left: 12px; border-left: 3px solid var(--rule); color: var(--soft); max-width: 66ch; }
main hr { border: 0; border-top: 1px solid var(--rule); width: 100%; }
.rp-card { background: var(--panel); box-shadow: var(--shadow); border-radius: 22px; padding: 18px; display: flex; flex-direction: column; gap: 10px; }
.rp-card header { display: flex; flex-wrap: wrap; gap: 4px 12px; align-items: baseline; }
.rp-card header span { font: 0.82rem var(--mono); color: var(--soft); }
.rp-open { color: var(--warn); } .rp-done { color: var(--good); }
.rp-facts { display: flex; flex-wrap: wrap; gap: 6px 22px; font: 0.88rem var(--mono); color: var(--soft); }
.rp-older { columns: 3 150px; font: 0.85rem var(--mono); }
</style>
"""


def finish(slug, title, lede, body, sources):
    """Wraps the page, takes the stub mark off its entry and dates it by its sources."""
    commit = git("rev-parse", "--short", "HEAD")
    changed = max(git("log", "-1", "--format=%cs", "--", *sources) or "0", "0")
    listing = builder.SKILL / "pages.json"
    data = json.loads(listing.read_text())
    for page in data["pages"]:
        if page["slug"] == slug:
            page.pop("stub", None)
            page.pop("source", None)
            page["updated"] = changed
    listing.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    names = ", ".join(f"<code>{esc(s)}</code>" for s in sources)
    content = f'{STYLE}<main>\n<h1>{esc(title)}</h1>\n<p class="lede">{lede}</p>\n{body}\n<p class="rp-from">Written from {names} at {commit}.</p>\n</main>\n'
    OUT.mkdir(parents=True, exist_ok=True)
    temp = OUT / f"{slug}.body.html"
    temp.write_text(content)
    builder.wrap(slug, temp)
    temp.unlink()


def changelog():
    text = (REPO / "CHANGELOG.md").read_text()
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    sections = re.split(r"^## ", text, flags=re.M)[1:]
    parts, older = [], []
    for number, section in enumerate(sections):
        heading, _, rest = section.partition("\n")
        name = re.match(r"\[([^\]]+)\](?:\s*[—-]\s*(.*))?", heading)
        if not name:
            continue
        label, date = name.group(1), (name.group(2) or "").strip()
        rest = re.sub(r"^\[[^\]]+\]:\s+\S+\s*$", "", rest, flags=re.M)   # the link footer
        if number <= RELEASES_IN_FULL:
            anchor = "unreleased" if label == "Unreleased" else "v" + label.replace(".", "-")
            title = "Since the last release" if label == "Unreleased" else f"{label} · {date}"
            parts.append(f'<h2 id="{anchor}">{esc(title)}</h2>\n{markdown(rest, shift=0)}')
        else:
            older.append(f"<li>{esc(label)} · {esc(date)}</li>")
    if older:
        parts.append(f'<h2 id="older">Older releases</h2><p>{len(older)} more, in <a href="{GH}/blob/main/CHANGELOG.md">CHANGELOG.md</a>.</p><ul class="rp-older">' + "".join(older) + "</ul>")
    finish("changelog", "Changelog", f"What each release changed, newest first, with what's landed since the last one at the top. The latest {RELEASES_IN_FULL} releases are here in full.",
           "\n".join(parts), ["CHANGELOG.md"])


def roadmap():
    text = (REPO / "ROADMAP.md").read_text()
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    body = text.split("\n", 1)[1] if text.startswith("# ") else text
    items = re.findall(r"^### (.*)$", body, flags=re.M)
    done = [i for i in items if i.startswith("~~")]
    facts = f'<div class="rp-facts"><span>{len(items)} items</span><span>{len(done)} finished</span><span>{len(items) - len(done)} open</span></div>'
    opened = "".join(f"<li>{inline(i)}</li>" for i in items if not i.startswith("~~"))
    finish("roadmap", "Roadmap", "The ledger of ideas. Finished items are struck through and keep their numbers; nothing is deleted.",
           f'{facts}\n<h2 id="open">Still open</h2><ul>{opened}</ul>\n{markdown(body, shift=0)}', ["ROADMAP.md"])


def plans():
    issues = gh_json("issue", "list", "--state", "all", "--label", "plan", "--limit", "500", "--json", "number,state,title") or []
    state = {i["number"]: i["state"] for i in issues}
    cards = []
    for path in sorted((REPO / "Plans").glob("*.md")):
        text = path.read_text()
        title = re.search(r"^# (.*)$", text, flags=re.M)
        tracker = re.search(r"^Tracking issue: #(\d+)", text, flags=re.M)
        status = re.search(r"^## Status\s*\n(.*?)(?=^## |\Z)", text, flags=re.M | re.S)
        table = re.search(r"((?:^\|.*\n)+)", status.group(1), flags=re.M) if status else None
        numbers = [int(n) for n in re.findall(r"#(\d+)", table.group(1))] if table else []
        phases = [n for n in dict.fromkeys(numbers) if n in state]
        open_phases = [n for n in phases if state[n] == "OPEN"]
        tracker_open = tracker and state.get(int(tracker.group(1))) == "OPEN"
        mark = (f'<span class="rp-open">{len(open_phases)} of {len(phases)} phase issues open</span>' if open_phases
                else f'<span class="rp-done">all {len(phases)} phase issues closed</span>' if phases else "<span>no phase issues</span>")
        link = f' · <a href="{GH}/issues/{tracker.group(1)}">#{tracker.group(1)}</a>' if tracker else ""
        cards.append((0 if open_phases or tracker_open else 1, path.name,
                      f'<article class="rp-card"><header><h3>{inline(title.group(1) if title else path.stem)}</h3>{mark}'
                      f'<span><a href="{GH}/blob/main/Plans/{path.name}">{path.name}</a>{link}</span></header>'
                      f'{markdown(table.group(1)) if table else "<p>No Status table.</p>"}</article>'))
    cards.sort()
    going = [c[2] for c in cards if c[0] == 0]
    over = [c[2] for c in cards if c[0] == 1]
    body = f'<div class="rp-facts"><span>{len(cards)} plans</span><span>{len(going)} with something open</span><span>{len(over)} finished</span></div>'
    body += '<h2 id="open">With something open</h2>' + "\n".join(going) + '<h2 id="finished">Finished</h2>' + "\n".join(over)
    finish("plans", "Plans", "Every plan and where each of its phases stands. The table is each plan's own Status table; the count beside its name is how many of its phase issues are still open on GitHub.",
           body, ["Plans"])


def decisions():
    pages = []
    for path in sorted((REPO / "docs" / "dev" / "decisions").glob("*.md")):
        text = path.read_text()
        title = re.search(r"^# (.*)$", text, flags=re.M)
        heads = re.findall(r"^## (.*)$", text, flags=re.M)
        dates = re.findall(r"\b(20\d\d-\d\d-\d\d)\b", "\n".join(heads) + "\n" + text[:600])
        latest = max(dates) if dates else ""
        items = "".join(f"<li>{inline(h)}</li>" for h in heads)
        pages.append((latest, path.name, f'<article class="rp-card"><header><h3>{inline(title.group(1) if title else path.stem)}</h3>'
                      f'<span><a href="{GH}/blob/main/docs/dev/decisions/{path.name}">{path.name}</a></span></header><ul>{items}</ul></article>'))
    pages.sort(key=lambda p: (p[0], p[1]), reverse=True)
    total = sum(p[2].count("<li>") for p in pages)
    body = f'<div class="rp-facts"><span>{len(pages)} subjects</span><span>{total} dated decisions</span></div>' + "\n".join(p[2] for p in pages)
    finish("decisions", "Decisions", "What's been decided and when, by subject, the most recently touched first. Each line is a heading on that subject's page, where the choice and the options turned down are written out.",
           body, ["docs/dev/decisions"])


def waiting():
    parts = []
    checklist = gh_json("issue", "view", "338", "--json", "body,state")
    if checklist and checklist["state"] == "OPEN":
        open_lines, section = [], ""
        for line in checklist["body"].split("\n"):
            if line.startswith("## "):
                section = line[3:].strip()
            elif re.match(r"^\s*- \[ \] ", line):
                open_lines.append((section, re.sub(r"^\s*- \[ \] ", "", line)))
        if open_lines:
            parts.append(f'<h2 id="tries">Tries waiting on you</h2><p>Unticked lines of the checklist, <a href="{GH}/issues/338">#338</a>.</p><ul>'
                         + "".join(f"<li>{inline(text)} <span class=\"rp-from\">({esc(section)})</span></li>" for section, text in open_lines) + "</ul>")
    questions = []
    for path in sorted((REPO / "Plans").glob("*.md")):
        found = re.search(r"^## Open questions\s*\n(.*?)(?=^## |\Z)", path.read_text(), flags=re.M | re.S)
        if found and found.group(1).strip() and not found.group(1).strip().lower().startswith("none"):
            questions.append(f'<article class="rp-card"><header><h3><a href="{GH}/blob/main/Plans/{path.name}">{path.name}</a></h3></header>{markdown(found.group(1))}</article>')
    parts.append('<h2 id="questions">Questions left open in a plan</h2>' + ("\n".join(questions) if questions else "<p>None: every plan's Open questions says so.</p>"))
    issues = gh_json("issue", "list", "--state", "open", "--limit", "200", "--json", "number,title,labels,updatedAt") or []
    rows = {"Plan phases": [], "Plans": [], "Everything else": []}
    for issue in sorted(issues, key=lambda i: -i["number"]):
        labels = [label["name"] for label in issue["labels"]]
        group = "Plan phases" if "plan-phase" in labels else "Plans" if "plan-tracker" in labels else "Everything else"
        shown = ", ".join(label for label in labels if label not in ("plan", "plan-phase", "plan-tracker"))
        rows[group].append(f'<tr><td><a href="{GH}/issues/{issue["number"]}">#{issue["number"]}</a></td><td>{esc(issue["title"])}</td><td>{esc(shown)}</td></tr>')
    parts.append(f'<h2 id="issues">Open issues ({len(issues)})</h2>')
    for group in ("Everything else", "Plan phases", "Plans"):
        if rows[group]:
            parts.append(f'<h3>{group}</h3><div class="scroll"><table><thead><tr><th></th><th>Issue</th><th>Labels</th></tr></thead><tbody>' + "".join(rows[group]) + "</tbody></table></div>")
    finish("waiting-on-you", "Waiting on you", "What only you can do, and what's still open: tries to make on the phone or your instance, questions a plan can't go on without, and the open issues.",
           "\n".join(parts), ["Plans"])
    # This page follows GitHub, not a file: it's as fresh as the day it was built.
    listing = builder.SKILL / "pages.json"
    data = json.loads(listing.read_text())
    today = subprocess.run(["date", "+%Y-%m-%d"], capture_output=True, text=True, env={"TZ": "America/New_York", "PATH": "/bin:/usr/bin"}).stdout.strip()
    for page in data["pages"]:
        if page["slug"] == "waiting-on-you":
            page["updated"] = today
    listing.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


PAGES = {"changelog": changelog, "roadmap": roadmap, "plans": plans, "decisions": decisions, "waiting": waiting}

if __name__ == "__main__":
    wanted = sys.argv[1:] or ["all"]
    if wanted == ["all"]:
        wanted = list(PAGES)
    for name in wanted:
        if name not in PAGES:
            sys.exit(__doc__)
        PAGES[name]()
    builder.home()
