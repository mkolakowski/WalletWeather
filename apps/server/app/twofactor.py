"""Two-factor sign-in codes (two-factor phase 1, #165).

The 6-digit codes are the standard authenticator-app kind (TOTP, RFC 6238:
HMAC-SHA1 over the 30-second step, six digits), written here from the
standard with Python's own hmac so the app needs no library for them. The
tests check them against the RFC's published values.

Recovery codes are random, used once, and only their SHA-256 is kept (like
API tokens: they're long enough that a slow hash adds nothing).
"""
import base64
import hashlib
import hmac
import re
import secrets
import struct
import time
from urllib.parse import quote

PERIOD = 30          # seconds a code is current for
DIGITS = 6
RECOVERY_CODES = 10  # made at set-up
# No 0/o, 1/i/l: recovery codes get read off paper.
_RECOVERY_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"
_CODE = re.compile(r"[0-9]{%d}" % DIGITS)


def new_secret() -> str:
    """A new key: 160 random bits as base32, the form authenticator apps take."""
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii")


def code_at(secret: str, step: int) -> str:
    """The code for one 30-second step."""
    key = base64.b32decode(secret, casefold=True)
    digest = hmac.new(key, struct.pack(">Q", step), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    number = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(number % 10 ** DIGITS).zfill(DIGITS)


def current_step(now: float | None = None) -> int:
    return int((time.time() if now is None else now) // PERIOD)


def looks_like_code(text: str) -> bool:
    return bool(_CODE.fullmatch(text))


def matching_step(secret: str, code: str, after_step: int | None = None,
                  now: float | None = None, drift: int = 1) -> int | None:
    """The step `code` is right for, or None.

    Accepts the current step and `drift` steps either side, for clocks that
    are a little off. A step at or before `after_step` (the last one used)
    never matches, so a code works once.
    """
    if not looks_like_code(code):
        return None
    step_now = current_step(now)
    found = None
    for step in range(step_now - drift, step_now + drift + 1):
        # Compare every candidate, in constant time each.
        if hmac.compare_digest(code_at(secret, step), code) and found is None:
            if after_step is None or step > after_step:
                found = step
    return found


def otpauth_url(secret: str, email: str, issuer: str) -> str:
    """The otpauth:// address an authenticator app reads from a QR code."""
    issuer = issuer.replace(":", " ").strip() or "WalletWeather"
    label = quote(f"{issuer}:{email}", safe="@")
    return (f"otpauth://totp/{label}?secret={secret}&issuer={quote(issuer, safe='')}"
            f"&algorithm=SHA1&digits={DIGITS}&period={PERIOD}")


def new_recovery_codes(count: int = RECOVERY_CODES) -> list[str]:
    """Codes like `abcde-fghjk` (about 49 random bits each)."""
    def one() -> str:
        chars = "".join(secrets.choice(_RECOVERY_ALPHABET) for _ in range(10))
        return chars[:5] + "-" + chars[5:]
    return [one() for _ in range(count)]


def hash_recovery_code(code: str) -> str:
    """SHA-256 of a recovery code as typed: case, spaces and dashes ignored."""
    plain = re.sub(r"[\s-]", "", code).lower()
    return hashlib.sha256(plain.encode("utf-8")).hexdigest()
