"""Forecasting: project balances forward by combining recurring templates and
known transactions.

Since 1.82.0 the numbers are worked out by the shared JavaScript core
(packages/core/walletweather-core.js, run by jscore.py), the same code the
iPhone app runs without a server (Plans/standalone.md, phase 2, #233). This
module reads the rows the core needs, each kind in id order (the order they
were added, so lines on the same date keep a stable order), and hands them
over. What each forecast row means is described above
`forecast` in the core.

packages/core/answer-key/ holds what the server answered before the switch;
tests/test_core_answer_key.py keeps the core and these readers to it.
"""
from calendar import monthrange
from datetime import date

from . import jscore
from .db import Account, RecurringTransaction, RecurringSkip, RecurringTag, Transaction, Tag, TransactionTag


def _iso(d):
    return d.isoformat() if d else None


def recurring_row(rec: RecurringTransaction, tags: list | None = None, dates_only: bool = False) -> dict:
    """A repeating item as the core takes it. `dates_only` leaves out the
    encrypted text and amount, for callers that only want its dates."""
    row = {
        "id": rec.id,
        "frequency": rec.frequency,
        "day_of_month": rec.day_of_month,
        "anchor_date": _iso(rec.anchor_date),
        "end_date": _iso(rec.end_date),
        "active": rec.active,
    }
    if dates_only:
        row.update(amount=0.0, description="", notes=None, category=None, category_id=None, tags=[])
    else:
        row.update(amount=float(rec.amount), description=rec.description, notes=rec.notes,
                   category=rec.category.name if rec.category else None,
                   category_id=rec.category_id, tags=tags or [])
    return row


def rows_for_forecast(db, account: Account, start: date | None = None, end: date | None = None,
                      with_tags: bool = True) -> dict:
    """The core's forecast input for one account: every line on the account,
    its active repeating items, their skipped dates and the tags of both.
    with_tags=False skips the tag lookups for callers that only need
    balances (e.g. actual_balance_as_of).

    Given the window, a line with neither date inside it can't be shown, so
    it goes without its text and planned amount: decrypting every line of a
    long history tripled the forecast's time (#233). The core only reads
    those fields for lines it shows."""
    txns = (db.query(Transaction).filter(Transaction.account_id == account.id)
            .order_by(Transaction.id).all())

    def shown(t) -> bool:
        if start is None or end is None:
            return True
        return any(d is not None and start <= d <= end for d in (t.forecast_date, t.actual_date))

    full = {t.id for t in txns if shown(t)}
    txn_tags: dict[int, list] = {}
    if with_tags and full:
        for txn_id, tag_id, name, color in (
                db.query(TransactionTag.transaction_id, Tag.id, Tag.name, Tag.color)
                .join(Tag, Tag.id == TransactionTag.tag_id)
                .filter(TransactionTag.transaction_id.in_(sorted(full)))
                .order_by(TransactionTag.transaction_id, Tag.id).all()):
            txn_tags.setdefault(txn_id, []).append({"id": tag_id, "name": name, "color": color})
    recs = (db.query(RecurringTransaction)
            .filter(RecurringTransaction.account_id == account.id,
                    RecurringTransaction.active == True)  # noqa: E712 (SQL)
            .order_by(RecurringTransaction.id).all())
    rec_tags: dict[int, list] = {}
    skips = []
    if recs:
        ids = [r.id for r in recs]
        skips = [{"recurring_id": rid, "date": d.isoformat()} for rid, d in (
            db.query(RecurringSkip.recurring_id, RecurringSkip.skip_date)
            .filter(RecurringSkip.recurring_id.in_(ids))
            .order_by(RecurringSkip.recurring_id, RecurringSkip.skip_date).all())]
        if with_tags:
            for rid, tid, name, color in (
                    db.query(RecurringTag.recurring_id, Tag.id, Tag.name, Tag.color)
                    .join(Tag, Tag.id == RecurringTag.tag_id)
                    .filter(RecurringTag.recurring_id.in_(ids))
                    .order_by(RecurringTag.recurring_id, Tag.id).all()):
                rec_tags.setdefault(rid, []).append({"id": tid, "name": name, "color": color})
    return {
        "starting_balance": float(account.starting_balance),
        "transactions": [_line_row(t, txn_tags.get(t.id, [])) if t.id in full else {
            "id": t.id,
            "recurring_id": t.recurring_id,
            "transfer_id": t.transfer_id,
            "amount": float(t.amount),
            "forecast_date": _iso(t.forecast_date),
            "actual_date": _iso(t.actual_date),
            "is_actual": t.is_actual,
        } for t in txns],
        "recurring": [recurring_row(r, rec_tags.get(r.id, [])) for r in recs],
        "skips": skips,
    }


