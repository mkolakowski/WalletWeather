"""CSV import runs on the shared core (Plans/standalone.md, phase 9, #243).

The answer key (packages/core/answer-key/imports.json, written by the
server's own Python before the switch) pins whole files. Here the pieces the
core copies from Python are checked against Python itself on many generated
inputs: csv.reader, the date formats tried with datetime.strptime, and the
amount reading built on float(). `_parse_csv_date` and `_parse_csv_amount`
below are the server's code as it was, kept as the reference.

Also: a file Python's csv reader refuses answers 400 rather than 500, and a
row naming one tag twice imports with it once (#248).
"""
import csv
import io
import json
import math
import random
from datetime import date, datetime

import pytest
from fastapi.testclient import TestClient

import jscore
from conftest import unique_email

PASSWORD = "correct-horse-battery"


# ---------- The reference: the server's Python as it was ----------

def _parse_csv_amount(raw):
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    neg = s.startswith("(") and s.endswith(")")
    s = s.replace("(", "").replace(")", "")
    s = s.replace("$", "").replace("£", "").replace("€", "").replace(",", "").strip()
    try:
        v = float(s)
    except ValueError:
        return None
    if not math.isfinite(v) or abs(v) > 1e12:
        return None
    return -v if neg else v


def _parse_csv_date(raw):
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%d/%m/%Y", "%d/%m/%y",
                "%Y/%m/%d", "%m-%d-%Y", "%d-%m-%Y", "%b %d, %Y", "%d %b %Y"):
        try:
            return datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            continue
    return None


def core(expression):
    return json.loads(jscore.context().eval(f"JSON.stringify({expression})"))


def core_each(helper, values):
    return core(f"{json.dumps(values)}.map((v) => WalletWeatherCore.{helper}(v))")


# ---------- The pieces, against Python ----------

def test_the_csv_reader_reads_as_pythons_does():
    rng = random.Random(243)
    alphabet = ['a', 'b', ',', ',', '"', '"', '\n', '\r', ' ', 'é', '\U0001F355', '\x00']
    texts = ["", "\n", "a,b\n", 'a,"b\nc",d\r\n', '"x""y",z', '"open', 'a"b,c', '"a"b,c', 'a,b\rc', ',,\n,']
    texts += ["".join(rng.choice(alphabet) for _ in range(rng.randint(0, 30))) for _ in range(4000)]
    for text in texts:
        try:
            want = list(csv.reader(io.StringIO(text)))
        except csv.Error:
            want = "error"
        try:
            got = core(f"WalletWeatherCore._csvReader({json.dumps(text)})")
        except Exception:
            got = "error"
        assert got == want, repr(text)


def test_dates_read_as_pythons_strptime_does():
    rng = random.Random(1243)
    pieces = ["2026", "26", "69", "68", "0000", "1", "01", "5", " 5", "12", "13", "29", "30", "31", "02",
              "Jan", "jan", "SEP", "sep", "Sept", "may", "ſep", "-", "/", ",", " ", "  ", "　",
              "٢٠٢٦", "٠١", "x"]
    values = ["2026-01-05", "1/5/26", "13/01/2026", "02/30/2026", "Jan 15, 2026", "16 Jan 2026", "2028-02-29",
              "2026-02-29", "SEP  4, 2026", "sep 3,2026", "2026-1-5", "05-01-2026", "", "   ", "0000-01-01"]
    values += ["".join(rng.choice(pieces) for _ in range(rng.randint(1, 6))) for _ in range(6000)]
    got = core_each("_parseCsvDate", values)
    for value, answer in zip(values, got):
        assert answer == _parse_csv_date(value), repr(value)


def test_amounts_read_as_pythons_float_does():
    rng = random.Random(2243)
    pieces = ["1", "0", "9", "_", ".", "e", "E", "-", "+", "(", ")", "$", "£", "€", ",", " ", " ",
              "inf", "nan", "Infinity", "١", "٣", "x", "1e12", "1e13"]
    values = ["1_000", "1__0", "(3.50)", " ( 3.50 ) ", "£1,000", "-", ".5", "5.", "nan", "-inf", "1e13",
              "1e12", "(0)", "١٢٣", "", "()", "((1))"]
    values += ["".join(rng.choice(pieces) for _ in range(rng.randint(1, 6))) for _ in range(6000)]
    got = core_each("_parseCsvAmount", values)
    for value, answer in zip(values, got):
        want = _parse_csv_amount(value)
        assert (answer is None) == (want is None) and (want is None or answer == want), repr(value)


# ---------- Through the API ----------

def account(app):
    c = TestClient(app)
    r = c.post("/api/auth/register", json={"email": unique_email(), "password": PASSWORD})
    assert r.status_code == 200, r.text
    r = c.post("/api/accounts", json={"name": "Checking", "starting_balance": 0,
                                      "starting_date": date.today().isoformat()})
    assert r.status_code == 200, r.text
    return c, r.json()["id"]


def test_preview_and_import_answer_as_before(app_started):
    c, acc = account(app_started)
    text = "Date,Description,Amount\n2026-01-05,Coffee,-4.50\nsomeday,Bad,1\n"
    r = c.post(f"/api/accounts/{acc}/import/preview", json={"csv_text": text})
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"headers", "mapping", "rows", "row_count", "skipped", "skipped_count",
                         "duplicate_count", "recurring_count", "sign_convention", "has_header"}
    assert body["headers"] == ["Date", "Description", "Amount"]
    assert (body["row_count"], body["skipped_count"], body["duplicate_count"]) == (1, 1, 0)
    row = body["rows"][0]
    assert (row["date"], row["description"], row["amount"], row["duplicate"]) == ("2026-01-05", "Coffee", -4.5, False)
    r = c.post(f"/api/accounts/{acc}/import/commit", json={"csv_text": text, "mapping": body["mapping"]})
    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True, "inserted": 1, "recurring_created": 0, "recurring_linked": 0,
                        "duplicates_skipped": 0, "total_rows": 1}
    # The same file again adds nothing.
    again = c.post(f"/api/accounts/{acc}/import/commit", json={"csv_text": text, "mapping": body["mapping"]})
    assert again.json()["inserted"] == 0 and again.json()["duplicates_skipped"] == 1


@pytest.mark.parametrize("route", ["preview", "commit"])
def test_a_file_pythons_csv_reader_refuses_is_a_400(app_started, route):
    c, acc = account(app_started)
    body = {"csv_text": "Date,Description,Amount\n2026-01-05,Coffee\rshop,-4\n", "mapping": {"date": 0}}
    r = c.post(f"/api/accounts/{acc}/import/{route}", json=body)
    assert r.status_code == 400, r.text
    assert r.json()["detail"].startswith("That file couldn't be read as CSV: new-line character seen")


def test_a_row_naming_a_tag_twice_imports_with_it_once(app_started):
    """#248: this used to fail the whole import on the join table's key."""
    c, acc = account(app_started)
    assert c.post("/api/tags", json={"name": "Work trip"}).status_code == 200
    text = 'Date,Description,Amount,Tags\n2026-01-05,Taxi,-20,"Work trip; work TRIP,Work trip"\n'
    r = c.post(f"/api/accounts/{acc}/import/commit", json={"csv_text": text, "mapping": {
        "date": 0, "description": 1, "amount": 2, "tags": 3}})
    assert r.status_code == 200, r.text
    assert r.json()["inserted"] == 1
    lines = c.get(f"/api/accounts/{acc}/transactions").json()
    assert [[t["name"] for t in line["tags"]] for line in lines if line["description"] == "Taxi"] == [["Work trip"]]
