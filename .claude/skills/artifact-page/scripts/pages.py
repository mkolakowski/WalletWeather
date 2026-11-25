#!/usr/bin/env python3
"""Builds the files of the one WalletWeather artifact (#351).

    pages.py home                      writes Home (index.html) and pages.css from pages.json
    pages.py wrap <slug> <body.html>   wraps a page's content in the shared header, as <slug>.html
    pages.py list                      prints the pages

Home is also the frame the other pages show in: the bar at the top lists every
page, a link is #slug, and Home's script swaps that page's <main> and its own
styles into view. So a page is plain HTML and CSS: a <script> in it won't run
there. Each page is also a whole document, for opening by itself.

Everything lands in apps/ios/build/artifact/ (not tracked), which is the folder
published: index.html is the page, the rest go as its files. pages.json, beside
this script's skill, is the list of pages: Home is written from it and from
nothing else, so the same list always gives the same Home.
"""
import html
import json
import pathlib
import sys

SKILL = pathlib.Path(__file__).resolve().parents[1]
REPO = SKILL.parents[2]
OUT = REPO / "apps" / "ios" / "build" / "artifact"
esc = html.escape

CSS = """/* WalletWeather's pages: a quiet notebook. One column, the app's own blue for what can be tapped. */
:root { --paper:#f4f6f8; --ink:#14181d; --soft:#58626e; --rule:#d6dbe1; --panel:#ffffff; --accent:#0b5fd9; --good:#1b7a45; --bad:#b3261e; --warn:#9a5b00;
  --sans:"IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif; --mono:"IBM Plex Mono", ui-monospace, Menlo, monospace; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#101317; --ink:#e6e9ed; --soft:#98a2ae; --rule:#2a3038; --panel:#181c21; --accent:#8ab6ff; --good:#6fd19a; --bad:#ff8a80; --warn:#f0b25a; color-scheme: dark } }
:root[data-theme="dark"] { --paper:#101317; --ink:#e6e9ed; --soft:#98a2ae; --rule:#2a3038; --panel:#181c21; --accent:#8ab6ff; --good:#6fd19a; --bad:#ff8a80; --warn:#f0b25a; color-scheme: dark }
html { color-scheme: light dark; }
body { margin: 0; background: var(--paper); color: var(--ink); font: 16px/1.55 var(--sans); padding-block: 20px 64px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
img { max-width: 100%; } [hidden] { display: none !important; }
main, .ww-top { max-width: 920px; margin: 0 auto; }
main { display: flex; flex-direction: column; gap: 22px; }
.ww-top { display: flex; gap: 6px; align-items: center; padding-bottom: 12px; margin-bottom: 20px; border-bottom: 1px solid var(--rule);
  overflow-x: auto; scrollbar-width: thin; }
.ww-top a { flex: none; color: var(--ink); text-decoration: none; font-size: 0.88rem; padding: 6px 12px; border-radius: 999px; border: 1px solid var(--rule); background: var(--panel); white-space: nowrap; }
.ww-top a:hover { border-color: var(--accent); }
.ww-top a:focus-visible, .ww-jump a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.ww-top a[aria-current="page"] { background: var(--accent); border-color: var(--accent); color: var(--paper); font-weight: 600; }
.ww-top a.ww-name { font-weight: 600; border-color: transparent; background: none; padding-left: 0; }
.ww-top a.ww-name[aria-current="page"] { color: var(--accent); background: none; }
.ww-jump { max-width: 920px; margin: 0 auto 18px; display: flex; flex-wrap: wrap; gap: 4px 14px; align-items: baseline; font-size: 0.85rem; }
.ww-jump span { font: 600 0.72rem var(--mono); letter-spacing: 0.05em; color: var(--soft); }
.ww-jump a { color: var(--accent); text-decoration: none; } .ww-jump a:hover { text-decoration: underline; }
.ww-wait { color: var(--soft); }
h1 { font: 600 1.9rem/1.15 var(--sans); letter-spacing: -0.01em; margin: 0; text-wrap: balance; }
h2 { font: 600 1.25rem/1.25 var(--sans); margin: 14px 0 0; padding-top: 16px; border-top: 2px solid var(--ink); text-wrap: balance; }
h3 { font: 600 1rem/1.3 var(--sans); margin: 0; }
p { margin: 0; max-width: 68ch; } a { color: var(--accent); }
code { font: 0.86em var(--mono); background: color-mix(in srgb, var(--ink) 8%, transparent); padding: 1px 4px; border-radius: 3px; overflow-wrap: anywhere; }
.lede { color: var(--soft); font-size: 1.05rem; }
.scroll { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-size: 0.92rem; }
th, td { text-align: left; padding: 6px 12px 6px 0; border-bottom: 1px solid var(--rule); vertical-align: top; }
th { font-weight: 600; color: var(--soft); font-size: 0.8rem; }
ul { margin: 0; padding-left: 20px; } li { margin: 3px 0; max-width: 66ch; }
.ww-pages { list-style: none; padding: 0; display: flex; flex-direction: column; gap: 10px; }
.ww-pages li { max-width: none; margin: 0; background: var(--panel); border: 1px solid var(--rule); border-radius: 8px; padding: 12px 14px; display: flex; flex-direction: column; gap: 2px; }
.ww-pages a { font-weight: 600; font-size: 1.05rem; text-decoration: none; } .ww-pages a:hover, .ww-pages a:focus-visible { text-decoration: underline; }
.ww-pages small { color: var(--soft); font: 0.8rem var(--mono); }
.ww-kind { font: 600 0.72rem var(--mono); letter-spacing: 0.05em; color: var(--soft); }
"""

