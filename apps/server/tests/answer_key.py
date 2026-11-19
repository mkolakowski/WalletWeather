"""The answer key for the shared JavaScript core (Plans/standalone.md, #232).

Builds three households in the test database, asks today's server code for
its answers (`build_forecast`, `actual_balance_as_of`, `upcoming_dates`,
`calendar_events`), and writes each case as the rows the core is given and
the JSON the server produced. The cases live in packages/core/answer-key/,
where the server's tests and (from phase 3) the iPhone app's tests read them.

Database ids differ from run to run, so every id is renumbered in the order
the household created it (accounts, categories, tags, bills, lines and
transfers each count from 1).

Since phase 2 (#233) the server's answers come from the core itself, so
rebuilding the cases checks the whole path: the rows the server reads
(`app.forecast.rows_for_forecast`), the engine and the routes. Rewrite the
key only for a deliberate change to the answers, and say why in the commit.

Rewrite the committed cases after a deliberate change to the server's
answers with:
    docker compose -f docker-compose.test.yml run --rm -e WRITE_ANSWER_KEY=1 tests tests/test_core_answer_key.py
"""
from __future__ import annotations

import json
from contextlib import contextmanager
from datetime import date
from decimal import Decimal
from pathlib import Path

from fastapi.testclient import TestClient

from app.db import (AccountPermission, Category, RecurringSkip, RecurringTag, RecurringTransaction,
                    SavedReport, SessionLocal, Tag, Transaction, TransactionTag, Transfer, User)
from app.forecast import (actual_balance_as_of, build_forecast, recurring_accounts, recurring_row,
                          rows_for_forecast, search_rows)
import app.main as main
from app.main import _recurring_upcoming, _user_visible_accounts, calendar_events
from conftest import unique_email

KEY_DIR = Path(__file__).resolve().parents[3] / "packages" / "core" / "answer-key"
PASSWORD = "correct-horse-battery"


# ---------- Households ----------

