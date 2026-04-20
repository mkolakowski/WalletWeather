"""Export/import of a user's data as plaintext JSON.

The export decrypts all Fernet-protected fields so the backup is portable and
restorable even if the encryption key is lost. The caller is responsible for
protecting the resulting file — it contains sensitive financial data.
"""
from datetime import date, datetime
from decimal import Decimal
from sqlalchemy.orm import Session

from .db import User, Account, RecurringTransaction, Transaction, Category, AccountPermission

BACKUP_VERSION = 3


def export_user(db: Session, user: User, accounts: list | None = None) -> dict:
    """Return a JSON-serializable dict containing the given accounts plus the user's
    categories. If `accounts` is None, exports all accounts owned by `user`
    (legacy behavior, kept for compatibility)."""
    categories_out = [
        {"name": c.name, "color": c.color}
        for c in db.query(Category).filter_by(owner_id=user.id).all()
    ]

    if accounts is None:
        accounts = db.query(Account).filter_by(owner_id=user.id).all()

    accounts_out = []
    for acc in accounts:
        accounts_out.append({
            "name": acc.name,
            "starting_balance": float(acc.starting_balance),
            "starting_date": acc.starting_date.isoformat(),
            "created_at": acc.created_at.isoformat() if acc.created_at else None,
            "recurring": [
                {
                    "description": r.description,
                    "amount": float(r.amount),
                    "frequency": r.frequency,
                    "day_of_month": r.day_of_month,
                    "anchor_date": r.anchor_date.isoformat() if r.anchor_date else None,
                    "end_date": r.end_date.isoformat() if r.end_date else None,
                    "active": r.active,
                    "category_name": r.category.name if r.category else None,
                    "notes": r.notes,
                }
                for r in acc.recurring
            ],
            "transactions": [
                {
                    "description": t.description,
                    "amount": float(t.amount),
                    "forecast_date": t.forecast_date.isoformat() if t.forecast_date else None,
                    "actual_date": t.actual_date.isoformat() if t.actual_date else None,
                    "forecast_amount": float(t.forecast_amount) if t.forecast_amount is not None else None,
                    "is_actual": t.is_actual,
                    "recurring_description": _rec_desc_for(t),
                    "category_name": t.category.name if t.category else None,
                    "notes": t.notes,
                }
                for t in acc.transactions
            ],
        })

    return {
        "version": BACKUP_VERSION,
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "user": {"email": user.email, "name": user.name},
        "categories": categories_out,
        "accounts": accounts_out,
    }


def _rec_desc_for(txn: Transaction) -> str | None:
    if txn.recurring_id and txn.account:
        for r in txn.account.recurring:
            if r.id == txn.recurring_id:
                return r.description
    return None


def _parse_date(s):
    if not s:
        return None
    return date.fromisoformat(s)


