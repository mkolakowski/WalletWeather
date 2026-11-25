"""Builds the review page of /ios-ui-review: one HTML file with every finding,
a picture of today beside the proposal, ready to publish as an artifact.

A review is a short Python file (start from review-template.py beside this)
that lists the findings and calls build(). Pictures of today are cut from the
run's own pictures; proposals are drawn with the helpers below, in the app's
light look, and say they're drawn. Python 3 and Swift from the system only.

    python3 <run>/review.py        writes <run>/review.html
"""
import base64
import html
import json
import pathlib
import subprocess
import tempfile

IOS = pathlib.Path(__file__).resolve().parents[4] / "apps" / "ios"
esc = html.escape


# ---- Pictures of today -------------------------------------------------

def shot(file, crop=None, caption="", height=560):
    """A picture from the run: `file` is <configuration>/<picture>.jpg. `crop` is
    (x, y, width, height) as fractions of the picture, to show only the part
    that matters."""
    return {"kind": "shot", "file": file, "crop": crop, "caption": caption, "height": height}


def mock(body, caption="", drawn="Drawn"):
    """A drawing made with phone(), card() and the rest."""
    return {"kind": "mock", "html": body, "caption": caption, "drawn": drawn}


def note(text):
    """A slot with no picture: say why (nothing exists today, a script can't reach it)."""
    return {"kind": "note", "text": text}


# ---- Drawing the app ---------------------------------------------------

def phone(*parts, title=None, bar=None, wide=False, sheet=False, tabs=None):
    """A screen. `title` is the large title; `bar` an inline bar as (left, title, right);
    `tabs` the selected tab's name, to draw the bar along the bottom."""
    head = ""
    if bar:
        left, middle, right = bar
        head = f'<div class="m-bar"><span>{left}</span><b>{esc(middle)}</b><span>{right}</span></div>'
    elif title:
        head = f'<div class="m-title">{esc(title)}</div>'
    foot = ""
    if tabs:
        names = ["Dashboard", "Forecast", "Bills & income", "Settings", "Search"]
        foot = '<div class="m-tabs">' + "".join(f'<span class="{"on" if n == tabs else ""}">{esc(n)}</span>' for n in names) + "</div>"
    classes = "m-phone" + (" m-wide" if wide else "") + (" m-sheet" if sheet else "")
    return f'<div class="{classes}">{head}<div class="m-body">{"".join(parts)}</div>{foot}</div>'


def card(*parts, plain=False):
    return f'<div class="m-card{" m-plain" if plain else ""}">{"".join(parts)}</div>'


def row(label, value="", sub=None, chevron=False, tint=False, red=False, check=False, mark=None):
    """A list row. `mark` puts a highlight ring round it: the part the finding is about."""
    classes = "m-row" + (" m-tint" if tint else "") + (" m-red" if red else "") + (" m-mark" if mark else "")
    below = f'<small>{esc(sub)}</small>' if sub else ""
    end = esc(value) + (' <i class="m-chev">›</i>' if chevron else "") + (' <i class="m-check">✓</i>' if check else "")
    return f'<div class="{classes}"><span>{esc(label)}{below}</span><span class="m-val">{end}</span></div>'


def cap(text):
    return f'<div class="m-cap">{esc(text)}</div>'


def big(text, red=False):
    return f'<div class="m-big{" m-red" if red else ""}">{esc(text)}</div>'


def text(body, small=False, grey=False, mark=False):
    classes = "m-text" + (" m-small" if small else "") + (" m-grey" if grey else "") + (" m-mark" if mark else "")
    return f'<div class="{classes}">{esc(body)}</div>'


def btn(label, kind="glass", mark=False):
    """kind: glass, prominent, plain or danger."""
    return f'<span class="m-btn m-{kind}{" m-mark" if mark else ""}">{esc(label)}</span>'


