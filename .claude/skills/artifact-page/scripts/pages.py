#!/usr/bin/env python3
"""Builds the files of the one WalletWeather artifact (#351).

    pages.py home                      writes Home (index.html) and pages.css from pages.json
    pages.py wrap <slug> <body.html>   wraps a page's content in the shared header, as <slug>.html
    pages.py stubs                     writes a placeholder page for every entry marked "stub": true
    pages.py list                      prints the pages

Home is also the frame the other pages show in: the bar at the top has three tabs
(Home, The project, Reviews and designs: the groups in pages.json), a link is
#slug, and Home's script swaps that page's <main> and its own styles into view;
a group's tab opens a list of its pages, and a page shows its group and the
pages either side. So a page is plain HTML and CSS: a <script> in it won't run
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

CSS = """/* WalletWeather's pages, in the iPhone app's look: a soft blue-tinted page, rounded cards, a large title, the app's blue for what can be tapped. */
:root { --paper:#eaf0f9; --paper2:#f6f8fc; --ink:#0f1620; --soft:#566274; --rule:#d3dbe6; --panel:#ffffff; --accent:#0a63d6; --accent-ink:#ffffff; --good:#1b7a45; --bad:#b3261e; --warn:#955600;
  --tint:rgba(10,99,214,.10); --glass:rgba(255,255,255,.72); --shadow:0 1px 2px rgba(20,40,80,.06), 0 6px 18px rgba(20,40,80,.06);
  --sans:-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, "Segoe UI", sans-serif; --mono:ui-monospace, "SF Mono", Menlo, monospace; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#0c1424; --paper2:#070b13; --ink:#e8edf5; --soft:#9aa6b8; --rule:#27344a; --panel:#141d2e; --accent:#6aa7ff; --accent-ink:#06111f; --good:#6fd19a; --bad:#ff8a80; --warn:#f0b25a;
  --tint:rgba(106,167,255,.14); --glass:rgba(20,29,46,.72); --shadow:0 1px 2px rgba(0,0,0,.4); color-scheme: dark } }
:root[data-theme="dark"] { --paper:#0c1424; --paper2:#070b13; --ink:#e8edf5; --soft:#9aa6b8; --rule:#27344a; --panel:#141d2e; --accent:#6aa7ff; --accent-ink:#06111f; --good:#6fd19a; --bad:#ff8a80; --warn:#f0b25a;
  --tint:rgba(106,167,255,.14); --glass:rgba(20,29,46,.72); --shadow:0 1px 2px rgba(0,0,0,.4); color-scheme: dark }
