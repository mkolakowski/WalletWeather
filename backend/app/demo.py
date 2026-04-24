"""Demo-mode seeding and teardown.

When DEMO_MODE is enabled, the app boots with a pre-populated admin user and
a realistic set of accounts, recurring transactions, and actual postings so
visitors can explore the product without signing up.

Demo users are identified by a reserved email suffix (DEMO_EMAIL_SUFFIX) —
that's the single source of truth for what counts as "demo data". Anything
owned by a user with that suffix is demo data; everything else is real user
data and must never be touched by the wipe path.

The `demo_seeded` AdminSetting row records whether we've already seeded, so
repeated startups are idempotent. When DEMO_MODE flips off, we delete the
demo users (cascades handle accounts/transactions/categories/etc.) and clear
the flag.
"""
from __future__ import annotations

import hashlib
from datetime import date, timedelta
from decimal import Decimal
import bcrypt
from sqlalchemy.orm import Session

from .db import (
    User, Account, RecurringTransaction, Transaction, Category,
    AccountPermission, AdminSetting, Transfer, CategoryBudget,
)


# --- Reserved demo identity ---
DEMO_EMAIL_SUFFIX = "@demo.walletweather.local"
DEMO_ADMIN_EMAIL = "admin" + DEMO_EMAIL_SUFFIX
DEMO_ADMIN_PASSWORD = "demo1234"  # intentionally simple — see README
DEMO_ADMIN_NAME = "Demo Admin"

# App title override shown when DEMO_MODE is enabled. This takes priority over
# any admin-customized app title so it's obvious the instance is in demo mode.
DEMO_APP_TITLE = "WalletWeather Demo"

# AdminSetting key that tracks whether demo data has been seeded.
DEMO_SEEDED_KEY = "demo_seeded"

# AdminSetting key that stores a hash of the demo data so the hourly reset
# loop can detect whether anything has actually changed since the last seed.
# If the hash matches the stored baseline, the reset is skipped.
DEMO_FINGERPRINT_KEY = "demo_fingerprint"


