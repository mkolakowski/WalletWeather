"""Export/import of a user's data, and the encrypted backup file around it.

The export decrypts all Fernet-protected fields so the backup is portable and
restorable even if the server's ENCRYPTION_KEY is lost. Since bank-sync phase 1
(#193) every backup is then sealed with a passphrase (`seal` / `open_sealed`),
so the file itself can't be read without it. The plain JSON is still what
"Download my data" hands out, as a copy to read rather than a backup, and
plain backup files from earlier versions still import.
"""
import base64
import json
import re
import secrets
from datetime import date, datetime
from decimal import Decimal

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from sqlalchemy.orm import Session

from .db import (
    User, Account, RecurringTransaction, RecurringSkip, RecurringTag, Transaction,
    TransactionTag, Category, AccountPermission, Tag, TagRule, BankConnection, BankAccountLink,
    MailConnection, MailSender, MailAlertKind, encrypt_str, decrypt_str,
)

# 4 (#117): tags, tag rules, and each recurring item's and transaction's tag
# names. Every addition is an optional key, so older backups still import.
BACKUP_VERSION = 4
TAG_NAME_MAX = 60          # Tag.name's column size
TAG_RULE_PATTERN_MAX = 120
_HEX_COLOR = re.compile(r"#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?")


# ---------- The encrypted file (#193) ----------
# A sealed backup is a small JSON object: a header saying how it was sealed,
# then the backup's JSON encrypted with AES-256-GCM under a key that scrypt
# derives from the passphrase. The header is bound to the ciphertext as
# associated data, so editing any of it makes the file refuse to open.
# Everything needed to open it is in the file, so it restores on any server
# with only the passphrase. The marker and field names below are read back
# from files on people's disks: never rename them (a new layout bumps
# SEALED_FORMAT and keeps reading the old one).
SEALED_MARKER = "walletweather-encrypted-backup"
SEALED_FORMAT = 1
PASSPHRASE_MIN = 12          # decided 2026-11-16 (#193)
# scrypt at the cost OWASP recommends (128 MiB, a fraction of a second).
SCRYPT_N, SCRYPT_R, SCRYPT_P = 2 ** 17, 8, 1
# A file says its own cost; refuse one asking for more than this, so a
# hand-made file can't make the server spend gigabytes trying it.
_SCRYPT_N_MAX, _SCRYPT_R_MAX, _SCRYPT_P_MAX = 2 ** 18, 16, 4

WRONG_PASSPHRASE = "That passphrase doesn't open this backup. Nothing was changed."


class BackupLocked(ValueError):
    """The file is encrypted and no passphrase, or the wrong one, was given."""


def passphrase_problem(passphrase) -> str | None:
    """Why a passphrase can't seal a backup, or None when it can."""
    if not isinstance(passphrase, str) or not passphrase:
        return "Enter a passphrase."
    if len(passphrase) < PASSPHRASE_MIN:
        return f"The passphrase must be at least {PASSPHRASE_MIN} characters."
    return None


def is_sealed(payload) -> bool:
    return isinstance(payload, dict) and payload.get("walletweather") == SEALED_MARKER


def _b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def _unb64(value) -> bytes:
    if not isinstance(value, str):
        raise ValueError("bad field")
    return base64.b64decode(value, validate=True)


def _header_bytes(header: dict) -> bytes:
    return json.dumps(header, sort_keys=True, separators=(",", ":")).encode()


def _key(passphrase: str, salt: bytes, n: int, r: int, p: int) -> bytes:
    return Scrypt(salt=salt, length=32, n=n, r=r, p=p).derive(passphrase.encode("utf-8"))