def chips(names, on=None):
    return '<div class="m-chips">' + "".join(f'<span class="{"on" if n == on else ""}">{esc(n)}</span>' for n in names) + "</div>"


def seg(names, on):
    return '<div class="m-seg">' + "".join(f'<span class="{"on" if n == on else ""}">{esc(n)}</span>' for n in names) + "</div>"


def banner(title, body, action=None):
    button = f'<div>{btn(action)}</div>' if action else ""
    return f'<div class="m-banner"><b>⚠ {esc(title)}</b><small>{esc(body)}</small>{button}</div>'


def line(name, amount, sub="", red=True):
    return (f'<div class="m-line"><span><b>{esc(name)}</b><small>{esc(sub)}</small></span>'
            f'<span class="m-amt{" m-red" if red else " m-green"}">{esc(amount)}</span></div>')


def columns(*parts):
    return '<div class="m-cols">' + "".join(f"<div>{p}</div>" for p in parts) + "</div>"


def raw(markup):
    return markup


# ---- The page ----------------------------------------------------------

PAGE_CSS = """
/* A working paper: one column of findings, each a pair of pictures. */
:root { --paper:#f6f7f9; --ink:#15181d; --soft:#5b6472; --rule:#d9dde4; --panel:#ffffff; --accent:#0b57d0;
  --bug:#b3261e; --slip:#9a5b00; --idea:#1a6b3c; --mark:#ff9f0a;
  --serif: "Source Serif 4", Georgia, serif; --sans: "Inter Tight", system-ui, -apple-system, "Segoe UI", sans-serif;
  --mono: ui-monospace, "SF Mono", Menlo, monospace; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#111418; --ink:#e8eaee; --soft:#9aa3b0; --rule:#2b313a;
  --panel:#191d23; --accent:#8ab4ff; --bug:#ff8a80; --slip:#ffb74d; --idea:#7bd49c; color-scheme: dark } }
:root[data-theme="dark"] { --paper:#111418; --ink:#e8eaee; --soft:#9aa3b0; --rule:#2b313a; --panel:#191d23; --accent:#8ab4ff;
  --bug:#ff8a80; --slip:#ffb74d; --idea:#7bd49c; color-scheme: dark }
body { background: var(--paper); color: var(--ink); font: 16px/1.55 var(--sans); padding-block: 28px 64px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
main { max-width: 920px; margin: 0 auto; display: flex; flex-direction: column; gap: 28px; }
h1 { font: 600 2rem/1.15 var(--serif); margin: 0; text-wrap: balance; }
h2 { font: 600 1.35rem/1.2 var(--serif); margin: 18px 0 0; padding-top: 18px; border-top: 2px solid var(--ink); }
h3 { font: 600 1.08rem/1.3 var(--sans); margin: 0; text-wrap: balance; }
p { margin: 0; max-width: 68ch; }
a { color: var(--accent); }
.lede { color: var(--soft); max-width: 68ch; }
.facts { display: flex; flex-wrap: wrap; gap: 6px 22px; font: 0.85rem var(--mono); color: var(--soft); }
table { border-collapse: collapse; width: 100%; font-size: 0.92rem; }
.scroll { overflow-x: auto; }
th, td { text-align: left; padding: 7px 10px 7px 0; border-bottom: 1px solid var(--rule); vertical-align: top; }
th { font-weight: 600; color: var(--soft); font-size: 0.8rem; }
td:first-child, th:first-child { white-space: nowrap; font-family: var(--mono); font-size: 0.85rem; }
.tag { font: 600 0.72rem var(--mono); padding: 2px 7px; border-radius: 4px; border: 1px solid currentColor; white-space: nowrap; }
.bug { color: var(--bug); } .slip { color: var(--slip); } .idea { color: var(--idea); }
"""

