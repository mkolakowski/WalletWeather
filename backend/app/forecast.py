"""Forecasting: project balances forward by combining recurring templates and known transactions.

Each row in the output carries enough information for the UI to inline-edit the
actual amount/date for that occurrence:

  forecast_date    — the planned date (None for one-off transactions with no forecast)
  forecast_amount  — what we expected
  forecast_balance — running balance using forecasted amounts
  actual_date      — when it cleared (None if not yet)
  actual_amount    — what actually happened (None if not yet)
  actual_balance   — running balance using actual where present, forecast where absent
  diff_amount      — actual - forecast (None if either side missing)
  diff_balance     — actual_balance - forecast_balance at this row
  recurring_id     — set when this row originates from a recurring template
  transaction_id   — set when a Transaction row backs this entry (so the UI can PATCH it)
"""
from datetime import date, timedelta
from decimal import Decimal
from calendar import monthrange
from .db import Account, RecurringTransaction, Transaction, Tag, TransactionTag


def _occurrences(rec: RecurringTransaction, start: date, end: date):
    """Yield (date, amount, description) for a recurring template within [start, end]."""
    amount = rec.amount
    desc = rec.description
    effective_end = end
    if rec.end_date is not None and rec.end_date < effective_end:
        effective_end = rec.end_date
    if effective_end < start:
        return

    if rec.frequency == "monthly_day" and rec.day_of_month:
        d = date(start.year, start.month, 1)
        while d <= effective_end:
            day = min(rec.day_of_month, monthrange(d.year, d.month)[1])
            occ = date(d.year, d.month, day)
            if start <= occ <= effective_end:
                yield occ, amount, desc
            if d.month == 12:
                d = date(d.year + 1, 1, 1)
            else:
                d = date(d.year, d.month + 1, 1)
    elif rec.frequency in ("weekly", "biweekly") and rec.anchor_date:
        step = 7 if rec.frequency == "weekly" else 14
        occ = rec.anchor_date
        while occ > start:
            occ -= timedelta(days=step)
        while occ < start:
            occ += timedelta(days=step)
        while occ <= effective_end:
            yield occ, amount, desc
            occ += timedelta(days=step)


def _tags_for_account_transactions(db, txn_ids: list[int]) -> dict[int, list[dict]]:
    """Bulk-load tag metadata for a list of transaction ids.

    Mirrors main._tags_for_transactions but duplicated here to avoid a
    circular import (main imports from forecast). Returns
    {txn_id: [{id,name,color}, ...]}; absent entries mean "no tags".
    """
    if not txn_ids:
        return {}
    rows = (
        db.query(TransactionTag.transaction_id, Tag.id, Tag.name, Tag.color)
        .join(Tag, Tag.id == TransactionTag.tag_id)
        .filter(TransactionTag.transaction_id.in_(txn_ids))
        .all()
    )
    out: dict[int, list[dict]] = {}
    for txn_id, tag_id, name, color in rows:
        out.setdefault(txn_id, []).append(
            {"id": tag_id, "name": name, "color": color}
        )
    for lst in out.values():
        lst.sort(key=lambda x: x["name"].lower())
    return out