def seal(payload: dict, passphrase: str, kind: str = "user") -> dict:
    """The backup `payload` encrypted with `passphrase`, as a JSON-ready dict.
    `kind` ("user" or "system") is left readable so a restore screen can say
    what the file is before it's opened."""
    problem = passphrase_problem(passphrase)
    if problem:
        raise ValueError(problem)
    salt, nonce = secrets.token_bytes(16), secrets.token_bytes(12)
    header = {
        "walletweather": SEALED_MARKER,
        "format": SEALED_FORMAT,
        "kind": kind,
        "exported_at": payload.get("exported_at"),
        "kdf": {"name": "scrypt", "n": SCRYPT_N, "r": SCRYPT_R, "p": SCRYPT_P, "salt": _b64(salt)},
        "cipher": {"name": "AES-256-GCM", "nonce": _b64(nonce)},
    }
    key = _key(passphrase, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P)
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ciphertext = AESGCM(key).encrypt(nonce, body, _header_bytes(header))
    # The ciphertext goes last, so the header can be read from a file's first
    # few hundred bytes (the Admin list does).
    return {**header, "ciphertext": _b64(ciphertext)}


def open_sealed(sealed: dict, passphrase) -> dict:
    """The backup inside a sealed file. Raises BackupLocked for a missing or
    wrong passphrase and ValueError for a file that isn't one or is damaged."""
    if not is_sealed(sealed):
        raise ValueError("Not an encrypted WalletWeather backup.")
    if sealed.get("format") != SEALED_FORMAT:
        raise ValueError("This backup was made by a newer version of WalletWeather. "
                         "Update this server, then restore it.")
    if not isinstance(passphrase, str) or not passphrase:
        raise BackupLocked("This backup is encrypted. Enter its passphrase.")
    damaged = "This backup file is damaged and can't be opened."
    header = {k: v for k, v in sealed.items() if k != "ciphertext"}
    try:
        kdf, cipher = sealed["kdf"], sealed["cipher"]
        n, r, p = kdf["n"], kdf["r"], kdf["p"]
        if (kdf.get("name") != "scrypt" or cipher.get("name") != "AES-256-GCM"
                or not all(type(x) is int for x in (n, r, p))
                or not (2 <= n <= _SCRYPT_N_MAX and n & (n - 1) == 0)
                or not (1 <= r <= _SCRYPT_R_MAX and 1 <= p <= _SCRYPT_P_MAX)):
            raise ValueError
        salt, nonce = _unb64(kdf["salt"]), _unb64(cipher["nonce"])
        ciphertext = _unb64(sealed["ciphertext"])
        if len(salt) < 16 or len(nonce) != 12:
            raise ValueError
    except (KeyError, TypeError, ValueError):
        raise ValueError(damaged)
    try:
        body = AESGCM(_key(passphrase, salt, n, r, p)).decrypt(nonce, ciphertext, _header_bytes(header))
    except InvalidTag:
        # A wrong passphrase and an edited file look the same to AES-GCM;
        # the passphrase is by far the likelier.
        raise BackupLocked(WRONG_PASSPHRASE)
    try:
        payload = json.loads(body)
    except ValueError:
        raise ValueError(damaged)
    if not isinstance(payload, dict):
        raise ValueError(damaged)
    return payload


def unwrap(payload, passphrase) -> tuple[dict, bool]:
    """`(backup, was_encrypted)` for a file as uploaded: a sealed file is
    opened with the passphrase, a plain one from an earlier version is
    passed through (decided 2026-11-16, #193: plain files still import)."""
    if is_sealed(payload):
        return open_sealed(payload, passphrase), True
    if not isinstance(payload, dict):
        raise ValueError("Not a valid backup file.")
    return payload, False


def _color(value) -> str | None:
    """A backup's colour if it is a hex colour, otherwise none: a file can
    be edited by hand, and colours end up in the page's markup (#183)."""
    return value if isinstance(value, str) and _HEX_COLOR.fullmatch(value) else None


def _tag_names(db: Session, link, key: str, ids: list[int]) -> dict[int, list[str]]:
    """`{id: [tag names]}` for a batch of recurring items or transactions
    (`link` is RecurringTag or TransactionTag, `key` its id column)."""
    if not ids:
        return {}
    col = getattr(link, key)
    out: dict[int, list[str]] = {}
    for item_id, name in (db.query(col, Tag.name).join(Tag, Tag.id == link.tag_id)
                            .filter(col.in_(ids)).order_by(Tag.name).all()):
        out.setdefault(item_id, []).append(name)
    return out