# What a finding is drawn with; the same whether the review is a page by itself or inside the WalletWeather artifact.
PARTS_CSS = """
.tag { font: 600 0.72rem var(--mono); padding: 2px 7px; border-radius: 4px; border: 1px solid currentColor; white-space: nowrap; }
.bug { color: var(--bug); } .slip { color: var(--slip); } .idea { color: var(--idea); }
.facts { display: flex; flex-wrap: wrap; gap: 6px 22px; font: 0.85rem var(--mono); color: var(--soft); }
td:first-child { white-space: nowrap; font-family: var(--mono); font-size: 0.85rem; }
article { background: var(--panel); border: 1px solid var(--rule); border-radius: 10px; padding: 18px; display: flex; flex-direction: column; gap: 12px; }
article header { display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: baseline; }
article header .id { font: 600 0.9rem var(--mono); }
.where, .proof { font-size: 0.88rem; color: var(--soft); }
.proof code, .where code, p code, li code { font: 0.85em var(--mono); background: color-mix(in srgb, var(--ink) 8%, transparent); padding: 1px 4px; border-radius: 3px; }
.pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; }
figure { margin: 0; display: flex; flex-direction: column; gap: 6px; min-width: 0; }
figure .label { font: 600 0.72rem var(--mono); letter-spacing: 0.06em; color: var(--soft); }
figure .frame { background: color-mix(in srgb, var(--ink) 6%, transparent); border-radius: 8px; padding: 10px; display: flex; justify-content: center; overflow-x: auto; }
figure img { max-width: 100%; height: auto; max-height: 560px; border-radius: 6px; display: block; }
figure figcaption { font-size: 0.85rem; color: var(--soft); }
figure .none { padding: 26px 14px; color: var(--soft); font-size: 0.9rem; text-align: center; }
.fix { border-left: 3px solid var(--accent); padding-left: 12px; }
.fix b { font-weight: 600; }
ul { margin: 0; padding-left: 20px; } li { margin: 2px 0; max-width: 66ch; }
.opts { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; }
.opts > div { border: 1px solid var(--rule); border-radius: 8px; padding: 10px; font-size: 0.9rem; }
.opts b { display: block; }

/* The app, drawn. One fixed look (the app's Light), whatever the page's theme: it's a picture of a screen. */
.m-phone { width: 280px; flex: none; border-radius: 26px; padding: 14px 12px 12px; color: #111; font: 13px/1.35 -apple-system, "SF Pro Text", system-ui, sans-serif;
  background: linear-gradient(#bfd3f0, #e9edf6 60%); border: 1px solid #aab4c4; display: flex; flex-direction: column; gap: 8px; min-height: 180px; }
.m-phone.m-wide { width: 520px; }
.m-phone.m-sheet { background: #eef1f7; border-radius: 22px 22px 8px 8px; }
.m-title { font: 700 22px/1.2 -apple-system, system-ui, sans-serif; padding: 6px 4px 2px; }
.m-bar { display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 2px 0 4px; }
.m-bar b { font-weight: 600; }
.m-body { display: flex; flex-direction: column; gap: 8px; }
.m-card { background: rgba(255,255,255,0.82); border-radius: 16px; padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; box-shadow: 0 1px 2px rgba(20,30,60,0.12); }
.m-card.m-plain { background: none; box-shadow: none; padding: 0 4px; }
.m-row { display: flex; justify-content: space-between; align-items: center; gap: 10px; min-height: 30px; border-bottom: 1px solid rgba(60,70,90,0.12); padding: 2px 0; }
.m-row:last-child { border-bottom: 0; }
.m-row small, .m-line small { display: block; color: #6b7280; font-size: 11px; }
.m-val { color: #6b7280; text-align: right; }
.m-tint, .m-tint .m-val { color: #0a5fe0; }
.m-red, .m-red .m-val { color: #c0283c; }
.m-green { color: #188046; }
.m-chev { font-style: normal; color: #a0a8b6; }
.m-check { font-style: normal; color: #0a5fe0; }
.m-cap { color: #6b7280; font-size: 11px; }
.m-big { font: 700 24px/1.15 -apple-system, system-ui, sans-serif; font-variant-numeric: tabular-nums; }
.m-text { font-size: 13px; } .m-small { font-size: 11px; } .m-grey { color: #6b7280; }
.m-btn { display: inline-block; padding: 5px 12px; border-radius: 999px; font-weight: 600; font-size: 12.5px; }
.m-glass { background: rgba(255,255,255,0.75); color: #0a5fe0; box-shadow: 0 0 0 1px rgba(60,70,90,0.15); }
.m-prominent { background: #0a5fe0; color: #fff; }
.m-plain.m-btn { color: #0a5fe0; padding-left: 0; }
.m-danger { color: #c0283c; background: rgba(255,255,255,0.75); box-shadow: 0 0 0 1px rgba(60,70,90,0.15); }
.m-chips, .m-seg { display: flex; gap: 6px; flex-wrap: wrap; }
.m-chips span { background: rgba(120,130,150,0.22); border-radius: 999px; padding: 3px 10px; font-weight: 600; font-size: 12px; }
.m-chips span.on { background: #0a5fe0; color: #fff; }
.m-seg { background: rgba(120,130,150,0.2); border-radius: 999px; padding: 2px; gap: 0; }
.m-seg span { flex: 1; text-align: center; padding: 3px 6px; border-radius: 999px; font-size: 12px; font-weight: 600; }
.m-seg span.on { background: #fff; }
.m-banner { background: rgba(255,255,255,0.9); border-radius: 14px; padding: 8px 10px; display: flex; flex-direction: column; gap: 4px; }
.m-banner b { color: #111; } .m-banner small { color: #6b7280; font-size: 11px; }
.m-line { display: flex; justify-content: space-between; gap: 8px; }
.m-amt { font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
.m-cols { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.m-tabs { display: flex; justify-content: space-between; background: rgba(255,255,255,0.7); border-radius: 999px; padding: 6px 10px; font-size: 9.5px; color: #333; margin-top: auto; }
.m-tabs .on { color: #0a5fe0; font-weight: 700; }
.m-mark { outline: 2px solid #ff9f0a; outline-offset: 2px; border-radius: 6px; }
"""