class Household:
    """A user and the rows they own, with every id noted in creation order."""

    def __init__(self, app, db, name: str):
        self.name, self.db = name, db
        self.client = TestClient(app)
        r = self.client.post("/api/auth/register", json={"email": unique_email(), "password": PASSWORD})
        assert r.status_code == 200, r.text
        self.user = db.get(User, r.json()["id"])
        self.ids = {k: [] for k in ("acc", "cat", "tag", "rec", "txn", "transfer", "report")}
        self.accounts, self.cats, self.tags, self.recs = {}, {}, {}, {}
        # A new user starts with the default categories (and any tags):
        # they count first.
        for model, kind in ((Category, "cat"), (Tag, "tag")):
            self.ids[kind] += [row.id for row in db.query(model).filter_by(owner_id=self.user.id)
                               .order_by(model.id)]

    def _note(self, kind, obj):
        self.db.add(obj)
        self.db.flush()
        self.ids[kind].append(obj.id)
        return obj

    def account(self, name, balance, starting):
        r = self.client.post("/api/accounts", json={"name": name, "starting_balance": balance,
                                                    "starting_date": starting})
        assert r.status_code == 200, r.text
        self.ids["acc"].append(r.json()["id"])
        self.db.expire_all()
        acc = next(a for a in _user_visible_accounts(self.db, self.user) if a.id == r.json()["id"])
        self.accounts[name] = acc
        return acc

    def category(self, name, color=None):
        self.cats[name] = self._note("cat", Category(owner_id=self.user.id, name=name, color=color))
        return self.cats[name]

    def tag(self, name, color=None):
        self.tags[name] = self._note("tag", Tag(owner_id=self.user.id, name=name, color=color))
        return self.tags[name]

    def bill(self, key, account, description, amount, frequency, day_of_month=None, anchor=None,
             end=None, category=None, notes=None, active=True, tags=()):
        r = RecurringTransaction(account_id=account.id, frequency=frequency, day_of_month=day_of_month,
                                 anchor_date=date.fromisoformat(anchor) if anchor else None,
                                 end_date=date.fromisoformat(end) if end else None,
                                 category_id=self.cats[category].id if category else None, active=active)
        r.description, r.amount, r.notes = description, Decimal(amount), notes
        self._note("rec", r)
        for t in tags:
            self.db.add(RecurringTag(recurring_id=r.id, tag_id=self.tags[t].id))
        self.recs[key] = r
        return r

    def line(self, account, description, amount, forecast=None, actual=None, cleared=False,
             bill=None, forecast_amount=None, category=None, notes=None, tags=(), transfer=None,
             bank_ref=None, mail_ref=None, bank_match=None, bank_left=False):
        t = Transaction(account_id=account.id,
                        recurring_id=self.recs[bill].id if bill else None,
                        category_id=self.cats[category].id if category else None,
                        transfer_id=transfer.id if transfer else None,
                        forecast_date=date.fromisoformat(forecast) if forecast else None,
                        actual_date=date.fromisoformat(actual) if actual else None,
                        is_actual=cleared, bank_ref=bank_ref, mail_ref=mail_ref,
                        bank_match=bank_match, bank_left=bank_left)
        t.description, t.amount, t.notes = description, Decimal(amount), notes
        if forecast_amount is not None:
            t.forecast_amount = Decimal(forecast_amount)
        self._note("txn", t)
        for name in tags:
            self.db.add(TransactionTag(transaction_id=t.id, tag_id=self.tags[name].id))
        return t

    def skip(self, bill, day):
        self.db.add(RecurringSkip(recurring_id=self.recs[bill].id, skip_date=date.fromisoformat(day)))

    def transfer(self, from_acc, to_acc, day, amount, description="Transfer"):
        tr = Transfer(owner_id=self.user.id, from_account_id=from_acc.id, to_account_id=to_acc.id,
                      transfer_date=date.fromisoformat(day))
        tr.description, tr.amount = description, Decimal(amount)
        self._note("transfer", tr)
        self.line(from_acc, description, f"-{amount}", actual=day, cleared=True, transfer=tr)
        self.line(to_acc, description, amount, actual=day, cleared=True, transfer=tr)
        return tr

    # ----- the cases -----

    def forecast_case(self, account, start, end):
        db = self.db
        rows = rows_for_forecast(db, account)
        expected = build_forecast(db, account, date.fromisoformat(start), date.fromisoformat(end))
        return self._case(f"{account.name} {start} to {end}", "forecast",
                          {"start": start, "end": end, **rows}, expected)

    def balance_case(self, account, as_of):
        rows = rows_for_forecast(self.db, account, with_tags=False)
        expected = actual_balance_as_of(self.db, account, date.fromisoformat(as_of))
        return self._case(f"{account.name} balance on {as_of}", "actualBalanceAsOf",
                          {"as_of": as_of, **rows}, expected)

    def upcoming_cases(self, account, today):
        db = self.db
        recs = (db.query(RecurringTransaction).filter(RecurringTransaction.account_id == account.id)
                .order_by(RecurringTransaction.id).all())
        day = date.fromisoformat(today)
        answers = _recurring_upcoming(db, recs, day)
        cases = []
        for r in recs:
            skipped = sorted(d.isoformat() for (d,) in db.query(RecurringSkip.skip_date)
                             .filter(RecurringSkip.recurring_id == r.id, RecurringSkip.skip_date >= day))
            paid = sorted(d.isoformat() for (d,) in db.query(Transaction.forecast_date)
                          .filter(Transaction.recurring_id == r.id, Transaction.is_actual.is_(True),
                                  Transaction.forecast_date >= day))
            cases.append(self._case(f"{r.description} from {today}", "upcomingDates",
                                    {"today": today, "recurring": recurring_row(r, []),
                                     "skipped": skipped, "paid": paid},
                                    [d.isoformat() for d in answers[r.id]]))
        return cases

    def calendar_case(self, start, end, account=None):
        db = self.db
        visible = _user_visible_accounts(db, self.user)
        if account is not None:
            visible = [a for a in visible if a.id == account.id]
        cats = db.query(Category).filter_by(owner_id=self.user.id).order_by(Category.id).all()
        expected = calendar_events(date.fromisoformat(start), date.fromisoformat(end),
                                   account_id=account.id if account else None, user=self.user, db=db)
        return self._case(f"Calendar {start} to {end}" + (f", {account.name} only" if account else ""),
                          "calendar", {
                              "start": start, "end": end, "single_account": account is not None,
                              "categories": [{"id": c.id, "name": c.name, "color": c.color} for c in cats],
                              "accounts": [{"id": a.id, "name": a.name, **rows_for_forecast(db, a)}
                                           for a in visible],
                          }, expected)

    def _accounts(self):
        return [{"id": a.id, "name": a.name, **rows_for_forecast(self.db, a)}
                for a in _user_visible_accounts(self.db, self.user)]

    def _categories(self):
        return [{"id": c.id, "name": c.name, "color": c.color}
                for c in self.db.query(Category).filter_by(owner_id=self.user.id).order_by(Category.id)]

    def dashboard_case(self, today):
        with _any_today():
            expected = main.dashboard(today=date.fromisoformat(today), user=self.user, db=self.db)
        return self._case(f"Dashboard on {today}", "dashboard",
                          {"today": today, "accounts": self._accounts()}, expected)

    def charts_case(self, window, today):
        with _any_today():
            expected = main.dashboard_charts(window=window, today=date.fromisoformat(today),
                                             user=self.user, db=self.db)
        return self._case(f"Dashboard charts, {window}, on {today}", "dashboardCharts",
                          {"window": window, "today": today, "categories": self._categories(),
                           "accounts": self._accounts()}, expected)

    def report(self, name, pinned=False):
        return self._note("report", SavedReport(owner_id=self.user.id, name=name, params="{}", pinned=pinned,
                                                sort_order=len(self.ids["report"])))

    def _levels(self):
        return dict(self.db.query(AccountPermission.account_id, AccountPermission.level)
                    .filter(AccountPermission.user_id == self.user.id))

    def recurring_case(self, today, archived=False, account=None):
        """Bills & income (/api/recurring) on `today`."""
        db, day = self.db, date.fromisoformat(today)
        visible = [a for a in _user_visible_accounts(db, self.user) if account is None or a.id == account.id]
        with _any_today():
            expected = main.list_all_recurring(archived=archived, account_id=account.id if account else None,
                                               today=day, user=self.user, db=db)
        return self._case(f"Bills & income on {today}" + (", ended" if archived else "")
                          + (f", {account.name} only" if account else ""), "recurringList",
                          {"today": today, "archived": archived,
                           "accounts": recurring_accounts(db, visible, self._levels(), day)}, expected)

    def transaction_search_case(self, label, **filters):
        """/api/transactions/search with `filters` (ids as model objects)."""
        db = self.db
        visible = _user_visible_accounts(db, self.user)
        given = {k: (v.id if hasattr(v, "id") else v) for k, v in filters.items()}
        expected = main.search_transactions(**{"q": None, "account_id": None, "category_id": None, "tag_id": None,
                                               "date_from": None, "date_to": None, "min_amount": None,
                                               "max_amount": None, "kind": None, "include_transfers": True,
                                               "limit": 100, "offset": 0,
                                               **{k: date.fromisoformat(v) if k.startswith("date_") else v
                                                  for k, v in given.items()}},
                                            user=self.user, db=db)
        return self._case(f"Transaction search: {label}", "searchTransactions", {
            **given,
            "accounts": [{"id": a.id, "name": a.name} for a in visible],
            "transactions": search_rows(db, db.query(Transaction).filter(
                Transaction.account_id.in_([a.id for a in visible]))),
        }, expected)

    def search_case(self, q, today, limit=20):
        """/api/search for `q` on `today`."""
        db, day = self.db, date.fromisoformat(today)
        visible = _user_visible_accounts(db, self.user)
        accounts = recurring_accounts(db, visible, self._levels(), day)
        for row, a in zip(accounts, visible):
            row["current_balance"] = actual_balance_as_of(db, a, day)
        with _any_today():
            expected = main.search_everything(q=q, limit=limit, today=day, user=self.user, db=db)
        return self._case(f"Search {q!r} on {today}" + (f", {limit} a group" if limit != 20 else ""), "search", {
            "q": q, "limit": limit, "today": today, "accounts": accounts,
            "transactions": search_rows(db, db.query(Transaction).filter(
                Transaction.account_id.in_([a.id for a in visible]))),
            "categories": self._categories(),
            "tags": [{"id": t.id, "name": t.name, "color": t.color}
                     for t in db.query(Tag).filter_by(owner_id=self.user.id).order_by(Tag.id)],
            "reports": [{"id": r.id, "name": r.name, "pinned": bool(r.pinned)}
                        for r in db.query(SavedReport).filter_by(owner_id=self.user.id)
                        .order_by(SavedReport.sort_order.asc(), SavedReport.id.asc())],
        }, expected)

    def _case(self, name, function, given, expected):
        # A JSON round trip, so dates and Decimals are what a client would see.
        expected = json.loads(json.dumps(expected, default=str))
        # A transaction search answers {total, results: [lines]}.
        kind = "txn" if function == "searchTransactions" else None
        return {"name": name, "function": function,
                "input": self.renumber(given), "expected": self.renumber(expected, kind)}

    def renumber(self, value, kind=None):
        """Replace every database id with its place in creation order."""
        maps = {k: {v: i + 1 for i, v in enumerate(ids)} for k, ids in self.ids.items()}
        by_key = {"transaction_id": "txn", "recurring_id": "rec", "transfer_id": "transfer",
                  "category_id": "cat", "account_id": "acc"}
        lists = {"transactions": "txn", "recurring": "rec", "tags": "tag", "categories": "cat",
                 "accounts": "acc", "cards": "acc", "reports": "report", "items": "rec"}
        by_key["tag_id"] = "tag"

        def walk(v, kind):
            if isinstance(v, dict):
                out = {}
                for k, x in v.items():
                    if k == "id" and kind:
                        out[k] = maps[kind][x]
                    elif k == "results" and kind:
                        # A search group ({total, results}) holds the kind of its name.
                        out[k] = walk(x, kind)
                    elif k in by_key and x is not None:
                        out[k] = maps[by_key[k]][x]
                    elif k in lists:
                        out[k] = walk(x, lists[k])
                    else:
                        out[k] = walk(x, None)
                return out
            if isinstance(v, list):
                return [walk(x, kind) for x in v]
            return v
        return walk(value, kind)