def export_user(db: Session, user: User, accounts: list | None = None,
                include_bank: bool = False) -> dict:
    """Return a JSON-serializable dict containing the given accounts plus the user's
    categories. If `accounts` is None, exports all accounts owned by `user`
    (legacy behavior, kept for compatibility). `include_bank` adds the user's
    bank connection: only for a backup that is then sealed, never for
    "Download my data" (decided 2026-11-16, #193, #194)."""
    categories_out = [
        {"name": c.name, "color": c.color}
        for c in db.query(Category).filter_by(owner_id=user.id).all()
    ]
    tags_out = [
        {"name": t.name, "color": t.color}
        for t in db.query(Tag).filter_by(owner_id=user.id).order_by(Tag.name).all()
    ]
    tag_rules_out = []
    for r in db.query(TagRule).filter_by(owner_id=user.id).order_by(TagRule.id).all():
        tag, cat = db.get(Tag, r.tag_id), (db.get(Category, r.category_id) if r.category_id else None)
        if not tag:
            continue
        tag_rules_out.append({
            "name": r.name, "description_pattern": r.description_pattern,
            "category_name": cat.name if cat else None, "tag_name": tag.name,
            "active": r.active,
        })

    if accounts is None:
        accounts = db.query(Account).filter_by(owner_id=user.id).all()

    accounts_out = []
    for acc in accounts:
        rec_tags = _tag_names(db, RecurringTag, "recurring_id", [r.id for r in acc.recurring])
        txn_tags = _tag_names(db, TransactionTag, "transaction_id", [t.id for t in acc.transactions])
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
                    "tags": rec_tags.get(r.id, []),
                    # Bank-match settings (#196). Older backups lack them.
                    "match_days": r.match_days,
                    "match_percent": r.match_percent,
                    # Occurrences deleted from the forecast. Older backups
                    # lack this key; restore treats that as "none".
                    "skipped_dates": sorted(
                        d.isoformat() for (d,) in
                        db.query(RecurringSkip.skip_date).filter_by(recurring_id=r.id)
                    ),
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
                    "tags": txn_tags.get(t.id, []),
                    # A hash of the bank's ids, so a restored line isn't
                    # synced again (#194). Older backups lack it.
                    "bank_ref": t.bank_ref,
                    # The same for a line from an email alert (#206).
                    "mail_ref": t.mail_ref,
                    # Bills matched by bank sync (#196). Older backups lack them.
                    "bank_match": t.bank_match,
                    "bank_text": t.bank_text,
                    "bank_left": bool(t.bank_left),
                }
                for t in acc.transactions
            ],
        })

    out = {
        "version": BACKUP_VERSION,
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "user": {"email": user.email, "name": user.name},
        "categories": categories_out,
        "tags": tags_out,
        "tag_rules": tag_rules_out,
        "accounts": accounts_out,
    }
    if include_bank:
        bank = _export_bank(db, user, accounts)
        if bank:
            out["bank_connection"] = bank
        mail = _export_mail(db, user, accounts)
        if mail:
            out["mail_connection"] = mail
    return out


def _export_bank(db: Session, user: User, accounts: list) -> dict | None:
    conn = db.query(BankConnection).filter_by(user_id=user.id).first()
    if not conn:
        return None
    names = {a.id: a.name for a in accounts}
    links = [{"bank_account_ref": l.bank_account_ref, "account_name": names[l.account_id],
              "start_date": l.start_date.isoformat(),
              "synced_through": l.synced_through.isoformat() if l.synced_through else None}
             for l in db.query(BankAccountLink).filter_by(connection_id=conn.id)
             if l.account_id in names]
    try:
        listing = json.loads(decrypt_str(conn.accounts_enc)) if conn.accounts_enc else []
    except Exception:
        listing = []
    return {"access_url": decrypt_str(conn.access_url_enc), "accounts": listing, "links": links}


_HEX64 = re.compile(r"[0-9a-f]{64}")


