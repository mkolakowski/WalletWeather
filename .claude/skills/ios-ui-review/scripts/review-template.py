#!/usr/bin/env python3
"""A review to start from. Copy it into the run's folder as review.py, fill it
in and run it: it writes review.html beside itself, ready to publish.

    cp .claude/skills/ios-ui-review/scripts/review-template.py apps/ios/build/ui-review/<run>/review.py
    python3 apps/ios/build/ui-review/<run>/review.py
"""
import pathlib
import sys

RUN = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(RUN.parents[4] / ".claude" / "skills" / "ios-ui-review" / "scripts"))
from review_kit import *  # noqa: E402,F403  (shot, mock, note, phone, card, row, …, build)

# Every finding: today beside the proposal. `shot` cuts a piece out of one of
# the run's pictures: crop is (x, y, width, height) as fractions of the
# picture. `mock` is drawn with the kit and marked as drawn. `note` is for a
# slot with no picture, and says why.
FINDINGS = [
    {
        "id": "B1", "group": "bugs", "kind": "bug",
        "title": "What a person would say is wrong, in one line",
        "where": "The page and the taps that get there; which devices, looks and text sizes",
        "what": "What happens, and why it matters to someone using the app. Two or three sentences.",
        "today": shot("iphone.light.large/forecast.top.jpg", crop=(0, 0.1, 1, 0.5), caption="What the picture shows."),
        "proposed": mock(phone(card(cap("Today"), big("$4,794.98")), title="Forecast"), caption="What changes."),
        "fix": "What to change, in the code's terms: the file, the line, the shape of the change.",
        "size": "Small: one file",
        "proof": "Which check or flow found it, on how many runs; <code>File.swift:123</code>; anything still to confirm on a phone.",
        # "options": [("A. Keep it", "What that means in a line"), ("B. Change it", "What that means")],
    },
]

build({
    "run": RUN,
    "title": "iOS UI Review 0.00.0",
    "lede": "One or two sentences: what was run, on what, and how to read the page.",
    "facts": ["iOS 0.00.0 at abc1234", "2026-00-00", "0 configurations", "0 screens", "0 pictures"],
    "groups": [
        ("bugs", "Bugs", "Plainly broken: fix whatever else is decided."),
        ("slips", "Inconsistencies", "The app doing one thing two ways, or breaking a convention it has already decided."),
        ("design", "Design", "Where the app could look and feel more current. Each is a choice, not a fault."),
    ],
    "findings": FINDINGS,
    "closing": "<h2>What this run couldn't see</h2><ul><li>…</li></ul>",
}, RUN / "review.html")