@contextmanager
def _any_today():
    """Let the routes take a date far from the server's (they refuse one
    more than a day off, as a viewer's own date can't be)."""
    real = main._viewer_today
    main._viewer_today = lambda today: today or date.today()
    try:
        yield
    finally:
        main._viewer_today = real


def _basics(app, db) -> list:
    """One checking account: bills of every rhythm, paid, late, changed,
    skipped and switched-off dates, bank and alert lines, sub-cent amounts."""
    h = Household(app, db, "basics")
    for name, color in (("Bills", "#e5534b"), ("Income", "#3fb950"), ("Fun", None)):
        h.category(name, color)
    for name, color in (("home", "#58a6ff"), ("Autopay", None), ("zeta", "#aaaaaa")):
        h.tag(name, color)
    acc = h.account("Checking", 1000, "2026-01-01")
    h.bill("rent", acc, "Rent", "-1500.00", "monthly_day", day_of_month=1, category="Bills",
           tags=("home", "Autopay"))
    h.bill("pay", acc, "Paycheck", "2000.00", "biweekly", anchor="2026-01-09", category="Income")
    h.bill("phone", acc, "Phone", "-65.43", "monthly_day", day_of_month=31, category="Bills",
           notes="family plan")
    h.bill("gym", acc, "Gym", "-12.50", "weekly", anchor="2026-02-03", end="2026-04-15", category="Fun")
    h.bill("insurance", acc, "Insurance", "-120.10", "monthly_day", day_of_month=15, anchor="2026-03-10")
    h.bill("magazine", acc, "Old magazine", "-9.99", "monthly_day", day_of_month=20, active=False)

    h.line(acc, "Coffee", "-4.75", actual="2026-01-03", cleared=True, category="Fun", tags=("zeta", "home"))
    h.line(acc, "Rent", "-1500.00", forecast="2026-02-01", actual="2026-02-03", cleared=True, bill="rent",
           forecast_amount="-1500.00", category="Bills")
    h.line(acc, "Phone", "-70.01", forecast="2026-02-28", actual="2026-03-02", cleared=True, bill="phone",
           forecast_amount="-65.43", category="Bills")
    h.line(acc, "Car repair", "-300.00", forecast="2026-03-12", notes="estimate")
    h.line(acc, "Paycheck", "2100.00", forecast="2026-02-20", bill="pay", forecast_amount="2000.00",
           category="Income")
    h.line(acc, "Cashback", "0.1", actual="2026-02-10", cleared=True)
    h.line(acc, "Cashback", "0.2", actual="2026-02-11", cleared=True)
    h.line(acc, "Interest", "10.005", actual="2026-02-27", cleared=True)
    h.line(acc, "Refund expected", "25.00", forecast="2026-03-05", actual="2026-03-06", cleared=True,
           forecast_amount="0")
    h.line(acc, "Odd line", "-5.00", forecast="2026-02-14", cleared=True)
    h.line(acc, "AMZN Mktp", "-42.17", actual="2026-02-16", cleared=True, bank_ref="b1")
    h.line(acc, "Rent", "-1500.00", forecast="2026-03-01", actual="2026-03-01", cleared=True, bill="rent",
           forecast_amount="-1500.00", mail_ref="m1", bank_match="auto", category="Bills")
    h.line(acc, "Parking", "-8.00", actual="2026-03-20", cleared=True, bank_ref="b3", bank_left=True)
    h.line(acc, "Example Internet", "-59.99", actual="2026-03-21", cleared=True, bank_ref="b4",
           bank_match="hand", bill="phone", forecast="2026-03-31")
    h.skip("pay", "2026-03-06")
    h.skip("gym", "2026-02-17")
    db.flush()

    cases = [h.forecast_case(acc, s, e) for s, e in (
        ("2025-12-01", "2025-12-31"), ("2026-01-01", "2026-01-31"), ("2026-02-01", "2026-02-28"),
        ("2026-03-01", "2026-03-31"), ("2026-04-01", "2026-04-30"), ("2026-02-15", "2026-05-16"))]
    cases += [h.balance_case(acc, d) for d in ("2026-02-15", "2026-02-28", "2026-03-01", "2026-03-31")]
    cases += h.upcoming_cases(acc, "2026-02-15") + h.upcoming_cases(acc, "2026-03-01")
    cases += [h.calendar_case("2026-02-01", "2026-02-28", acc), h.calendar_case("2026-03-01", "2026-03-31")]
    cases += [h.dashboard_case(d) for d in ("2026-02-15", "2026-03-31")]
    cases += [h.charts_case(w, "2026-03-15") for w in ("month", "30d", "90d")]
    cases += [h.recurring_case("2026-02-15"), h.recurring_case("2026-05-01"),
              h.recurring_case("2026-05-01", archived=True)]
    cases += [h.transaction_search_case(label, **f) for label, f in (
        ("everything", {}), ("rent", {"q": "rent"}), ("padded upper case", {"q": "  PHONE "}),
        ("notes", {"q": "ESTIMATE"}), ("spending", {"kind": "spending"}), ("income", {"kind": "income"}),
        ("a category", {"category_id": h.cats["Bills"]}), ("a tag", {"tag_id": h.tags["home"]}),
        ("February", {"date_from": "2026-02-01", "date_to": "2026-02-28"}),
        ("amounts", {"min_amount": -100, "max_amount": 0.15}), ("a page", {"limit": 3, "offset": 2}),
        ("past the end", {"limit": 5, "offset": 50}), ("no limit below one", {"limit": 0}),
        ("an account", {"account_id": acc, "q": "pay"}))]
    cases += [h.search_case(q, "2026-03-01") for q in ("rent", "family", "check", "bills", "AUTO", "  ", "zzz")]
    cases += [h.search_case("e", "2026-03-01", limit=2), h.search_case("gym", "2026-05-01")]
    return cases


