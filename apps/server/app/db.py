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
SCHEMA_VERSION = "33"

# --- SCHEMA CHANGELOG ---------------------------------------------------------
# Format for every new line (keep newest at TOP):
#   # vN (YYYY-MM-DD, <your name or handle>): <one-line summary of the change>
# Example:
#   # v7 (2026-05-01, mkolakowski): add `currency` column to accounts
#
# When you bump SCHEMA_VERSION, add the matching line here. Do not rewrite
# history — only append new entries.
#
# v33 (2026-11-20, claude+mkolakowski): the bank's own category for a synced
#     line (bank-providers phase 2, #255). transactions.bank_category (what
#     Teller or Plaid called it, plain text, null for SimpleFIN and for lines
#     that didn't come from a bank). New table bank_category_maps (a user's
#     mapping from a provider's category onto one of their categories).
# v32 (2026-11-20, claude+mkolakowski): many bank connections, from
#     SimpleFIN, Teller or Plaid (bank-providers phase 1, #254).
#     bank_connections loses its one-per-user rule and gains .provider
#     ('simplefin' for the ones already there) and .cursor (where Plaid's
#     next /transactions/sync starts). New table bank_link_attempts (a
#     Teller or Plaid connection started in Settings, kept a few hours).
# v31 (2026-11-17, claude+mkolakowski): bills learn bank text (match-by-hand
#     phase 3, #224). recurring_transactions.match_text_enc, the encrypted
#     name of the bank lines a bill was taught to take.
# v30 (2026-11-17, claude+mkolakowski): email alerts matched to bills
#     (bank-alert-emails phase 4, #209). mail_check_runs.matched, how many of
#     a check's alerts paid a planned bill.
# v29 (2026-11-17, claude+mkolakowski): email alerts checked by themselves
#     (bank-alert-emails phase 2, #207). New table mail_check_runs (the
#     mailbox's log of checks that brought something in or failed);
#     mail_connections.check_minutes (5, 15 or 60); transactions.mail_run_id,
#     the check that brought a line in.
# v28 (2026-11-17, claude+mkolakowski): bills matched by bank sync
#     (bank-sync phase 4, #196). recurring_transactions.match_days and
#     .match_percent (how close a bank line must be, 5 days and 10% to
#     start); transactions.bank_match ('auto' or 'hand': a planned line paid
#     by a bank line), .bank_text_enc (that bank line's own text, encrypted,
#     for un-matching) and .bank_left (taken off the Unmatched list);
#     bank_sync_runs.matched.
# v27 (2026-11-16, claude+mkolakowski): email alerts (bank-alert-emails
#     phase 1, #206). New tables mail_connections (a user's Microsoft
#     sign-in, encrypted, and the folder read), mail_senders, mail_alert_kinds
#     (what each taught alert looks like) and mail_unread (alerts that
#     didn't become lines); transactions.mail_ref, the mail a line came from.
# v26 (2026-11-16, claude+mkolakowski): daily bank sync and its log
#     (bank-sync phase 3, #195). New table bank_sync_runs (one row per
#     linked account per sync, for its owner's sync log);
#     bank_connections.last_ok_at and .needs_reconnect;
#     transactions.bank_sync_run_id, the sync that brought a line in.
# v25 (2026-11-16, claude+mkolakowski): bank sync (bank-sync phase 2, #194).
#     New tables bank_connections (a user's SimpleFIN access address,
#     encrypted) and bank_account_links (a bank account matched to one of
#     theirs, with a start date); transactions.bank_ref, a hash of the bank's
#     own id, so a synced line is never brought in twice.
# v24 (2026-11-16, claude+mkolakowski): add account_invitations — an offer
#     of access to an account, by email, waiting for that person to accept
#     (#189). Existing shares are untouched.
# v23 (2026-11-16, claude+mkolakowski): add users.session_epoch — raised to
#     sign a user out of every browser at once (#186). Existing sessions
#     carry no number and count as 0, so nobody is signed out by the update.
# v22 (2026-11-16, claude+mkolakowski): blank category and tag colours that
#     aren't hex colours (#183). New ones are checked as they come in.
# v21 (2026-11-15, claude+mkolakowski): add remembered_browsers — browsers
#     that skip the two-factor code for 30 days (two-factor phase 3, #167).
#     Only the SHA-256 of each browser's cookie is kept.
# v20 (2026-11-15, claude+mkolakowski): two-factor sign-in (#165):
#     users.totp_secret_enc (the authenticator key, encrypted),
#     users.totp_enabled_at and users.totp_last_step (the last code step
#     used, so a code works once); new recovery_codes table (hashes only).
# v19 (2026-11-15, claude+mkolakowski): add app_sign_in_codes — the
#     one-time codes the "sign in an app" page hands a native app, swapped
#     for an API token (ios-app phase 1, #87). Only their SHA-256 is kept.
# v18 (2026-11-15, claude+mkolakowski): add audit_events — sign-ins,
#     failed sign-ins and blocked sign-ins (login-limits phase 1, #132);
#     failed ones are what the login rate limit counts.
# v17 (2026-11-15, claude+mkolakowski): add api_tokens.expires_at (NULL =
#     never expires) and api_tokens.last_used_at (NULL = never used) (#43).
# v16 (2026-11-15, claude+mkolakowski): add api_tokens — personal API
#     tokens (owner, name, access read/full/admin, SHA-256 of the token,
#     created/revoked dates). The token itself is never stored (#42).
# v15 (2026-11-15, claude+mkolakowski): add recurring_tags, the tags on a
#     recurring item (many-to-many, cascade from either side). Lines created
#     from the item start with its tags (recurring-tags plan, #118).
# v14 (2026-11-14, claude+mkolakowski): add users.notice_ack_at — when the
#     user acknowledged the "Important notice" (the disclaimer shown once
#     after sign-in). NULL = not yet; existing users start NULL on purpose,
#     so everyone sees it once (#46).
# v13 (2026-10-15, claude+mkolakowski): add users.recurring_position for
#     the Forecast page layout preference ('above'/'below' — where the
#     Recurring transactions panel sits relative to the forecast table).
# v12 (2026-10-08, claude+mkolakowski): add `recurring_skips` table —
#     (recurring_id, skip_date) pairs marking single occurrences of a
#     recurring template that were deleted, so the forecast stops
#     projecting them without touching the template itself.
# v11 (2026-04-24, claude+mkolakowski): add `saved_reports` table —
#     per-user named report with a JSON params blob (group_by, range,
#     filters, chart type) and a `pinned` flag for dashboard placement.
#     Stored as TEXT JSON rather than columns so the params shape can
#     evolve without further migrations.
# v10 (2026-04-24, claude+mkolakowski): add `tag_rules` table — per-user
#     auto-tagging recipes (description substring + optional category
#     filter → target tag). Applied on transaction create, on PATCH, and
#     during CSV import; can also be backfilled across existing rows.
# v9 (2026-04-24, claude+mkolakowski): add `tags` table (per-user label with
#     optional color) and `transaction_tags` many-to-many join. Tags are a
#     lighter-weight alternative to splits for cross-cutting reporting.
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
    ForeignKey, Boolean, LargeBinary, Text, UniqueConstraint, Index, BigInteger
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
    # Forecast page layout: where the Recurring transactions panel sits
    # relative to the forecast table. One of: 'above' | 'below'.
    # NULL means unset → frontend falls back to 'above'.
    recurring_position = Column(String(10), nullable=True)
    # When the user acknowledged the "Important notice" (the disclaimer shown
    # once after sign-in). NULL means not yet. Demo users are never asked.
    notice_ack_at = Column(DateTime, nullable=True)
    # A session is good only while it carries this number (#186).
    session_epoch = Column(Integer, nullable=False, default=0, server_default="0")
    # Two-factor sign-in (#165). The authenticator key, encrypted like the
    # financial fields; it's there from the start of set-up, and two-factor is
    # on only once totp_enabled_at is set. totp_last_step is the last
    # 30-second step a code was accepted for, so the same code never works
    # twice.
    totp_secret_enc = Column(LargeBinary, nullable=True)
    totp_enabled_at = Column(DateTime, nullable=True)
    totp_last_step = Column(BigInteger, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    accounts = relationship("Account", back_populates="owner", cascade="all, delete-orphan")

    @property
    def totp_secret(self) -> str | None:
        return decrypt_str(self.totp_secret_enc)

    @totp_secret.setter
    def totp_secret(self, v: str | None):
        self.totp_secret_enc = encrypt_str(v) if v else None


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


class AccountInvitation(Base):
    """An owner's offer of access to an account, to an email address, until
    that person accepts or declines it (#189). One per account and address."""
    __tablename__ = "account_invitations"
    __table_args__ = (UniqueConstraint("account_id", "email", name="uq_invitation_account_email"),)
    id = Column(Integer, primary_key=True)
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    email = Column(String(320), nullable=False, index=True)   # lowercase
    level = Column(String(10), nullable=False)                # 'read' | 'edit' | 'owner'
    invited_by = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


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
    # For 'monthly_day', anchor_date is optional and acts as a start date —
    # no occurrences are projected before it.
    frequency = Column(String(20), nullable=False)
    day_of_month = Column(Integer, nullable=True)
    anchor_date = Column(Date, nullable=True)
    # When to stop emitting occurrences. NULL means "forever".
    end_date = Column(Date, nullable=True)
    active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    # How close a bank line must be to pay one of its dates (#196): days
    # either side, and how far the amount may differ, in percent.
    match_days = Column(Integer, nullable=False, default=5)
    match_percent = Column(Integer, nullable=False, default=10)
    # The name of the bank lines this bill was taught to take (#224),
    # encrypted like the bank's text on a line.
    match_text_enc = Column(LargeBinary, nullable=True)

    @property
    def match_text(self) -> str | None:
        return decrypt_str(self.match_text_enc) if self.match_text_enc else None

    @match_text.setter
    def match_text(self, v: str | None):
        self.match_text_enc = encrypt_str(v) if v else None

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
    # A line that came from bank sync, or one bank sync found already here:
    # sha256 of the bank's account and transaction ids (#194), so it's found
    # without decrypting every row and is never brought in twice.
    bank_ref = Column(String(64), nullable=True)
    # The sync that brought it in, for the sync log (#195).
    bank_sync_run_id = Column(Integer, ForeignKey("bank_sync_runs.id", ondelete="SET NULL"), nullable=True)
    # A line that came from an email alert (#206): sha256 of the mail's own
    # id, so one mail never becomes two lines.
    mail_ref = Column(String(64), nullable=True)
    # The check that brought it in, for the mailbox's log (#207).
    mail_run_id = Column(Integer, ForeignKey("mail_check_runs.id", ondelete="SET NULL"), nullable=True)
    # Bills matched by bank sync (#196): 'auto' or 'hand' when this planned
    # line was paid by a bank line, whose own text is kept for un-matching.
    bank_match = Column(String(4), nullable=True)
    bank_text_enc = Column(LargeBinary, nullable=True)
    # A synced line taken off the Unmatched list ("Leave as its own line").
    bank_left = Column(Boolean, nullable=False, default=False)
    # What the bank's provider called the line (Teller's details.category,
    # Plaid's personal_finance_category.primary), lowercased, as it was when
    # the line landed (#255). Plain, like category_id. None for SimpleFIN.
    bank_category = Column(String(60), nullable=True)

    @property
    def bank_text(self) -> str | None:
        return decrypt_str(self.bank_text_enc) if self.bank_text_enc else None

    @bank_text.setter
    def bank_text(self, v: str | None):
        self.bank_text_enc = encrypt_str(v) if v else None

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


class Tag(Base):
    """A user-owned label that can be attached to any number of transactions.

    Deliberately lighter than Category: a transaction has zero-or-one Category
    (the primary bucket) and zero-or-many Tags (cross-cutting labels like
    "vacation" or "reimbursable"). Names aren't encrypted — we follow the
    same pattern as Category here, because searchability is more valuable
    than confidentiality for short labels that users explicitly share with
    the filter UI.
    """
    __tablename__ = "tags"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(60), nullable=False)
    color = Column(String(20), nullable=True)  # hex like '#58a6ff', optional
    created_at = Column(DateTime, default=datetime.utcnow)