def _import_bank(db: Session, user: User, data, acc_by_name: dict) -> bool:
    """Restore a backup's bank connection for a user who has none, matching
    its links to the accounts this import made, by name. Returns whether one
    was restored."""
    if not isinstance(data, dict) or not isinstance(data.get("access_url"), str):
        return False
    if db.query(BankConnection).filter_by(user_id=user.id).first():
        return False
    access = data["access_url"].strip()[:2000]
    if not access.startswith("https://"):
        return False
    listing = [a for a in (data.get("accounts") or []) if isinstance(a, dict)
               and isinstance(a.get("id"), str)][:100]
    listing = [{"id": a["id"][:200], "name": _text(a.get("name"), 120),
                "org": _text(a.get("org"), 120)} for a in listing]
    conn = BankConnection(user_id=user.id, access_url_enc=encrypt_str(access),
                          accounts_enc=encrypt_str(json.dumps(listing)), calls_json="[]")
    db.add(conn)
    db.flush()
    used_refs, used_accounts = set(), set()
    for l in data.get("links") or []:
        if not isinstance(l, dict):
            continue
        ref, acc = l.get("bank_account_ref"), acc_by_name.get(l.get("account_name"))
        if (not isinstance(ref, str) or not _HEX64.fullmatch(ref) or acc is None
                or ref in used_refs or acc.id in used_accounts):
            continue
        try:
            start = _parse_date(l.get("start_date")) or date.today()
            through = _parse_date(l.get("synced_through"))
        except (TypeError, ValueError):
            continue
        used_refs.add(ref)
        used_accounts.add(acc.id)
        db.add(BankAccountLink(connection_id=conn.id, bank_account_ref=ref, account_id=acc.id,
                               start_date=start, synced_through=through))
    return True


def _export_kinds(db: Session, sender) -> list:
    out = []
    for k in db.query(MailAlertKind).filter_by(sender_id=sender.id).order_by(MailAlertKind.id):
        try:
            out.append({"subject_key": k.subject_key, "direction": k.direction,
                        "anchors": json.loads(decrypt_str(k.anchors_enc)),
                        "sample": decrypt_str(k.sample_enc)})
        except Exception:
            continue
    return out


def _export_mail(db: Session, user: User, accounts: list) -> dict | None:
    """The user's mailbox for email alerts (#206): the sign-in, the folder and
    what was taught, with accounts by name. Only into sealed backups."""
    conn = db.query(MailConnection).filter_by(user_id=user.id).first()
    if not conn:
        return None
    try:
        tokens = json.loads(decrypt_str(conn.tokens_enc))
    except Exception:
        return None   # a damaged sign-in must not stop the whole system backup
    names = {a.id: a.name for a in accounts}
    senders = []
    for s in db.query(MailSender).filter_by(connection_id=conn.id).order_by(MailSender.id):
        try:
            cards = json.loads(s.cards_json or "{}")
        except ValueError:
            cards = {}
        senders.append({
            "address": s.address, "label": s.label, "account_name": names.get(s.account_id),
            "cards": {k: names[v] for k, v in cards.items() if v in names},
            "kinds": _export_kinds(db, s),
        })
    return {"provider": conn.provider, "auth_mode": conn.auth_mode,
            "tokens": tokens,
            "address": decrypt_str(conn.address_enc) if conn.address_enc else None,
            "folder_id": conn.folder_id, "folder_name": conn.folder_name,
            "start_date": conn.start_date.isoformat(),
            "utc_offset_minutes": conn.utc_offset_minutes,
            "check_minutes": conn.check_minutes,
            "scanned_through": conn.scanned_through.isoformat() if conn.scanned_through else None,
            "senders": senders}


def _anchor_ok(a) -> bool:
    return (isinstance(a, dict) and isinstance(a.get("before"), str) and isinstance(a.get("after"), str)
            and len(a["before"]) <= 200 and len(a["after"]) <= 200)


