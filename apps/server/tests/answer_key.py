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

from app.csv_import import csv_rows
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
             end=None, category=None, notes=None, active=True, tags=(), match_days=None,
             match_percent=None, match_text=None):
        r = RecurringTransaction(account_id=account.id, frequency=frequency, day_of_month=day_of_month,
                                 anchor_date=date.fromisoformat(anchor) if anchor else None,
                                 end_date=date.fromisoformat(end) if end else None,
                                 category_id=self.cats[category].id if category else None, active=active)
        r.description, r.amount, r.notes = description, Decimal(amount), notes
        if match_days is not None:
            r.match_days = match_days
        if match_percent is not None:
            r.match_percent = match_percent
        r.match_text = match_text
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

    def csv_case(self, label, account, body, commit=False):
        """CSV import (#243): /import/preview, or /import/commit and the rows
        it made (new bills in id order, then new lines with the bill each
        links to: one made by this import by its place, or an earlier one)."""
        db = self.db
        given = {**body, **csv_rows(db, self.user, account)}
        if not commit:
            expected = main.csv_import_preview(account.id, main.CSVPreviewIn(**body), user=self.user, db=db)
            return self._case(f"CSV preview: {label}", "csvPreview", given, expected)

        def last(model):
            return max([row.id for row in db.query(model).filter(model.account_id == account.id)] or [0])
        rec_from, txn_from = last(RecurringTransaction), last(Transaction)
        real_commit, db.commit = db.commit, db.flush   # keep the household's rows in one rollback
        try:
            result = main.csv_import_commit(account.id, main.CSVCommitIn(**body), user=self.user, db=db)
        finally:
            db.commit = real_commit
        db.flush()
        recs = (db.query(RecurringTransaction).filter(RecurringTransaction.account_id == account.id,
                                                      RecurringTransaction.id > rec_from)
                .order_by(RecurringTransaction.id).all())
        txns = (db.query(Transaction).filter(Transaction.account_id == account.id, Transaction.id > txn_from)
                .order_by(Transaction.id).all())
        made = {r.id: i for i, r in enumerate(recs)}
        expected = {
            "result": result,
            "templates": [{"category_id": r.category_id, "frequency": r.frequency, "day_of_month": r.day_of_month,
                           "anchor_date": r.anchor_date.isoformat() if r.anchor_date else None,
                           "end_date": r.end_date.isoformat() if r.end_date else None,
                           "description": r.description, "amount": float(r.amount), "notes": r.notes}
                          for r in recs],
            "transactions": [{"date": t.actual_date.isoformat(), "description": t.description,
                              "amount": float(t.amount), "notes": t.notes, "category_id": t.category_id,
                              "recurring": (None if t.recurring_id is None else
                                            {"new": made[t.recurring_id]} if t.recurring_id in made
                                            else {"id": t.recurring_id}),
                              "tag_ids": [tid for (tid,) in db.query(TransactionTag.tag_id)
                                          .filter_by(transaction_id=t.id).order_by(TransactionTag.tag_id)]}
                             for t in txns],
        }
        case = self._case(f"CSV import: {label}", "csvCommit", given, expected)
        # What this import made is part of the household from here on.
        self.ids["rec"] += [r.id for r in recs]
        self.ids["txn"] += [t.id for t in txns]
        return case

    # ----- bank matching (#239) -----

    def match_rows(self, account) -> dict:
        """The matching functions' input: every bill on the account (active or
        not) with its match settings, their deleted dates and every line, the
        amounts as the server's Decimals write them."""
        db = self.db
        recs = (db.query(RecurringTransaction).filter(RecurringTransaction.account_id == account.id)
                .order_by(RecurringTransaction.id).all())
        skips = [{"recurring_id": rid, "date": d.isoformat()} for rid, d in (
            db.query(RecurringSkip.recurring_id, RecurringSkip.skip_date)
            .filter(RecurringSkip.recurring_id.in_([r.id for r in recs] or [0]))
            .order_by(RecurringSkip.recurring_id, RecurringSkip.skip_date))]
        txns = db.query(Transaction).filter(Transaction.account_id == account.id).order_by(Transaction.id)
        iso = lambda d: d.isoformat() if d else None  # noqa: E731
        return {
            "recurring": [{"id": r.id, "frequency": r.frequency, "day_of_month": r.day_of_month,
                           "anchor_date": iso(r.anchor_date), "end_date": iso(r.end_date), "active": r.active,
                           "description": r.description, "amount": str(r.amount), "match_days": r.match_days,
                           "match_percent": r.match_percent, "match_text": r.match_text} for r in recs],
            "skips": skips,
            "transactions": [{"id": t.id, "recurring_id": t.recurring_id, "transfer_id": t.transfer_id,
                              "description": t.description, "notes": t.notes, "amount": str(t.amount),
                              "forecast_date": iso(t.forecast_date), "actual_date": iso(t.actual_date),
                              "is_actual": t.is_actual, "bank_match": t.bank_match,
                              "has_bank_ref": bool(t.bank_ref), "has_mail_ref": bool(t.mail_ref),
                              "bank_left": bool(t.bank_left)} for t in txns],
        }

    def bank_match_case(self, label, account, lines):
        """Bank sync's matching (main._bank_sync_locked) of new bank lines
        [(date, amount, the bank's text)], in order: the bill date each pays."""
        bills = main._bills_to_match(self.db, account.id)
        expected = []
        for day, amount, raw in lines:
            short = main.simplefin.short_name(raw)
            hit = main._bill_for_bank_line(bills, date.fromisoformat(day), Decimal(amount), short or raw)
            if hit:
                bills["covered"].add((hit[0].id, hit[1]))
                expected.append({"recurring_id": hit[0].id, "forecast_date": hit[1].isoformat()})
            else:
                expected.append(None)
        return self._case(f"Bank match: {label}", "bankMatch", {
            **self.match_rows(account),
            "lines": [{"date": d, "amount": a, "text": t} for d, a, t in lines]}, expected)

    def unmatched_case(self, account):
        expected = main.bank_unmatched(account.id, user=self.user, db=self.db)
        return self._case(f"Unmatched list of {account.name}", "bankUnmatched",
                          {"transactions": self.match_rows(account)["transactions"]}, expected)

    def candidates_case(self, label, account, line):
        expected = main.bank_unmatched_candidates(account.id, line.id, user=self.user, db=self.db)
        return self._case(f"Match candidates: {label}", "bankCandidates",
                          {**self.match_rows(account), "transaction_id": line.id}, expected)

    def near_case(self, label, account, line=None, bill=None, day=None):
        planned = ({"transaction_id": line.id} if line is not None
                   else {"recurring_id": self.recs[bill].id, "forecast_date": day})
        expected = main.bank_unmatched_near(account.id, transaction_id=planned.get("transaction_id"),
                                            recurring_id=planned.get("recurring_id"),
                                            forecast_date=date.fromisoformat(day) if day else None,
                                            user=self.user, db=self.db)
        return self._case(f"Unmatched lines near: {label}", "bankNear",
                          {**self.match_rows(account), "planned": planned}, expected)

    def catch_up_case(self, label, account, bill, name):
        """Teaching `bill` the name `name` (matching by hand with "remember"):
        the Unmatched lines that then pay its dates. Rolled back afterwards."""
        db, rec = self.db, self.recs[bill]
        nested = db.begin_nested()
        try:
            rec.match_text = name
            db.flush()
            given = {**self.match_rows(account), "recurring_id": rec.id}
            before = {t.id: (t.bank_ref, t.mail_ref) for t in main._unmatched_query(db, account.id)}
            last = max(t["id"] for t in given["transactions"])
            main._catch_up_taught(db, account, rec)
            db.flush()
            made = (db.query(Transaction).filter(Transaction.account_id == account.id, Transaction.id > last)
                    .order_by(Transaction.id).all())
            by_ref = {refs: tid for tid, refs in before.items()}
            expected = [{"transaction_id": by_ref[(t.bank_ref, t.mail_ref)],
                         "forecast_date": t.forecast_date.isoformat()} for t in made]
        finally:
            nested.rollback()
        db.expire_all()
        return self._case(f"Catch up after teaching: {label}", "bankCatchUp", given, expected)

    def _case(self, name, function, given, expected):
        # A JSON round trip, so dates and Decimals are what a client would see.
        expected = json.loads(json.dumps(expected, default=str))
        # A transaction search answers {total, results: [lines]}.
        kind = "txn" if function == "searchTransactions" else None
        # The bank matching's lines (and the one line) are transactions.
        extra = {"line": "txn", "lines": "txn"} if function.startswith("bank") else {}
        return {"name": name, "function": function,
                "input": self.renumber(given, extra=extra), "expected": self.renumber(expected, kind, extra)}

    def renumber(self, value, kind=None, extra=None):
        """Replace every database id with its place in creation order."""
        maps = {k: {v: i + 1 for i, v in enumerate(ids)} for k, ids in self.ids.items()}
        by_key = {"transaction_id": "txn", "recurring_id": "rec", "transfer_id": "transfer",
                  "category_id": "cat", "account_id": "acc", "default_category_id": "cat"}
        lists = {"transactions": "txn", "recurring": "rec", "tags": "tag", "categories": "cat",
                 "accounts": "acc", "cards": "acc", "reports": "report", "items": "rec"}
        by_key["tag_id"] = "tag"
        lists = {**lists, **(extra or {})}

        def walk(v, kind):
            if isinstance(v, dict):
                out = {}
                for k, x in v.items():
                    if k == "id" and kind:
                        out[k] = maps[kind][x]
                    elif k == "results" and kind:
                        # A search group ({total, results}) holds the kind of its name.
                        out[k] = walk(x, kind)
                    elif k == "tag_ids":
                        out[k] = [maps["tag"][t] for t in x]
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