def _hash(pw: str) -> str:
    return bcrypt.hashpw(pw.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode("utf-8")


def is_demo_email(email: str) -> bool:
    return (email or "").lower().endswith(DEMO_EMAIL_SUFFIX)


def _get_flag(db: Session) -> bool:
    row = db.get(AdminSetting, DEMO_SEEDED_KEY)
    return bool(row and row.value == "true")


def _set_flag(db: Session, seeded: bool) -> None:
    row = db.get(AdminSetting, DEMO_SEEDED_KEY)
    if seeded:
        if row is None:
            db.add(AdminSetting(key=DEMO_SEEDED_KEY, value="true"))
        else:
            row.value = "true"
    else:
        if row is not None:
            db.delete(row)
    db.commit()


def _get_fingerprint(db: Session) -> str | None:
    row = db.get(AdminSetting, DEMO_FINGERPRINT_KEY)
    return row.value if row else None


def _set_fingerprint(db: Session, value: str | None) -> None:
    row = db.get(AdminSetting, DEMO_FINGERPRINT_KEY)
    if value is None:
        if row is not None:
            db.delete(row)
    else:
        if row is None:
            db.add(AdminSetting(key=DEMO_FINGERPRINT_KEY, value=value))
        else:
            row.value = value
    db.commit()


def _demo_user_ids(db: Session) -> list[int]:
    """Return every user id whose email ends with the demo suffix."""
    rows = db.query(User.id).filter(
        User.email.like("%" + DEMO_EMAIL_SUFFIX)
    ).all()
    return sorted(r[0] for r in rows)


def _compute_demo_fingerprint(db: Session) -> str:
    """SHA256 hash over the logical content of all demo-owned data.

    We hash decrypted property values (not the raw `*_enc` bytes) because Fernet
    uses a fresh random IV on every write, so the ciphertext of otherwise-
    identical content differs between seedings. Decrypted values are stable.

    The hash covers:
      - users (demo users themselves — email/name/theme/chart_position)
      - accounts owned by demo users
      - categories owned by demo users
      - recurring transactions on demo-owned accounts
      - transactions on demo-owned accounts
      - transfers owned by demo users
      - category budgets owned by demo users

    Any insert, delete, or edit on any of these rows changes the hash. When the
    hash doesn't match the post-seed baseline, the demo data has drifted and
    the reset loop will rebuild it.
    """
    demo_ids = _demo_user_ids(db)
    lines: list[str] = []
    if not demo_ids:
        return hashlib.sha256(b"").hexdigest()

    # Users
    users = db.query(User).filter(User.id.in_(demo_ids)).order_by(User.id).all()
    for u in users:
        lines.append(
            f"U|{u.id}|{u.email}|{u.name or ''}|{u.theme_preference or ''}|"
            f"{u.chart_position or ''}|{int(bool(u.disabled))}"
        )

    # Accounts
    accounts = (db.query(Account)
                  .filter(Account.owner_id.in_(demo_ids))
                  .order_by(Account.id).all())
    account_ids = [a.id for a in accounts]
    for a in accounts:
        lines.append(
            f"A|{a.id}|{a.owner_id}|{a.name}|{a.starting_balance}|"
            f"{a.starting_date.isoformat()}|{int(bool(a.archived))}"
        )

    # Categories
    cats = (db.query(Category)
              .filter(Category.owner_id.in_(demo_ids))
              .order_by(Category.id).all())
    for c in cats:
        lines.append(f"C|{c.id}|{c.owner_id}|{c.name}|{c.color or ''}")

    # Recurring transactions (scoped by account)
    if account_ids:
        recs = (db.query(RecurringTransaction)
                  .filter(RecurringTransaction.account_id.in_(account_ids))
                  .order_by(RecurringTransaction.id).all())
        for r in recs:
            anchor = r.anchor_date.isoformat() if r.anchor_date else ""
            end = r.end_date.isoformat() if r.end_date else ""
            lines.append(
                f"R|{r.id}|{r.account_id}|{r.category_id or ''}|{r.description}|"
                f"{r.amount}|{r.notes or ''}|{r.frequency}|{r.day_of_month or ''}|"
                f"{anchor}|{end}|{int(bool(r.active))}"
            )

        # Transactions
        txns = (db.query(Transaction)
                  .filter(Transaction.account_id.in_(account_ids))
                  .order_by(Transaction.id).all())
        for t in txns:
            fd = t.forecast_date.isoformat() if t.forecast_date else ""
            ad = t.actual_date.isoformat() if t.actual_date else ""
            fa = t.forecast_amount if t.forecast_amount is not None else ""
            lines.append(
                f"T|{t.id}|{t.account_id}|{t.recurring_id or ''}|"
                f"{t.category_id or ''}|{t.transfer_id or ''}|{t.description}|"
                f"{t.amount}|{fd}|{ad}|{fa}|{t.notes or ''}|"
                f"{int(bool(t.is_actual))}"
            )

    # Transfers (owner-scoped)
    transfers = (db.query(Transfer)
                   .filter(Transfer.owner_id.in_(demo_ids))
                   .order_by(Transfer.id).all())
    for tr in transfers:
        lines.append(
            f"X|{tr.id}|{tr.owner_id}|{tr.from_account_id}|{tr.to_account_id}|"
            f"{tr.transfer_date.isoformat()}|{tr.description}|{tr.amount}|"
            f"{tr.notes or ''}"
        )

    # Category budgets (owner-scoped)
    budgets = (db.query(CategoryBudget)
                 .filter(CategoryBudget.owner_id.in_(demo_ids))
                 .order_by(CategoryBudget.id).all())
    for b in budgets:
        lines.append(
            f"B|{b.id}|{b.owner_id}|{b.category_id}|{b.period}|{b.amount}"
        )

    payload = "\n".join(lines).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


# --- Categories/recurring/transactions used for seed ---
# Category names below must match one of DEFAULT_CATEGORIES in main.py so the
# helper can look them up after the default seed runs.
_RECURRING = [
    # (account_name, description, amount, frequency, day_of_month, anchor_offset_days, category_name, notes)
    ("Checking",    "Paycheck",         2800.00, "biweekly",    None, -4, "Income",         None),
    ("Checking",    "Rent",            -1650.00, "monthly_day", 1,    None, "Rent/Mortgage", None),
    ("Checking",    "Electric",         -85.00,  "monthly_day", 12,   None, "Utilities",     None),
    ("Checking",    "Internet",         -59.99,  "monthly_day", 18,   None, "Utilities",     None),
    ("Checking",    "Gym",              -39.00,  "monthly_day", 5,    None, "Subscriptions", None),
    ("Checking",    "Netflix",          -15.49,  "monthly_day", 15,   None, "Subscriptions", None),
    ("Credit Card", "Phone bill",       -65.00,  "monthly_day", 20,   None, "Utilities",     None),
]

# One-off actuals in the past ~3 weeks. offsets are days before today.
_ONE_OFF_ACTUALS = [
    # (account_name, description, amount, days_ago, category_name, notes)
    ("Checking",    "Trader Joe's",    -87.42,  2,  "Groceries",     None),
    ("Checking",    "Whole Foods",     -54.91,  9,  "Groceries",     None),
    ("Checking",    "Costco",         -142.33,  16, "Groceries",     None),
    ("Checking",    "Shell",           -48.70,  4,  "Transportation", None),
    ("Checking",    "Target",          -72.18,  11, "Shopping",       None),
    ("Credit Card", "Chipotle",        -14.25,  1,  "Dining",         None),
    ("Credit Card", "Starbucks",        -8.50,  3,  "Dining",         None),
    ("Credit Card", "Uber",            -22.40,  5,  "Transportation", None),
    ("Credit Card", "AMC Theaters",    -28.00,  12, "Entertainment",  None),
    ("Credit Card", "Doctor copay",    -40.00,  18, "Healthcare",     None),
]


def _find_category(db: Session, owner_id: int, name: str) -> Category | None:
    return db.query(Category).filter_by(owner_id=owner_id, name=name).one_or_none()


def _create_account(db: Session, user: User, name: str, starting_balance: float,
                    starting_date: date) -> Account:
    acc = Account(owner_id=user.id, starting_date=starting_date)
    acc.name = name
    acc.starting_balance = Decimal(str(starting_balance))
    db.add(acc)
    db.flush()  # get acc.id
    # Mirror the creator-is-owner rule from account creation in main.py
    db.add(AccountPermission(account_id=acc.id, user_id=user.id, level="owner"))
    return acc


def _create_recurring(db: Session, account: Account, description: str, amount: float,
                      frequency: str, day_of_month: int | None, anchor_date: date | None,
                      category: Category | None, notes: str | None) -> RecurringTransaction:
    r = RecurringTransaction(
        account_id=account.id,
        category_id=category.id if category else None,
        frequency=frequency,
        day_of_month=day_of_month,
        anchor_date=anchor_date,
        active=True,
    )
    r.description = description
    r.amount = Decimal(str(amount))
    if notes:
        r.notes = notes
    db.add(r)
    return r


def _create_transaction(db: Session, account: Account, description: str, amount: float,
                        actual_date: date, category: Category | None,
                        notes: str | None) -> Transaction:
    t = Transaction(
        account_id=account.id,
        category_id=category.id if category else None,
        actual_date=actual_date,
        forecast_date=actual_date,  # one-off actuals: forecast == actual
        is_actual=True,
    )
    t.description = description
    t.amount = Decimal(str(amount))
    t.forecast_amount = Decimal(str(amount))
    if notes:
        t.notes = notes
    db.add(t)
    return t


def seed_demo_data(db: Session, seed_default_categories) -> None:
    """Create the demo admin user and sample data if not already present.

    `seed_default_categories` is injected from main.py to avoid a circular
    import. It populates the user's default categories, same as signup flow.
    """
    if _get_flag(db):
        return  # already seeded

    # Don't collide with a pre-existing row (e.g. from a prior demo session
    # whose flag was lost). Reuse if present so we're idempotent.
    user = db.query(User).filter_by(email=DEMO_ADMIN_EMAIL).one_or_none()
    if user is None:
        user = User(
            email=DEMO_ADMIN_EMAIL,
            name=DEMO_ADMIN_NAME,
            password_hash=_hash(DEMO_ADMIN_PASSWORD),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    seed_default_categories(db, user)

    today = date.today()
    account_start = today - timedelta(days=90)

    checking = _create_account(db, user, "Checking",     4250.00, account_start)
    savings  = _create_account(db, user, "Savings",     18500.00, account_start)
    credit   = _create_account(db, user, "Credit Card",  -842.33, account_start)
    db.commit()
    by_name = {"Checking": checking, "Savings": savings, "Credit Card": credit}

    # Recurring transactions
    for acc_name, desc, amt, freq, dom, anchor_off, cat_name, notes in _RECURRING:
        acc = by_name[acc_name]
        anchor = (today + timedelta(days=anchor_off)) if anchor_off is not None else None
        cat = _find_category(db, user.id, cat_name)
        _create_recurring(db, acc, desc, amt, freq, dom, anchor, cat, notes)

    # One-off actual transactions
    for acc_name, desc, amt, days_ago, cat_name, notes in _ONE_OFF_ACTUALS:
        acc = by_name[acc_name]
        cat = _find_category(db, user.id, cat_name)
        _create_transaction(db, acc, desc, amt, today - timedelta(days=days_ago), cat, notes)

    db.commit()
    _set_flag(db, True)
    # Stamp a fingerprint of the freshly-seeded data so the hourly reset loop
    # has a baseline to compare against.
    _set_fingerprint(db, _compute_demo_fingerprint(db))


def wipe_demo_data(db: Session) -> int:
    """Delete every user whose email ends with DEMO_EMAIL_SUFFIX.

    Cascade deletes remove their accounts, recurring transactions, actual
    transactions, categories, and permission rows. Real users are never
    touched because they can't have the demo email suffix.

    Returns the number of users deleted.
    """
    demo_users = db.query(User).filter(
        User.email.like("%" + DEMO_EMAIL_SUFFIX)
    ).all()
    n = 0
    for u in demo_users:
        db.delete(u)
        n += 1
    db.commit()
    _set_flag(db, False)
    _set_fingerprint(db, None)
    return n


def reseed_demo_if_changed(db: Session, seed_default_categories) -> bool:
    """Rebuild demo data iff it has drifted from the last-seeded baseline.

    Called on a timer (hourly) by the background scheduler in main.py. If the
    stored fingerprint matches the current one, nothing has been edited since
    the last seed and we skip the reset — visitors who haven't touched the app
    don't get surprised by a wipe. If they differ, we wipe everything owned by
    demo users and re-seed from scratch.

    Returns True if a reseed happened, False if the demo was untouched.
    """
    if not _get_flag(db):
        # First-time boot: seed and bail. This also handles the case where the
        # fingerprint row was lost (e.g. manual DB edit) — seed_demo_data is
        # idempotent on the user row and will stamp a fresh fingerprint.
        seed_demo_data(db, seed_default_categories)
        return True

    baseline = _get_fingerprint(db)
    current = _compute_demo_fingerprint(db)
    if baseline is not None and baseline == current:
        return False

    # Drifted — rebuild.
    wipe_demo_data(db)
    seed_demo_data(db, seed_default_categories)
    return True
