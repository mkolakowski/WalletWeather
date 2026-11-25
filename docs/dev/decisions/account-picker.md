# Account picker

Decisions for [`Plans/account-picker.md`](../../../Plans/account-picker.md).

## 2026-11-25: the picture lives on the server

**Decided:** 2026-11-25, by Matthew, in the scoping round. **Status:** accepted (#380).

**The question:** the iPhone's account picker should show the person's profile picture, but nothing keeps one today. Where does it come from?

**Options considered:**
- **The server keeps it:** set in the web app's Your account, taken from Google at sign-in; initials until one is set.
- **Initials only for now,** pictures later.
- **Gravatar:** looks the email up on gravatar.com, sending a hash of each email to a third party.

**The decision:** the server keeps it (phase 1, #377), the web app sets it (phase 2, #378), the iPhone reads it (phase 3, #379).

## 2026-11-25: the picture replaces the connection chip

**Decided:** 2026-11-25, by Matthew, after the artifact page *Account picker: where it sits* drew both. **Status:** accepted. Settles open question 1 (#379).

**The question:** on the Dashboard and Settings, does the round picture button replace the connection chip under the title, or sit beside it?

**Options considered:**
- **A, replaces the chip:** the picture on the title's line at the right; the chip goes and the cards move up by its height. One control, like the web app's round account button and the App Store's.
- **B, beside the chip:** the same picture, with the chip kept, so the connection's name stays on the page.

**The decision:** A. The connection's name shows in the picture's menu and on Settings → Connections.

## 2026-11-25: in the demo, your picture with a sparkles badge

**Decided:** 2026-11-25, by Matthew. **Status:** accepted. Settles open question 3 (#379).

**The question:** what does the button show in the demo, where the lock usually puts you and where the picker is the way back?

**Options considered:**
- **Your picture with a sparkles badge,** from the connection the demo goes back to, also while locked: a picture shows no numbers, address or email.
- **The demo's sparkles alone,** so nothing of yours shows in the demo.
- **Sparkles while locked, your picture once unlocked.**

**The decision:** your picture with a small sparkles badge, locked or not. Choosing a real connection from its menu still asks for Face ID first (`LockGate`).

## 2026-11-25: Google's picture only when there's none

**Decided:** 2026-11-25, by Matthew. **Status:** accepted. Settles open question 2 (#377).

**The question:** when does a Google sign-in copy the account's Google picture?

**Options considered:**
- **Only when the person has no picture yet,** so one set by hand is never replaced.
- **At every Google sign-in,** following a change at Google but overwriting one set by hand.
- **Never.**

**The decision:** only when there's none yet. A failure to fetch it never stops the sign-in.
