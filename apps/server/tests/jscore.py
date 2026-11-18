"""Runs the shared JavaScript core (packages/core/walletweather-core.js) in
quickjs-ng, the engine chosen for the server (Plans/standalone.md, open
question 1, decided 2026-11-18). Test-only in phase 1 (#232); phase 2 moves
this into the app."""
import json
from pathlib import Path

import quickjs

CORE = Path(__file__).resolve().parents[3] / "packages" / "core" / "walletweather-core.js"

_context = None


def context():
    """One engine for the whole run, with the core loaded."""
    global _context
    if _context is None:
        _context = quickjs.Context()
        _context.eval(CORE.read_text(encoding="utf-8"))
    return _context


def run(name: str, given):
    """Call one of the core's functions with plain Python data."""
    ctx = context()
    ctx.set("__name", name)
    ctx.set("__input", json.dumps(given))
    return json.loads(ctx.eval("WalletWeatherCore.run(__name, __input)"))