FONTS = '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;600&display=swap">'


def pages():
    return json.loads((SKILL / "pages.json").read_text())


def ordered(data):
    """Every page in the bar's order: the ones kept up to date, then the rest, newest first."""
    rank = {"standing": 0, "dated": 1}
    return sorted(data["pages"], key=lambda p: (rank.get(p["kind"], 2), tuple(-int(n) for n in p["updated"].split("-")), p["slug"]))


def top(here=None, shell=False):
    """The bar every page carries: Home and every page, the one in view marked. In Home's own
    document the links are `#slug` (its script swaps the page in); in a page opened by itself
    they go back through Home."""
    data = pages()
    base = "" if shell else "index.html"
    links = [f'<a class="ww-name" href="{base or "#"}"{"" if here else " aria-current=page"} data-slug="">WalletWeather</a>']
    for page in ordered(data):
        current = ' aria-current="page"' if page["slug"] == here else ""
        links.append(f'<a href="{base}#{page["slug"]}" data-slug="{page["slug"]}"{current}>{esc(page.get("short") or page["title"])}</a>')
    return '<nav class="ww-top" aria-label="WalletWeather pages">' + "".join(links) + "</nav>"


# Home is also the frame the other pages show in: a page's link is #slug, and this swaps its
# <main> and its own styles into view, so the bar stays put and the address says where you are.
# #slug--part is a place within a page. A page that can't be fetched falls back to its own file.
ROUTER = """<script>
(function () {
  var view = document.getElementById("ww-view"), jump = document.getElementById("ww-jump");
  var home = view.innerHTML, kept = {}, slugs = SLUGS;
  function mark(slug) {
    document.querySelectorAll(".ww-top a").forEach(function (a) {
      if (a.dataset.slug === slug) { a.setAttribute("aria-current", "page"); a.scrollIntoView({ block: "nearest", inline: "nearest" }); }
      else { a.removeAttribute("aria-current"); }
    });
  }
  function load(slug) {
    if (kept[slug]) { return Promise.resolve(kept[slug]); }
    return fetch(slug + ".html").then(function (answer) {
      if (!answer.ok) { throw new Error(answer.status); }
      return answer.text();
    }).then(function (text) {
      var page = new DOMParser().parseFromString(text, "text/html"), main = page.querySelector("main");
      var styles = Array.prototype.map.call(page.querySelectorAll("body style"), function (s) { return s.outerHTML; }).join("");
      kept[slug] = styles + (main ? main.outerHTML : page.body.innerHTML);
      return kept[slug];
    });
  }
  function settle(slug, part) {
    // Links to a place on the page keep the page in the address; headings become the jump list.
    view.querySelectorAll('a[href^="#"]').forEach(function (a) {
      var name = a.getAttribute("href").slice(1);
      if (name && slugs.indexOf(name) < 0 && name.indexOf("--") < 0) { a.setAttribute("href", "#" + slug + "--" + name); }
    });
    var heads = view.querySelectorAll("h2"), links = [];
    heads.forEach(function (h, i) {
      if (!h.id) { h.id = "part-" + (i + 1); }
      links.push('<a href="#' + slug + "--" + h.id + '">' + h.textContent.replace(/[<>&]/g, "") + "</a>");
    });
    jump.innerHTML = slug && links.length > 2 ? "<span>ON THIS PAGE</span>" + links.join("") : "";
    jump.hidden = !jump.innerHTML;
    var target = part && document.getElementById(part);
    if (target) { target.scrollIntoView(); } else { window.scrollTo(0, 0); }
  }
  var showing = null;
  function route() {
    var parts = location.hash.replace(/^#/, "").split("--"), slug = parts[0], part = parts[1];
    if (slugs.indexOf(slug) < 0) { slug = ""; }
    if (slug === showing) { settle(slug, part); return; }
    mark(slug);
    if (!slug) { view.innerHTML = home; showing = ""; settle("", null); return; }
    view.innerHTML = '<main><p class="ww-wait">Opening…</p></main>';
    load(slug).then(function (content) {
      view.innerHTML = content; showing = slug; settle(slug, part);
    }).catch(function () {
      showing = null;
      view.innerHTML = '<main><p>This page didn\u2019t load here. <a href="' + slug + '.html">Open it by itself</a>.</p></main>';
    });
  }
  window.addEventListener("hashchange", route);
  route();
})();
</script>"""