# Inside the artifact its own style supplies the page; these name its colours the way the parts expect.
ALIASES = ":root { --bug: var(--bad); --slip: var(--warn); --idea: var(--good); --mark: #ff9f0a; }"
CSS = PAGE_CSS + PARTS_CSS



def _pictures(findings, run):
    """Cuts every shot to size in one go, and gives each its bytes."""
    work = pathlib.Path(tempfile.mkdtemp(prefix="ww-review-"))
    sheets, wanted = [], []
    for finding in findings:
        for side in ("today", "proposed"):
            figures = finding.get(side) or []
            for figure in figures if isinstance(figures, list) else [figures]:
                if figure["kind"] != "shot":
                    continue
                out = work / f"{len(wanted)}.jpg"
                cell = {"path": str(run / figure["file"]), "label": ""}
                if figure.get("crop"):
                    cell["crop"] = list(figure["crop"])
                # ui-sheet draws a 14-point border and a caption strip; ask for one bare picture.
                sheets.append({"out": str(out), "height": figure["height"], "rows": [[cell]], "bare": True})
                wanted.append((figure, out))
    if sheets:
        manifest = work / "manifest.json"
        manifest.write_text(json.dumps(sheets))
        subprocess.run(["swift", str(IOS / "Scripts" / "ui-sheet.swift"), str(manifest)], check=True, capture_output=True)
    for figure, out in wanted:
        figure["data"] = base64.b64encode(out.read_bytes()).decode() if out.exists() else None


