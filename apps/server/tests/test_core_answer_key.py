"""The shared JavaScript core gives the server's answers (Plans/standalone.md,
phase 1, #232).

- Every case in packages/core/answer-key/ comes out of the core exactly as
  it came out of the server: the core adds the same doubles in the same
  order (with Python's compensated sum() where the server uses it), so every
  number agrees to the last bit.
- The committed cases still match what today's server code answers, so the
  key can't drift from the server while both copies exist.
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
    assert functions == {"forecast", "actualBalanceAsOf", "upcomingDates", "calendar"}


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
