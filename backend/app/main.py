"""FastAPI application: local + Google auth, accounts, transactions, forecasting."""
import os
import re
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path

import bcrypt
from fastapi import FastAPI, Depends, HTTPException, Request, status
from fastapi.responses import RedirectResponse, JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr, Field

from .db import (
    init_db, get_db, User, Account, RecurringTransaction, Transaction, Category,
    AccountPermission, BackupSchedule, SessionLocal,
)
from .forecast import build_forecast
from .backup import export_user, import_user

SECRET_KEY = os.environ["SESSION_SECRET"]
APP_BASE_URL = os.environ.get("APP_BASE_URL", "http://localhost:8300")
ALLOWED_EMAILS = {e.strip().lower() for e in os.environ.get("ALLOWED_EMAILS", "").split(",") if e.strip()}
ALLOW_REGISTRATION = os.environ.get("ALLOW_REGISTRATION", "true").lower() == "true"
ADMIN_EMAILS = {e.strip().lower() for e in os.environ.get("ADMIN_EMAILS", "").split(",") if e.strip()}
BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", "/data/backups"))

# Demo mode: when on, the app boots with a pre-seeded admin user and sample
# data. Default ON so first-time users can click around without signing up.
# Set DEMO_MODE=false to turn the demo off and wipe its data on next start.
DEMO_MODE = os.environ.get("DEMO_MODE", "true").lower() == "true"
from .demo import (
    DEMO_ADMIN_EMAIL, DEMO_ADMIN_PASSWORD, seed_demo_data, wipe_demo_data,
)
if DEMO_MODE:
    # Make the demo admin an actual admin without requiring the operator to
    # add them to ADMIN_EMAILS in .env.
    ADMIN_EMAILS.add(DEMO_ADMIN_EMAIL.lower())

# Google OAuth is optional - only enabled if both client id and secret are set
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "").strip()
GOOGLE_ENABLED = bool(GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET)

app = FastAPI(title="WalletWeather")
app.add_middleware(SessionMiddleware, secret_key=SECRET_KEY, same_site="lax", https_only=False)

oauth = None
if GOOGLE_ENABLED:
    from authlib.integrations.starlette_client import OAuth
    oauth = OAuth()
    oauth.register(
        name="google",
        client_id=GOOGLE_CLIENT_ID,
        client_secret=GOOGLE_CLIENT_SECRET,
        server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
        client_kwargs={"scope": "openid email profile"},
    )


import json
import threading
import time


@app.on_event("startup")
def _startup():
    init_db()
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    # Backfill: seed default categories for any existing user who has none.
    from .db import SessionLocal
    db = SessionLocal()
    try:
        for user in db.query(User).all():
            seed_default_categories(db, user)
        # Demo-mode reconciliation. This must run after init_db so the
        # admin_settings table exists.
        if DEMO_MODE:
            seed_demo_data(db, seed_default_categories)
        else:
            # If the demo was seeded previously and the operator has now
            # turned it off, wipe the demo user(s) and their data. Real
            # users are safe — we only delete the reserved demo email suffix.
            wipe_demo_data(db)
    finally:
        db.close()
    # Start the backup scheduler daemon thread
    t = threading.Thread(target=_backup_scheduler_loop, daemon=True)
    t.start()


def _run_system_backup() -> str:
    """Execute a full-system backup to BACKUP_DIR. Returns the filename."""
    from .db import SessionLocal
    from .backup import export_full_system
    db = SessionLocal()
    try:
        payload = export_full_system(db)
        stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        filename = f"system-backup-{stamp}.json"
        filepath = BACKUP_DIR / filename
        filepath.write_text(json.dumps(payload, indent=2))
        return filename
    finally:
        db.close()


def _enforce_retention(retention_days: int):
    """Delete backup files older than retention_days."""
    if retention_days <= 0:
        return
    cutoff = datetime.utcnow() - timedelta(days=retention_days)
    for f in sorted(BACKUP_DIR.glob("system-backup-*.json")):
        try:
            # Parse timestamp from filename: system-backup-YYYYMMDD_HHMMSS.json
            parts = f.stem.replace("system-backup-", "")
            file_dt = datetime.strptime(parts, "%Y%m%d_%H%M%S")
            if file_dt < cutoff:
                f.unlink()
        except (ValueError, OSError):
            pass


def _backup_scheduler_loop():
    """Background daemon that checks every 30 minutes whether a scheduled
    backup should run. Reads config from the BackupSchedule table."""
    from .db import SessionLocal
    while True:
        time.sleep(1800)  # 30 minutes
        db = SessionLocal()
        try:
            sched = db.query(BackupSchedule).first()
            if not sched or not sched.enabled:
                continue
            now = datetime.utcnow()
            # Decide if it's time to run based on frequency + hour
            should_run = False
            if sched.last_run_at is None:
                should_run = True
            elif sched.frequency == "daily":
                # Run if we haven't run today and current hour >= scheduled hour
                last_date = sched.last_run_at.date()
                if now.date() > last_date and now.hour >= sched.hour:
                    should_run = True
            elif sched.frequency == "weekly":
                days_since = (now - sched.last_run_at).days
                if days_since >= 7 and now.hour >= sched.hour:
                    should_run = True
            elif sched.frequency == "monthly":
                # Run if we're in a new month
                if (now.year, now.month) > (sched.last_run_at.year, sched.last_run_at.month) \
                   and now.hour >= sched.hour:
                    should_run = True
            if not should_run:
                continue
            try:
                filename = _run_system_backup()
                _enforce_retention(sched.retention_days)
                sched.last_run_at = now
                sched.last_run_status = f"OK: {filename}"
            except Exception as e:
                sched.last_run_at = now
                sched.last_run_status = f"ERROR: {str(e)[:200]}"
            db.commit()
        except Exception:
            pass  # never crash the daemon
        finally:
            db.close()


