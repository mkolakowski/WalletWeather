# Security policy

WalletWeather is a self-hosted app that holds personal financial data. It is
built for a home network or a private tunnel, and the README says not to put
it on the public internet. Reports of security problems are welcome.

## Reporting a problem

Please report it privately, not in a public issue:

1. Open the repository's **Security** tab on GitHub.
2. Choose **Report a vulnerability** and describe what you found: the
   version (`/api/version` shows it), what an attacker could do, and the
   steps to reproduce it.

If that button isn't there, open a public issue that says only "I have a
security report" with no details, and you'll be contacted for the rest.

## What to expect

This is a personal project maintained in spare time, with no paid support
and no bounty. Reports are read, a reply is usually sent within a week, and a
fix that's confirmed ships in the next release with a note under
**Security** in the changelog. You'll be credited there unless you'd rather
not be.

## Which versions get fixes

Only the newest release. Fixes are not back-ported: update to the latest
version to get them.

## Known limits

These are known and listed in the README's Security Notes and the roadmap,
so they don't need a report: there is no
self-serve password reset, and session cookies are not marked HTTPS-only.
Two-factor sign-in is each user's choice unless an admin requires it, it
covers password sign-ins only (Google sign-in relies on Google's own), and
API tokens work without it by design. A browser the user chose to remember
skips the code (not the password) for 30 days. With it on, changing the
password, deleting the account and making a token ask for a fresh code. Anyone who can read both the database
and the `ENCRYPTION_KEY` can read the two-factor keys. When the iPhone app
renews its Cloudflare Access sign-in, the server hands the Cloudflare token
to whichever app on the phone has claimed the `walletweather://` address; it
can't tell the real app from another one, so a hostile app already on the
phone could receive it. That token gets a request through Cloudflare, not
into WalletWeather.
