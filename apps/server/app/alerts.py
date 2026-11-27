"""Reading bank alert emails (bank-alert-emails phase 1, #206).

An email is text written by a stranger, so it's only ever read as text:
HTML is turned into plain lines, nothing in it is run, no link is followed,
no image is fetched, and a long mail is cut off.

Teaching (decided 2026-11-16): a built-in guess finds the amount, the
merchant, the date and the card's last four digits in a sample alert; the
user corrects it by marking the right text. What's kept for each value is
the text around it in the sample (an "anchor": up to ANCHOR_BEFORE characters
before it and ANCHOR_AFTER after), never a pattern anyone writes, so a
crafted alert or a crafted teaching can't make the reader slow. Reading a
new alert looks for the longest tail of the text before each value that the
alert has, and takes what follows, up to the text after it.

A kind of alert (a purchase, a deposit) is told apart by how its subject
starts, before the first digit or currency sign: "You made a $4.50 purchase
at …" starts "you made a".
"""
import re
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation
from html.parser import HTMLParser

MAX_TEXT = 20_000
ANCHOR_BEFORE = 40
ANCHOR_AFTER = 16
FIELDS = ("amount", "merchant", "date", "card")
LIMITS = {"amount": 40, "merchant": 120, "date": 40, "card": 40}
MAX_AMOUNT = Decimal("1000000000")

_BLOCK = {"p", "div", "br", "tr", "li", "ul", "ol", "table", "tbody", "thead", "h1", "h2", "h3",
          "h4", "h5", "h6", "section", "article", "header", "footer", "blockquote", "hr", "center",
          "dl", "dt", "dd", "pre", "address", "form", "fieldset"}
_CELL = {"td", "th"}
_SKIP = {"script", "style", "head", "title", "noscript", "template", "svg", "object", "iframe"}
_INVISIBLE = re.compile("[​‌‍⁠﻿­͏᠎]")
_SPACES = re.compile(r"[ \t\r\f\v  -   　]+")
_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.skip = 0
        self.size = 0

    def handle_starttag(self, tag, attrs):
        if tag in _SKIP:
            self.skip += 1
        elif tag in _BLOCK:
            self.parts.append("\n")

    def handle_startendtag(self, tag, attrs):
        if tag in _BLOCK:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in _SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag in _BLOCK:
            self.parts.append("\n")
        elif tag in _CELL:
            self.parts.append(" ")

    def handle_data(self, data):
        if not self.skip and self.size < MAX_TEXT * 4:
            self.parts.append(data)
            self.size += len(data)


def to_text(body: str, html: bool) -> str:
    """A mail body as plain lines: no markup, single spaces, no empty lines,
    at most MAX_TEXT characters. The same body always gives the same text,
    so places marked in it while teaching can be found again."""
    body = (body or "")[:400_000]
    if html:
        p = _Text()
        try:
            p.feed(body)
            p.close()
        except Exception:
            pass
        body = "".join(p.parts)
    body = _CONTROL.sub(" ", _INVISIBLE.sub("", body))
    lines = (_SPACES.sub(" ", line).strip() for line in body.split("\n"))
    return "\n".join(line for line in lines if line)[:MAX_TEXT]


def subject_key(subject: str) -> str:
    """How a subject starts, lowercased, before its first digit or currency
    sign; the whole subject (without digits) when that leaves too little."""
    s = _SPACES.sub(" ", (subject or "").lower()).strip()
    head = re.split(r"[\d$€£¥]", s, maxsplit=1)[0].strip(" :-–—|")
    if len(head) < 3:
        head = re.sub(r"[\d$€£¥.,]+", " ", s)
        head = _SPACES.sub(" ", head).strip(" :-–—|")
    return head[:200]


def subject_matches(key: str, subject: str) -> bool:
    k = (key or "").strip().lower()
    s = _SPACES.sub(" ", (subject or "").lower()).strip()
    return bool(k) and s.startswith(k)