class TransactionTag(Base):
    """Many-to-many link between Transaction and Tag. Cascade delete from
    either side so deleting a tag cleans up its links and deleting a
    transaction doesn't leave orphan rows behind."""
    __tablename__ = "transaction_tags"
    transaction_id = Column(Integer,
                            ForeignKey("transactions.id", ondelete="CASCADE"),
                            primary_key=True)
    tag_id = Column(Integer,
                    ForeignKey("tags.id", ondelete="CASCADE"),
                    primary_key=True)


class RecurringTag(Base):
    """Many-to-many link between RecurringTransaction and Tag (#118). A line
    created from the item starts with these tags; changing them later leaves
    lines already saved alone. Cascade delete from either side."""
    __tablename__ = "recurring_tags"
    recurring_id = Column(Integer,
                          ForeignKey("recurring_transactions.id", ondelete="CASCADE"),
                          primary_key=True)
    tag_id = Column(Integer,
                    ForeignKey("tags.id", ondelete="CASCADE"),
                    primary_key=True)


class TagRule(Base):
    """Auto-tagging rule. When a transaction's description contains
    `description_pattern` (case-insensitive substring) and — if
    `category_id` is set — its category matches, the rule's target tag
    is attached automatically.

    Why substring rather than regex: regex is footgun-y in a UI without
    a sandbox; 90% of useful rules are "STARBUCKS" / "AMZN" / "Whole
    Foods" — pure literals. We store the lowercased pattern so the
    apply path can do `description.lower().contains(pattern)` without
    re-folding case for every transaction every time.
    """
    __tablename__ = "tag_rules"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    # Optional human-readable label so the rules list is scannable. Falls
    # back to the pattern itself when blank.
    name = Column(String(80), nullable=True)
    description_pattern = Column(String(120), nullable=False)  # already lowered
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="SET NULL"),
                         nullable=True)
    tag_id = Column(Integer, ForeignKey("tags.id", ondelete="CASCADE"),
                    nullable=False)
    active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class SavedReport(Base):
    """User-saved report definition.

    The `params` column is JSON text (not a JSONB column) because the
    only consumers are SQLAlchemy + a single-instance Postgres deployment;
    the value is read whole, parsed in Python, and pushed back whole.
    Schema-less storage means the params shape can grow (new chart
    types, new group_by values, new filter dimensions) without further
    SCHEMA_VERSION bumps.

    Fields baked into columns rather than the JSON blob:
      - `name` because we list/sort by it on the picker
      - `pinned` because the dashboard pulls "all my pinned reports" via
        a where clause and a JSON path query would be uglier
      - `sort_order` so the pinned-on-dashboard order is user-controllable
    """
    __tablename__ = "saved_reports"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                      nullable=False)
    name = Column(String(120), nullable=False)
    params = Column(Text, nullable=False)  # JSON-encoded report definition
    pinned = Column(Boolean, nullable=False, default=False)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)