def _imports(app, db) -> list:
    """CSV import (#243): bank exports with every column, quoting the way
    Python's csv reader takes it, dates and amounts in every accepted form
    (and some that aren't), debit and credit columns, a file with no header,
    repeating rows linked to a bill old and new, duplicates of lines already
    there and within the file, and the same file imported twice."""
    h = Household(app, db, "imports")
    h.category("groceries")          # two categories that match "Groceries"
    h.tag("reimbursable")
    h.tag("Work Trip")
    chk = h.account("Checking", "1000", "2026-01-01")
    card = h.account("Card", "-250", "2026-01-01")
    h.bill("stream", chk, "Streaming service", "-15.99", "monthly_day", day_of_month=1)
    h.line(chk, "  COFFEE shop ", "-4.5", actual="2026-01-05", cleared=True)
    h.line(chk, "Planned rent", "-900", forecast="2026-02-01")
    h.line(chk, "No date at all", "-1")
    db.flush()

    bank = "\r\n".join([
        "Date,Description,Amount,Category,Tags,Notes",
        "2026-01-05,Coffee Shop,-4.50,Dining,,",                     # a line already there
        '01/07/2026,"Grocery store, Main St",-84.23, groceries ,reimbursable; work trip ,  ',
        '1/9/2026,"Says ""hi""",$1,234.56,Income,,paid',
        '2026-01-10,"Two\r\nlines",(12.00),Unknown,nope,"note, with comma"',
        "13/01/2026,Day first,€5,,,",
        "02/30/2026,Not a day,-1,,,",
        "Jan 15, 2026,Month name,-2,,,",
        '"Jan 16, 2026",Quoted month name,-3,,,',
        "16 Jan 2026,Day month year,-4,,,",
        "",
        "2026-01-17,No amount,,,,",
        "someday,Bad date,-5,,,",
        "2026-01-18,,-6,,,",
        "2026-01-19,Short row",
        "2026-01-20,Café Straße \U0001F355,-7.25,,reimbursable;Work Trip,",
        "2026-01-20,Café Straße \U0001F355,-7.25,,,",          # the same line twice in one file
        "2026-01-21," + "x" * 520 + ",-8,,,",
        '2026-01-22,"unterminated, quote,-9',
        "",
    ])
    cards = "\n".join([
        "Posted Date,Payee,Withdrawal,Deposit",
        "2026-01-03,Hardware,25.00,",
        "2026-01-04,Refund,,10.50",
        "2026-01-05,Both,3,1",
        "2026-01-06,Neither,,",
        "2026-01-07,Zeroes,0,0.00",
        "2026-01-08,Negative withdrawal,-2,",
    ])
    bare = "\n".join([
        "1/5/26,Bakery,12.5",
        "12/31/69,Old,1",
        "1/1/68,New,1",
        "2026-1-5,Single digits,2",
        "1-5-2026,Dashes,3",
        "2026/01/06,Slashes,4",
        "05-01-2026,Day first dashes,5",
        "sep 3, 2026,Lower month,6",
        "SEP  4, 2026,Two spaces,7",
        "2026-02-29,Not a leap day,8",
        "2028-02-29,Leap day,9",
        "\u0662\u0660\u0662\u0666-\u0660\u0661-\u0660\u0665,Other digits,\u0661\u0662\u0663",
    ])
    numbers = "\n".join([
        "date,memo,value",
        "2026-03-01,underscores,1_000",
        "2026-03-01,exponent,1e3",
        "2026-03-01,not a number,nan",
        "2026-03-01,infinite,-inf",
        "2026-03-01,too big,1e13",
        "2026-03-01,just a sign,-",
        "2026-03-01,plus,+5",
        "2026-03-01,leading point,.5",
        "2026-03-01,trailing point,5.",
        "2026-03-01,spaced, ( 3.50 ) ",
        "2026-03-01,pounds,£1,000",
        "2026-03-01,double underscore,1__0",
        "2026-03-01,thin space,1\u20092",
        "2026-03-01,zero in brackets,(0)",
        "2026-03-01,tiny,0.004",
        "2026-03-01,half cent,2.675",
    ])
    repeating = "\n".join([
        "Date,Description,Amount,Category,Frequency,End Date,Recurring Group",
        "2026-01-01,Streaming service,-15.99,Subscriptions,Monthly,,",
        "2026-02-01,streaming SERVICE,-17.99,,monthly,,",
        "2026-01-02,Gym JAN,-39,,Monthly,2026-12-31,gym",
        "2026-02-02,Gym FEB,-41,Fun,monthly,,GYM",
        "2026-01-03,Allowance,20,,bi-weekly,,",
        "2026-01-17,Allowance,20,,every 2 weeks,,",
        "2026-01-04,Lawn,-30,,Weekly,,",
        "2026-01-05,Taxes,-500,,quarterly,,",
        "2026-01-06,Once,-1,,,,",
    ])

    cases = [
        h.csv_case("a bank's export", chk, {"csv_text": bank}),
        h.csv_case("debit and credit", card, {"csv_text": cards, "sign_convention": "debit_credit"}),
        h.csv_case("no header, columns given, signs flipped", chk, {
            "csv_text": bare, "has_header": False, "sign_convention": "amount_invert",
            "mapping": {"date": 0, "description": 1, "amount": 2, "notes": 7, "category": -1}}),
        h.csv_case("numbers", chk, {"csv_text": numbers}),
        h.csv_case("repeating rows", chk, {"csv_text": repeating}),
        h.csv_case("a blank first line", chk, {"csv_text": "\nDate,Description,Amount\n2026-01-05,x,1\n"}),
        h.csv_case("only a header", chk, {"csv_text": "Date,Amount\n"}),
    ]
    utilities = h.db.query(Category).filter_by(owner_id=h.user.id, name="Utilities").first()
    detected = cases[0]["expected"]["mapping"]
    cases += [
        h.csv_case("a bank's export, a default category", chk, {
            "csv_text": bank, "mapping": detected, "default_category_id": utilities.id}, commit=True),
        h.csv_case("the same file again", chk, {
            "csv_text": bank, "mapping": detected, "default_category_id": utilities.id}, commit=True),
        h.csv_case("repeating rows", chk, {
            "csv_text": repeating, "mapping": cases[4]["expected"]["mapping"]}, commit=True),
        h.csv_case("repeating rows again, duplicates kept", chk, {
            "csv_text": repeating, "mapping": cases[4]["expected"]["mapping"], "skip_duplicates": False},
            commit=True),
        h.csv_case("debit and credit", card, {
            "csv_text": cards, "mapping": cases[1]["expected"]["mapping"], "sign_convention": "debit_credit"},
            commit=True),
        h.csv_case("after importing", chk, {"csv_text": bank}),
    ]
    return cases