def _import_mail(db: Session, user: User, data, acc_by_name: dict) -> bool:
    """Restore a backup's mailbox for a user who has none, matching accounts
    by name. Returns whether one was restored."""
    if not isinstance(data, dict) or not isinstance(data.get("tokens"), dict):
        return False
    if db.query(MailConnection).filter_by(user_id=user.id).first():
        return False
    tokens = {k: data["tokens"].get(k) for k in ("access", "refresh", "expires_at")}
    if not isinstance(tokens["refresh"], str) or len(tokens["refresh"]) > 20000:
        return False
    try:
        start = _parse_date(data.get("start_date")) or date.today()
        scanned = datetime.fromisoformat(data["scanned_through"]) if data.get("scanned_through") else None
    except (TypeError, ValueError):
        start, scanned = date.today(), None
    offset = data.get("utc_offset_minutes")
    conn = MailConnection(
        user_id=user.id, provider="microsoft",
        auth_mode="web" if data.get("auth_mode") == "web" else "device",
        tokens_enc=encrypt_str(json.dumps(tokens)),
        address_enc=encrypt_str(_text(data["address"], 320)) if isinstance(data.get("address"), str) else None,
        folder_id=_text(data.get("folder_id"), 400) or None,
        folder_name=_text(data.get("folder_name"), 200) or None,
        start_date=start, scanned_through=scanned,
        utc_offset_minutes=offset if isinstance(offset, int) and -840 <= offset <= 840 else 0,
        check_minutes=data.get("check_minutes") if data.get("check_minutes") in (5, 15, 60) else 5)
    db.add(conn)
    db.flush()
    seen = set()
    for s in (data.get("senders") or [])[:100]:
        if not isinstance(s, dict) or not isinstance(s.get("address"), str):
            continue
        address = _text(s["address"], 320).lower()
        if not address or address in seen:
            continue
        seen.add(address)
        acc = acc_by_name.get(s.get("account_name"))
        cards = {}
        for last4, name in (s.get("cards") or {}).items() if isinstance(s.get("cards"), dict) else []:
            if isinstance(last4, str) and re.fullmatch(r"\d{4}", last4) and acc_by_name.get(name):
                cards[last4] = acc_by_name[name].id
        sender = MailSender(connection_id=conn.id, address=address,
                            label=_text(s.get("label"), 80) or address,
                            account_id=acc.id if acc else None, cards_json=json.dumps(cards))
        db.add(sender)
        db.flush()
        for k in (s.get("kinds") or [])[:50]:
            if not isinstance(k, dict) or not isinstance(k.get("anchors"), dict):
                continue
            anchors = {f: a for f, a in k["anchors"].items()
                       if f in ("amount", "merchant", "date", "card") and _anchor_ok(a)}
            key = _text(k.get("subject_key"), 200).lower()
            if "amount" not in anchors or len(key) < 3:
                continue
            db.add(MailAlertKind(sender_id=sender.id, subject_key=key,
                                 direction="in" if k.get("direction") == "in" else "out",
                                 anchors_enc=encrypt_str(json.dumps(anchors)),
                                 sample_enc=encrypt_str(_text(k.get("sample"), 20000))))
    return True


def _rec_desc_for(txn: Transaction) -> str | None:
    if txn.recurring_id and txn.account:
        for r in txn.account.recurring:
            if r.id == txn.recurring_id:
                return r.description
    return None


def _amount(value) -> Decimal:
    """A backup's number as an amount: finite and of a size money comes in
    (security-fixes phase 2, #185). A file can be edited by hand."""
    try:
        d = Decimal(str(value))
    except Exception:
        raise ValueError(f"Not an amount: {value!r}")
    if not d.is_finite() or abs(d) > Decimal("1e12"):
        raise ValueError(f"Not an amount: {value!r}")
    return d


def _text(value, limit: int) -> str:
    return str(value if value is not None else "")[:limit]


def _frequency(value) -> str:
    """Kept as written, cut to the column's size: the forecast projects
    nothing for a frequency it doesn't know, so an old backup still restores."""
    return str(value or "monthly_day")[:20]


def _bounded_int(value, lo: int, hi: int, default: int) -> int:
    """A whole number from a backup within [lo, hi], else `default`."""
    if isinstance(value, bool) or not isinstance(value, int) or not lo <= value <= hi:
        return default
    return value


def _day_of_month(value):
    """A day the forecast can use, or none (it then projects nothing)."""
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 31:
        return None
    return value


