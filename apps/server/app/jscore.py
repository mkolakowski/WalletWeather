"""Runs the shared JavaScript core (packages/core/walletweather-core.js) in
quickjs-ng: the money logic the server, the iPhone app and later the web app
share (Plans/standalone.md, phase 2, #233; engine decided 2026-11-18).

The only JavaScript ever run is the core file shipped in the image, loaded
once. Requests reach it as data: a function name and a JSON string, never
code (pinned by test_security_guards.py).

quickjs-ng crashes when two threads touch one runtime, so every call goes
through one `quickjs.Function`, which runs on its own thread behind a lock.
A call takes milliseconds; the limits below stop a runaway one.
"""
import json
from pathlib import Path

import quickjs

_HERE = Path(__file__).resolve()
# /app/packages/core in the image, packages/core at the repo root otherwise.
_CANDIDATES = (_HERE.parents[2] / "packages" / "core" / "walletweather-core.js",
               _HERE.parents[3] / "packages" / "core" / "walletweather-core.js")
CORE = next((p for p in _CANDIDATES if p.is_file()), _CANDIDATES[-1])

MEMORY_LIMIT = 256 * 1024 * 1024
TIME_LIMIT_SECONDS = 30

# Clean up the engine's memory every this many calls, not after each one
# (that took as long as the forecast itself). The core's data has no cycles,
# so reference counting frees it between clean-ups anyway.
GC_EVERY = 100

_run = None
_calls = 0


def _function():
    global _run
    if _run is None:
        source = CORE.read_text(encoding="utf-8")
        source += "\nfunction __walletweather_run(name, json) { return WalletWeatherCore.run(name, json); }\n"
        f = quickjs.Function("__walletweather_run", source, own_executor=True)
        f.set_memory_limit(MEMORY_LIMIT)
        f.set_time_limit(TIME_LIMIT_SECONDS)
        _run = f
    return _run


class CoreError(Exception):
    """The core refused its input (e.g. a CSV file Python's csv reader would
    refuse too); the message is the core's."""


def run(name: str, given):
    """Call one of the core's functions with plain Python data and get
    plain Python data back."""
    global _calls
    _calls += 1
    try:
        out = _function()(name, json.dumps(given), run_gc=_calls % GC_EVERY == 0)
    except quickjs.JSException as e:
        raise CoreError(str(e).removeprefix("Error: ")) from e
    return json.loads(out)

