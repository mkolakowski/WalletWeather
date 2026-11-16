"""The open findings of the 2026-11-16 security review (#178, #179), one test
each, written as the behaviour the fix should give.

Every test here is marked `xfail(strict=True)`: it fails today, which is the
finding, and the run stays green. When a fix lands, its test starts passing,
strict mode turns that into a failure, and the marker comes off in the same
commit. From then on the test guards the fix like any other.

The ids (WW-SEC-01 ...) are the review's; Plans/security-fixes.md says which
phase closes each. A fixed finding's tests move to test_security_fixes.py. A test marked "design" assumes an answer to one of the
plan's open questions and is rewritten if the answer differs.

Run them as they'd run once fixed, to see each finding fail for its own
reason:  ... run --rm tests tests/test_security_findings.py --runxfail
"""
import os
import subprocess
import sys
import uuid
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"
TODAY = date.today().isoformat()
SERVER_DIR = Path(__file__).resolve().parent.parent


def finding(ref, why, design=False):
    return pytest.mark.xfail(strict=True, reason=f"{ref}{' (design)' if design else ''}: {why}")


def register(app, email=None, **extra):
    # A server error is an answer here (500), not an exception in the test.
    c = TestClient(app, raise_server_exceptions=False)
    email = email or unique_email()
    r = c.post("/api/auth/register", json={"email": email, "password": PASSWORD, **extra})
    assert r.status_code == 200, r.text
    return c, {"email": email, "id": r.json()["id"]}


def make_account(c, name="Checking"):
    r = c.post("/api/accounts", json={"name": name, "starting_balance": 100,
                                      "starting_date": TODAY})
    assert r.status_code == 200, r.text
    return r.json()["id"]


REFUSED = (400, 403, 404, 409, 413, 422)
# What a colour field could carry into a page that puts it inside an
# attribute: 20 characters, the column's size.
NOT_A_COLOUR = '"onclick=eval(name) '


# ---------- WW-SEC-06: everyone's address ----------

@finding("WW-SEC-06", "the Permissions panel lists every user's email and name", design=True)
def test_you_dont_see_the_addresses_of_people_you_share_nothing_with(app_started):
    _, stranger = register(app_started)
    c, _ = register(app_started)
    make_account(c)
    assert stranger["email"] not in c.get("/api/permissions").text
