"""Database models with field-level encryption for sensitive data."""
import os
import base64
from datetime import date, datetime
from cryptography.fernet import Fernet

# =============================================================================
# SCHEMA VERSION
# =============================================================================
# Human-readable marker for the current database schema shape.
#
# *** AI ASSISTANT INSTRUCTIONS — READ BEFORE EDITING ***
# If you modify the schema — i.e. you add/remove/alter a SQLAlchemy model
# above, OR you add a new statement to the `migrations` list inside
# init_db() — YOU MUST:
#   1. Increment SCHEMA_VERSION below (bump the last number).
#   2. Add a matching "# vN → vN+1:" comment above the new migration(s).
#   3. Add an entry to the SCHEMA CHANGELOG block below (see format there).
# Idempotency rule still applies: every migration must be safe to run on an
# already-up-to-date database (use `ADD COLUMN IF NOT EXISTS`,
# `ON CONFLICT DO NOTHING`, etc).
# -----------------------------------------------------------------------------
SCHEMA_VERSION = "8"

# --- SCHEMA CHANGELOG ---------------------------------------------------------
# Format for every new line (keep newest at TOP):
#   # vN (YYYY-MM-DD, <your name or handle>): <one-line summary of the change>
# Example:
#   # v7 (2026-05-01, mkolakowski): add `currency` column to accounts
#
# When you bump SCHEMA_VERSION, add the matching line here. Do not rewrite
# history — only append new entries.
#
# v8 (2026-04-23, claude+mkolakowski): add `transfers` table (account-to-account
#     money movements), `transactions.transfer_id` link column, and
#     `category_budgets` table (per-category monthly spend caps).
# v7 (2026-04-23, claude+mkolakowski): add users.chart_position for the
#     dashboard chart placement preference ('above'/'below'/'inside').
# v6 (2026-04-22, claude+mkolakowski): add users.theme_preference for
#     server-side UI theme persistence.
# v5 (prior):  users.disabled flag for admin-disabled accounts.
# v4 (prior):  accounts.archived flag for hiding accounts without deleting.
# v3 (prior):  encrypted notes_enc on recurring_transactions and transactions.
# v2 (prior):  end_date + category_id on recurring_transactions; category_id
#              on transactions.
# v1 (prior):  initial schema — users, accounts, transactions, recurring,
#              categories, permissions, backup schedule.
# -----------------------------------------------------------------------------

from sqlalchemy import (
    create_engine, Column, Integer, String, Date, DateTime, Numeric,
    ForeignKey, Boolean, LargeBinary, Text
)
from sqlalchemy.orm import declarative_base, relationship, sessionmaker
from decimal import Decimal

# --- Encryption setup ---
# ENCRYPTION_KEY must be a urlsafe base64-encoded 32-byte key.
# Generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
_key = os.environ.get("ENCRYPTION_KEY")
if not _key:
    raise RuntimeError("ENCRYPTION_KEY environment variable is required")
_fernet = Fernet(_key.encode() if isinstance(_key, str) else _key)


def encrypt_str(value: str | None) -> bytes | None:
    if value is None:
        return None
    return _fernet.encrypt(value.encode("utf-8"))


def decrypt_str(value: bytes | None) -> str | None:
    if value is None:
        return None
    return _fernet.decrypt(value).decode("utf-8")


def encrypt_decimal(value: Decimal | float | None) -> bytes | None:
    if value is None:
        return None
    return _fernet.encrypt(str(Decimal(value)).encode("utf-8"))


def decrypt_decimal(value: bytes | None) -> Decimal | None:
    if value is None:
        return None
    return Decimal(_fernet.decrypt(value).decode("utf-8"))


