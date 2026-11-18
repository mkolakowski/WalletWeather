"""Licence check: no copyleft or unlicensed dependency gets in unreviewed.

It reads the licence each installed package declares, so it covers everything
`requirements-dev.txt` pulls in, the packages nobody asked for by name
included. The rule is in CLAUDE.md ("Licensing guardrails"); the packages
shipped in the image are listed in THIRD_PARTY_NOTICES.md.

When this fails on a new package: don't add it to a list to get past the
failure. Find a permissively licensed alternative, or ask whether the package
is acceptable; if it is, add it to REVIEWED_COPYLEFT (or REVIEWED_UNSTATED)
with its licence, and to THIRD_PARTY_NOTICES.md.
"""
import importlib.metadata as md
import re

# Copyleft packages already reviewed and accepted: unmodified dependencies,
# listed in THIRD_PARTY_NOTICES.md. Names are lowercase, with "-" for "_".
REVIEWED_COPYLEFT = {
    "psycopg": "LGPL-3.0",
    "psycopg-binary": "LGPL-3.0",
    "certifi": "MPL-2.0 (a list of certificate authorities, via httpx)",
}

# Packages that state no licence in their metadata but were checked by hand.
REVIEWED_UNSTATED: dict[str, str] = {
    # The engine for the shared JavaScript core (Plans/standalone.md, #232):
    # the MIT licence file ships in the wheel, the metadata doesn't name it.
    "quickjs-ng": "MIT (licence file in the wheel; the bundled quickjs-ng engine is MIT)",
}

_COPYLEFT = re.compile(
    r"\b(A?GPL|LGPL|MPL|EPL|CDDL|EUPL|OSL|SSPL)\b"
    r"|GNU (Affero |Lesser |Library )?General Public"
    r"|Mozilla Public|Eclipse Public|Server Side Public"
    r"|Common Development and Distribution|European Union Public",
    re.IGNORECASE,
)


def declared_licences(meta) -> list[str]:
    """Every licence statement in a package's metadata."""
    found = []
    if meta.get("License-Expression"):
        found.append(meta["License-Expression"])
    # The License field is sometimes the whole licence text: its first line
    # is the name, and the classifiers say the same more reliably.
    if meta.get("License"):
        found.append(meta["License"].strip().splitlines()[0][:120])
    found += [c.split(" :: ")[-1] for c in meta.get_all("Classifier", [])
              if c.startswith("License ::")]
    return [f for f in found if f and f.upper() != "UNKNOWN"]


def is_copyleft(licences: list[str]) -> bool:
    return any(_COPYLEFT.search(text) for text in licences)


def _normalise(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def test_no_unreviewed_copyleft_or_unlicensed_packages():
    copyleft, unstated = [], []
    for dist in md.distributions():
        name = _normalise(dist.metadata["Name"])
        licences = declared_licences(dist.metadata)
        if not licences:
            if name not in REVIEWED_UNSTATED:
                unstated.append(name)
        elif is_copyleft(licences) and name not in REVIEWED_COPYLEFT:
            copyleft.append(f"{name} ({'; '.join(licences)})")
    assert not copyleft, (
        "Copyleft packages that haven't been reviewed: " + ", ".join(sorted(copyleft)))
    assert not unstated, (
        "Packages that state no licence: " + ", ".join(sorted(unstated)))


def test_the_reviewed_list_has_no_stale_entries():
    # A package that's gone, or no longer copyleft, shouldn't stay excused.
    installed = {_normalise(d.metadata["Name"]): d.metadata for d in md.distributions()}
    stale = [name for name in REVIEWED_COPYLEFT
             if name not in installed or not is_copyleft(declared_licences(installed[name]))]
    assert not stale, "Remove from REVIEWED_COPYLEFT: " + ", ".join(stale)


class _FakeMeta(dict):
    def get_all(self, key, default=None):
        return self.get(key + "s", default)


def test_the_check_recognises_copyleft_and_permissive_licences():
    gpl = _FakeMeta({"Classifiers": [
        "License :: OSI Approved :: GNU General Public License v2 or later (GPLv2+)"]})
    assert is_copyleft(declared_licences(gpl))
    assert is_copyleft(["AGPL-3.0-only"])
    assert is_copyleft(["Mozilla Public License 2.0 (MPL 2.0)"])
    for permissive in (["MIT"], ["BSD-3-Clause"], ["Apache-2.0 OR BSD-3-Clause"],
                       ["PSF-2.0"], ["MIT-0"], ["Apache Software License"]):
        assert not is_copyleft(permissive)