def _parse_date(s):
    if not s:
        return None
    return date.fromisoformat(s)


def import_user(db: Session, user: User, payload: dict, mode: str = "merge",
                account_names: list[str] | None = None) -> dict:
    """Import a previously exported payload into `user`'s account.

    mode='replace' — delete the user's existing accounts, categories and tags
                     (and their tag rules) first.
    mode='merge'   — keep existing data and add alongside. Categories and tags
                     with the same name are reused; new ones are created.
    account_names  — if provided, only import accounts whose name is in this list.
                     If None, every account in the backup is imported.

    Returns a small summary dict. Accepts backups from versions 1 to 4.
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
        if isinstance(payload.get("bank_connection"), dict):
            # The backup's connection replaces theirs (#194).
            for conn in db.query(BankConnection).filter_by(user_id=user.id).all():
                db.delete(conn)
        if isinstance(payload.get("mail_connection"), dict):
            # And its mailbox theirs (#206).
            for conn in db.query(MailConnection).filter_by(user_id=user.id).all():
                db.delete(conn)
        for acc in db.query(Account).filter_by(owner_id=user.id).all():
            db.delete(acc)
        for cat in db.query(Category).filter_by(owner_id=user.id).all():
            db.delete(cat)
        # Deleting a tag removes its links and rules (ON DELETE CASCADE).
        for tag in db.query(Tag).filter_by(owner_id=user.id).all():
            db.delete(tag)
        db.flush()

    counts = {"categories": 0, "accounts": 0, "recurring": 0, "transactions": 0,
              "tags": 0, "tag_rules": 0}
    acc_by_name: dict[str, Account] = {}

    cat_by_name: dict[str, Category] = {}
    for c in db.query(Category).filter_by(owner_id=user.id).all():
        cat_by_name[c.name] = c
    for c_data in payload.get("categories", []):
        name = str(c_data.get("name", "")).strip()[:80]
        if not name or name in cat_by_name:
            continue
        cat = Category(owner_id=user.id, name=name, color=_color(c_data.get("color")))
        db.add(cat)
        db.flush()
        cat_by_name[name] = cat
        counts["categories"] += 1

    # Tags are matched by name. One that's used but not listed (a tag from
    # someone else's share, or a hand-edited file) is created without a colour.
    tag_by_name: dict[str, Tag] = {t.name: t for t in db.query(Tag).filter_by(owner_id=user.id).all()}

    def get_tag(name, color=None) -> Tag | None:
        name = str(name or "").strip()[:TAG_NAME_MAX]
        if not name:
            return None
        if name not in tag_by_name:
            tag = Tag(owner_id=user.id, name=name, color=_color(color))
            db.add(tag)
            db.flush()
            tag_by_name[name] = tag
            counts["tags"] += 1
        return tag_by_name[name]

    for tg in payload.get("tags") or []:
        if isinstance(tg, dict):
            get_tag(tg.get("name"), tg.get("color"))

    seen_rules = {(r.description_pattern, r.tag_id, r.category_id)
                  for r in db.query(TagRule).filter_by(owner_id=user.id).all()}
    for rd in payload.get("tag_rules") or []:
        if not isinstance(rd, dict):
            continue
        pattern = str(rd.get("description_pattern") or "").strip().lower()[:TAG_RULE_PATTERN_MAX]
        tag = get_tag(rd.get("tag_name"))
        if not pattern or tag is None:
            continue
        cat = cat_by_name.get(rd.get("category_name")) if rd.get("category_name") else None
        key = (pattern, tag.id, cat.id if cat else None)
        if key in seen_rules:
            continue
        seen_rules.add(key)
        db.add(TagRule(owner_id=user.id, name=(rd.get("name") or None), description_pattern=pattern,
                       category_id=cat.id if cat else None, tag_id=tag.id,
                       active=bool(rd.get("active", True))))
        counts["tag_rules"] += 1

    for acc_data in payload["accounts"]:
        if not isinstance(acc_data, dict):
            raise ValueError("Each account must be an object")
        acc_name = _text(acc_data.get("name", "Imported account"), 120)
        if name_filter is not None and acc_name not in name_filter:
            continue
        acc = Account(
            owner_id=user.id,
            starting_date=_parse_date(acc_data["starting_date"]) or date.today(),
        )
        acc.name = acc_name
        acc.starting_balance = _amount(acc_data.get("starting_balance", 0))
        db.add(acc)
        db.flush()
        # The importing user becomes the owner of every restored account.
        # Without this row, the new account would be invisible to them since
        # authorization is gated on account_permissions, not Account.owner_id.
        db.add(AccountPermission(account_id=acc.id, user_id=user.id, level="owner"))
        counts["accounts"] += 1
        acc_by_name.setdefault(acc.name, acc)

        rec_by_desc: dict[str, RecurringTransaction] = {}
        for r_data in acc_data.get("recurring", []):
            cat_name = r_data.get("category_name")
            rec = RecurringTransaction(
                account_id=acc.id,
                frequency=_frequency(r_data.get("frequency", "monthly_day")),
                day_of_month=_day_of_month(r_data.get("day_of_month")),
                anchor_date=_parse_date(r_data.get("anchor_date")),
                end_date=_parse_date(r_data.get("end_date")),
                active=bool(r_data.get("active", True)),
                category_id=cat_by_name[cat_name].id if cat_name and cat_name in cat_by_name else None,
            )
            rec.description = _text(r_data.get("description", ""), 500)
            rec.amount = _amount(r_data.get("amount", 0))
            rec.notes = _text(r_data.get("notes"), 256) or None   # (#191)
            rec.match_days = _bounded_int(r_data.get("match_days"), 0, 31, 5)
            rec.match_percent = _bounded_int(r_data.get("match_percent"), 0, 100, 10)
            db.add(rec)
            db.flush()
            for sd in {_parse_date(x) for x in r_data.get("skipped_dates") or []} - {None}:
                db.add(RecurringSkip(recurring_id=rec.id, skip_date=sd))
            for tag in {tg.id: tg for tg in (get_tag(n) for n in r_data.get("tags") or []) if tg}.values():
                db.add(RecurringTag(recurring_id=rec.id, tag_id=tag.id))
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
            t.description = _text(t_data.get("description", ""), 500)
            t.amount = _amount(t_data.get("amount", 0))
            t.notes = _text(t_data.get("notes"), 256) or None     # (#191)
            if t_data.get("forecast_amount") is not None:
                t.forecast_amount = _amount(t_data["forecast_amount"])
            ref = t_data.get("bank_ref")
            if isinstance(ref, str) and _HEX64.fullmatch(ref):
                t.bank_ref = ref
                if t_data.get("bank_match") in ("auto", "hand"):
                    t.bank_match = t_data["bank_match"]
                    t.bank_text = _text(t_data.get("bank_text"), 500) or None
                t.bank_left = t_data.get("bank_left") is True
            ref = t_data.get("mail_ref")
            if isinstance(ref, str) and _HEX64.fullmatch(ref):
                t.mail_ref = ref
                # An email alert's line carries the same match fields (#209).
                if t_data.get("bank_match") in ("auto", "hand"):
                    t.bank_match = t_data["bank_match"]
                    t.bank_text = _text(t_data.get("bank_text"), 500) or None
                t.bank_left = t_data.get("bank_left") is True
            rec_desc = t_data.get("recurring_description")
            if rec_desc and rec_desc in rec_by_desc:
                t.recurring_id = rec_by_desc[rec_desc].id
            db.add(t)
            counts["transactions"] += 1
            t_tags = {tg.id: tg for tg in (get_tag(n) for n in t_data.get("tags") or []) if tg}
            if t_tags:
                db.flush()   # need t.id for the links
                for tag in t_tags.values():
                    db.add(TransactionTag(transaction_id=t.id, tag_id=tag.id))

    counts["bank_connection"] = int(_import_bank(db, user, payload.get("bank_connection"), acc_by_name))
    counts["mail_connection"] = int(_import_mail(db, user, payload.get("mail_connection"), acc_by_name))
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
        user_data = export_user(db, user, accounts=user_accounts, include_bank=True)
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