def _edges(app, db) -> list:
    """Leap days, month ends that clamp, a year boundary, an item that
    starts after the window opens, and a balance that rounds on a tie."""
    h = Household(app, db, "edges")
    acc = h.account("Leap", "250.50", "2027-12-01")
    h.bill("d29", acc, "On the 29th", "-100", "monthly_day", day_of_month=29)
    h.bill("d30", acc, "On the 30th", "-30", "monthly_day", day_of_month=30)
    h.bill("weekly", acc, "Weekly", "1", "weekly", anchor="2028-02-26")
    h.bill("late", acc, "Starts later", "-7.77", "biweekly", anchor="2028-03-15")
    h.bill("d31", acc, "On the 31st", "-31", "monthly_day", day_of_month=31, end="2028-02-29")
    h.line(acc, "New Year", "-50", forecast="2027-12-31", actual="2028-01-02", cleared=True)
    h.line(acc, "Eighths", "-0.375", actual="2028-01-05", cleared=True)
    h.line(acc, "Pending eighths", "-0.25", forecast="2028-02-29")
    db.flush()
    cases = [h.forecast_case(acc, s, e) for s, e in (
        ("2027-12-01", "2027-12-31"), ("2027-12-15", "2028-01-15"), ("2028-01-01", "2028-01-31"),
        ("2028-02-01", "2028-02-29"), ("2028-03-01", "2028-03-31"), ("2029-02-01", "2029-02-28"),
        ("2028-01-01", "2028-12-31"))]
    cases += [h.balance_case(acc, d) for d in ("2028-01-05", "2028-01-31", "2028-02-29", "2029-02-28")]
    cases += h.upcoming_cases(acc, "2028-02-20")
    cases.append(h.calendar_case("2028-02-01", "2028-03-15", acc))
    cases += [h.dashboard_case("2028-02-29"), h.charts_case("90d", "2028-03-01"),
              h.charts_case("month", "2027-12-31")]
    return cases


