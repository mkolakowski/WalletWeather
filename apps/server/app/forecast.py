"""Forecasting: project balances forward by combining recurring templates and known transactions.

Each row in the output carries enough information for the UI to inline-edit the
actual amount/date for that occurrence:

  forecast_date    — the planned date (None for one-off transactions with no forecast)
  forecast_amount  — what we expected
  forecast_balance — running balance using forecasted amounts
  actual_date      — when it cleared (None if not yet)
  actual_amount    — what actually happened (None if not yet)
  actual_balance   — running balance using actual where present, forecast where absent,
                     accumulated in actual-date order (so a line that cleared late
                     shows the balance as of the day it actually cleared)
  diff_amount      — actual - forecast (None if either side missing)
  diff_balance     — actual_balance minus the planned balance at the same point:
                     every line planned before this line's actual date, plus
                     same-day lines up to and including this one
  recurring_id     — set when this row originates from a recurring template
  transaction_id   — set when a Transaction row backs this entry (so the UI can PATCH it)
  category_id      — the line's category, so an edit can keep it (the iOS app, #88)
"""
from datetime import date, timedelta
from decimal import Decimal
from calendar import monthrange
from .db import Account, RecurringTransaction, RecurringSkip, RecurringTag, Transaction, Tag, TransactionTag


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
        # For monthly templates anchor_date is optional and acts as a start
        # date: no occurrence is emitted before it. NULL means "always ran".
        effective_start = start
        if rec.anchor_date is not None and rec.anchor_date > effective_start:
            effective_start = rec.anchor_date
        if effective_end < effective_start:
            return
        d = date(effective_start.year, effective_start.month, 1)
        while d <= effective_end:
            day = min(rec.day_of_month, monthrange(d.year, d.month)[1])
            occ = date(d.year, d.month, day)
            if effective_start <= occ <= effective_end:
                yield occ, amount, desc
            if d.month == 12:
                d = date(d.year + 1, 1, 1)
            else:
                d = date(d.year, d.month + 1, 1)
    elif rec.frequency in ("weekly", "biweekly") and rec.anchor_date:
        # The anchor is both the cadence phase and the first occurrence:
        # nothing is projected before it.
        step = 7 if rec.frequency == "weekly" else 14
        occ = rec.anchor_date
        if occ < start:
            occ += timedelta(days=step * -(-(start - occ).days // step))
        while occ <= effective_end:
            yield occ, amount, desc
            occ += timedelta(days=step)


def upcoming_dates(rec: RecurringTransaction, today: date, skipped: set, paid: set,
                   count: int = 6) -> list[date]:
    """The next `count` dates of a repeating item from `today` on, leaving
    out dates deleted from the forecast (`skipped`) and dates already paid
    (`paid`, a cleared transaction saved for that date). Empty for an item
    that's switched off or has ended. Looks up to 400 days ahead."""
    if not rec.active:
        return []
    out = []
    for occ, _amount, _desc in _occurrences(rec, today, today + timedelta(days=400)):
        if occ in skipped or occ in paid:
            continue
        out.append(occ)
        if len(out) >= count:
            break
    return out


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


def build_forecast(db, account: Account, start: date, end: date, with_tags: bool = True):
    """Return rich forecast data with parallel forecast/actual balances.

    with_tags=False skips the per-transaction tag lookup for callers that only
    need balances (e.g. actual_balance_as_of).
    """
    txns = (
        db.query(Transaction)
        .filter(Transaction.account_id == account.id)
        .all()
    )
    # Bulk-load tags for every transaction on this account — cheaper than
    # per-row N+1, and the forecast loop already has the ids in hand.
    tags_by_txn = (_tags_for_account_transactions(db, [t.id for t in txns])
                   if with_tags else {})

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
        # A cleared transaction belongs to the window holding its actual date —
        # the same rule the opening balance above uses, so a line that cleared
        # in a different month than planned is counted once, in the month it
        # really cleared. Anything not cleared yet anchors on its planned date.
        if t.is_actual and t.actual_date:
            anchor = t.actual_date
        else:
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
            "category_id": t.category_id,
            "notes": t.notes,
            "forecast_amount": f_amt_float,
            "actual_amount": displayed_actual_amount,
            "is_actual_real": t.is_actual,
            "recurring_id": t.recurring_id,
            "transaction_id": t.id,
            "transfer_id": t.transfer_id,
            # 'auto' or 'hand' when bank sync paid this line (#196).
            "bank_match": t.bank_match,
            # 'alert' or 'bank': what paid the line (#209); None when nothing did.
            "match_source": (("alert" if t.mail_ref else "bank") if t.bank_match else None),
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
    # Occurrences the user deleted from the forecast (see RecurringSkip).
    skipped = set()
    if recs:
        skipped = set(
            db.query(RecurringSkip.recurring_id, RecurringSkip.skip_date)
            .filter(RecurringSkip.recurring_id.in_([r.id for r in recs]),
                    RecurringSkip.skip_date >= start,
                    RecurringSkip.skip_date <= end)
            .all()
        )
    # A projected row shows its recurring item's tags (#118): a line saved
    # from it starts with them.
    tags_by_rec: dict[int, list[dict]] = {}
    if with_tags and recs:
        for rid, tid, name, color in (
                db.query(RecurringTag.recurring_id, Tag.id, Tag.name, Tag.color)
                .join(Tag, Tag.id == RecurringTag.tag_id)
                .filter(RecurringTag.recurring_id.in_([r.id for r in recs]))
                .all()):
            tags_by_rec.setdefault(rid, []).append({"id": tid, "name": name, "color": color})
        for lst in tags_by_rec.values():
            lst.sort(key=lambda x: x["name"].lower())
    for rec in recs:
        rec_cat = rec.category.name if rec.category else None
        rec_notes = rec.notes
        for occ_date, amount, desc in _occurrences(rec, start, end):
            if (rec.id, occ_date) in txn_by_rec_date or (rec.id, occ_date) in skipped:
                continue
            amt_float = float(amount)
            events.append({
                "anchor_date": occ_date,
                "forecast_date": occ_date.isoformat(),
                "actual_date": occ_date.isoformat(),       # default to forecast date
                "description": desc,
                "category": rec_cat,
                "category_id": rec.category_id,
                "notes": rec_notes,
                "forecast_amount": amt_float,
                "actual_amount": amt_float,                 # default to forecast amount
                "is_actual_real": False,
                "recurring_id": rec.id,
                "transaction_id": None,
                "transfer_id": None,
                "bank_match": None,
                "match_source": None,
                # The item's tags; a line saved from this row starts with them.
                "tags": tags_by_rec.get(rec.id, []),
            })

    # Sort by planned date (the anchor only decides which window a row falls
    # in), then put already-cleared (has actual) rows after pending ones on
    # the same day so the running balance reads naturally.
    events.sort(key=lambda e: (e["forecast_date"] or e["anchor_date"].isoformat(),
                               0 if e["actual_amount"] is None else 1))

    # Forecast running balance: in the order above (planned date).
    fbals = []
    fbal = opening
    for ev in events:
        f = ev["forecast_amount"]
        fbal += f if f is not None else 0.0
        fbals.append(fbal)

    # Actual running balance (actual amount when present, else forecast): in
    # actual-date order, so a line that cleared later than planned picks up
    # the balance of the day it really cleared. The sort is stable, so lines
    # on the same actual date keep the order above.
    abals = [0.0] * len(events)
    abal = opening
    by_actual = sorted(range(len(events)),
                       key=lambda i: events[i]["actual_date"] or events[i]["anchor_date"].isoformat())
    for i in by_actual:
        f = events[i]["forecast_amount"]
        a = events[i]["actual_amount"]
        abal += a if a is not None else (f if f is not None else 0.0)
        abals[i] = abal

    # Δ Bal compares each line's actual balance with the planned balance at
    # the same point in time, so a late-cleared line isn't measured against
    # the forecast balance back at its planned date.
    pos = {i: k for k, i in enumerate(by_actual)}
    day = lambda ev, key: ev[key] or ev["anchor_date"].isoformat()
    planned_at = []
    for i, ev in enumerate(events):
        d = day(ev, "actual_date")
        planned_at.append(opening + sum(
            other["forecast_amount"] or 0.0
            for j, other in enumerate(events)
            if day(other, "forecast_date") < d
            or (day(other, "forecast_date") == d and pos[j] <= pos[i])))

    rows = []
    for ev, fbal_row, abal_row, planned in zip(events, fbals, abals, planned_at):
        f = ev["forecast_amount"]
        a = ev["actual_amount"]
        diff_amt = (a - f) if (a is not None and f is not None) else None
        diff_bal = abal_row - planned
        rows.append({
            "forecast_date": ev["forecast_date"],
            "actual_date": ev["actual_date"],
            "description": ev["description"],
            "category": ev["category"],
            "category_id": ev["category_id"],
            "notes": ev["notes"],
            "forecast_amount": f,
            "forecast_balance": fbal_row,
            "actual_amount": a,
            "actual_balance": abal_row,
            "diff_amount": diff_amt,
            "diff_balance": diff_bal,
            "is_actual_real": ev["is_actual_real"],
            "recurring_id": ev["recurring_id"],
            "transaction_id": ev["transaction_id"],
            "transfer_id": ev["transfer_id"],
            "bank_match": ev.get("bank_match"),
            "match_source": ev.get("match_source"),
            "tags": ev.get("tags", []),
        })

    return {
        "opening_balance": float(opening),
        "forecast_ending_balance": fbal,
        "actual_ending_balance": abal,
        "rows": rows,
    }


def actual_balance_as_of(db, account: Account, as_of: date) -> float:
    """Actual balance as of `as_of`, computed exactly like the forecast
    table's "Actual bal" column for the month view containing that date:
    the month's opening balance plus every row of that month whose actual
    date is on or before `as_of` (cleared rows at their real amount,
    not-yet-cleared rows at their forecast amount). Actual bal accumulates in
    actual-date order, so this is its value at the last row through `as_of`.

    This is what the Forecast page's "Current balance" and Today-bar balance
    show, so they agree with the Actual bal column at the same point.
    """
    start = as_of.replace(day=1)
    end = start.replace(day=monthrange(start.year, start.month)[1])
    data = build_forecast(db, account, start, end, with_tags=False)
    cutoff = as_of.isoformat()
    total = data["opening_balance"] + sum(
        (r["actual_amount"] if r["actual_amount"] is not None else (r["forecast_amount"] or 0.0))
        for r in data["rows"]
        if (r["actual_date"] or r["forecast_date"] or "") <= cutoff)
    return round(total, 2)