class RecurringSkip(Base):
    """One deleted occurrence of a recurring template.

    The forecast never projects `recurring_id` on `skip_date`. Rows go away
    with their template via the DB-level ON DELETE CASCADE (no ORM
    relationship, so a plain db.delete(template) doesn't try to null them).
    """
    __tablename__ = "recurring_skips"
    __table_args__ = (UniqueConstraint("recurring_id", "skip_date",
                                       name="uq_recurring_skip"),)
    id = Column(Integer, primary_key=True)
    recurring_id = Column(Integer, ForeignKey("recurring_transactions.id",
                                              ondelete="CASCADE"),
                          nullable=False, index=True)
    skip_date = Column(Date, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class BankConnection(Base):
    """One of a user's bank connections (#194; many per user since #254).
    `provider` is 'simplefin', 'teller' or 'plaid'. `access_url_enc` holds
    what the provider issued: SimpleFIN's access address, or Teller's or
    Plaid's access token. It reads the bank, so it's encrypted with
    ENCRYPTION_KEY and never logged or sent to the browser. `accounts_enc`
    is the last list of bank accounts the provider gave (JSON: id, name,
    org); `cursor` is where Plaid's next /transactions/sync starts."""
    __tablename__ = "bank_connections"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    provider = Column(String(10), nullable=False, default="simplefin")
    access_url_enc = Column(LargeBinary, nullable=False)
    cursor = Column(Text, nullable=True)
    accounts_enc = Column(LargeBinary, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_sync_at = Column(DateTime, nullable=True)
    last_sync_ok = Column(Boolean, nullable=True)
    last_sync_status = Column(String(300), nullable=True)
    # When each call to SimpleFIN's /accounts was made in the last day (JSON
    # list of ISO times): Bridge disables a token that asks too often.
    calls_json = Column(Text, nullable=False, default="[]")
    # The last sync that worked (#195), and whether SimpleFIN has stopped
    # accepting the connection, which stops the daily sync until reconnected.
    last_ok_at = Column(DateTime, nullable=True)
    needs_reconnect = Column(Boolean, nullable=False, default=False)


class BankLinkAttempt(Base):
    """A Teller or Plaid connection started in Settings → Bank sync and not
    finished yet (#254). Made after the two-factor code is checked, so the
    connect page and the check-back need no code of their own. `token_enc`
    is Plaid's link token (encrypted); `nonce` is the random value Teller
    Connect is set up with. `connection_id` is set once it's finished.
    Expired rows are cleared as new ones are made."""
    __tablename__ = "bank_link_attempts"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    provider = Column(String(10), nullable=False)
    public_id = Column(String(64), nullable=False, unique=True)
    token_enc = Column(LargeBinary, nullable=True)
    nonce = Column(String(64), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False)
    # Goes with its connection, so a disconnected one never reads as open.
    connection_id = Column(Integer, ForeignKey("bank_connections.id", ondelete="CASCADE"), nullable=True)
    exited = Column(Boolean, nullable=False, default=False)


class BankAccountLink(Base):
    """A bank account matched to one of the user's own accounts (#194).
    Nothing dated before `start_date` comes in. `synced_through` is the
    newest date the last good sync covered; None until the first."""
    __tablename__ = "bank_account_links"
    id = Column(Integer, primary_key=True)
    connection_id = Column(Integer, ForeignKey("bank_connections.id", ondelete="CASCADE"), nullable=False)
    bank_account_ref = Column(String(64), nullable=False)
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    start_date = Column(Date, nullable=False)
    synced_through = Column(Date, nullable=True)
    __table_args__ = (UniqueConstraint("connection_id", "bank_account_ref", name="uq_bank_link_ref"),
                      UniqueConstraint("connection_id", "account_id", name="uq_bank_link_account"))


class BankCategoryMap(Base):
    """One provider category a user's bank sync has seen, and the category of
    theirs it lands in (#255). `key` is the provider's own name for it,
    lowercased ("food_and_drink", "dining"); `category_id` None lands the
    line uncategorized. A row is made when the category is first seen,
    filled in where a category of the user's has the same name, and changed
    only by the user. Changing it never touches lines already in."""
    __tablename__ = "bank_category_maps"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    provider = Column(String(10), nullable=False)
    key = Column(String(60), nullable=False)
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    __table_args__ = (UniqueConstraint("user_id", "provider", "key", name="uq_bank_category_map"),)


class BankSyncRun(Base):
    """One sync of one linked account (#195): the owner's sync log. Kept as
    long as the audit log (AUDIT_RETENTION_DAYS)."""
    __tablename__ = "bank_sync_runs"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    run_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    trigger = Column(String(10), nullable=False)    # 'schedule' | 'manual'
    added = Column(Integer, nullable=False, default=0)
    skipped = Column(Integer, nullable=False, default=0)
    matched = Column(Integer, nullable=False, default=0)   # paid a planned line (#196)
    error = Column(String(300), nullable=True)
    __table_args__ = (Index("ix_bank_sync_runs_account_run", "account_id", "run_at"),)


class MailConnection(Base):
    """A user's mailbox for email alerts (bank-alert-emails phase 1, #206): one
    per user. `tokens_enc` holds Microsoft's sign-in (JSON: access, refresh,
    expires_at), encrypted with ENCRYPTION_KEY and never logged or sent to the
    browser. `auth_mode` is 'device' (signed in with a code) or 'web' (the
    Connect button, renewed with MS_CLIENT_SECRET). Only mail in `folder_id`
    received from `start_date` on is read; `scanned_through` is how far the
    last good check got."""
    __tablename__ = "mail_connections"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True)
    provider = Column(String(20), nullable=False, default="microsoft")
    auth_mode = Column(String(10), nullable=False, default="device")
    tokens_enc = Column(LargeBinary, nullable=False)
    address_enc = Column(LargeBinary, nullable=True)
    folder_id = Column(Text, nullable=True)
    folder_name = Column(String(200), nullable=True)
    start_date = Column(Date, nullable=False)
    # The user's clock, minutes east of UTC, for the day an alert arrived.
    utc_offset_minutes = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    scanned_through = Column(DateTime, nullable=True)
    last_check_at = Column(DateTime, nullable=True)
    last_check_ok = Column(Boolean, nullable=True)
    last_check_status = Column(String(300), nullable=True)
    last_ok_at = Column(DateTime, nullable=True)
    needs_reconnect = Column(Boolean, nullable=False, default=False)
    # How often the server looks at the mailbox by itself, in minutes: 5, 15
    # or 60 (#207; decided 2026-11-16, open question 5).
    check_minutes = Column(Integer, nullable=False, default=5)


class MailCheckRun(Base):
    """One check of a user's mailbox that brought something in or failed
    (#207): the mailbox's log, owner only. Checks that found nothing aren't
    kept. Pruned with the audit log (AUDIT_RETENTION_DAYS)."""
    __tablename__ = "mail_check_runs"
    id = Column(Integer, primary_key=True)
    connection_id = Column(Integer, ForeignKey("mail_connections.id", ondelete="CASCADE"), nullable=False)
    run_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    trigger = Column(String(10), nullable=False)    # 'schedule' | 'manual'
    added = Column(Integer, nullable=False, default=0)
    skipped = Column(Integer, nullable=False, default=0)
    unread = Column(Integer, nullable=False, default=0)
    # Of `added`, how many paid a planned bill instead of landing as their
    # own line (#209).
    matched = Column(Integer, nullable=False, default=0)
    error = Column(String(300), nullable=True)
    __table_args__ = (Index("ix_mail_check_runs_conn_run", "connection_id", "run_at"),)


class MailSender(Base):
    """An address whose alerts have been taught (#206). New lines go to
    `account_id`, or to the account a card's last four digits are matched to
    (`cards_json`: {"1234": account_id})."""
    __tablename__ = "mail_senders"
    id = Column(Integer, primary_key=True)
    connection_id = Column(Integer, ForeignKey("mail_connections.id", ondelete="CASCADE"), nullable=False)
    address = Column(String(320), nullable=False)
    label = Column(String(80), nullable=False)
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True)
    cards_json = Column(Text, nullable=False, default="{}")
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    __table_args__ = (UniqueConstraint("connection_id", "address", name="uq_mail_sender_address"),)


