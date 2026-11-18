"""The shared JavaScript core for the tests: `run` is the app's own
(app/jscore.py), and `context()` loads the core into a separate engine so a
test can call its date, rounding and summing helpers directly."""
import quickjs

from app.jscore import CORE, run  # noqa: F401 (run is re-exported)

_context = None


def context():
    global _context
    if _context is None:
        _context = quickjs.Context()
        _context.eval(CORE.read_text(encoding="utf-8"))
    return _context