# ---------- Password helpers ----------
def hash_password(pw: str) -> str:
    return bcrypt.hashpw(pw.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode("utf-8")


def verify_password(pw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(pw.encode("utf-8"), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def _email_ok(email: str) -> bool:
    return bool(re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email))


# ---------- Auth ----------
def current_user(request: Request, db: Session = Depends(get_db)) -> User:
    uid = request.session.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Not authenticated")
    user = db.get(User, uid)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if user.disabled:
        # Disabled users get logged out cleanly
        request.session.clear()
        raise HTTPException(status_code=403, detail="Account disabled")
    return user


def is_admin(user: User) -> bool:
    return bool(ADMIN_EMAILS) and user.email.lower() in ADMIN_EMAILS


def current_admin(user: User = Depends(current_user)) -> User:
    if not is_admin(user):
        raise HTTPException(status_code=403, detail="Admin access required")
    return user


# ---------- Local auth schemas ----------
class RegisterIn(BaseModel):
    email: str
    password: str = Field(min_length=8, max_length=128)
    name: str | None = None


class LoginIn(BaseModel):
    email: str
    password: str


@app.get("/api/auth/config")
def auth_config():
    """Public endpoint so the frontend knows which login methods to show."""
    return {
        "google_enabled": GOOGLE_ENABLED,
        "registration_enabled": ALLOW_REGISTRATION,
        "demo_mode": DEMO_MODE,
        "demo_email": DEMO_ADMIN_EMAIL if DEMO_MODE else None,
        "demo_password": DEMO_ADMIN_PASSWORD if DEMO_MODE else None,
    }


@app.post("/api/auth/register")
def register(payload: RegisterIn, request: Request, db: Session = Depends(get_db)):
    if not ALLOW_REGISTRATION:
        raise HTTPException(403, "Registration is disabled")
    email = payload.email.strip().lower()
    if not _email_ok(email):
        raise HTTPException(400, "Invalid email")
    if ALLOWED_EMAILS and email not in ALLOWED_EMAILS:
        raise HTTPException(403, "This email is not authorized for this app")
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(409, "An account with that email already exists")
    user = User(
        email=email,
        name=payload.name or email.split("@")[0],
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    seed_default_categories(db, user)
    request.session["uid"] = user.id
    return {"id": user.id, "email": user.email}


@app.post("/api/auth/login")
def local_login(payload: LoginIn, request: Request, db: Session = Depends(get_db)):
    email = payload.email.strip().lower()
    user = db.query(User).filter_by(email=email).first()
    # Constant-ish failure path: still verify against a dummy hash to reduce timing leaks
    if not user or not user.password_hash:
        bcrypt.checkpw(b"x", b"$2b$12$" + b"." * 53)
        raise HTTPException(401, "Invalid email or password")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, "Invalid email or password")
    if user.disabled:
        raise HTTPException(403, "Account disabled")
    request.session["uid"] = user.id
    return {"id": user.id, "email": user.email}


@app.get("/auth/login")
async def google_login(request: Request):
    if not GOOGLE_ENABLED:
        raise HTTPException(404, "Google login is not configured")
    redirect_uri = f"{APP_BASE_URL}/auth/callback"
    return await oauth.google.authorize_redirect(request, redirect_uri)


@app.get("/auth/callback")
async def auth_callback(request: Request, db: Session = Depends(get_db)):
    if not GOOGLE_ENABLED:
        raise HTTPException(404, "Google login is not configured")
    token = await oauth.google.authorize_access_token(request)
    info = token.get("userinfo") or {}
    sub = info.get("sub")
    email = (info.get("email") or "").lower()
    if not sub or not email:
        raise HTTPException(400, "Google did not return an identity")
    if ALLOWED_EMAILS and email not in ALLOWED_EMAILS:
        raise HTTPException(403, "This email is not authorized for this app")
    # Match by google_sub first, then by email (link existing local account)
    user = db.query(User).filter_by(google_sub=sub).one_or_none()
    is_new = False
    if not user:
        user = db.query(User).filter_by(email=email).one_or_none()
        if user:
            user.google_sub = sub  # link Google to existing local account
        else:
            if not ALLOW_REGISTRATION:
                raise HTTPException(403, "Registration is disabled")
            user = User(google_sub=sub, email=email, name=info.get("name"))
            db.add(user)
            is_new = True
    db.commit()
    db.refresh(user)
    if user.disabled:
        raise HTTPException(403, "Account disabled")
    if is_new:
        seed_default_categories(db, user)
    request.session["uid"] = user.id
    return RedirectResponse("/")


@app.post("/auth/logout")
async def logout(request: Request):
    request.session.clear()
    return {"ok": True}


@app.get("/api/me")
def me(user: User = Depends(current_user)):
    return {"id": user.id, "email": user.email, "name": user.name,
            "is_admin": is_admin(user)}


# ---------- Schemas ----------
class AccountIn(BaseModel):
    name: str
    starting_balance: float
    starting_date: date


class RecurringIn(BaseModel):
    description: str
    amount: float  # signed: negative = withdraw
    frequency: str  # 'monthly_day' | 'weekly' | 'biweekly'
    day_of_month: int | None = None
    anchor_date: date | None = None
    end_date: date | None = None
    category_id: int | None = None
    notes: str | None = Field(default=None, max_length=256)
    active: bool = True


class TransactionIn(BaseModel):
    description: str
    amount: float
    forecast_date: date | None = None
    actual_date: date | None = None
    forecast_amount: float | None = None
    is_actual: bool = False
    recurring_id: int | None = None
    category_id: int | None = None
    notes: str | None = Field(default=None, max_length=256)


class CategoryIn(BaseModel):
    name: str
    color: str | None = None


# ---------- Categories ----------
DEFAULT_CATEGORIES = [
    ("Groceries",      "#3fb950"),
    ("Dining",         "#f0883e"),
    ("Transportation", "#58a6ff"),
    ("Utilities",      "#56d4dd"),
    ("Rent/Mortgage",  "#a371f7"),
    ("Insurance",      "#2ea043"),
    ("Healthcare",     "#ff7b72"),
    ("Entertainment",  "#e3b341"),
    ("Shopping",       "#db61a2"),
    ("Subscriptions",  "#7c6be6"),
    ("Income",         "#3fb950"),
    ("Savings",        "#d29922"),
    ("Other",          "#8b949e"),
]


def seed_default_categories(db: Session, user: User) -> int:
    """Insert default categories for a user who has none. Idempotent: if the
    user already has any categories, this is a no-op. Returns the number of
    rows inserted."""
    existing = db.query(Category).filter_by(owner_id=user.id).count()
    if existing > 0:
        return 0
    for name, color in DEFAULT_CATEGORIES:
        db.add(Category(owner_id=user.id, name=name, color=color))
    db.commit()
    return len(DEFAULT_CATEGORIES)


def _own_category(db: Session, user: User, cat_id: int) -> Category:
    cat = db.get(Category, cat_id)
    if not cat or cat.owner_id != user.id:
        raise HTTPException(404, "Category not found")
    return cat


@app.get("/api/categories")
def list_categories(user: User = Depends(current_user), db: Session = Depends(get_db)):
    cats = db.query(Category).filter_by(owner_id=user.id).order_by(Category.name).all()
    return [{"id": c.id, "name": c.name, "color": c.color} for c in cats]


@app.post("/api/categories")
def create_category(payload: CategoryIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    name = payload.name.strip()
    if not name:
        raise HTTPException(400, "Name is required")
    existing = db.query(Category).filter_by(owner_id=user.id, name=name).first()
    if existing:
        raise HTTPException(409, "A category with that name already exists")
    cat = Category(owner_id=user.id, name=name, color=payload.color)
    db.add(cat)
    db.commit()
    db.refresh(cat)
    return {"id": cat.id, "name": cat.name, "color": cat.color}


@app.patch("/api/categories/{cat_id}")
def update_category(cat_id: int, payload: CategoryIn,
                    user: User = Depends(current_user), db: Session = Depends(get_db)):
    cat = _own_category(db, user, cat_id)
    cat.name = payload.name.strip()
    cat.color = payload.color
    db.commit()
    return {"ok": True}


@app.delete("/api/categories/{cat_id}")
def delete_category(cat_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    cat = _own_category(db, user, cat_id)
    db.delete(cat)
    db.commit()
    return {"ok": True}


# ---------- Accounts & Permissions ----------
LEVEL_RANK = {"deny": 0, "read": 1, "edit": 2, "owner": 3}


def _user_level(db: Session, user: User, account_id: int) -> str:
    """Return the user's effective level on an account: 'owner' | 'edit' | 'read' | 'deny'."""
    p = db.query(AccountPermission).filter_by(
        account_id=account_id, user_id=user.id
    ).first()
    return p.level if p else "deny"


def _account_with_perm(db: Session, user: User, account_id: int,
                       required: str) -> Account:
    """Fetch an account if the user has at least `required` access, else 404.

    We return 404 (not 403) to avoid leaking which account ids exist.
    """
    acc = db.get(Account, account_id)
    if not acc:
        raise HTTPException(404, "Account not found")
    level = _user_level(db, user, account_id)
    if LEVEL_RANK[level] < LEVEL_RANK[required]:
        raise HTTPException(404, "Account not found")
    return acc


def _own_account(db: Session, user: User, account_id: int) -> Account:
    """Backwards-compatible alias used by older endpoints. Requires edit."""
    return _account_with_perm(db, user, account_id, "edit")


def _user_visible_accounts(db: Session, user: User, include_archived: bool = False) -> list[Account]:
    """All accounts the user has at least 'read' access to.

    By default archived accounts are excluded so they don't appear on the
    Accounts page or Dashboard. Pass include_archived=True for Settings
    management views that need to see everything.
    """
    q = (
        db.query(Account, AccountPermission.level)
        .join(AccountPermission, AccountPermission.account_id == Account.id)
        .filter(AccountPermission.user_id == user.id)
        .filter(AccountPermission.level.in_(["owner", "edit", "read"]))
    )
    if not include_archived:
        q = q.filter(Account.archived == False)
    return [acc for (acc, _level) in q.all()]


def _user_editable_accounts(db: Session, user: User, include_archived: bool = False) -> list[Account]:
    """All accounts the user has at least 'edit' access to."""
    q = (
        db.query(Account)
        .join(AccountPermission, AccountPermission.account_id == Account.id)
        .filter(AccountPermission.user_id == user.id)
        .filter(AccountPermission.level.in_(["owner", "edit"]))
    )
    if not include_archived:
        q = q.filter(Account.archived == False)
    return list(q.all())


@app.get("/api/accounts")
def list_accounts(include_archived: bool = False,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    out = []
    for a in _user_visible_accounts(db, user, include_archived=include_archived):
        out.append({
            "id": a.id, "name": a.name,
            "starting_balance": float(a.starting_balance),
            "starting_date": a.starting_date.isoformat(),
            "archived": a.archived,
            "level": _user_level(db, user, a.id),
        })
    return out


@app.post("/api/accounts")
def create_account(payload: AccountIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = Account(owner_id=user.id, starting_date=payload.starting_date)
    acc.name = payload.name
    acc.starting_balance = Decimal(str(payload.starting_balance))
    db.add(acc)
    db.flush()  # populate acc.id without committing
    db.add(AccountPermission(account_id=acc.id, user_id=user.id, level="owner"))
    db.commit()
    db.refresh(acc)
    return {"id": acc.id}


class AccountPatchIn(BaseModel):
    archived: bool | None = None


@app.patch("/api/accounts/{account_id}")
def update_account(account_id: int, payload: AccountPatchIn,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    # Must have edit on the account to toggle archive state. We bypass the
    # visible-accounts filter (which excludes archived) by going straight
    # through _account_with_perm, which uses db.get() directly.
    acc = _account_with_perm(db, user, account_id, "edit")
    if payload.archived is not None:
        acc.archived = payload.archived
    db.commit()
    return {"ok": True, "archived": acc.archived}


@app.delete("/api/accounts/{account_id}")
def delete_account(account_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _account_with_perm(db, user, account_id, "owner")
    db.delete(acc)
    db.commit()
    return {"ok": True}


# ---------- Recurring ----------
@app.get("/api/accounts/{account_id}/recurring")
def list_recurring(account_id: int, archived: bool = False,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _account_with_perm(db, user, account_id, "read")
    today = date.today()
    out = []
    for r in acc.recurring:
        is_expired = r.end_date is not None and r.end_date < today
        if archived != is_expired:
            continue
        out.append({
            "id": r.id,
            "description": r.description,
            "amount": float(r.amount),
            "frequency": r.frequency,
            "day_of_month": r.day_of_month,
            "anchor_date": r.anchor_date.isoformat() if r.anchor_date else None,
            "end_date": r.end_date.isoformat() if r.end_date else None,
            "category_id": r.category_id,
            "category_name": r.category.name if r.category else None,
            "notes": r.notes,
            "active": r.active,
            "expired": is_expired,
        })
    return out


@app.post("/api/accounts/{account_id}/recurring")
def create_recurring(account_id: int, payload: RecurringIn,
                     user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)
    if payload.category_id is not None:
        _own_category(db, user, payload.category_id)
    rec = RecurringTransaction(
        account_id=acc.id,
        frequency=payload.frequency,
        day_of_month=payload.day_of_month,
        anchor_date=payload.anchor_date,
        end_date=payload.end_date,
        category_id=payload.category_id,
        active=payload.active,
    )
    rec.description = payload.description
    rec.amount = Decimal(str(payload.amount))
    rec.notes = payload.notes
    db.add(rec)
    db.commit()
    db.refresh(rec)
    return {"id": rec.id}


@app.patch("/api/recurring/{rec_id}")
def update_recurring(rec_id: int, payload: RecurringIn,
                     user: User = Depends(current_user), db: Session = Depends(get_db)):
    rec = db.get(RecurringTransaction, rec_id)
    if not rec:
        raise HTTPException(404)
    _account_with_perm(db, user, rec.account_id, "edit")
    if payload.category_id is not None:
        _own_category(db, user, payload.category_id)
    rec.description = payload.description
    rec.amount = Decimal(str(payload.amount))
    rec.frequency = payload.frequency
    rec.day_of_month = payload.day_of_month
    rec.anchor_date = payload.anchor_date
    rec.end_date = payload.end_date
    rec.category_id = payload.category_id
    rec.notes = payload.notes
    rec.active = payload.active
    db.commit()
    return {"ok": True}


@app.delete("/api/recurring/{rec_id}")
def delete_recurring(rec_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    rec = db.get(RecurringTransaction, rec_id)
    if not rec:
        raise HTTPException(404)
    _account_with_perm(db, user, rec.account_id, "edit")
    db.delete(rec)
    db.commit()
    return {"ok": True}


# ---------- Transactions ----------
@app.get("/api/accounts/{account_id}/transactions")
def list_transactions(account_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _account_with_perm(db, user, account_id, "read")
    return [
        {"id": t.id, "description": t.description, "amount": float(t.amount),
         "forecast_date": t.forecast_date.isoformat() if t.forecast_date else None,
         "actual_date": t.actual_date.isoformat() if t.actual_date else None,
         "forecast_amount": float(t.forecast_amount) if t.forecast_amount is not None else None,
         "is_actual": t.is_actual, "recurring_id": t.recurring_id,
         "category_id": t.category_id,
         "category_name": t.category.name if t.category else None,
         "notes": t.notes}
        for t in acc.transactions
    ]


@app.post("/api/accounts/{account_id}/transactions")
def create_transaction(account_id: int, payload: TransactionIn,
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)
    if payload.category_id is not None:
        _own_category(db, user, payload.category_id)
    t = Transaction(
        account_id=acc.id,
        recurring_id=payload.recurring_id,
        category_id=payload.category_id,
        forecast_date=payload.forecast_date,
        actual_date=payload.actual_date,
        is_actual=payload.is_actual,
    )
    t.description = payload.description
    t.amount = Decimal(str(payload.amount))
    t.notes = payload.notes
    if payload.forecast_amount is not None:
        t.forecast_amount = Decimal(str(payload.forecast_amount))
    db.add(t)
    db.commit()
    db.refresh(t)
    return {"id": t.id}


@app.patch("/api/transactions/{tid}")
def update_transaction(tid: int, payload: TransactionIn,
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    t = db.get(Transaction, tid)
    if not t:
        raise HTTPException(404)
    _account_with_perm(db, user, t.account_id, "edit")
    if payload.category_id is not None:
        _own_category(db, user, payload.category_id)
    t.description = payload.description
    t.amount = Decimal(str(payload.amount))
    t.forecast_date = payload.forecast_date
    t.actual_date = payload.actual_date
    t.is_actual = payload.is_actual
    t.category_id = payload.category_id
    t.notes = payload.notes
    if payload.forecast_amount is not None:
        t.forecast_amount = Decimal(str(payload.forecast_amount))
    db.commit()
    return {"ok": True}


@app.delete("/api/transactions/{tid}")
def delete_transaction(tid: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    t = db.get(Transaction, tid)
    if not t:
        raise HTTPException(404)
    _account_with_perm(db, user, t.account_id, "edit")
    db.delete(t)
    db.commit()
    return {"ok": True}


# ---------- Forecast ----------
class ForecastActualIn(BaseModel):
    """Body for upserting an actual against a forecast row.

    If transaction_id is provided we update that transaction.
    Otherwise recurring_id + forecast_date + forecast_amount + description are
    required so we can create a brand-new Transaction backing this occurrence.
    Pass actual_amount=None and actual_date=None to clear the actual back to
    a pure forecast (deletes the transaction if it had no other purpose).
    """
    transaction_id: int | None = None
    recurring_id: int | None = None
    forecast_date: date | None = None
    forecast_amount: float | None = None
    description: str | None = None
    category_id: int | None = None
    actual_amount: float | None = None
    actual_date: date | None = None
    notes: str | None = Field(default=None, max_length=256)


@app.post("/api/accounts/{account_id}/forecast/actual")
def upsert_forecast_actual(account_id: int, payload: ForecastActualIn,
                           user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)

    # Update existing transaction
    if payload.transaction_id is not None:
        t = db.get(Transaction, payload.transaction_id)
        if not t or t.account_id != acc.id:
            raise HTTPException(404, "Transaction not found")
        if payload.actual_amount is None and payload.actual_date is None:
            # Clear the actual. If this transaction was a pure recurring-backed
            # actual (no manual content beyond the override), delete it so the
            # forecast view shows the template projection again.
            if t.recurring_id is not None:
                db.delete(t)
            else:
                t.is_actual = False
                t.actual_date = None
            db.commit()
            return {"ok": True}
        if payload.actual_amount is not None:
            t.amount = Decimal(str(payload.actual_amount))
        if payload.actual_date is not None:
            t.actual_date = payload.actual_date
        if payload.notes is not None:
            t.notes = payload.notes
        t.is_actual = True
        db.commit()
        return {"ok": True, "transaction_id": t.id}

    # Create a new transaction backing this forecast occurrence
    if payload.recurring_id is None or payload.forecast_date is None:
        raise HTTPException(400, "transaction_id or (recurring_id + forecast_date) is required")
    rec = db.get(RecurringTransaction, payload.recurring_id)
    if not rec or rec.account_id != acc.id:
        raise HTTPException(404, "Recurring template not found")
    fc_amt = payload.forecast_amount if payload.forecast_amount is not None else float(rec.amount)
    actual_amt = payload.actual_amount if payload.actual_amount is not None else fc_amt
    t = Transaction(
        account_id=acc.id,
        recurring_id=rec.id,
        category_id=payload.category_id if payload.category_id is not None else rec.category_id,
        forecast_date=payload.forecast_date,
        actual_date=payload.actual_date or payload.forecast_date,
        is_actual=True,
    )
    t.description = payload.description or rec.description
    t.amount = Decimal(str(actual_amt))
    t.forecast_amount = Decimal(str(fc_amt))
    t.notes = payload.notes if payload.notes is not None else rec.notes
    db.add(t)
    db.commit()
    db.refresh(t)
    return {"ok": True, "transaction_id": t.id}


@app.get("/api/accounts/{account_id}/forecast")
def forecast(account_id: int, days: int = 90,
             start: date | None = None, end: date | None = None,
             user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _account_with_perm(db, user, account_id, "read")
    if start is None or end is None:
        today = date.today()
        start = today
        end = today + timedelta(days=days)
    return build_forecast(db, acc, start, end)


# ---------- Backup: export / import ----------
@app.get("/api/backup/export")
def backup_export(account_ids: str | None = None,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    editable = _user_editable_accounts(db, user, include_archived=True)
    if account_ids:
        # CSV of account ids; filter to editable ones the caller actually has
        try:
            wanted = {int(x) for x in account_ids.split(",") if x.strip()}
        except ValueError:
            raise HTTPException(400, "Invalid account_ids (must be comma-separated integers)")
        accounts = [a for a in editable if a.id in wanted]
        if not accounts:
            raise HTTPException(404, "No matching accounts found")
    else:
        accounts = editable
    payload = export_user(db, user, accounts=accounts)
    filename = f"walletweather-backup-{date.today().isoformat()}.json"
    return JSONResponse(
        content=payload,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


class ImportIn(BaseModel):
    mode: str = "merge"  # 'merge' or 'replace'
    payload: dict
    account_names: list[str] | None = None  # if set, only import these by name


@app.post("/api/backup/import")
def backup_import(body: ImportIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    try:
        counts = import_user(db, user, body.payload, mode=body.mode,
                             account_names=body.account_names)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"ok": True, "imported": counts}


# ---------- Dashboard ----------
@app.get("/api/dashboard")
def dashboard(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Return per-account summary cards for the current month.

    For each account the user owns, runs a forecast for the current calendar
    month and computes:
      - forecast high (max of forecast_balance) and the date it occurs
      - forecast low (min of forecast_balance) and the date it occurs
      - actual high (max of actual_balance) — no date per spec
      - actual low (min of actual_balance) — no date per spec
      - opening / forecast_end / actual_end balances
    """
    today = date.today()
    # First and last day of current month
    start = date(today.year, today.month, 1)
    if today.month == 12:
        end = date(today.year, 12, 31)
    else:
        end = date(today.year, today.month + 1, 1) - timedelta(days=1)

    cards = []
    for acc in _user_visible_accounts(db, user):
        data = build_forecast(db, acc, start, end)
        rows = data["rows"]

        # Defaults: if there are no rows in this month, treat the opening
        # balance as the only "value" we know about for high/low purposes.
        if not rows:
            cards.append({
                "id": acc.id,
                "name": acc.name,
                "month_label": start.strftime("%B %Y"),
                "opening_balance": data["opening_balance"],
                "forecast_end": data["forecast_ending_balance"],
                "actual_end": data["actual_ending_balance"],
                "forecast_high": data["opening_balance"],
                "forecast_high_date": None,
                "forecast_low": data["opening_balance"],
                "forecast_low_date": None,
                "actual_high": data["opening_balance"],
                "actual_low": data["opening_balance"],
                "row_count": 0,
            })
            continue

        # Walk rows once to find min/max of both balances and the dates of
        # the forecast extremes (we don't need actual extreme dates).
        f_high = f_low = rows[0]["forecast_balance"]
        f_high_date = f_low_date = rows[0]["forecast_date"]
        a_high = a_low = rows[0]["actual_balance"]
        for r in rows:
            if r["forecast_balance"] > f_high:
                f_high = r["forecast_balance"]
                f_high_date = r["forecast_date"]
            if r["forecast_balance"] < f_low:
                f_low = r["forecast_balance"]
                f_low_date = r["forecast_date"]
            if r["actual_balance"] > a_high:
                a_high = r["actual_balance"]
            if r["actual_balance"] < a_low:
                a_low = r["actual_balance"]

        cards.append({
            "id": acc.id,
            "name": acc.name,
            "month_label": start.strftime("%B %Y"),
            "opening_balance": data["opening_balance"],
            "forecast_end": data["forecast_ending_balance"],
            "actual_end": data["actual_ending_balance"],
            "forecast_high": f_high,
            "forecast_high_date": f_high_date,
            "forecast_low": f_low,
            "forecast_low_date": f_low_date,
            "actual_high": a_high,
            "actual_low": a_low,
            "row_count": len(rows),
        })

    return {"cards": cards}


# ---------- Permissions ----------
class PermissionIn(BaseModel):
    account_id: int
    user_id: int
    level: str  # 'owner' | 'edit' | 'read' | 'deny'


@app.get("/api/permissions")
def list_permissions(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Return everything needed to render the permissions matrix."""
    editable = _user_editable_accounts(db, user)
    if not editable:
        return {"users": [], "accounts": [], "permissions": []}

    editable_ids = [a.id for a in editable]
    # All users in the system, since we need to be able to grant access to any.
    all_users = db.query(User).order_by(User.email).all()
    perms = (
        db.query(AccountPermission)
        .filter(AccountPermission.account_id.in_(editable_ids))
        .all()
    )
    # For each account, also include the caller's own level so the frontend
    # knows which columns they can manage owner rows on (vs just read/edit).
    account_rows = []
    for a in editable:
        account_rows.append({
            "id": a.id,
            "name": a.name,
            "caller_level": _user_level(db, user, a.id),
        })
    return {
        "self_id": user.id,
        "users": [{"id": u.id, "email": u.email, "name": u.name} for u in all_users],
        "accounts": account_rows,
        "permissions": [
            {"account_id": p.account_id, "user_id": p.user_id, "level": p.level}
            for p in perms
        ],
    }


@app.post("/api/permissions")
def set_permission(payload: PermissionIn,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    if payload.level not in ("owner", "edit", "read", "deny"):
        raise HTTPException(400, "Invalid level")

    # Caller must have at least edit on the account to touch any permission.
    _account_with_perm(db, user, payload.account_id, "edit")
    caller_level = _user_level(db, user, payload.account_id)

    target = db.get(User, payload.user_id)
    if not target:
        raise HTTPException(404, "User not found")

    existing = db.query(AccountPermission).filter_by(
        account_id=payload.account_id, user_id=payload.user_id
    ).first()
    existing_level = existing.level if existing else "deny"

    # --- Owner protection rules ---

    # An edit (non-owner) user cannot touch rows where the target currently
    # has owner. This blocks hostile takeover — only an owner can demote
    # another owner.
    if existing_level == "owner" and caller_level != "owner":
        raise HTTPException(
            403,
            "Only owners can modify other owners' permissions.",
        )

    # Only owners can grant owner. This prevents edit users from minting new
    # owners (whether themselves or anyone else).
    if payload.level == "owner" and caller_level != "owner":
        raise HTTPException(
            403,
            "Only owners can promote users to owner.",
        )

    # --- Last-owner guardrail ---
    # Never let the change leave an account with zero owners. This matters if
    # an owner is demoting themselves or another owner: at least one owner
    # must remain on the account.
    if existing_level == "owner" and payload.level != "owner":
        owner_count = db.query(AccountPermission).filter_by(
            account_id=payload.account_id, level="owner"
        ).count()
        if owner_count <= 1:
            raise HTTPException(
                400,
                "Cannot remove the last owner. Promote someone else to owner first.",
            )

    # --- Last-edit-user guardrail (kept from before) ---
    # If the user is being demoted from edit+ to read/deny and there would be
    # no more edit+ users on the account, refuse. This is a UX safety net,
    # distinct from the owner guardrail above.
    if existing_level in ("owner", "edit") and payload.level in ("read", "deny"):
        editor_count = db.query(AccountPermission).filter_by(
            account_id=payload.account_id
        ).filter(AccountPermission.level.in_(["owner", "edit"])).count()
        if editor_count <= 1:
            raise HTTPException(
                400,
                "Cannot remove the last user with edit access. Grant edit to "
                "someone else first.",
            )

    # --- Apply ---
    if payload.level == "deny":
        if existing:
            db.delete(existing)
            db.commit()
        return {"ok": True, "level": "deny"}

    if existing:
        existing.level = payload.level
    else:
        db.add(AccountPermission(
            account_id=payload.account_id,
            user_id=payload.user_id,
            level=payload.level,
        ))
    db.commit()
    return {"ok": True, "level": payload.level}


# ---------- Reports ----------
@app.get("/api/report")
def report(start: date | None = None, end: date | None = None,
           account_id: int | None = None,
           user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Category rollup of forecast and actual amounts across selected accounts.

    - start/end: defaults to the current calendar month
    - account_id: restrict to a single account; otherwise all visible accounts
    - Each row in the response represents one category. Rows with no activity
      in the period are omitted. Uncategorized transactions are bucketed under
      the synthetic "(uncategorized)" name.
    - Spending is negative, income is positive (matching the storage convention).
    - The response is intentionally redundant (forecast and actual side-by-side)
      so the frontend can render multiple cuts without re-computing.
    """
    # Default to current calendar month
    if start is None or end is None:
        today = date.today()
        start = date(today.year, today.month, 1)
        if today.month == 12:
            end = date(today.year, 12, 31)
        else:
            end = date(today.year, today.month + 1, 1) - timedelta(days=1)

    # Pick accounts the user can read
    visible = _user_visible_accounts(db, user)
    if account_id is not None:
        visible = [a for a in visible if a.id == account_id]
        if not visible:
            raise HTTPException(404, "Account not found")

    # Walk every account's forecast in the window. We use build_forecast so
    # that recurring template projections are included alongside materialized
    # transactions, matching what the user sees in the forecast view.
    # Each row contributes to the category bucket twice: once for forecast,
    # once for actual (using the displayed/defaulted actual values).
    cat_buckets: dict[str, dict] = {}
    UNCAT = "(uncategorized)"

    def _bucket(name):
        if name not in cat_buckets:
            cat_buckets[name] = {
                "name": name,
                "forecast_total": 0.0,
                "actual_total": 0.0,
                "forecast_count": 0,
                "actual_count": 0,
            }
        return cat_buckets[name]

    for acc in visible:
        data = build_forecast(db, acc, start, end)
        for r in data["rows"]:
            cat = r.get("category") or UNCAT
            b = _bucket(cat)
            f = r.get("forecast_amount")
            a = r.get("actual_amount")
            if f is not None:
                b["forecast_total"] += f
                b["forecast_count"] += 1
            if a is not None:
                b["actual_total"] += a
                b["actual_count"] += 1

    # Look up the actual category records for color info. Categories are per-
    # user, not per-account, so a single query covers everything.
    cat_colors: dict[str, str | None] = {}
    for c in db.query(Category).filter_by(owner_id=user.id).all():
        cat_colors[c.name] = c.color

    categories_out = []
    for name, b in sorted(cat_buckets.items()):
        # Skip rows that are pure zero (no activity at all)
        if b["forecast_count"] == 0 and b["actual_count"] == 0:
            continue
        categories_out.append({
            "name": name,
            "color": cat_colors.get(name),
            "forecast_total": round(b["forecast_total"], 2),
            "actual_total": round(b["actual_total"], 2),
            "forecast_count": b["forecast_count"],
            "actual_count": b["actual_count"],
        })

    # Top-line totals (income = positive sums, spending = negative sums)
    f_income = sum(c["forecast_total"] for c in categories_out if c["forecast_total"] > 0)
    a_income = sum(c["actual_total"]   for c in categories_out if c["actual_total"]   > 0)
    f_spend  = sum(c["forecast_total"] for c in categories_out if c["forecast_total"] < 0)
    a_spend  = sum(c["actual_total"]   for c in categories_out if c["actual_total"]   < 0)

    return {
        "start": start.isoformat(),
        "end": end.isoformat(),
        "accounts": [{"id": a.id, "name": a.name} for a in visible],
        "categories": categories_out,
        "totals": {
            "forecast_income":   round(f_income, 2),
            "actual_income":     round(a_income, 2),
            "forecast_spending": round(f_spend,  2),
            "actual_spending":   round(a_spend,  2),
            "forecast_net":      round(f_income + f_spend, 2),
            "actual_net":        round(a_income + a_spend, 2),
        },
    }


# ---------- Admin ----------
class AdminUserPatchIn(BaseModel):
    disabled: bool | None = None
    new_password: str | None = Field(default=None, min_length=8, max_length=128)


class AdminBackupConfigIn(BaseModel):
    enabled: bool
    frequency: str = "daily"  # 'daily' | 'weekly' | 'monthly'
    hour: int = 3
    retention_days: int = 30


@app.get("/api/admin/users")
def admin_list_users(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    users = db.query(User).order_by(User.id).all()
    out = []
    for u in users:
        acct_count = db.query(AccountPermission).filter_by(user_id=u.id).filter(
            AccountPermission.level.in_(["owner", "edit", "read"])
        ).count()
        owned_count = db.query(AccountPermission).filter_by(
            user_id=u.id, level="owner"
        ).count()
        out.append({
            "id": u.id,
            "email": u.email,
            "name": u.name,
            "disabled": u.disabled,
            "is_admin": is_admin(u),
            "created_at": u.created_at.isoformat() if u.created_at else None,
            "account_count": acct_count,
            "owned_count": owned_count,
            "has_password": u.password_hash is not None,
            "has_google": u.google_sub is not None,
        })
    return out


@app.patch("/api/admin/users/{uid}")
def admin_update_user(uid: int, payload: AdminUserPatchIn,
                      user: User = Depends(current_admin), db: Session = Depends(get_db)):
    target = db.get(User, uid)
    if not target:
        raise HTTPException(404, "User not found")
    # Protect against disabling yourself
    if payload.disabled is not None:
        if target.id == user.id and payload.disabled:
            raise HTTPException(400, "Cannot disable your own account")
        target.disabled = payload.disabled
    if payload.new_password is not None:
        target.password_hash = hash_password(payload.new_password)
    db.commit()
    return {"ok": True}


@app.delete("/api/admin/users/{uid}")
def admin_delete_user(uid: int,
                      user: User = Depends(current_admin), db: Session = Depends(get_db)):
    target = db.get(User, uid)
    if not target:
        raise HTTPException(404, "User not found")
    if target.id == user.id:
        raise HTTPException(400, "Cannot delete your own account")
    db.delete(target)
    db.commit()
    return {"ok": True}


@app.get("/api/admin/permissions")
def admin_list_permissions(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Return ALL permissions across ALL accounts (admin view)."""
    all_accounts = db.query(Account).order_by(Account.id).all()
    all_users = db.query(User).order_by(User.email).all()
    perms = db.query(AccountPermission).all()
    return {
        "self_id": user.id,
        "users": [{"id": u.id, "email": u.email, "name": u.name} for u in all_users],
        "accounts": [{"id": a.id, "name": a.name, "caller_level": "admin"}
                     for a in all_accounts],
        "permissions": [
            {"account_id": p.account_id, "user_id": p.user_id, "level": p.level}
            for p in perms
        ],
    }


@app.post("/api/admin/permissions")
def admin_set_permission(payload: PermissionIn,
                         user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Set any permission on any account (admin override).
    Admins bypass the owner-only restrictions and can assign any level.
    The only guardrail kept: cannot leave an account with zero owners."""
    if payload.level not in ("owner", "edit", "read", "deny"):
        raise HTTPException(400, "Invalid level")
    acc = db.get(Account, payload.account_id)
    if not acc:
        raise HTTPException(404, "Account not found")
    target = db.get(User, payload.user_id)
    if not target:
        raise HTTPException(404, "User not found")

    existing = db.query(AccountPermission).filter_by(
        account_id=payload.account_id, user_id=payload.user_id
    ).first()
    existing_level = existing.level if existing else "deny"

    # Last-owner guardrail
    if existing_level == "owner" and payload.level != "owner":
        owner_count = db.query(AccountPermission).filter_by(
            account_id=payload.account_id, level="owner"
        ).count()
        if owner_count <= 1:
            raise HTTPException(400, "Cannot remove the last owner. Promote someone else first.")

    if payload.level == "deny":
        if existing:
            db.delete(existing)
            db.commit()
        return {"ok": True, "level": "deny"}

    if existing:
        existing.level = payload.level
    else:
        db.add(AccountPermission(
            account_id=payload.account_id,
            user_id=payload.user_id,
            level=payload.level,
        ))
    db.commit()
    return {"ok": True, "level": payload.level}


@app.get("/api/admin/backup-config")
def admin_get_backup_config(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    sched = db.query(BackupSchedule).first()
    if not sched:
        return {"enabled": False, "frequency": "daily", "hour": 3,
                "retention_days": 30, "last_run_at": None, "last_run_status": None}
    return {
        "enabled": sched.enabled,
        "frequency": sched.frequency,
        "hour": sched.hour,
        "retention_days": sched.retention_days,
        "last_run_at": sched.last_run_at.isoformat() if sched.last_run_at else None,
        "last_run_status": sched.last_run_status,
    }


@app.post("/api/admin/backup-config")
def admin_set_backup_config(payload: AdminBackupConfigIn,
                            user: User = Depends(current_admin), db: Session = Depends(get_db)):
    if payload.frequency not in ("daily", "weekly", "monthly"):
        raise HTTPException(400, "Invalid frequency")
    if not (0 <= payload.hour <= 23):
        raise HTTPException(400, "Hour must be 0-23")
    if payload.retention_days < 1:
        raise HTTPException(400, "Retention must be at least 1 day")
    sched = db.query(BackupSchedule).first()
    if not sched:
        sched = BackupSchedule()
        db.add(sched)
    sched.enabled = payload.enabled
    sched.frequency = payload.frequency
    sched.hour = payload.hour
    sched.retention_days = payload.retention_days
    db.commit()
    return {"ok": True}


@app.get("/api/admin/backups")
def admin_list_backups(user: User = Depends(current_admin)):
    """List backup files on disk, newest first."""
    files = sorted(BACKUP_DIR.glob("system-backup-*.json"), reverse=True)
    out = []
    for f in files:
        try:
            stat = f.stat()
            out.append({
                "filename": f.name,
                "size": stat.st_size,
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
            })
        except OSError:
            pass
    return out


@app.post("/api/admin/backups/now")
def admin_trigger_backup(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    try:
        filename = _run_system_backup()
        # Update schedule status so the admin panel shows when the last backup ran
        sched = db.query(BackupSchedule).first()
        if sched:
            sched.last_run_at = datetime.utcnow()
            sched.last_run_status = f"OK (manual): {filename}"
            db.commit()
        return {"ok": True, "filename": filename}
    except Exception as e:
        raise HTTPException(500, f"Backup failed: {e}")


@app.post("/api/admin/backups/restore/{filename}")
def admin_restore_backup(filename: str,
                         user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Restore from a local system backup file. This is a destructive operation
    that replaces ALL data for ALL users present in the backup."""
    filepath = BACKUP_DIR / filename
    if not filepath.exists() or not filepath.name.startswith("system-backup-"):
        raise HTTPException(404, "Backup file not found")
    try:
        payload = json.loads(filepath.read_text())
    except (json.JSONDecodeError, OSError) as e:
        raise HTTPException(400, f"Could not read backup: {e}")
    if not payload.get("system_backup") or "users" not in payload:
        raise HTTPException(400, "Not a valid system backup file")

    # Restore each user's data. For each user in the backup, find or create
    # the user by email, then use the existing import_user in replace mode.
    from .backup import import_user
    restored = {"users": 0, "accounts": 0}
    for udata in payload["users"]:
        email = udata.get("user", {}).get("email")
        if not email:
            continue
        target = db.query(User).filter_by(email=email.lower()).first()
        if not target:
            # Create the user (no password — they can reset via admin later)
            target = User(email=email.lower(), name=udata.get("user", {}).get("name", ""))
            db.add(target)
            db.commit()
            db.refresh(target)
        counts = import_user(db, target, udata, mode="replace")
        restored["users"] += 1
        restored["accounts"] += counts.get("accounts", 0)
    return {"ok": True, "restored": restored}


@app.get("/api/admin/backups/download/{filename}")
def admin_download_backup(filename: str, user: User = Depends(current_admin)):
    filepath = BACKUP_DIR / filename
    if not filepath.exists() or not filepath.name.startswith("system-backup-"):
        raise HTTPException(404, "Backup file not found")
    return FileResponse(filepath, media_type="application/json",
                        headers={"Content-Disposition": f'attachment; filename="{filename}"'})


# ---------- Static frontend ----------
STATIC_DIR = Path(__file__).parent.parent / "static"
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/")
    def index():
        return FileResponse(STATIC_DIR / "index.html")