class MailAlertKind(Base):
    """One kind of alert from a sender (#206): mail whose subject starts with
    `subject_key`. `anchors_enc` is the text around each value in the sample
    (JSON), `sample_enc` the sample's text, both encrypted: they hold words
    from the user's own mail."""
    __tablename__ = "mail_alert_kinds"
    id = Column(Integer, primary_key=True)
    sender_id = Column(Integer, ForeignKey("mail_senders.id", ondelete="CASCADE"), nullable=False)
    subject_key = Column(String(200), nullable=False)
    direction = Column(String(3), nullable=False)    # 'out' | 'in'
    anchors_enc = Column(LargeBinary, nullable=False)
    sample_enc = Column(LargeBinary, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class MailUnread(Base):
    """An alert from a taught sender that didn't become a line (#206): the
    reader couldn't make sense of it, its card isn't matched to an account,
    or it failed the sender check ("may not be from your bank"). Its text is
    kept, encrypted, so it can be taught from; removed with the audit log
    (AUDIT_RETENTION_DAYS) or when dismissed."""
    __tablename__ = "mail_unread"
    id = Column(Integer, primary_key=True)
    connection_id = Column(Integer, ForeignKey("mail_connections.id", ondelete="CASCADE"), nullable=False)
    message_ref = Column(String(64), nullable=False)
    received_at = Column(DateTime, nullable=False)
    sender = Column(String(320), nullable=False)
    reason = Column(String(20), nullable=False)
    detail = Column(String(200), nullable=True)
    subject_enc = Column(LargeBinary, nullable=False)
    text_enc = Column(LargeBinary, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    __table_args__ = (UniqueConstraint("connection_id", "message_ref", name="uq_mail_unread_ref"),)


class ApiToken(Base):
    """A personal API token (#42), sent as `Authorization: Bearer <token>`.

    Only the SHA-256 of the token is kept: the token is shown once, when it's
    made. `access` is 'read' (GET only), 'full' (anything a signed-in user can
    do except the Admin endpoints and managing tokens) or 'admin' (full, plus
    the Admin endpoints while the owner is in ADMIN_EMAILS). A revoked token
    keeps its row, with `revoked_at` set. Rows go with their owner via the
    DB-level ON DELETE CASCADE (no ORM relationship).
    """
    __tablename__ = "api_tokens"
    id = Column(Integer, primary_key=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                      nullable=False, index=True)
    name = Column(String(80), nullable=False)
    access = Column(String(10), nullable=False)
    token_hash = Column(String(64), nullable=False, unique=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    revoked_at = Column(DateTime, nullable=True)
    # NULL = never expires. A token past this time gets 401 (#43).
    expires_at = Column(DateTime, nullable=True)
    # When the token last signed a request in; written at most once a minute.
    last_used_at = Column(DateTime, nullable=True)


class AuditEvent(Base):
    """Something that happened on the server, for the audit log (#132).

    Phase 1 of login-limits writes `login`, `login_failed` and
    `login_blocked`; the login rate limit counts `login_failed` rows for an
    email and address. `email` is what was typed (so it can name an account
    that doesn't exist); `ip` is the visitor's address when known. Never a
    password. `user_id` is kept as NULL when the user is deleted.
    """
    __tablename__ = "audit_events"
    __table_args__ = (Index("ix_audit_events_login", "email", "ip", "created_at"),)
    id = Column(Integer, primary_key=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    event = Column(String(40), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    email = Column(String(320), nullable=True)
    ip = Column(String(45), nullable=True)
    detail = Column(String(200), nullable=True)


class AppSignInCode(Base):
    """A one-time code from the "sign in an app" page (ios-app phase 1, #87).

    Made when someone signed in to the web app allows a native app in; the
    app swaps it, once, for an API token, proving with `code_verifier` that
    it's the app that asked (PKCE, S256: `code_challenge` is the base64url
    SHA-256 of the verifier). Only the SHA-256 of the code is kept. A code is
    spent by its first swap, right or wrong, and lasts a few minutes. Rows go
    with their user via the DB-level ON DELETE CASCADE.
    """
    __tablename__ = "app_sign_in_codes"
    id = Column(Integer, primary_key=True)
    code_hash = Column(String(64), nullable=False, unique=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    name = Column(String(80), nullable=False)
    access = Column(String(10), nullable=False)
    code_challenge = Column(String(64), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False)
    used_at = Column(DateTime, nullable=True)


class RecoveryCode(Base):
    """A one-time recovery code for two-factor sign-in (#165).

    Ten are made when two-factor is switched on, for signing in without the
    authenticator app. Only the SHA-256 is kept; a used code keeps its row
    with `used_at` set. Rows go with their user via the DB-level ON DELETE
    CASCADE, and are deleted when two-factor is switched off or the codes
    are remade.
    """
    __tablename__ = "recovery_codes"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    code_hash = Column(String(64), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    used_at = Column(DateTime, nullable=True)


class RememberedBrowser(Base):
    """A browser that skips the two-factor code (two-factor phase 3, #167).

    Made when the user ticks "Don't ask on this browser for 30 days" on the
    code step. The browser holds a random cookie; only its SHA-256 is kept
    here. `label` is a short name worked out from the browser's user-agent
    ("Safari on iPhone"), never the user-agent string itself. Rows go with
    their user via ON DELETE CASCADE, and all of a user's go when two-factor
    is switched off or the password changes.
    """
    __tablename__ = "remembered_browsers"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    token_hash = Column(String(64), nullable=False, unique=True)
    label = Column(String(60), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_used_at = Column(DateTime, nullable=True)
    expires_at = Column(DateTime, nullable=False)


def init_db():
    """Create missing tables, then apply in-place column migrations.

    This is intentionally lightweight — we're not pulling in Alembic for a
    personal app. Every migration here must be idempotent so init_db can run
    on every container start without side effects.
    """
    from sqlalchemy import text
    Base.metadata.create_all(engine)
    migrations = [
        # v32 → v33: the bank's category for a synced line (#255).
        # bank_category_maps comes from create_all.
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS bank_category VARCHAR(60)",
        # v31 → v32: many bank connections, from SimpleFIN, Teller or Plaid
        # (#254). bank_link_attempts comes from create_all. The unique
        # constraint's name is PostgreSQL's default for a unique column.
        "ALTER TABLE bank_connections DROP CONSTRAINT IF EXISTS bank_connections_user_id_key",
        "CREATE INDEX IF NOT EXISTS ix_bank_connections_user_id ON bank_connections (user_id)",
        "ALTER TABLE bank_connections ADD COLUMN IF NOT EXISTS provider VARCHAR(10) NOT NULL DEFAULT 'simplefin'",
        "ALTER TABLE bank_connections ADD COLUMN IF NOT EXISTS cursor TEXT",
        # v30 → v31: bills learn bank text (#224).
        "ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS match_text_enc BYTEA",
        # v29 → v30: email alerts matched to bills (#209).
        "ALTER TABLE mail_check_runs ADD COLUMN IF NOT EXISTS matched INTEGER NOT NULL DEFAULT 0",
        # v28 → v29: email alerts checked by themselves (#207). mail_check_runs
        # comes from create_all.
        "ALTER TABLE mail_connections ADD COLUMN IF NOT EXISTS check_minutes INTEGER NOT NULL DEFAULT 5",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS mail_run_id INTEGER "
        "REFERENCES mail_check_runs(id) ON DELETE SET NULL",
        # v27 → v28: bills matched by bank sync (#196).
        "ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS match_days INTEGER NOT NULL DEFAULT 5",
        "ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS match_percent INTEGER NOT NULL DEFAULT 10",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS bank_match VARCHAR(4)",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS bank_text_enc BYTEA",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS bank_left BOOLEAN NOT NULL DEFAULT FALSE",
        "ALTER TABLE bank_sync_runs ADD COLUMN IF NOT EXISTS matched INTEGER NOT NULL DEFAULT 0",
        # v26 → v27: email alerts (#206). mail_connections, mail_senders,
        # mail_alert_kinds and mail_unread come from create_all.
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS mail_ref VARCHAR(64)",
        "CREATE INDEX IF NOT EXISTS ix_transactions_account_mail_ref "
        "ON transactions (account_id, mail_ref) WHERE mail_ref IS NOT NULL",
        # v25 → v26: daily bank sync and its log (#195). bank_sync_runs comes
        # from create_all.
        "ALTER TABLE bank_connections ADD COLUMN IF NOT EXISTS last_ok_at TIMESTAMP",
        "ALTER TABLE bank_connections ADD COLUMN IF NOT EXISTS needs_reconnect BOOLEAN NOT NULL DEFAULT FALSE",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS bank_sync_run_id INTEGER "
        "REFERENCES bank_sync_runs(id) ON DELETE SET NULL",
        # v24 → v25: bank sync (#194). The two tables come from create_all.
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS bank_ref VARCHAR(64)",
        "CREATE INDEX IF NOT EXISTS ix_transactions_account_bank_ref "
        "ON transactions (account_id, bank_ref) WHERE bank_ref IS NOT NULL",
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
        # v8 → v9: tags + transaction_tags
        # (Both tables are created by Base.metadata.create_all above;
        # this entry is a no-op on a fresh DB. It's here so that
        # `ALTER`-style migrations remain possible if the schema evolves
        # — e.g. adding a future `description` column to tags.)
        # v9 → v10: tag_rules
        # (Created by Base.metadata.create_all above. No ALTER needed
        # for fresh databases; this comment marks the version boundary
        # so future column tweaks can hang an `ADD COLUMN IF NOT EXISTS`
        # underneath without renumbering.)
        # v10 → v11: saved_reports
        # (Created by Base.metadata.create_all above. Same idempotency
        # story as v9 → v10 — boundary marker only.)
        # v11 → v12: recurring_skips
        # (Created by Base.metadata.create_all above — boundary marker only.)
        # v12 → v13: per-user Forecast page layout (recurring panel position)
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS recurring_position VARCHAR(10)",
        # v13 → v14: when the user acknowledged the "Important notice".
        # No backfill: existing users see the notice once too.
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS notice_ack_at TIMESTAMP",
        # v14 → v15: recurring_tags
        # (Created by Base.metadata.create_all above — boundary marker only.)
        # v15 → v16: api_tokens
        # (Created by Base.metadata.create_all above — boundary marker only.)
        # v16 → v17: token expiry and last-used time. Existing tokens never
        # expire and show as never used until their next request.
        "ALTER TABLE api_tokens ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP",
        "ALTER TABLE api_tokens ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMP",
        # v17 → v18: audit_events
        # (Created by Base.metadata.create_all above — boundary marker only.)
        # v18 → v19: app_sign_in_codes
        # (Created by Base.metadata.create_all above — boundary marker only.)
        # v19 → v20: two-factor sign-in. recovery_codes is created by
        # Base.metadata.create_all above. Existing users have it off.
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret_enc BYTEA",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled_at TIMESTAMP",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_last_step BIGINT",
        # v20 → v21: remembered_browsers
        # (Created by Base.metadata.create_all above — boundary marker only.)
        # v21 → v22: a colour is a hex colour or nothing (#183).
        "UPDATE categories SET color = NULL "
        "WHERE color IS NOT NULL AND color !~ '^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$'",
        "UPDATE tags SET color = NULL "
        "WHERE color IS NOT NULL AND color !~ '^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$'",
        # v23 → v24: account_invitations
        # (Created by Base.metadata.create_all above — boundary marker only.)
        # v22 → v23: users.session_epoch (#186)
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS session_epoch INTEGER NOT NULL DEFAULT 0",
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
