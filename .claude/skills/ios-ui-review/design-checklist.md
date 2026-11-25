# What "modern" is measured against

The design part of `/ios-ui-review` reads a run's pictures against this
list. Each line is a question with what to look at. A "no" is a finding only
when a person would notice it; say which picture shows it.

**Last brought up to date: 2026-11-24** (#346), from Apple's iOS 26 guidance
as Claude knows it, plus press and Apple's own session notes on iOS 27
(below). Apple's Human Interface Guidelines themselves weren't read that day:
the site needs a browser. Before a review, search for what has changed since
this date ("what's new in SwiftUI", "Human Interface Guidelines changes") and
add to this file what a run should now look for, with the date and the
source.

## The system's look (iOS 26 and 27)

1. **Bars and controls are glass, content isn't.** Tab bar, toolbars, sheets'
   handles and floating buttons use the system's own glass (`.glassEffect`,
   `.buttonStyle(.glass)`, `.glassProminent`). Content sits on plain or
   softly tinted surfaces. Look for: glass on glass (a glass card under a
   glass bar), a card that's glass only for decoration, a home-made blur
   (`.ultraThinMaterial`) standing in for the system's.
2. **Content runs under the bars.** Lists and pages scroll behind the tab bar
   and the title, with the system's soft edge. Look for: a hard line or an
   opaque band where a bar meets the page, text that stays unreadable under a
   bar, content that stops short of the screen's edge for no reason.
3. **Corners are concentric.** A shape inside another shares its centre:
   inner radius = outer radius − the gap. Look for: a tight corner inside a
   round card, the same kind of card with two radii. The source check's
   survey lists every radius in use; more than four or five is a sign.
4. **One primary action a screen, and it looks it.** The tinted, prominent
   button is the thing most people came to do. Look for: two prominent
   buttons, a destructive action as prominent as the main one, a primary
   action that's plain text.
5. **Toolbars are sparse and grouped.** A few symbols, grouped by meaning,
   text for Cancel, Save and Done. Look for: more than three items a side, a
   symbol nobody could guess, the same action in different places on
   different pages.
6. **The system's own parts where they exist.** Lists, forms, menus, sheets,
   pickers, search, swipe actions, pull to refresh, confirmation dialogs.
   Look for: a home-made switch or picker, an alert doing a sheet's job, a
   menu rebuilt as buttons.
7. **Type is the system's styles.** Large title, headline, body, footnote,
   caption: a clear order on every screen, nothing smaller than caption 2,
   numbers that line up (monospaced digits in columns). Look for: three sizes
   doing one job, a heading that's only bold body text, a figure that wraps
   mid-number.
8. **Symbols are SF Symbols, one weight, one meaning each.** Look for: the
   same idea with two symbols (the survey's symbol list), filled beside
   outlined with no reason, a symbol out of line with its text.
9. **Space is even.** The same margin at the screen's edge on every page of
   one kind, the same gap between cards, rows at least 44 points tall. The
   report's "Comparing screens" lists left margins; judge them by eye in the
   overview sheets.
10. **Colour means something.** Tint for what can be tapped, red for money
    out and for destructive actions, green for money in and for done. Look
    for: tinted text that isn't a button, a button that isn't tinted, red
    used for both a warning and an ordinary negative on one card.
11. **Every look and every glass setting.** Light, dark, and the app's own
    looks; iOS 27 lets people turn glass from clear to opaque, and SwiftUI's
    own glass follows it. Look for: text that fades into its background in
    one look (the audit's contrast findings point at candidates; check them
    against the picture), a home-made translucent surface that wouldn't
    follow the system's setting.
12. **Every size of window.** From iOS 27 an iPhone app's window can be
    resized (iPhone Mirroring, an iPad), so a layout has to hold at widths no
    iPhone has, as the closed Duo's 466 points already asks. Look for: two
    columns squeezed where one would do, a fixed width, text that wraps
    letter by letter.
13. **Every text size.** At Accessibility Large nothing is cut off, overlaps
    or needs sideways scrolling; rows stack instead of squeezing. The `ax-l`
    configurations show it.
14. **Motion is the system's.** Sheets, pushes and menus move as iOS moves
    them; anything the app animates itself fades when Reduce Motion is on.
    The walk can't see motion: read the code the source check's `motion` rule
    points at.
15. **Empty, loading and failed states are designed.** A page with nothing
    says what would be there and how to add it; a failure says what to do. The
    table has several (`search-nothing`, `line-editor-save-failed`); look for
    pages with no such state at all.

## This app's own conventions

Decided, so a break is an inconsistency rather than a matter of taste. The
decision pages are in `docs/dev/decisions/`.

- **Labels are sentence case** (2026-11-23, `ios-review.md`). The source
  check's `label-case` rule and the walk's `all-capitals` check.
- **One row style in lists:** plain, a chevron when it opens something, a
  highlight for the open one (`ios-review.md`, R27).
- **A failed save shows in the banner at the top of the editor,** with its
  way forward; an alert is for a question (`ios-review.md`, R25).
- **Sizes follow the phone's text size** (`ios-review.md`, R16).
- **A calendar day is written as Settings → Dates & display says** (#296).
  The `.iso` configuration lists every date that doesn't follow it.
- **Amounts come from the Kit's `Money`:** a minus before the dollar sign,
  two decimals, short forms ("-$1.6K") only where space is counted in
  points (the Calendar's days, widgets).
- **Settings is sections of rows that each open a page; open on the Duo it's
  a sidebar with the page beside it** (`ios-review.md`, Settings).
- **Flat open, a page's two halves stay where they are; half open they keep
  clear of the fold** (`ios-review.md`, the Duo).
- **Money out is red and money in is green, in every look,** from `Palette`.

## What iOS 27 changed (as reported; check before leaning on it)

- Liquid Glass was refined, and people can set how clear it is; apps built
  with SwiftUI's own glass follow without changes
  ([Apple, WWDC26 "What's new in SwiftUI"](https://developer.apple.com/videos/play/wwdc2026/269/),
  [MacRumors, 2026-06-10](https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/)).
- iPhone apps' windows became resizable
  ([Apple, WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/)).
- Toolbars gained visibility priorities; lists, grids and sections gained
  reordering ([the same session](https://developer.apple.com/videos/play/wwdc2026/269/)).
- App icons take more glass layers in Icon Composer
  ([MacRumors, 2026-06-16](https://macrumors.com/2026/06/16/ios-27-revamps-app-icons)).
- Nothing was found on how Apple wants a folding iPhone laid out; the app's
  own decisions (above) stand in for it.