# --- Database setup ---
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+psycopg://walletweather:walletweather@db:5432/walletweather",
)
engine = create_engine(DATABASE_URL, pool_pre_ping=True, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
Base = declarative_base()


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    # google_sub is set only for users that signed in via Google OAuth
    google_sub = Column(String(255), unique=True, nullable=True, index=True)
    email = Column(String(320), unique=True, nullable=False)
    name = Column(String(255))
    # bcrypt hash (which embeds its own per-user salt). Null for OAuth-only users.
    password_hash = Column(String(255), nullable=True)
    disabled = Column(Boolean, default=False, nullable=False)
    # UI theme preference. One of: 'dark' | 'light' | 'system' | 'dracula' |
    # 'solarized' | 'nord' | 'synthwave' | 'forest' | 'mint' | 'monokai' |
    # 'sunset'. NULL means unset → frontend falls back to 'system' (which
    # follows the OS preference).
    theme_preference = Column(String(20), nullable=True)
    # Dashboard chart placement. One of: 'above' | 'below' | 'inside'.
    # NULL means unset → frontend falls back to 'above'.
    chart_position = Column(String(10), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    accounts = relationship("Account", back_populates="owner", cascade="all, delete-orphan")


class Account(Base):
    __tablename__ = "accounts"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    # Encrypted fields stored as bytes
    name_enc = Column(LargeBinary, nullable=False)
    starting_balance_enc = Column(LargeBinary, nullable=False)
    starting_date = Column(Date, nullable=False)
    archived = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="accounts")
    recurring = relationship("RecurringTransaction", back_populates="account", cascade="all, delete-orphan")
    transactions = relationship("Transaction", back_populates="account", cascade="all, delete-orphan")

    # Convenience accessors
    @property
    def name(self) -> str:
        return decrypt_str(self.name_enc)

    @name.setter
    def name(self, v: str):
        self.name_enc = encrypt_str(v)

    @property
    def starting_balance(self) -> Decimal:
        return decrypt_decimal(self.starting_balance_enc)

    @starting_balance.setter
    def starting_balance(self, v):
        self.starting_balance_enc = encrypt_decimal(v)


class Category(Base):
    __tablename__ = "categories"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(80), nullable=False)
    color = Column(String(20), nullable=True)  # hex like '#58a6ff', optional
    created_at = Column(DateTime, default=datetime.utcnow)


class BackupSchedule(Base):
    """Singleton config row for the scheduled local backup job.

    There's at most one row in this table; the scheduler reads it on each tick
    to decide whether to run.
    """
    __tablename__ = "backup_schedule"
    id = Column(Integer, primary_key=True)
    enabled = Column(Boolean, default=False, nullable=False)
    frequency = Column(String(20), default="daily", nullable=False)  # 'daily' | 'weekly'
    hour = Column(Integer, default=3, nullable=False)  # 0-23, server local time
    retention_days = Column(Integer, default=30, nullable=False)
    last_run_at = Column(DateTime, nullable=True)
    last_run_status = Column(String(255), nullable=True)


class AccountPermission(Base):
    """Per-(account, user) access level. Absence of a row = 'deny'.

    Levels (high to low): 'owner' > 'edit' > 'read' > 'deny'.

    - owner: full control, can manage permissions including other owners,
             cannot be demoted or revoked by non-owners. Account creators are
             owners by default.
    - edit:  can modify data and manage read/edit permissions for non-owner
             users. Cannot touch owner rows at all.
    - read:  can view the forecast only.
    - deny:  account is invisible (no row in this table).
    """
    __tablename__ = "account_permissions"
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"),
                        primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                     primary_key=True)
    level = Column(String(10), nullable=False)  # 'owner' | 'edit' | 'read'
    created_at = Column(DateTime, default=datetime.utcnow)


class AdminSetting(Base):
    """Simple key-value store for admin configuration."""
    __tablename__ = "admin_settings"
    key = Column(String(100), primary_key=True)
    value = Column(String(4000), nullable=True)  # JSON-encoded