def _line_row(t: Transaction, tags: list) -> dict:
    return {
            "id": t.id,
            "recurring_id": t.recurring_id,
            "category_id": t.category_id,
            "category": t.category.name if t.category else None,
            "transfer_id": t.transfer_id,
            "description": t.description,
            "notes": t.notes,
            "amount": float(t.amount),
            "forecast_amount": float(t.forecast_amount) if t.forecast_amount is not None else None,
            "forecast_date": _iso(t.forecast_date),
            "actual_date": _iso(t.actual_date),
            "is_actual": t.is_actual,
            "bank_match": t.bank_match,
            "has_bank_ref": bool(t.bank_ref),
            "has_mail_ref": bool(t.mail_ref),
            "bank_left": bool(t.bank_left),
            "tags": tags,
    }


def account_rows(db, accounts: list, start: date | None = None, end: date | None = None) -> list[dict]:
    """The core's per-account input for pages that cover several accounts
    (Dashboard, Calendar), for the window the page shows."""
    return [{"id": a.id, "name": a.name, **rows_for_forecast(db, a, start, end)} for a in accounts]


def _occurrences(rec: RecurringTransaction, start: date, end: date):
    """(date, amount, description) for each date of a repeating item within
    [start, end]."""
    dates = jscore.run("occurrences", {"recurring": recurring_row(rec, dates_only=True),
                                       "start": start.isoformat(), "end": end.isoformat()})
    if not dates:
        return []
    amount, desc = rec.amount, rec.description
    return [(date.fromisoformat(o["date"]), amount, desc) for o in dates]


def upcoming_dates(rec: RecurringTransaction, today: date, skipped: set, paid: set,
                   count: int = 6) -> list[date]:
    """The next `count` dates of a repeating item from `today` on, leaving
    out dates deleted from the forecast (`skipped`) and dates already paid
    (`paid`). Empty for an item that's switched off or has ended."""
    if not rec.active:
        return []
    out = jscore.run("upcomingDates", {
        "recurring": recurring_row(rec, dates_only=True), "today": today.isoformat(),
        "skipped": sorted(d.isoformat() for d in skipped), "paid": sorted(d.isoformat() for d in paid),
        "count": count})
    return [date.fromisoformat(d) for d in out]


def build_forecast(db, account: Account, start: date, end: date, with_tags: bool = True):
    """Rich forecast data with parallel planned and actual balances: the
    opening balance, both ending balances and one row per line."""
    return jscore.run("forecast", {"start": start.isoformat(), "end": end.isoformat(),
                                   **rows_for_forecast(db, account, start, end, with_tags)})


def actual_balance_as_of(db, account: Account, as_of: date) -> float:
    """The Forecast table's "Actual bal" at the last row through `as_of`, in
    that date's month: what the Forecast page's "Current balance" and the
    Today bar show."""
    start = as_of.replace(day=1)
    end = start.replace(day=monthrange(start.year, start.month)[1])
    return jscore.run("actualBalanceAsOf", {"as_of": as_of.isoformat(),
                                            **rows_for_forecast(db, account, start, end, with_tags=False)})


# ---------- Bills & income and search (Plans/standalone.md, phase 4, #235) ----------

def _tags_by(db, link, key, ids: list[int]) -> dict[int, list]:
    """{row id: [{id, name, color}]} for a batch of lines or repeating items
    (the core puts each list in name order)."""
    out: dict[int, list] = {}
    if not ids:
        return out
    for row_id, tid, name, color in (
            db.query(key, Tag.id, Tag.name, Tag.color).join(Tag, Tag.id == link.tag_id)
            .filter(key.in_(ids)).order_by(key, Tag.id).all()):
        out.setdefault(row_id, []).append({"id": tid, "name": name, "color": color})
    return out