html { color-scheme: light dark; background: var(--paper2); }
body { margin: 0; min-height: 100vh; background: linear-gradient(180deg, var(--paper) 0, var(--paper2) 560px) no-repeat; color: var(--ink); font: 16px/1.5 var(--sans); -webkit-text-size-adjust: 100%;
  padding-block: 0 72px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
img { max-width: 100%; } [hidden] { display: none !important; }
main, .ww-bar-in, .ww-jump, .ww-crumb, .ww-step { max-width: 920px; margin-left: auto; margin-right: auto; }
main { display: flex; flex-direction: column; gap: 20px; padding-top: 6px; }

/* The bar: the name, and three tabs. */
.ww-bar { position: sticky; top: 0; z-index: 20; margin: 0 calc(-1 * max(16px, env(safe-area-inset-left, 0px))); padding: 10px max(16px, env(safe-area-inset-left, 0px)) 8px;
  background: var(--glass); -webkit-backdrop-filter: saturate(1.6) blur(18px); backdrop-filter: saturate(1.6) blur(18px); border-bottom: 1px solid color-mix(in srgb, var(--rule) 60%, transparent); }
.ww-bar-in { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.ww-name { font-weight: 700; font-size: 1.02rem; color: var(--ink); text-decoration: none; letter-spacing: -0.01em; flex: none; }
.ww-tabs { display: flex; flex: 1 1 260px; max-width: 460px; margin-left: auto; padding: 3px; gap: 2px; background: var(--tint); border-radius: 999px; }
.ww-tabs a { flex: 1 1 0; text-align: center; text-decoration: none; color: var(--soft); font-size: 0.9rem; font-weight: 600; padding: 7px 10px; border-radius: 999px; white-space: nowrap; min-height: 20px; }
.ww-tabs a:hover { color: var(--ink); }
.ww-tabs a[aria-current="page"] { background: var(--panel); color: var(--accent); box-shadow: var(--shadow); }
.ww-tabs a:focus-visible, .ww-name:focus-visible, .ww-jump a:focus-visible, .ww-step a:focus-visible, .ww-crumb a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
@media (max-width: 520px) { .ww-tabs { flex-basis: 100%; max-width: none; margin-left: 0; } }

/* Where you are, and what's near. */
.ww-crumb { padding: 14px 0 0; font-size: 0.9rem; color: var(--soft); }
.ww-crumb a { color: var(--accent); text-decoration: none; font-weight: 600; } .ww-crumb a:hover { text-decoration: underline; }
.ww-jump { display: flex; gap: 8px; align-items: center; margin-top: 12px; margin-bottom: 8px; overflow-x: auto; scrollbar-width: none; padding-bottom: 2px; }
.ww-jump::-webkit-scrollbar { display: none; }
.ww-jump span { flex: none; font: 700 0.68rem var(--sans); letter-spacing: 0.06em; color: var(--soft); }
.ww-jump a { flex: none; color: var(--ink); text-decoration: none; font-size: 0.84rem; padding: 5px 12px; border-radius: 999px; background: var(--panel); box-shadow: var(--shadow); white-space: nowrap; }
.ww-jump a:hover { color: var(--accent); }
.ww-step { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 28px; }
.ww-step a { display: flex; flex-direction: column; gap: 2px; text-decoration: none; background: var(--panel); border-radius: 18px; padding: 12px 16px; box-shadow: var(--shadow); min-width: 0; }
.ww-step a:last-child:nth-child(2) { text-align: right; }
.ww-step small { color: var(--soft); font-size: 0.76rem; } .ww-step b { color: var(--accent); font-weight: 600; font-size: 0.98rem; overflow-wrap: anywhere; }
.ww-wait { color: var(--soft); }

/* Home and the two lists. */
.ww-hero { padding: 18px 0 2px; } .ww-hero h1, h1 { font: 700 2.1rem/1.1 var(--sans); letter-spacing: -0.02em; margin: 0; text-wrap: balance; }
.ww-list { list-style: none; margin: 0; padding: 0; background: var(--panel); border-radius: 22px; box-shadow: var(--shadow); overflow: hidden; }
.ww-list li { margin: 0; max-width: none; border-top: 1px solid var(--rule); } .ww-list li:first-child { border-top: 0; }
.ww-list a.ww-row { display: grid; grid-template-columns: 1fr auto; gap: 2px 12px; align-items: center; padding: 14px 18px; text-decoration: none; color: var(--ink); min-height: 48px; }
.ww-list a.ww-row:hover { background: var(--tint); }
.ww-list .ww-t { font-weight: 600; font-size: 1.02rem; } .ww-list .ww-a { grid-column: 1; color: var(--soft); font-size: 0.88rem; max-width: 60ch; }
.ww-list .ww-m { grid-column: 1; color: var(--soft); font: 0.76rem var(--mono); margin-top: 4px; }
.ww-list .ww-go { grid-row: 1 / span 3; grid-column: 2; color: var(--soft); font-size: 1.3rem; opacity: .7; }
.ww-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 14px; }
.ww-card { display: flex; flex-direction: column; gap: 6px; text-decoration: none; color: var(--ink); background: var(--panel); border-radius: 22px; padding: 18px; box-shadow: var(--shadow); }
.ww-card:hover { outline: 2px solid var(--accent); outline-offset: -2px; }
.ww-card h2 { margin: 0; padding: 0; border: 0; font: 700 1.3rem/1.2 var(--sans); } .ww-card p { color: var(--soft); font-size: 0.92rem; }
.ww-card ul { list-style: none; padding: 0; margin: 6px 0 0; display: flex; flex-wrap: wrap; gap: 6px; } .ww-card li { margin: 0; font-size: 0.78rem; color: var(--accent); background: var(--tint); padding: 3px 10px; border-radius: 999px; max-width: none; }
.ww-card .ww-n { color: var(--soft); font: 0.76rem var(--mono); margin-top: 4px; }
.ww-tag { font: 700 0.68rem var(--mono); letter-spacing: 0.05em; color: var(--warn); background: color-mix(in srgb, var(--warn) 14%, transparent); border-radius: 999px; padding: 2px 8px; align-self: flex-start; }
.ww-stubnote { background: var(--panel); border-radius: 22px; padding: 18px; display: flex; flex-direction: column; gap: 8px; box-shadow: var(--shadow); }

/* What's on a page. */
h2 { font: 700 1.3rem/1.25 var(--sans); letter-spacing: -0.01em; margin: 18px 0 0; text-wrap: balance; }
h3 { font: 600 1.02rem/1.3 var(--sans); margin: 0; }
p { margin: 0; max-width: 68ch; } a { color: var(--accent); }
code { font: 0.86em var(--mono); background: var(--tint); padding: 1px 5px; border-radius: 5px; overflow-wrap: anywhere; }
.lede { color: var(--soft); font-size: 1.05rem; }
.scroll { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-size: 0.92rem; }
th, td { text-align: left; padding: 7px 12px 7px 0; border-bottom: 1px solid var(--rule); vertical-align: top; }
th { font-weight: 600; color: var(--soft); font-size: 0.8rem; }
ul { margin: 0; padding-left: 20px; } li { margin: 3px 0; max-width: 66ch; }
.ww-pages { list-style: none; padding: 0; display: flex; flex-direction: column; gap: 10px; }
.ww-pages li { max-width: none; margin: 0; background: var(--panel); border-radius: 18px; padding: 12px 16px; display: flex; flex-direction: column; gap: 2px; box-shadow: var(--shadow); }
.ww-pages a { font-weight: 600; font-size: 1.05rem; text-decoration: none; } .ww-pages a:hover, .ww-pages a:focus-visible { text-decoration: underline; }
.ww-pages small { color: var(--soft); font: 0.8rem var(--mono); }
.ww-kind { font: 700 0.7rem var(--mono); letter-spacing: 0.05em; color: var(--soft); }
.ww-foot { color: var(--soft); font-size: 0.88rem; }
"""


def pages():
    return json.loads((SKILL / "pages.json").read_text())


def ordered(data):
    """Every page: the groups in order, each group's pages in its own order (the group's `order`
    list first, then the rest newest first, a page not filled in yet last)."""
    out = []
    for group in data["groups"]:
        members = [p for p in data["pages"] if p.get("group") == group["slug"]]
        pinned = [next(p for p in members if p["slug"] == s) for s in group.get("order", []) if any(p["slug"] == s for p in members)]
        rest = sorted((p for p in members if p not in pinned),
                      key=lambda p: (1 if p.get("stub") else 0, tuple(-int(n) for n in p["updated"].split("-")), p["slug"]))
        out += pinned + rest
    return out + [p for p in data["pages"] if p not in out]   # a page with no group still lists


def in_group(data, group_slug):
    return [p for p in ordered(data) if p.get("group") == group_slug]


def top(here=None, shell=False):
    """The bar every page carries: the name and three tabs (Home and the two groups), the one in
    view marked, which for a page is its group. In Home's own document the links are `#slug` (its
    script swaps the page in); in a page opened by itself they go back through Home."""
    data = pages()
    base = "" if shell else "index.html"
    group_of = {p["slug"]: p.get("group") for p in data["pages"]}
    active = here if here in [g["slug"] for g in data["groups"]] else group_of.get(here, "") if here else ""
    tabs = [f'<a href="{base or "#"}" data-tab=""{" aria-current=page" if not active else ""}>Home</a>']
    for g in data["groups"]:
        tabs.append(f'<a href="{base}#{g["slug"]}" data-tab="{g["slug"]}"{" aria-current=page" if g["slug"] == active else ""}>{esc(g["title"] if len(g["title"]) < 14 else g["short"])}</a>')
    return ('<header class="ww-bar"><div class="ww-bar-in">'
            f'<a class="ww-name" href="{base or "#"}">WalletWeather</a>'
            '<nav class="ww-tabs" aria-label="WalletWeather">' + "".join(tabs) + "</nav></div></header>")


def crumb(page):
    data = pages()
    group = next((g for g in data["groups"] if g["slug"] == page.get("group")), None)
    if not group:
        return ""
    return f'<div class="ww-crumb"><a href="index.html#{group["slug"]}">&lsaquo; {esc(group["title"])}</a></div>'


def row(page, base=""):
    """One line of a group's list: its name, what it says, when it changed."""
    kind = {"standing": "kept up to date, ", "dated": "written "}[page["kind"]]
    stub = '<span class="ww-tag">NOT FILLED IN YET</span>' if page.get("stub") else ""
    issue = f' &middot; <a href="https://github.com/mkolakowski/WalletWeather/issues/{page["issue"]}">#{page["issue"]}</a>' if page.get("issue") else ""
    return (f'<li><a class="ww-row" href="{base}#{page["slug"]}"><span class="ww-t">{esc(page["title"])}</span>'
            f'<span class="ww-a">{esc(page["about"])}</span>{stub}<span class="ww-m">{kind}{page["updated"]}</span><span class="ww-go" aria-hidden="true">&rsaquo;</span></a></li>')