def _figure(label, figures):
    figures = figures if isinstance(figures, list) else [figures]
    inner, captions = [], []
    for figure in figures:
        if figure["kind"] == "shot":
            inner.append(f'<img alt="" src="data:image/jpeg;base64,{figure["data"]}">' if figure.get("data")
                         else f'<div class="none">Picture missing: {esc(figure["file"])}</div>')
        elif figure["kind"] == "mock":
            inner.append(figure["html"])
        else:
            inner.append(f'<div class="none">{esc(figure["text"])}</div>')
        if figure.get("caption"):
            captions.append(esc(figure["caption"]))
    kinds = {f["kind"] for f in figures}
    suffix = " · drawn" if "mock" in kinds else (" · from the simulator" if "shot" in kinds else "")
    caption = f'<figcaption>{" ".join(captions)}</figcaption>' if captions else ""
    return f'<figure><span class="label">{label.upper()}{suffix}</span><div class="frame">{"".join(inner)}</div>{caption}</figure>'


def build(review, out, fragment=False):
    """`review`: title, lede, facts (a list of short strings), groups ([(id, title, blurb)]),
    findings (each: id, group, kind (bug, slip or idea), title, where, what, proof, fix, size,
    today, proposed, and optionally options [(name, what it means)]), and closing (HTML)."""
    run = pathlib.Path(review["run"])
    _pictures(review["findings"], run)
    kinds = {"bug": "Bug", "slip": "Inconsistency", "idea": "Design"}
    if fragment:
        # A page of the WalletWeather artifact: its content only, for pages.py to wrap.
        parts = [f"<style>{ALIASES}{PARTS_CSS}</style>", "<main>"]
    else:
        parts = [f'<title>{esc(review["title"])}</title>', '<meta name="claude:viewport-fit-sides" content="cover">',
                 '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter+Tight:wght@400;600&family=Source+Serif+4:opsz,wght@8..60,600&display=swap">',
                 f"<style>{CSS}</style>", "<main>"]
    parts += [f'<h1>{esc(review["title"])}</h1>', f'<p class="lede">{review["lede"]}</p>',
              '<div class="facts">' + "".join(f"<span>{esc(fact)}</span>" for fact in review["facts"]) + "</div>"]
    parts.append('<div class="scroll"><table><thead><tr><th></th><th>Finding</th><th>Kind</th><th>Size of the fix</th></tr></thead><tbody>')
    for finding in review["findings"]:
        parts.append(f'<tr><td><a href="#{finding["id"].lower()}">{finding["id"]}</a></td><td>{esc(finding["title"])}</td>'
                     f'<td><span class="tag {finding["kind"]}">{kinds[finding["kind"]]}</span></td><td>{esc(finding.get("size", ""))}</td></tr>')
    parts.append("</tbody></table></div>")
    for group, title, blurb in review["groups"]:
        members = [f for f in review["findings"] if f["group"] == group]
        if not members:
            continue
        parts.append(f'<h2 id="{group}">{esc(title)}</h2><p class="lede">{blurb}</p>')
        for finding in members:
            options = ""
            if finding.get("options"):
                options = '<div class="opts">' + "".join(f"<div><b>{esc(name)}</b>{esc(meaning)}</div>" for name, meaning in finding["options"]) + "</div>"
            parts.append(
                f'<article id="{finding["id"].lower()}"><header><span class="id">{finding["id"]}</span>'
                f'<h3>{esc(finding["title"])}</h3><span class="tag {finding["kind"]}">{kinds[finding["kind"]]}</span></header>'
                f'<div class="where">{finding["where"]}</div><p>{finding["what"]}</p>'
                f'<div class="pair">{_figure("Today", finding["today"])}{_figure("Proposed", finding["proposed"])}</div>'
                f'<p class="fix"><b>The fix.</b> {finding["fix"]}</p>{options}'
                f'<div class="proof">{finding["proof"]}</div></article>')
    parts.append(review.get("closing", ""))
    parts.append("</main>")
    pathlib.Path(out).write_text("\n".join(parts))
    size = pathlib.Path(out).stat().st_size / 1e6
    print(f"review: {len(review['findings'])} findings, {size:.1f} MB, {out}")