def _two_accounts(app, db) -> list:
    """Two accounts with a transfer between them, and descriptions that sort
    by case and beyond ASCII."""
    h = Household(app, db, "two accounts")
    h.category("Bills", "#e5534b")
    h.category("Food")
    h.tag("trip")
    chk = h.account("Checking", 500, "2026-04-01")
    sav = h.account("Savings", 10000, "2026-04-01")
    h.account("Empty", "0.1", "2026-04-01")
    h.bill("rent", chk, "Rent", "-800", "monthly_day", day_of_month=1, category="Bills")
    h.bill("interest", sav, "Interest", "12.34", "monthly_day", day_of_month=28)
    h.transfer(chk, sav, "2026-05-10", "250.00", "To savings")
    for desc in ("zebra", "Apple", "Éclair café", "\U0001F355 Pizza", "apple pie"):
        h.line(chk, desc, "-3.21", forecast="2026-05-12", category="Food", tags=("trip",))
    db.flush()
    cases = [h.forecast_case(a, "2026-05-01", "2026-05-31") for a in (chk, sav)]
    cases += [h.calendar_case("2026-05-01", "2026-05-31"), h.calendar_case("2026-05-01", "2026-05-31", chk),
              h.calendar_case("2026-04-15", "2026-06-15", sav)]
    cases += [h.dashboard_case("2026-05-12"), h.dashboard_case("2026-04-10"),
              h.charts_case("month", "2026-05-20"), h.charts_case("30d", "2026-05-20")]
    return cases