class RecurringTransaction(Base):
    """A recurring expected transaction template (e.g., rent on the 1st)."""
    __tablename__ = "recurring_transactions"
    id = Column(Integer, primary_key=True)
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="SET NULL"), nullable=True)
    description_enc = Column(LargeBinary, nullable=False)
    amount_enc = Column(LargeBinary, nullable=False)  # signed: negative=withdraw
    notes_enc = Column(LargeBinary, nullable=True)
    # Schedule: 'monthly_day' (day_of_month), 'biweekly' (anchor_date), 'weekly' (anchor_date)
    frequency = Column(String(20), nullable=False)
    day_of_month = Column(Integer, nullable=True)
    anchor_date = Column(Date, nullable=True)
    # When to stop emitting occurrences. NULL means "forever".
    end_date = Column(Date, nullable=True)
    active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    account = relationship("Account", back_populates="recurring")
    category = relationship("Category")

    @property
    def description(self) -> str:
        return decrypt_str(self.description_enc)

    @description.setter
    def description(self, v: str):
        self.description_enc = encrypt_str(v)

    @property
    def amount(self) -> Decimal:
        return decrypt_decimal(self.amount_enc)

    @amount.setter
    def amount(self, v):
        self.amount_enc = encrypt_decimal(v)

    @property
    def notes(self) -> str | None:
        return decrypt_str(self.notes_enc) if self.notes_enc else None

    @notes.setter
    def notes(self, v: str | None):
        self.notes_enc = encrypt_str(v) if v else None

    def is_expired(self, as_of: date | None = None) -> bool:
        if self.end_date is None:
            return False
        ref = as_of or date.today()
        return self.end_date < ref


class Transaction(Base):
    """An actual or one-time transaction. If recurring_id is set, this is the
    actual posting for that recurring instance on a particular date."""
    __tablename__ = "transactions"
    id = Column(Integer, primary_key=True)
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    recurring_id = Column(Integer, ForeignKey("recurring_transactions.id", ondelete="SET NULL"), nullable=True)
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="SET NULL"), nullable=True)
    # When set, this transaction is one of the two legs of an account transfer.
    # Both legs share the same transfer_id. Spending/income aggregations on
    # the dashboard, reports, and budgets exclude rows where transfer_id is
    # not None so transfers don't double-count as expense + income.
    transfer_id = Column(Integer, ForeignKey("transfers.id", ondelete="CASCADE"), nullable=True)
    description_enc = Column(LargeBinary, nullable=False)
    amount_enc = Column(LargeBinary, nullable=False)  # signed
    forecast_date = Column(Date, nullable=True)  # what we expected
    actual_date = Column(Date, nullable=True)    # when it really posted
    forecast_amount_enc = Column(LargeBinary, nullable=True)  # what we expected
    notes_enc = Column(LargeBinary, nullable=True)
    is_actual = Column(Boolean, default=False)   # has it cleared?
    created_at = Column(DateTime, default=datetime.utcnow)

    account = relationship("Account", back_populates="transactions")
    category = relationship("Category")

    @property
    def description(self) -> str:
        return decrypt_str(self.description_enc)

    @description.setter
    def description(self, v: str):
        self.description_enc = encrypt_str(v)

    @property
    def amount(self) -> Decimal:
        return decrypt_decimal(self.amount_enc)

    @amount.setter
    def amount(self, v):
        self.amount_enc = encrypt_decimal(v)

    @property
    def forecast_amount(self) -> Decimal | None:
        return decrypt_decimal(self.forecast_amount_enc) if self.forecast_amount_enc else None

    @forecast_amount.setter
    def forecast_amount(self, v):
        self.forecast_amount_enc = encrypt_decimal(v) if v is not None else None

    @property
    def notes(self) -> str | None:
        return decrypt_str(self.notes_enc) if self.notes_enc else None

    @notes.setter
    def notes(self, v: str | None):
        self.notes_enc = encrypt_str(v) if v else None