def _matching(app, db) -> list:
    """Bank matching (#239): which bill a bank line pays (exact, within a
    bill's days and percent and just outside, the nearest date, a tie, a
    taught name at any amount and winning a tie, money in and out, a paid,
    deleted or switched-off bill's date, one line after another), the
    Unmatched list (bank and email alert lines, and lines that aren't on
    it), the match pop-in's candidates and choices (with a one-off planned
    line), the Unmatched lines near a planned line, and the lines a newly
    taught name catches up."""
    h = Household(app, db, "matching")
    acc = h.account("Checking", "2500", "2026-08-01")
    h.bill("rent", acc, "Rent", "-1500.00", "monthly_day", day_of_month=1)
    h.bill("phone", acc, "Phone", "-65.43", "monthly_day", day_of_month=15, match_days=3, match_percent=5)
    h.bill("internet", acc, "Internet", "-59.99", "monthly_day", day_of_month=20, match_text="EXAMPLE INTERNET*123")
    h.bill("gym", acc, "Gym", "-30.00", "weekly", anchor="2026-09-02")
    h.bill("club", acc, "Climbing club", "-31.00", "weekly", anchor="2026-09-02")
    h.bill("pay", acc, "Paycheck", "2000.00", "biweekly", anchor="2026-09-04")
    h.bill("stream_a", acc, "Streaming A", "-15.99", "monthly_day", day_of_month=10, match_text="StreamCo")
    h.bill("stream_b", acc, "streaming B", "-15.99", "monthly_day", day_of_month=10)
    h.bill("old", acc, "Old magazine", "-9.99", "monthly_day", day_of_month=5, active=False)
    h.bill("insurance", acc, "Insurance", "-100.005", "biweekly", anchor="2026-09-01", match_days=10)
    h.bill("water", acc, "Water", "-40", "monthly_day", day_of_month=25)
    h.bill("ended", acc, "Ended plan", "-20", "monthly_day", day_of_month=3, end="2026-08-31")
    h.skip("rent", "2026-10-01")
    h.skip("old", "2026-10-05")
    # Paid and planned lines.
    h.line(acc, "Phone", "-66.00", forecast="2026-09-15", actual="2026-09-15", cleared=True, bill="phone",
           forecast_amount="-65.43", bank_ref="p1", bank_match="auto")
    repair = h.line(acc, "Car repair", "-300", forecast="2026-09-12")
    h.line(acc, "Rent (planned early)", "-1500.00", forecast="2026-11-01", bill="rent")
    h.line(acc, "Coffee", "-4.50", actual="2026-09-03", cleared=True)
    # Synced lines: on the Unmatched list or not.
    shop = h.line(acc, "Car repair shop", "-310.00", forecast="2026-09-13", actual="2026-09-13", cleared=True,
                  bank_ref="b1", notes="POS Withdrawal Car repair shop / ID: 99812")
    h.line(acc, "CITY WATER #4411", "-41.00", forecast="2026-09-26", actual="2026-09-26", cleared=True,
           bank_ref="b2")
    h.line(acc, "City Water", "-45", forecast="2026-10-24", actual="2026-10-24", cleared=True,
           notes="Withdrawal City Water / ACH Trace Number: 7", bank_ref="b3")
    h.line(acc, "City water refund", "40", forecast="2026-10-25", actual="2026-10-25", cleared=True, bank_ref="b4")
    h.line(acc, "CITY  WATER", "-40", forecast="2026-12-01", actual="2026-12-01", cleared=True, bank_ref="b5")
    alert = h.line(acc, "Card ending 1234", "-30.00", forecast="2026-09-09", actual="2026-09-09", cleared=True,
                   mail_ref="m1")
    h.line(acc, "Parking", "-8.00", forecast="2026-09-20", actual="2026-09-20", cleared=True, bank_ref="b6",
           bank_left=True)
    h.line(acc, "Example Internet", "-59.99", forecast="2026-09-20", actual="2026-09-21", cleared=True,
           bank_ref="b7", bank_match="hand", bill="internet")
    h.line(acc, "Not yet posted", "-12", forecast="2026-09-22", bank_ref="b8")
    h.line(acc, "No posted date", "-1.25", forecast="2026-09-24", cleared=True, bank_ref="b9")
    db.flush()

    cases = [
        h.bank_match_case("exact amounts on the day", acc, [
            ("2026-09-01", "-1500.00", "RENT PAYMENT"), ("2026-09-04", "2000", "PAYROLL / ACME")]),
        h.bank_match_case("within a bill's days and percent", acc, [
            ("2026-10-18", "-68.70", "Phone Co"), ("2026-09-06", "-1650.00", "Landlord")]),
        h.bank_match_case("just outside", acc, [
            ("2026-10-15", "-68.71", "Phone Co"), ("2026-10-11", "-65.43", "Phone Co"),
            ("2026-09-06", "-1650.01", "Landlord"), ("2026-09-07", "-1500", "Landlord")]),
        h.bank_match_case("the nearest date", acc, [("2026-09-06", "-100.00", "Insurer")]),
        h.bank_match_case("a tie", acc, [("2026-09-09", "-30.50", "GYM OR CLUB"),
                                         ("2026-09-10", "-15.99", "Some stream")]),
        h.bank_match_case("a taught name wins a tie", acc, [("2026-09-10", "-15.99", "STREAMCO*99X1")]),
        h.bank_match_case("a taught name at any amount", acc, [
            ("2026-10-21", "-75.00", "Withdrawal Example Internet *88 / ID: 1"),
            ("2026-10-26", "-75.00", "EXAMPLE  INTERNET#7"), ("2026-10-21", "75.00", "Example Internet")]),
        h.bank_match_case("money in and out", acc, [
            ("2026-10-15", "65.43", "Phone Co refund"), ("2026-09-18", "-2000", "Paycheck clawback"),
            ("2026-09-18", "2000.00", "Paycheck")]),
        h.bank_match_case("a one-off and other lines", acc, [
            ("2026-09-12", "-300", "Car repair"), ("2026-09-03", "-4.50", "Coffee"), ("2026-09-05", "0", "Zero")]),
        h.bank_match_case("paid, deleted, switched-off and ended dates", acc, [
            ("2026-09-15", "-65.43", "Phone Co"), ("2026-10-01", "-1500", "Rent"),
            ("2026-11-01", "-1500", "Rent"), ("2026-09-05", "-9.99", "Magazine"),
            ("2026-09-03", "-20", "Ended plan")]),
        h.bank_match_case("one line after another", acc, [
            ("2026-09-01", "-1500.00", "Rent"), ("2026-09-02", "-1500.00", "Rent"),
            ("2026-09-25", "-40", "Water"), ("2026-09-24", "-40", "Water")]),
        h.unmatched_case(acc),
        h.candidates_case("a bank line with its bank text", acc, shop),
        h.candidates_case("an email alert's line", acc, alert),
        h.near_case("a one-off planned line", acc, line=repair),
        h.near_case("a bill's date", acc, bill="water", day="2026-10-25"),
        h.near_case("a bill's date with its own days", acc, bill="phone", day="2026-10-15"),
        h.near_case("an income date", acc, bill="pay", day="2026-09-18"),
        h.catch_up_case("water", acc, "water", "CITY WATER #9"),
        h.catch_up_case("a name no line has", acc, "gym", "Planet Gym"),
    ]
    return cases


HOUSEHOLDS = {"basics": _basics, "edges": _edges, "two-accounts": _two_accounts, "words": _words,
              "imports": _imports, "matching": _matching}


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
        path = KEY_DIR / f"{name}.json"
        # Only a household whose answers changed is rewritten: the same
        # answers with their keys in another order leave the file alone.
        if path.is_file() and json.loads(path.read_text())["cases"] == items:
            continue
        path.write_text(json.dumps({"household": name, "cases": items}, indent=1, ensure_ascii=False) + "\n")


def load() -> dict[str, list]:
    return {p.stem: json.loads(p.read_text())["cases"] for p in sorted(KEY_DIR.glob("*.json"))}