def _words(app, db) -> list:
    """Searching: names beyond ASCII (ß, final sigma, the dotless ı, an
    emoji), notes, a transfer, ended and switched-off items on two
    accounts, and saved reports."""
    h = Household(app, db, "words")
    h.category("Straße & Co", "#123456")
    h.category("ΟΔΟΣ")
    h.category("Fun")
    h.tag("Iğdır trip", "#00ff00")
    h.tag("istanbul")
    h.tag("Ünder")
    chk = h.account("Checking", "100.10", "2026-06-01")
    sav = h.account("Savings ΣΑΣ", 5000, "2026-06-01")
    h.bill("rent", chk, "Rent on Straße", "-950", "monthly_day", day_of_month=3, category="Straße & Co",
           notes="landlord: Jürgen", tags=("Ünder", "istanbul"))
    h.bill("old", chk, "rent (old flat)", "-700", "monthly_day", day_of_month=3, end="2026-06-30")
    h.bill("paused", chk, "Paused STRASSE fee", "-5", "weekly", anchor="2026-06-02", active=False)
    h.bill("pay", sav, "Pay", "1234.56", "biweekly", anchor="2026-06-05", notes="via ΟΔΟΣ bank")
    h.bill("odd", sav, "Yearly thing", "-99", "yearly")
    h.line(chk, "Café Straße", "-4.20", actual="2026-06-10", cleared=True, category="Straße & Co",
           tags=("Iğdır trip",))
    h.line(chk, "strasse parking", "-3", forecast="2026-06-20", notes="meter")
    h.line(chk, "İstanbul tickets", "-310", forecast="2026-07-01", actual="2026-07-02", cleared=True,
           category="Fun", tags=("istanbul", "Iğdır trip"))
    h.line(chk, "\U0001F355 pizza", "-12", actual="2026-06-10", cleared=True, notes="ΣΑΣ")
    h.line(chk, "Rent on Straße", "-950", forecast="2026-07-03", actual="2026-07-03", cleared=True,
           bill="rent", forecast_amount="-950")
    h.line(sav, "Pay", "1234.56", forecast="2026-06-19", actual="2026-06-19", cleared=True, bill="pay")
    h.line(sav, "no notes", "0", forecast="2026-06-25")
    h.transfer(chk, sav, "2026-06-15", "50.00", "To savings")
    h.skip("rent", "2026-08-03")
    h.report("Monthly Straße")
    h.report("Fun times", pinned=True)
    db.flush()
    cases = [h.recurring_case("2026-07-01"), h.recurring_case("2026-07-01", archived=True),
             h.recurring_case("2026-07-01", account=sav), h.recurring_case("2026-06-01")]
    cases += [h.transaction_search_case(label, **f) for label, f in (
        ("ß", {"q": "STRASSE"}), ("ß typed", {"q": "straße"}), ("dotted İ", {"q": "i̇stanbul"}),
        ("emoji", {"q": "\U0001F355"}), ("transfers", {"kind": "transfers"}),
        ("no transfers", {"include_transfers": False}), ("a tag and words", {"tag_id": h.tags["istanbul"], "q": "tick"}),
        ("from a date", {"date_from": "2026-06-20"}), ("up to a date", {"date_to": "2026-06-15"}))]
    cases += [h.search_case(q, "2026-07-01") for q in (
        "STRASSE", "straße", "ς", "σας", "ı", "I", "istanbul", "İSTANBUL", "ünder", "to savings", "fun",
        "\U0001F355", "rent", "Jürgen", "monthly")]
    return cases


HOUSEHOLDS = {"basics": _basics, "edges": _edges, "two-accounts": _two_accounts, "words": _words}


def build_cases(app) -> dict[str, list]:
    """Every household's cases, from today's server code. Nothing is kept:
    the rows are rolled back afterwards."""
    out = {}
    db = SessionLocal()
    try:
        for name, make in HOUSEHOLDS.items():
            out[name] = make(app, db)
    finally:
        db.rollback()
        db.close()
    return out


def write(cases: dict[str, list]) -> None:
    KEY_DIR.mkdir(parents=True, exist_ok=True)
    for name, items in cases.items():
        (KEY_DIR / f"{name}.json").write_text(
            json.dumps({"household": name, "cases": items}, indent=1, ensure_ascii=False) + "\n")


def load() -> dict[str, list]:
    return {p.stem: json.loads(p.read_text())["cases"] for p in sorted(KEY_DIR.glob("*.json"))}
