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

## 2026-11-25: the picker shows whenever something is in front

**Decided:** 2026-11-25, by Matthew, while phase 3 was built. **Status:** accepted (#379).

**The question:** the connection chip showed only with two or more connections, or in the demo. Does the picture button follow the same rule?

**Options considered:**
- **Always,** whenever something is in front: a server's picture or initials, the household on this iPhone's icon, the demo's picture with its badge. One rule, like the web app's account button.
- **Always, but not the household alone,** which has no picture to show.
- **As the chip did:** people with one server would never see their picture on the phone.

**The decision:** always. With one server, the picture still says who's signed in, and its menu still offers the demo and Manage connections….

## 2026-11-25: the picture moves to the bar's buttons

**Decided:** 2026-11-25, by Matthew, from the UI review of 0.73.0 (#382, finding B1). **Status:** accepted (#383). Changes "the picture replaces the connection chip" above: still in its place, but at the top right among the bar's buttons rather than on the large title's line.

**The question:** on the phone the picture sat on the large title's line as a `.largeTitle` toolbar item, which isn't in the accessibility tree: VoiceOver, Switch Control and Voice Control couldn't reach it, and with it the way out of the demo. How should it be fixed?

**Options considered:**
- **A, keep it on the title's line and try to make it reachable:** nothing visible changes, if SwiftUI allows it at all.
- **B, move it into the bar beside +,** as the open Duo already had it: reachable for certain, and the system's large title comes back.
- **C, draw the title row in the page itself:** reachable and on the title's line, but more code, and it scrolls away with the page.

**The decision:** B. It sits at the right of + as a bare circle (no shared glass), on the phone, the closed Duo and the open Duo; in Settings' sidebar on the open Duo it stays in the header, with a 44-point tap area (#384).