def recurring_accounts(db, accounts: list, levels: dict, today: date, keep=None) -> list[dict]:
    """The core's `accounts` for Bills & income and search: each account's
    repeating items (switched off ones too) in id order, with every skipped
    date and the paid dates from `today` on. `keep(rec)` narrows the items
    (search keeps only those whose text matches, so the rest stay
    encrypted)."""
    recs = {a.id: [r for r in sorted(a.recurring, key=lambda r: r.id) if keep is None or keep(r)]
            for a in accounts}
    ids = [r.id for rs in recs.values() for r in rs]
    tags = _tags_by(db, RecurringTag, RecurringTag.recurring_id, ids)
    skips: dict[int, list] = {}
    paid: dict[int, list] = {}
    if ids:
        for rid, d in (db.query(RecurringSkip.recurring_id, RecurringSkip.skip_date)
                       .filter(RecurringSkip.recurring_id.in_(ids))
                       .order_by(RecurringSkip.recurring_id, RecurringSkip.skip_date)):
            skips.setdefault(rid, []).append({"recurring_id": rid, "date": d.isoformat()})
        for rid, d in (db.query(Transaction.recurring_id, Transaction.forecast_date)
                       .filter(Transaction.recurring_id.in_(ids), Transaction.is_actual.is_(True),
                               Transaction.forecast_date >= today)
                       .order_by(Transaction.recurring_id, Transaction.forecast_date)):
            paid.setdefault(rid, []).append({"recurring_id": rid, "date": d.isoformat()})
    out = []
    for a in accounts:
        rows = []
        for r in recs[a.id]:
            row = recurring_row(r, tags.get(r.id, []))
            row.update(category_color=r.category.color if r.category else None,
                       match_days=r.match_days, match_percent=r.match_percent, match_text=r.match_text)
            rows.append(row)
        out.append({"id": a.id, "name": a.name, "level": levels.get(a.id, "read"), "recurring": rows,
                    "skips": [s for r in recs[a.id] for s in skips.get(r.id, [])],
                    "paid": [p for r in recs[a.id] for p in paid.get(r.id, [])]})
    return out


def search_rows(db, query, shown=None) -> list[dict]:
    """The core's `transactions` for the searches: the lines `query`
    selects, in id order, with their tags. `shown(description, notes)` says
    which lines' text matches: the others go without their text and amounts
    (decrypting every line took a third longer than before, #235), which is
    all the core needs of a line it won't show."""
    txns = query.order_by(Transaction.id).all()
    tags: dict[int, list] = {}
    if txns:
        for txn_id, tid, name, color in (
                db.query(TransactionTag.transaction_id, Tag.id, Tag.name, Tag.color)
                .join(Tag, Tag.id == TransactionTag.tag_id)
                .filter(TransactionTag.transaction_id.in_(query.with_entities(Transaction.id).order_by(None)))
                .order_by(TransactionTag.transaction_id, Tag.id)):
            tags.setdefault(txn_id, []).append({"id": tid, "name": name, "color": color})
    out = []
    for t in txns:
        row = {
            "id": t.id,
            "account_id": t.account_id,
            "actual_date": _iso(t.actual_date),
            "forecast_date": _iso(t.forecast_date),
            "is_actual": t.is_actual,
            "category_id": t.category_id,
            "recurring_id": t.recurring_id,
            "transfer_id": t.transfer_id,
            "tags": tags.get(t.id, []),
        }
        description, notes = t.description, t.notes
        if shown is None or shown(description, notes):
            row.update(description=description, notes=notes, amount=float(t.amount),
                       forecast_amount=float(t.forecast_amount) if t.forecast_amount is not None else None,
                       category=t.category.name if t.category else None)
        else:
            row.update(description="", notes=None, amount=0.0, forecast_amount=None, category=None)
        out.append(row)
    return out