def import_user(db: Session, user: User, payload: dict, mode: str = "merge",
                account_names: list[str] | None = None) -> dict:
    """Import a previously exported payload into `user`'s account.

    mode='replace' — delete the user's existing accounts and categories first.
    mode='merge'   — keep existing data and add alongside. Categories with the
                     same name are reused; new ones are created.
    account_names  — if provided, only import accounts whose name is in this list.
                     If None, every account in the backup is imported.

    Returns a small summary dict. Accepts backups from version 1 and 2.
    """
    if not isinstance(payload, dict) or "accounts" not in payload:
        raise ValueError("Not a valid backup file (missing 'accounts').")
    version = payload.get("version")
    if version is None or int(version) > BACKUP_VERSION:
        raise ValueError(f"Unsupported backup version: {version!r}")
    if mode not in ("merge", "replace"):
        raise ValueError("mode must be 'merge' or 'replace'")

    name_filter = set(account_names) if account_names else None

    if mode == "replace":
        for acc in db.query(Account).filter_by(owner_id=user.id).all():
            db.delete(acc)
        for cat in db.query(Category).filter_by(owner_id=user.id).all():
            db.delete(cat)
        db.flush()

    counts = {"categories": 0, "accounts": 0, "recurring": 0, "transactions": 0}

    cat_by_name: dict[str, Category] = {}
    for c in db.query(Category).filter_by(owner_id=user.id).all():
        cat_by_name[c.name] = c
    for c_data in payload.get("categories", []):
        name = str(c_data.get("name", "")).strip()
        if not name or name in cat_by_name:
            continue
        cat = Category(owner_id=user.id, name=name, color=c_data.get("color"))
        db.add(cat)
        db.flush()
        cat_by_name[name] = cat
        counts["categories"] += 1

    for acc_data in payload["accounts"]:
        if not isinstance(acc_data, dict):
            raise ValueError("Each account must be an object")
        acc_name = str(acc_data.get("name", "Imported account"))
        if name_filter is not None and acc_name not in name_filter:
            continue
        acc = Account(
            owner_id=user.id,
            starting_date=_parse_date(acc_data["starting_date"]) or date.today(),
        )
        acc.name = acc_name
        acc.starting_balance = Decimal(str(acc_data.get("starting_balance", 0)))
        db.add(acc)
        db.flush()
        # The importing user becomes the owner of every restored account.
        # Without this row, the new account would be invisible to them since
        # authorization is gated on account_permissions, not Account.owner_id.
        db.add(AccountPermission(account_id=acc.id, user_id=user.id, level="owner"))
        counts["accounts"] += 1

        rec_by_desc: dict[str, RecurringTransaction] = {}
        for r_data in acc_data.get("recurring", []):
            cat_name = r_data.get("category_name")
            rec = RecurringTransaction(
                account_id=acc.id,
                frequency=str(r_data.get("frequency", "monthly_day")),
                day_of_month=r_data.get("day_of_month"),
                anchor_date=_parse_date(r_data.get("anchor_date")),
                end_date=_parse_date(r_data.get("end_date")),
                active=bool(r_data.get("active", True)),
                category_id=cat_by_name[cat_name].id if cat_name and cat_name in cat_by_name else None,
            )
            rec.description = str(r_data.get("description", ""))
            rec.amount = Decimal(str(r_data.get("amount", 0)))
            db.add(rec)
            db.flush()
            rec_by_desc[rec.description] = rec
            counts["recurring"] += 1

        for t_data in acc_data.get("transactions", []):
            cat_name = t_data.get("category_name")
            t = Transaction(
                account_id=acc.id,
                forecast_date=_parse_date(t_data.get("forecast_date")),
                actual_date=_parse_date(t_data.get("actual_date")),
                is_actual=bool(t_data.get("is_actual", False)),
                category_id=cat_by_name[cat_name].id if cat_name and cat_name in cat_by_name else None,
            )
            t.description = str(t_data.get("description", ""))
            t.amount = Decimal(str(t_data.get("amount", 0)))
            if t_data.get("forecast_amount") is not None:
                t.forecast_amount = Decimal(str(t_data["forecast_amount"]))
            rec_desc = t_data.get("recurring_description")
            if rec_desc and rec_desc in rec_by_desc:
                t.recurring_id = rec_by_desc[rec_desc].id
            db.add(t)
            counts["transactions"] += 1

    db.commit()
    return counts


def export_full_system(db: Session) -> dict:
    """Export every user's accounts, categories, transactions, and recurring
    templates as a single JSON structure. Used for admin/scheduled backups.

    The file is keyed by user email so that a restore can map each section
    back to the right owner.
    """
    users_out = []
    for user in db.query(User).order_by(User.id).all():
        user_accounts = db.query(Account).filter_by(owner_id=user.id).all()
        user_data = export_user(db, user, accounts=user_accounts)
        user_data["user"]["id"] = user.id
        user_data["user"]["disabled"] = user.disabled
        # Include permissions for every account this user owns
        perms_out = []
        for acc in user_accounts:
            for p in db.query(AccountPermission).filter_by(account_id=acc.id).all():
                target = db.get(User, p.user_id)
                perms_out.append({
                    "account_name": acc.name,
                    "user_email": target.email if target else f"user_{p.user_id}",
                    "level": p.level,
                })
        user_data["permissions"] = perms_out
        users_out.append(user_data)
    return {
        "system_backup": True,
        "version": BACKUP_VERSION,
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "users": users_out,
    }
