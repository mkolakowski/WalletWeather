"""The shared JavaScript core gives the server's answers (Plans/standalone.md,
phase 1, #232).

- Every case in packages/core/answer-key/ comes out of the core exactly as
  it came out of the server: the core adds the same doubles in the same
  order (with Python's compensated sum() where the server uses it), so every
  number agrees to the last bit.
- Rebuilding the cases through the server (its readers, the engine and the
  routes) still gives the committed answers. Before phase 2 (#233) this
  compared the server's own Python with the key; the key was written by it.
- The core's date and rounding helpers agree with Python's on wide ranges.

To rewrite the key after a deliberate change, see tests/answer_key.py.
"""
import math
import os
import random
from datetime import date, timedelta

import pytest

import answer_key
import jscore

# Exact: see the module docstring. Raise it only with a reason here.
TOLERANCE = 0


def differences(got, want, path="$"):
    """Where two JSON values differ: numbers within TOLERANCE (and 100 equals
    100.0), everything else exactly."""
    if isinstance(want, bool) or isinstance(got, bool):
        return [] if got is want else [f"{path}: {got!r} != {want!r}"]
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        return [] if math.isclose(got, want, rel_tol=0, abs_tol=TOLERANCE) else [f"{path}: {got!r} != {want!r}"]
    if isinstance(want, dict) and isinstance(got, dict):
        if set(got) != set(want):
            return [f"{path}: keys {sorted(set(got) ^ set(want))} differ"]
        return [d for k in want for d in differences(got[k], want[k], f"{path}.{k}")]
    if isinstance(want, list) and isinstance(got, list):
        if len(got) != len(want):
            return [f"{path}: {len(got)} items != {len(want)}"]
        return [d for i, (g, w) in enumerate(zip(got, want)) for d in differences(g, w, f"{path}[{i}]")]
    return [] if got == want else [f"{path}: {got!r} != {want!r}"]


def _committed():
    return [(f"{house}: {case['name']}", case)
            for house, cases in answer_key.load().items() for case in cases]


@pytest.mark.parametrize("name,case", _committed())
def test_the_core_gives_the_servers_answer(name, case):
    got = jscore.run(case["function"], case["input"])
    problems = differences(got, case["expected"])
    assert not problems, f"{name}:\n" + "\n".join(problems[:10])


def test_the_key_has_every_function():
    functions = {case["function"] for _, case in _committed()}
    assert functions == {"forecast", "actualBalanceAsOf", "upcomingDates", "calendar", "dashboard",
                         "dashboardCharts", "recurringList", "searchTransactions", "search"}


def test_the_key_still_matches_the_server(app_started):
    live = answer_key.build_cases(app_started)
    if os.environ.get("WRITE_ANSWER_KEY") == "1":
        answer_key.write(live)
        pytest.skip(f"answer key rewritten in {answer_key.KEY_DIR}")
    committed = answer_key.load()
    assert set(committed) == set(live), "households differ: rewrite the key (see tests/answer_key.py)"
    for house, cases in live.items():
        assert [c["name"] for c in committed[house]] == [c["name"] for c in cases], house
        for want, got in zip(committed[house], cases):
            problems = differences(got, want)
            assert not problems, f"{house}: {want['name']}:\n" + "\n".join(problems[:10])


def test_day_numbers_match_python():
    epoch = date(1970, 1, 1)
    day = date(1899, 12, 25)
    while day < date(2101, 1, 10):
        iso = day.isoformat()
        assert jscore.context().eval(f"WalletWeatherCore._dayNumber('{iso}')") == (day - epoch).days, iso
        assert jscore.context().eval(f"WalletWeatherCore._isoOf({(day - epoch).days})") == iso
        day += timedelta(days=13)


def test_rounding_matches_python():
    rng = random.Random(232)
    values = [0.125, 0.375, -0.125, 250.125, 250.375, 2.675, 1.005, -1.005, 0.005, 1e-9, 123456789.125,
              -0.0, 0.0, 1e12, -1e12]
    values += [rng.uniform(-1e6, 1e6) for _ in range(2000)]
    values += [round(rng.uniform(-1e4, 1e4), 3) for _ in range(2000)]
    values += [k / 8 for k in range(-400, 400)]
    for v in values:
        got = jscore.context().eval(f"WalletWeatherCore._round2({v!r})")
        assert got == round(v, 2), v


def test_sum_matches_python():
    rng = random.Random(1232)
    for _ in range(300):
        values = [rng.choice([round(rng.uniform(-2000, 2000), 2), round(rng.uniform(-50, 50), 3), 0.1, 0.2, 10.005])
                  for _ in range(rng.randint(0, 40))]
        js = "[" + ",".join(repr(v) for v in values) + "]"
        assert jscore.context().eval(f"WalletWeatherCore._pySum({js})") == sum(values), values


def test_the_iphone_copy_matches():
    """The iPhone app runs a copy of the core (SwiftPM can't take a file from
    outside its package, #234). CI doesn't run the app's tests, so the copy
    is checked here: after changing the core, run
    apps/ios/WalletWeatherKit/Scripts/copy-core.sh."""
    copy = (answer_key.KEY_DIR.parents[2] / "apps" / "ios" / "WalletWeatherKit" / "Sources"
            / "WalletWeatherKit" / "Core" / "walletweather-core.js")
    assert copy.read_bytes() == jscore.CORE.read_bytes(), "run apps/ios/WalletWeatherKit/Scripts/copy-core.sh"


def test_casefold_matches_python():
    """Search matches casefolded text (#235). Over every assigned code point,
    two characters fold together in the core exactly when they do in
    Python, and realistic words fold to the same text."""
    import json
    import unicodedata
    chars = [chr(c) for c in range(0x110000)
             if not 0xD800 <= c <= 0xDFFF and unicodedata.category(chr(c)) != "Cn"]
    folded = json.loads(jscore.context().eval(
        f"JSON.stringify({json.dumps(chars)}.map(WalletWeatherCore._casefold))"))
    py_groups, js_groups = {}, {}
    for ch, js in zip(chars, folded):
        py_groups.setdefault(ch.casefold(), []).append(ch)
        js_groups.setdefault(js, []).append(ch)
    py_partition = {ch: tuple(py_groups[ch.casefold()]) for ch in chars}
    js_partition = {ch: tuple(js_groups[js]) for ch, js in zip(chars, folded)}
    wrong = [ch for ch in chars if py_partition[ch] != js_partition[ch]]
    assert not wrong, [f"U+{ord(c):04X}" for c in wrong[:20]]
    for word in ("Straße", "STRASSE", "ΣΑΣ", "σας", "İstanbul", "Iğdır", "ǅungla", "ﬁne", "Ŀeft", "Éclair"):
        assert jscore.context().eval(f"WalletWeatherCore._casefold({json.dumps(word)})") == word.casefold(), word


def test_strip_matches_python():
    import json
    # From U+0001: the engine's Python binding cuts a returned string at a NUL.
    for c in range(1, 0x3100):
        text = f"{chr(c)}a{chr(c)}b{chr(c)}"
        got = jscore.context().eval(f"WalletWeatherCore._pyStrip({json.dumps(text)})")
        assert got == text.strip(), f"U+{c:04X}"