def group_html(data, group):
    members = in_group(data, group["slug"])
    return ("<main>" f'<div class="ww-hero"><h1>{esc(group["title"])}</h1></div><p class="lede">{esc(group["about"])}</p>'
            '<ul class="ww-list">' + "".join(row(p) for p in members) + "</ul></main>")


# Home is also the frame the other pages show in: a page's link is #slug, and this swaps its
# <main> and its own styles into view, so the bar stays put and the address says where you are.
# The two group pages are written into Home as <template>s. #slug--part is a place within a
# page. A page that can't be fetched falls back to its own file.
ROUTER = """<script>
(function () {
  var view = document.getElementById("ww-view"), jump = document.getElementById("ww-jump"), crumb = document.getElementById("ww-crumb"), step = document.getElementById("ww-step");
  var home = view.innerHTML, kept = {}, SITE = SITEDATA, slugs = SITE.pages.map(function (p) { return p.slug; }), groups = SITE.groups.map(function (g) { return g.slug; });
  function byslug(slug) { return SITE.pages.filter(function (p) { return p.slug === slug; })[0]; }
  function mark(tab) {
    document.querySelectorAll(".ww-tabs a").forEach(function (a) {
      if (a.dataset.tab === tab) { a.setAttribute("aria-current", "page"); } else { a.removeAttribute("aria-current"); }
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
  function around(slug) {
    // Where you are, and the pages either side of this one in its group.
    var page = byslug(slug); crumb.innerHTML = ""; step.innerHTML = "";
    if (!page) { crumb.hidden = step.hidden = true; return; }
    var g = SITE.groups.filter(function (x) { return x.slug === page.group; })[0], list = SITE.pages.filter(function (p) { return p.group === page.group; });
    crumb.innerHTML = '<a href="#' + g.slug + '">&lsaquo; ' + g.title + "</a>"; crumb.hidden = false;
    var i = list.indexOf(page), parts = [];
    if (i > 0) { parts.push('<a href="#' + list[i - 1].slug + '"><small>&lsaquo; Previous</small><b>' + list[i - 1].title + "</b></a>"); }
    if (i < list.length - 1) { parts.push('<a href="#' + list[i + 1].slug + '"><small>Next &rsaquo;</small><b>' + list[i + 1].title + "</b></a>"); }
    step.innerHTML = parts.join(""); step.hidden = !parts.length;
    if (parts.length === 1 && i === 0) { step.style.gridTemplateColumns = "1fr"; } else { step.style.gridTemplateColumns = ""; }
  }
  function settle(slug, part) {
    // Links to a place on the page keep the page in the address; headings become the jump list.
    view.querySelectorAll('a[href^="#"]').forEach(function (a) {
      var name = a.getAttribute("href").slice(1);
      if (name && slugs.indexOf(name) < 0 && groups.indexOf(name) < 0 && name.indexOf("--") < 0) { a.setAttribute("href", "#" + slug + "--" + name); }
    });
    var heads = view.querySelectorAll("h2"), links = [];
    heads.forEach(function (h, i) {
      if (!h.id) { h.id = "part-" + (i + 1); }
      links.push('<a href="#' + slug + "--" + h.id + '">' + h.textContent.replace(/[<>&]/g, "") + "</a>");
    });
    jump.innerHTML = byslug(slug) && links.length > 2 ? "<span>ON THIS PAGE</span>" + links.join("") : "";
    jump.hidden = !jump.innerHTML;
    var target = part && document.getElementById(part);
    if (target) { target.scrollIntoView(); } else { window.scrollTo(0, 0); }
  }
  var showing = null;
  function route() {
    var parts = location.hash.replace(/^#/, "").split("--"), slug = parts[0], part = parts[1];
    if (slugs.indexOf(slug) < 0 && groups.indexOf(slug) < 0) { slug = ""; }
    if (slug === showing) { settle(slug, part); return; }
    var page = byslug(slug);
    mark(page ? page.group : slug);
    document.title = (slug ? (page ? page.title : SITE.groups.filter(function (g) { return g.slug === slug; })[0].title) + " \\u00b7 " : "") + "WalletWeather";
    if (!slug) { view.innerHTML = home; showing = ""; around(""); settle("", null); return; }
    if (groups.indexOf(slug) >= 0) { view.innerHTML = document.getElementById("ww-g-" + slug).innerHTML; showing = slug; around(""); settle(slug, null); return; }
    view.innerHTML = '<main><p class="ww-wait">Opening\\u2026</p></main>';
    load(slug).then(function (content) {
      view.innerHTML = content; showing = slug; around(slug); settle(slug, part);
    }).catch(function () {
      showing = null; around("");
      view.innerHTML = '<main><p>This page didn\\u2019t load here. <a href="' + slug + '.html">Open it by itself</a>.</p></main>';
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
    parts = ['<title>WalletWeather</title>', '<meta name="claude:viewport-fit-sides" content="cover">',
             '<link rel="stylesheet" href="pages.css">', top(shell=True),
             '<div class="ww-crumb" id="ww-crumb" hidden></div>', '<nav class="ww-jump" id="ww-jump" aria-label="On this page" hidden></nav>',
             '<div id="ww-view">', "<main>",
             f'<div class="ww-hero"><h1>WalletWeather</h1></div><p class="lede">{data["lede"]}</p>', '<div class="ww-cards">']
    for group in data["groups"]:
        members = in_group(data, group["slug"])
        newest = max(p["updated"] for p in members) if members else ""
        parts.append(f'<a class="ww-card" href="#{group["slug"]}"><h2>{esc(group["title"])} &rsaquo;</h2><p>{esc(group["about"])}</p><ul>'
                     + "".join(f'<li>{esc(p.get("short") or p["title"])}</li>' for p in members)
                     + f'</ul><span class="ww-n">{len(members)} pages &middot; latest {newest}</span></a>')
    parts.append("</div>")
    if data.get("elsewhere"):
        parts.append('<h2>Older pages, at their own links</h2><ul class="ww-pages">')
        for item in data["elsewhere"]:
            parts.append(f'<li><a href="{item["url"]}">{esc(item["title"])}</a><span>{esc(item["about"])}</span><small>{item["date"]}</small></li>')
        parts.append("</ul>")
    parts += ["</main>", "</div>", '<nav class="ww-step" id="ww-step" aria-label="Next and previous" hidden></nav>']
    for group in data["groups"]:
        parts.append(f'<template id="ww-g-{group["slug"]}">{group_html(data, group)}</template>')
    site = {"groups": [{k: g[k] for k in ("slug", "title")} for g in data["groups"]],
            "pages": [{"slug": p["slug"], "title": p.get("short") or p["title"], "group": p.get("group")} for p in ordered(data)]}
    parts.append(ROUTER.replace("SITEDATA", json.dumps(site)))
    (OUT / "index.html").write_text("\n".join(parts) + "\n")
    print(f"pages: Home lists {len(data['pages'])} page(s) in {len(data['groups'])} group(s); {OUT / 'index.html'}")


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
<link rel="stylesheet" href="pages.css">
<style>:root {{ padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px); }}</style>
</head>
<body>
{top(page["slug"])}
{crumb(page)}
{body}
</body>
</html>
"""
    (OUT / f"{slug}.html").write_text(doc)
    print(f"pages: {OUT / (slug + '.html')} ({len(doc) / 1e6:.2f} MB)")