def home():
    data = pages()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "pages.css").write_text(CSS)
    parts = ['<title>WalletWeather</title>', '<meta name="claude:viewport-fit-sides" content="cover">', FONTS,
             '<link rel="stylesheet" href="pages.css">', top(shell=True), '<nav class="ww-jump" id="ww-jump" aria-label="On this page" hidden></nav>',
             '<div id="ww-view">', "<main>",
             "<h1>WalletWeather</h1>", f'<p class="lede">{data["lede"]}</p>']
    kinds = [("standing", "Kept up to date"), ("dated", "Written once")]
    for kind, title in kinds:
        members = [p for p in data["pages"] if p["kind"] == kind]
        if not members:
            continue
        members.sort(key=lambda p: p["updated"], reverse=True)
        parts.append(f"<h2>{title}</h2><ul class=\"ww-pages\">")
        for page in members:
            issue = f' · <a href="https://github.com/mkolakowski/WalletWeather/issues/{page["issue"]}">#{page["issue"]}</a>' if page.get("issue") else ""
            parts.append(f'<li><a href="#{page["slug"]}">{esc(page["title"])}</a><span>{esc(page["about"])}</span>'
                         f'<small>{"updated" if kind == "standing" else "written"} {page["updated"]}{issue}</small></li>')
        parts.append("</ul>")
    if data.get("elsewhere"):
        parts.append('<h2>Older pages, at their own links</h2><ul>')
        for item in data["elsewhere"]:
            parts.append(f'<li><a href="{item["url"]}">{esc(item["title"])}</a> ({item["date"]}): {esc(item["about"])}</li>')
        parts.append("</ul>")
    parts.append("</main>")
    parts.append("</div>")
    parts.append(ROUTER.replace("SLUGS", json.dumps([p["slug"] for p in ordered(data)])))
    (OUT / "index.html").write_text("\n".join(parts) + "\n")
    print(f"pages: Home lists {len(data['pages'])} page(s); {OUT / 'index.html'}")


def wrap(slug, body_file):
    page = next((p for p in pages()["pages"] if p["slug"] == slug), None)
    if page is None:
        sys.exit(f"pages: no page called '{slug}' in pages.json; add it there first")
    body = pathlib.Path(body_file).read_text()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "pages.css").write_text(CSS)
    # A page other than Home is published as a file, so it carries its own document.
    doc = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{esc(page["title"])} · WalletWeather</title>
{FONTS}
<link rel="stylesheet" href="pages.css">
<style>:root {{ padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px); }}</style>
</head>
<body>
{top(page["slug"])}
{body}
</body>
</html>
"""
    (OUT / f"{slug}.html").write_text(doc)
    print(f"pages: {OUT / (slug + '.html')} ({len(doc) / 1e6:.2f} MB)")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "home":
        home()
    elif command == "wrap" and len(sys.argv) == 4:
        wrap(sys.argv[2], sys.argv[3])
    elif command == "list":
        for page in pages()["pages"]:
            print(f'{page["slug"]:28} {page["kind"]:9} {page["updated"]}  {page["title"]}')
    else:
        sys.exit(__doc__)
