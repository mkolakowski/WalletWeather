"""Screenshots of the web client for web-refresh (Plans/web-refresh.md).

Signs in to the demo stack (demo-compose.yml, sample data) and saves one picture per page, at
desktop and phone size, in Dark and Light:

    python3 capture.py OUT_DIR [page,page,...] [base URL]

Needs Playwright for Python with Chromium. Keep OUT_DIR outside the repo.
"""
import pathlib, sys
from playwright.sync_api import sync_playwright

OUT = pathlib.Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
ONLY = set(sys.argv[2].split(",")) if len(sys.argv) > 2 and sys.argv[2] != "-" else None
BASE = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:8377"
PAGES = ["dashboard", "networth", "accounts", "subscriptions", "calendar", "reports", "settings", "admin"]
RUNS = [("desk-dark", {"width": 1440, "height": 900}, "dark", False), ("desk-light", {"width": 1440, "height": 900}, "light", False),
        ("phone-dark", {"width": 390, "height": 844}, "dark", True), ("phone-light", {"width": 390, "height": 844}, "light", True)]

def run(p, tag, viewport, scheme, mobile):
    browser = p.chromium.launch()
    ctx = browser.new_context(viewport=viewport, color_scheme=scheme, device_scale_factor=2, is_mobile=mobile, has_touch=mobile)
    page = ctx.new_page()
    page.goto(BASE, wait_until="networkidle")
    page.wait_for_selector("#login:not(.hidden)", timeout=10000)
    if not ONLY or "login" in ONLY: page.screenshot(path=str(OUT / f"{tag}-login.png"))
    page.evaluate("fillDemoCreds()"); page.evaluate("doSignin()"); page.wait_for_timeout(1500)
    if page.locator("#notice:not(.hidden)").count(): page.click("#noticeAgreeBtn"); page.wait_for_timeout(1200)
    page.wait_for_selector("#app:not(.hidden)", timeout=10000)
    for name in PAGES:
        if ONLY and name not in ONLY: continue
        page.evaluate(f"showPage('{name}')"); page.wait_for_timeout(1400)
        # the demo user's saved theme is System: force the one asked for
        page.evaluate("(t) => t ? document.documentElement.setAttribute('data-theme', t) : document.documentElement.removeAttribute('data-theme')",
                      "light" if scheme == "light" else None)
        page.wait_for_timeout(300); page.evaluate("window.scrollTo(0, 0)")
        page.screenshot(path=str(OUT / f"{tag}-{name}.png"))
    browser.close()

with sync_playwright() as p:
    for tag, viewport, scheme, mobile in RUNS: run(p, tag, viewport, scheme, mobile)
print("saved to", OUT)