# ---------- Values ----------

_AMOUNT = re.compile(r"(?<![\w.])(?:(?P<cur>[$€£¥])\s?|(?:USD|US\$)\s?)?(?P<num>\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"
                     r"(?:\s?(?P<tail>USD|dollars))?(?![\w])", re.IGNORECASE)
_MONTHS = {m: i + 1 for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"])}
_MONTH_NAME = r"(?P<mon>jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?"
_DATES = [
    re.compile(r"\b(?P<y>\d{4})-(?P<m>\d{1,2})-(?P<d>\d{1,2})\b"),
    re.compile(r"\b(?P<m>\d{1,2})/(?P<d>\d{1,2})(?:/(?P<y>\d{4}|\d{2}))?\b"),
    re.compile(r"\b" + _MONTH_NAME + r"\s+(?P<d>\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(?P<y>\d{4}))?\b", re.IGNORECASE),
    re.compile(r"\b(?P<d>\d{1,2})(?:st|nd|rd|th)?\s+" + _MONTH_NAME + r"(?:,?\s+(?P<y>\d{4}))?\b", re.IGNORECASE),
]
_CARD = re.compile(r"(?:ending(?:\s+in)?|last\s+(?:4|four)(?:\s+digits)?(?:\s+of)?|account|card|acct)\D{0,12}?(\d{4})\b"
                   r"|(?:[*xX•·.]{2,}|\bx)\s?(\d{4})\b", re.IGNORECASE)
_MERCHANT_LABEL = re.compile(r"\b(?:merchant(?:\s+name)?|description|payee|where|store|location|vendor)(?:\s*[:\-]\s*|\s+)"
                             r"(?P<v>[^\n]{1,120})", re.IGNORECASE)
_MERCHANT_WORD = re.compile(r"\b(?:at|with|to|from)\s+(?P<v>[A-Za-z][^\n]{0,119})", re.IGNORECASE)
_MERCHANT_STOP = re.compile(r"\s+(?:on|for|was|has|have|using|with|ending|in the amount|exceed\w*)\b|[.,;!(]\s|[.!;]$|\s+-\s",
                            re.IGNORECASE)
_IN_WORDS = re.compile(r"\b(?:deposit\w*|credit(?:ed)?|received|refund\w*|incoming|direct dep|paid you|sent you)\b",
                       re.IGNORECASE)


def parse_amount(text: str) -> Decimal | None:
    m = _AMOUNT.search(text or "")
    if not m:
        return None
    try:
        value = Decimal(m.group("num").replace(",", ""))
    except InvalidOperation:
        return None
    if not value.is_finite() or value <= 0 or value >= MAX_AMOUNT:
        return None
    return value.quantize(Decimal("0.01"))


def parse_date(text: str, received: date) -> date | None:
    """A date in the text; a year left out is the one that puts the date
    nearest before the day the mail arrived."""
    for pat in _DATES:
        m = pat.search(text or "")
        if not m:
            continue
        g = m.groupdict()
        try:
            month = int(g["m"]) if g.get("m") else _MONTHS[g["mon"][:3].lower()]
            day = int(g["d"])
            year = g.get("y")
            if year:
                year = int(year)
                year = year + 2000 if year < 100 else year
                found = date(year, month, day)
            else:
                found = date(received.year, month, day)
                if found > received + timedelta(days=1):
                    found = date(received.year - 1, month, day)
        except (ValueError, KeyError):
            continue
        if abs((found - received).days) <= 400:
            return found
    return None


def parse_card(text: str) -> str | None:
    found = re.findall(r"\d{4}", text or "")
    return found[-1] if found else None


def clean_merchant(text: str) -> str | None:
    v = _SPACES.sub(" ", (text or "").replace("\n", " ")).strip(" :-–—|*\"'")
    return v[:LIMITS["merchant"]] or None


def marked(field: str, raw: str, received: date):
    """The value in text a person marked while teaching, or None. Stricter
    than reading: the marked text has to be the value itself, not text with
    a number somewhere in it."""
    raw = (raw or "").strip()
    if field == "amount":
        return parse_amount(raw) if _AMOUNT.fullmatch(raw) else None
    if field == "card":
        return parse_card(raw) if re.fullmatch(r"\D{0,12}\d{4}", raw) else None
    return _value(field, raw, received)


def _value(field: str, raw: str, received: date):
    if field == "amount":
        return parse_amount(raw)
    if field == "date":
        return parse_date(raw, received)
    if field == "card":
        return parse_card(raw)
    return clean_merchant(raw)


# ---------- The built-in guess ----------

def guess(text: str, subject: str = "") -> dict:
    """Where each value probably is, as {field: [start, end]} offsets into
    `text` (missing when not found), and whether it looks like money in."""
    out: dict = {}
    for m in _AMOUNT.finditer(text):
        if (m.group("cur") or m.group("tail") or "." in m.group("num")) and parse_amount(m.group(0)):
            out["amount"] = [m.start(), m.end()]
            break
    for m in _CARD.finditer(text):
        g = 1 if m.group(1) else 2
        out["card"] = [m.start(g), m.end(g)]
        break
    best = None
    for pat in _DATES:
        m = pat.search(text)
        if m and (best is None or m.start() < best[0]):
            best = [m.start(), m.end()]
    if best:
        out["date"] = best
    m = _MERCHANT_LABEL.search(text) or _MERCHANT_WORD.search(text)
    if m:
        start = m.start("v")
        raw = m.group("v")
        stop = _MERCHANT_STOP.search(raw)
        end = start + (stop.start() if stop else len(raw.rstrip()))
        if end > start and clean_merchant(text[start:end]):
            out["merchant"] = [start, end]
    out_words = _IN_WORDS.search(subject or "") or _IN_WORDS.search(text[:600])
    return {"fields": out, "direction": "in" if out_words else "out"}


# ---------- Anchors ----------

def anchor(text: str, start: int, end: int) -> dict:
    """The text around a marked value: what comes before it (up to
    ANCHOR_BEFORE characters, the line before included when the value starts
    a line) and after it on the same line (up to ANCHOR_AFTER; "\\n" when the
    value ends its line)."""
    if not (0 <= start < end <= len(text)):
        raise ValueError("outside the text")
    before = text[max(0, start - ANCHOR_BEFORE):start]
    line_end = text.find("\n", end)
    line_end = len(text) if line_end < 0 else line_end
    after = text[end:min(line_end, end + ANCHOR_AFTER)] or "\n"
    return {"before": before, "after": after}


def _tails(before: str, minimum: int):
    """The text before a value, longest first, down to `minimum` visible
    characters, cut at word edges."""
    seen = set()
    cuts = [0] + [i + 1 for i, ch in enumerate(before) if ch in " \n"]
    for c in cuts:
        tail = before[c:]
        if len(tail.strip()) >= minimum and tail not in seen:
            seen.add(tail)
            yield tail


def _shape(tail: str) -> re.Pattern:
    """A tail of anchor text, with each run of digits standing for any run
    of digits, with any commas and points inside it ("$4.50 at " also finds
    "$1,212.00 at "). Built here from the
    sample's literal text, never from anything a person types; digit runs
    are always separated by literal text, so it can't backtrack badly."""
    parts = re.split(r"(\d(?:[\d,.]*\d)?)", tail)
    return re.compile("".join(r"\d(?:[\d,.]*\d)?" if p[:1].isdigit() else re.escape(p)
                              for p in parts if p))


def _afters(after: str):
    """The text after a value, as candidates to look for: whole words from
    its start, longest first, then the same with leading words dropped (a
    word right after the value may itself vary, "#123" after "STARBUCKS"),
    each with at least two visible characters."""
    words = re.findall(r"\s*\S+", after)
    seen = set()
    for i in range(len(words)):
        for j in range(len(words), i, -1):
            cand = "".join(words[i:j])
            if len(cand.strip()) >= 2 and cand not in seen:
                seen.add(cand)
                yield cand


def _take(text: str, pos: int, after: str, limit: int) -> str:
    window = text[pos:pos + limit + ANCHOR_AFTER + 1]
    line = window.split("\n", 1)[0]
    if after != "\n":
        for cand in _afters(after):
            m = _shape(cand).search(line)
            if m and 0 < m.start() <= limit:
                return line[:m.start()]
    return line[:limit]


# A merchant is any text, so its anchor has to be longer to be trusted; the
# typed values must also read as an amount, a date or four digits.
_MIN_TAIL = {"merchant": 3, "amount": 2, "date": 2, "card": 2}


def find(text: str, a: dict, field: str, received: date):
    """The value at an anchor in a new alert, or None."""
    before, after, limit = a.get("before") or "", a.get("after") or "\n", LIMITS[field]
    if not before.strip():
        return _value(field, _take(text, 0, after, limit), received)
    for tail in _tails(before, _MIN_TAIL[field]):
        for tries, m in enumerate(_shape(tail).finditer(text)):
            if tries >= 20:
                break
            v = _value(field, _take(text, m.end(), after, limit), received)
            if v is not None:
                return v
    return None


def read(text: str, anchors: dict, received: date) -> dict | None:
    """Every taught value read from an alert, or None when the amount (or
    another value that was taught) can't be found."""
    out = {}
    for field in FIELDS:
        a = anchors.get(field)
        if not a:
            continue
        v = find(text, a, field, received)
        if v is None:
            return None
        out[field] = v
    return out if "amount" in out else None


# ---------- Is it really from the bank? ----------

def _domain(address: str) -> str:
    return address.rsplit("@", 1)[-1].strip().lower() if "@" in (address or "") else ""


def _aligned(from_domain: str, d: str) -> bool:
    d = d.strip().lower().strip(".")
    return bool(d) and (from_domain == d or from_domain.endswith("." + d) or d.endswith("." + from_domain))


def sender_verified(sender: str, auth_results: list[str]) -> bool:
    """Whether the receiving mail server's own check says the mail came from
    the sender's domain: DMARC passed for that domain, or a DKIM signature
    from it verified. Only the topmost Authentication-Results header counts:
    it's the one the mailbox provider added; ones further down could have
    been written by the sender."""
    dom = _domain(sender)
    if not dom or not auth_results:
        return False
    top = auth_results[0].lower()
    dmarc = re.search(r"\bdmarc=(\w+)[^;]*?header\.from=([\w.\-]+)", top)
    if dmarc and dmarc.group(1) == "pass" and _aligned(dom, dmarc.group(2)):
        return True
    for m in re.finditer(r"\bdkim=(\w+)[^;]*?header\.d=([\w.\-]+)", top):
        if m.group(1) == "pass" and _aligned(dom, m.group(2)):
            return True
    return False


def authserv_id(header: str) -> str:
    """The server id an Authentication-Results header starts with (RFC 8601:
    `mx.google.com; dkim=pass ...` or `mx.google.com 1; ...`), lowercased."""
    head = re.sub(r"\([^)]*\)", " ", (header or "").split(";", 1)[0]).split()
    return head[0].strip().lower() if head else ""


def trusted_results(headers: list[str], authserv: str | None) -> list[str]:
    """The headers, when the topmost one was written by the mailbox's own
    server (its id is `authserv`); none otherwise, so the sender check fails.
    A server that adds no header of its own leaves the sender's on top, and
    a sender can write anything (decided 2026-11-27, #208)."""
    want = (authserv or "").strip().lower()
    if not want or not headers or authserv_id(headers[0]) != want:
        return []
    return headers


def received_day(received: datetime, offset_minutes: int) -> date:
    """The day a mail arrived, in the user's own time (minutes east of UTC)."""
    return (received + timedelta(minutes=offset_minutes)).date()