class Transfer(Base):
    """A money movement between two accounts owned (or co-owned) by the user.

    Each Transfer materializes two Transaction rows linked back via
    transactions.transfer_id: one negative on from_account, one positive on
    to_account. Both transactions share transfer_date as actual_date and are
    is_actual=True so balances reflect the move immediately. Editing or
    deleting the Transfer cascades to both legs.

    The amount is stored as a positive magnitude; the sign is applied per-leg
    when the linked transactions are created.
    """
    __tablename__ = "transfers"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    from_account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    to_account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    transfer_date = Column(Date, nullable=False)
    description_enc = Column(LargeBinary, nullable=False)
    amount_enc = Column(LargeBinary, nullable=False)  # positive magnitude
    notes_enc = Column(LargeBinary, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    @property
    def description(self) -> str:
        return decrypt_str(self.description_enc)

    @description.setter
    def description(self, v: str):
        self.description_enc = encrypt_str(v)

    @property
    def amount(self) -> Decimal:
        return decrypt_decimal(self.amount_enc)

    @amount.setter
    def amount(self, v):
        self.amount_enc = encrypt_decimal(v)

    @property
    def notes(self) -> str | None:
        return decrypt_str(self.notes_enc) if self.notes_enc else None

    @notes.setter
    def notes(self, v: str | None):
        self.notes_enc = encrypt_str(v) if v else None


class CategoryBudget(Base):
    """A per-category spending cap. Currently monthly only; the period field
    is included for forward compatibility with weekly/quarterly/yearly later.

    Amount is stored as a positive magnitude representing the maximum spend
    (i.e. budget = $400 means "don't spend more than $400 in this category
    this month"). Compared against the absolute value of negative postings.
    """
    __tablename__ = "category_budgets"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="CASCADE"),
                         nullable=False, unique=True)
    period = Column(String(20), nullable=False, default="monthly")
    amount_enc = Column(LargeBinary, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    category = relationship("Category")

    @property
    def amount(self) -> Decimal:
        return decrypt_decimal(self.amount_enc)

    @amount.setter
    def amount(self, v):
        self.amount_enc = encrypt_decimal(v)


def init_db():
    """Create missing tables, then apply in-place column migrations.

    This is intentionally lightweight — we're not pulling in Alembic for a
    personal app. Every migration here must be idempotent so init_db can run
    on every container start without side effects.
    """
    from sqlalchemy import text
    Base.metadata.create_all(engine)
    migrations = [
        # v1 → v2: end_date + category support
        "ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS end_date DATE",
        "ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL",
        # v2 → v3: notes
        "ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS notes_enc BYTEA",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS notes_enc BYTEA",
        # v3 → v4: account archiving
        "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS archived BOOLEAN NOT NULL DEFAULT FALSE",
        # v4 → v5: user disabled flag
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS disabled BOOLEAN NOT NULL DEFAULT FALSE",
        # v5 → v6: per-user UI theme preference
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS theme_preference VARCHAR(20)",
        # v6 → v7: per-user dashboard chart placement
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS chart_position VARCHAR(10)",
        # v7 → v8: transfers + transactions.transfer_id + category_budgets
        # (transfers and category_budgets tables themselves are created by
        # Base.metadata.create_all above; we only need the FK column added
        # to the existing transactions table.)
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS transfer_id INTEGER REFERENCES transfers(id) ON DELETE CASCADE",
    ]
    with engine.begin() as conn:
        for sql in migrations:
            conn.execute(text(sql))
        # Backfill: every existing account must grant edit to its owner.
        # This is safe to run repeatedly because of ON CONFLICT DO NOTHING.
        conn.execute(text("""
            INSERT INTO account_permissions (account_id, user_id, level, created_at)
            SELECT id, owner_id, 'edit', NOW() FROM accounts
            ON CONFLICT (account_id, user_id) DO NOTHING
        """))
        # Upgrade creator rows to 'owner'. Only the original creator gets
        # elevated, not every user who had edit, so delegated editors don't
        # suddenly get owner-level power over the creator.
        conn.execute(text("""
            UPDATE account_permissions ap
            SET level = 'owner'
            FROM accounts a
            WHERE ap.account_id = a.id
              AND ap.user_id = a.owner_id
              AND ap.level = 'edit'
        """))


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
