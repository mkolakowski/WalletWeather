"""Contrast check of every theme in apps/web/index.html (WCAG ratio, 4.5 passes).

Prints each failing pair with the smallest fix that keeps the colour's hue, then a
stylesheet of the fixes. Run from anywhere: python3 Plans/web-refresh/theme-contrast.py
It only reads; nothing is written.
"""
import re, json, pathlib
src = (pathlib.Path(__file__).resolve().parents[2] / "apps/web/index.html").read_text().split("* { box-sizing")[0]
themes = {}
for m in re.finditer(r':root(?:\[data-theme="(\w+)"\])?\s*\{([^}]*)\}', src):
    name = m.group(1) or "dark"
    toks = {k: (v if len(v) == 7 else "#" + "".join(ch * 2 for ch in v[1:])) for k, v in re.findall(r'--([\w-]+):\s*(#[0-9a-fA-F]{6}|#[0-9a-fA-F]{3})\b', m.group(2))}
    if "bg" in toks: themes[name] = toks
def rgb(h): return [int(h[i:i+2], 16) for i in (1, 3, 5)]
def hexs(c): return "#" + "".join(f"{round(max(0, min(255, v))):02x}" for v in c)
def lum(h):
    f = lambda v: (v/255/12.92) if v/255 <= 0.03928 else ((v/255+0.055)/1.055) ** 2.4
    r, g, b = (f(v) for v in rgb(h)); return 0.2126*r + 0.7152*g + 0.0722*b
def cr(a, b):
    la, lb = lum(a), lum(b); return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
def mix(a, b, t): return hexs([x + (y - x) * t for x, y in zip(rgb(a), rgb(b))])
PAIRS = [("muted", "panel", "Muted labels on a panel"), ("muted", "bg", "Muted labels on the page"),
         ("accent", "panel", "Accent text (active tab, links)"), ("on-accent", "accent", "Text on a filled button"),
         ("good", "panel", "Money-in green"), ("bad", "panel", "Money-out red"), ("warn", "panel", "Warning text"),
         ("text", "panel", "Body text")]
rows, fixes, summary = [], {}, {}
for name, t in themes.items():
    new = dict(t); fails = 0
    for fg, bg, what in PAIRS:
        r0 = cr(t[fg], t[bg])
        if r0 >= 4.5: continue
        fails += 1
        if fg == "on-accent":
            if cr(t[fg], new["accent"]) >= 4.5:   # the accent fix above already rescued it
                rows.append({"theme": name, "what": what, "fg": fg, "old": t[fg], "on": t[bg], "ratio": round(r0, 2),
                             "new": t[fg], "newRatio": round(cr(t[fg], new["accent"]), 2), "note": "fixed by the darker accent"}); continue
            cands = ["#ffffff", t["bg-deep"], t["text"], "#0b1220"]
            new[fg] = max(cands, key=lambda c: cr(c, new["accent"]))
        else:
            import colorsys
            r_, g_, b_ = (v / 255 for v in rgb(t[fg])); h_, l_, s_ = colorsys.rgb_to_hls(r_, g_, b_)
            step = 0.005 if lum(t["panel"]) < 0.3 else -0.005     # lighter on dark themes, darker on light ones
            others = [b for f, b, _ in PAIRS if f == fg]; c = t[fg]; k = 0
            while min(cr(c, new[o]) for o in others) < 4.5 and k < 120:
                k += 1; l2 = max(0, min(1, l_ + step * k)); c = hexs([v * 255 for v in colorsys.hls_to_rgb(h_, l2, s_)])
            new[fg] = c
        rows.append({"theme": name, "what": what, "fg": fg, "old": t[fg], "on": t[bg], "ratio": round(r0, 2),
                     "new": new[fg], "newRatio": round(cr(new[fg], new[bg]), 2)})
    summary[name] = fails
    ch = {k: v for k, v in new.items() if v != t[k]}
    if ch: fixes[name] = ch
# dedupe: muted on panel/bg both listed with the same fix; keep the worse one
seen = {}; out = []
for r in rows:
    k = (r["theme"], r["fg"])
    if k in seen:
        if r["ratio"] < seen[k]["ratio"]: seen[k].update(r)
        continue
    seen[k] = r; out.append(r)
summary = {n: sum(1 for r in out if r["theme"] == n) for n in themes}
css = ["/* 13. Theme contrast fixes (smallest change that reaches 4.5:1) */"]
for name, ch in fixes.items():
    if name in ("dark", "light"): continue   # the trial stylesheet already retunes these two
    css.append(f':root[data-theme="{name}"] {{ ' + " ".join(f"--{k}:{v};" for k, v in ch.items()) + " }")
for r in out: print(r.get("note", ""), f'{r["theme"]:10} {r["what"]:34} {r["old"]} on {r["on"]}  {r["ratio"]:5.2f} -> {r["new"]} {r["newRatio"]:5.2f}')
print(summary)
print("\n".join(css))

# Text on the tinted surfaces the refresh added (#292): grey on a chip, accent text on its tint, red text
# on a Delete button's tint. Each uses its own *-ink token; every pair must reach 4.5:1.
TINTED = [("muted-chip", ["chip-bg", "panel", "bg"], None),
          ("accent-ink", ["bg", "panel"], ("accent", .10)),
          ("accent-ink", ["panel"], ("accent", .13)),            # the initials button
          ("bad-ink", ["panel", "bg", "chip-bg"], ("bad", .08))]
bad_pairs = []
for name, t in themes.items():
    for fg, onto, tint in TINTED:
        for o in onto:
            bgc = t[o] if tint is None else mix(t[o], t[tint[0]], tint[1])
            if cr(t[fg], bgc) < 4.5:
                bad_pairs.append(f'{name:10} {fg} on {o}{"" if tint is None else " + " + str(round(tint[1]*100)) + "% " + tint[0]}  {cr(t[fg], bgc):.2f}')
print("\nTinted surfaces under 4.5:1:", "none" if not bad_pairs else "")
print("\n".join(bad_pairs))
