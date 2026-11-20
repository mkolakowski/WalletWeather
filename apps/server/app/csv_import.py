"""CSV import from a bank's export (Plans/standalone.md, phase 9, #243).

The parsing, the duplicate check and the grouping of repeating rows live in
the shared JavaScript core (`csvPreview`, `csvCommit`), so the iPhone with no
server imports a file exactly as the server does. This module reads what the
core needs from the database; main.py's preview and commit routes call it.
"""
from __future__ import annotations

from .db import Account, Category, RecurringTransaction, Tag, Transaction, User


def csv_rows(db, user: User, account: Account) -> dict:
    """What the core compares an import with: the account's lines (for
    duplicates), its repeating items (to link a series to), and the user's
    categories and tags (matched by name). Everything in id order, so a
    name used twice resolves the same way every time."""
    lines = []
    for t in (db.query(Transaction).filter(Transaction.account_id == account.id)
              .order_by(Transaction.id)):
        d = t.actual_date or t.forecast_date
        if not d:
            continue
        lines.append({"date": d.isoformat(), "amount": float(t.amount), "description": t.description or ""})
    recurring = [{"id": r.id, "frequency": r.frequency, "description": r.description or ""}
                 for r in (db.query(RecurringTransaction)
                           .filter(RecurringTransaction.account_id == account.id)
                           .order_by(RecurringTransaction.id))]
    categories = [{"id": c.id, "name": c.name}
                  for c in db.query(Category).filter_by(owner_id=user.id).order_by(Category.id)]
    tags = [{"id": t.id, "name": t.name}
            for t in db.query(Tag).filter_by(owner_id=user.id).order_by(Tag.id)]
    return {"lines": lines, "recurring": recurring, "categories": categories, "tags": tags}