def build_forecast(db, account: Account, start: date, end: date):
    """Return rich forecast data with parallel forecast/actual balances."""
    txns = (
        db.query(Transaction)
        .filter(Transaction.account_id == account.id)
        .all()
    )
    # Bulk-load tags for every transaction on this account — cheaper than
    # per-row N+1, and the forecast loop already has the ids in hand.
    tags_by_txn = _tags_for_account_transactions(db, [t.id for t in txns])

    # Opening balance: starting balance + every cleared txn before the window.
    # Convert to float up-front so the running balances below don't mix
    # Decimal and float (which raises TypeError in Python).
    opening = float(account.starting_balance)
    for t in txns:
        ref_date = t.actual_date or t.forecast_date
        if ref_date and ref_date < start and t.is_actual:
            opening += float(t.amount)

    # Build "events" — one per row to display.
    # Each event is a dict so we can mutate fields easily during processing.
    events = []
    # Map (recurring_id, forecast_date) → existing transaction so we can suppress
    # duplicate template-generated rows when a transaction already covers that occurrence.
    txn_by_rec_date = {}

    for t in txns:
        if t.recurring_id and t.forecast_date:
            txn_by_rec_date[(t.recurring_id, t.forecast_date)] = t

        # Decide which date this transaction is "anchored at" for the window check.
        # We always anchor on forecast_date if present (so a delayed actual still
        # appears in the month it was planned for); otherwise use actual_date.
        anchor = t.forecast_date or t.actual_date
        if not anchor or not (start <= anchor <= end):
            continue

        cat_name = t.category.name if t.category else None
        forecast_amt = t.forecast_amount if t.forecast_amount is not None else (
            t.amount if not t.is_actual else None
        )
        # Default the displayed actual amount/date to the forecast values when
        # no real actual has been recorded yet. The frontend uses these as
        # pre-filled inputs; the row only becomes a "real" actual when the user
        # changes one of them.
        f_amt_float = float(forecast_amt) if forecast_amt is not None else None
        if t.is_actual:
            displayed_actual_amount = float(t.amount)
            displayed_actual_date = t.actual_date.isoformat() if t.actual_date else None
        else:
            displayed_actual_amount = f_amt_float
            displayed_actual_date = t.forecast_date.isoformat() if t.forecast_date else None
        events.append({
            "anchor_date": anchor,
            "forecast_date": t.forecast_date.isoformat() if t.forecast_date else None,
            "actual_date": displayed_actual_date,
            "description": t.description,
            "category": cat_name,
            "notes": t.notes,
            "forecast_amount": f_amt_float,
            "actual_amount": displayed_actual_amount,
            "is_actual_real": t.is_actual,
            "recurring_id": t.recurring_id,
            "transaction_id": t.id,
            "transfer_id": t.transfer_id,
            "tags": tags_by_txn.get(t.id, []),
        })

    # Add recurring projections that don't already have a backing transaction
    recs = (
        db.query(RecurringTransaction)
        .filter(
            RecurringTransaction.account_id == account.id,
            RecurringTransaction.active == True,
        )
        .all()
    )
    for rec in recs:
        rec_cat = rec.category.name if rec.category else None
        rec_notes = rec.notes
        for occ_date, amount, desc in _occurrences(rec, start, end):
            if (rec.id, occ_date) in txn_by_rec_date:
                continue
            amt_float = float(amount)
            events.append({
                "anchor_date": occ_date,
                "forecast_date": occ_date.isoformat(),
                "actual_date": occ_date.isoformat(),       # default to forecast date
                "description": desc,
                "category": rec_cat,
                "notes": rec_notes,
                "forecast_amount": amt_float,
                "actual_amount": amt_float,                 # default to forecast amount
                "is_actual_real": False,
                "recurring_id": rec.id,
                "transaction_id": None,
                "transfer_id": None,
                # Projected rows have no backing transaction yet, so no tags
                # can be attached until the user saves the row first.
                "tags": [],
            })

    # Sort by anchor date, then put already-cleared (has actual) rows after pending
    # ones on the same day so the running balance reads naturally.
    events.sort(key=lambda e: (e["anchor_date"], 0 if e["actual_amount"] is None else 1))

    rows = []
    fbal = opening  # forecast running balance
    abal = opening  # actual running balance (uses actual when present, else forecast)
    for ev in events:
        f = ev["forecast_amount"]
        a = ev["actual_amount"]
        f_for_bal = f if f is not None else 0.0
        a_for_bal = a if a is not None else (f if f is not None else 0.0)
        fbal += f_for_bal
        abal += a_for_bal
        diff_amt = (a - f) if (a is not None and f is not None) else None
        diff_bal = abal - fbal
        rows.append({
            "forecast_date": ev["forecast_date"],
            "actual_date": ev["actual_date"],
            "description": ev["description"],
            "category": ev["category"],
            "notes": ev["notes"],
            "forecast_amount": f,
            "forecast_balance": fbal,
            "actual_amount": a,
            "actual_balance": abal,
            "diff_amount": diff_amt,
            "diff_balance": diff_bal,
            "is_actual_real": ev["is_actual_real"],
            "recurring_id": ev["recurring_id"],
            "transaction_id": ev["transaction_id"],
            "transfer_id": ev["transfer_id"],
            "tags": ev.get("tags", []),
        })

    return {
        "opening_balance": float(opening),
        "forecast_ending_balance": fbal,
        "actual_ending_balance": abal,
        "rows": rows,
    }