def stubs():
    """A page for every entry marked `"stub": true`: its name, what it will hold and where that
    will come from, all from pages.json. A stub stops being one when its entry loses the mark
    and something wraps real content under its slug."""
    made = 0
    for page in pages()["pages"]:
        if not page.get("stub"):
            continue
        issue = f' It\'s tracked in <a href="https://github.com/mkolakowski/WalletWeather/issues/{page["issue"]}">#{page["issue"]}</a>.' if page.get("issue") else ""
        body = OUT / f'{page["slug"]}.stub.html'
        OUT.mkdir(parents=True, exist_ok=True)
        body.write_text(f'<main>\n<h1>{esc(page["title"])}</h1>\n<p class="lede">{esc(page["about"])}</p>\n'
                        f'<div class="ww-stubnote"><span class="ww-tag">NOT FILLED IN YET</span>'
                        f'<p>{page.get("source", "")}{issue}</p></div>\n</main>\n')
        wrap(page["slug"], body)
        body.unlink()
        made += 1
    print(f"pages: {made} stub(s)")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "home":
        home()
    elif command == "wrap" and len(sys.argv) == 4:
        wrap(sys.argv[2], sys.argv[3])
    elif command == "stubs":
        stubs()
    elif command == "list":
        for page in pages()["pages"]:
            print(f'{page["slug"]:28} {page.get("group", "-"):8} {"stub" if page.get("stub") else page["kind"]:9} {page["updated"]}  {page["title"]}')
    else:
        sys.exit(__doc__)
