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
into WalletWeather. Bank sync (off unless an admin switches it on) keeps
each connection's SimpleFIN access address, or Teller's or Plaid's access
token, encrypted with `ENCRYPTION_KEY`: anyone who can read both the
database and that key can read users' bank transactions through that
provider until the user disconnects (and, for SimpleFIN, disables the token
there). With Teller, they'd also need the instance's Teller certificate and
key; with Plaid, its `PLAID_SECRET`. It can't move money. Teller's
certificate and private key and Plaid's secret stay on the server: they're
mounted or set in `.env` and never sent to a browser or an app. The one page
that loads another site's script, `/bank/teller` (Teller Connect from
`cdn.teller.io`), has a Content-Security-Policy of its own allowing only
that, and takes no inline scripts. The access token Teller Connect hands the
page is kept only if Teller accepts it straight away. While that page is open,
Teller's script runs with the page's rights, the person's sign-in included,
as any script on the app's own address would; that's why it's on one page
that is opened only to connect a bank, and why Teller is offered only when
the operator sets it up. It's also in encrypted
backups, so a backup's passphrase guards it too. Email alerts (off unless an
admin switches them on) keep each connected user's Microsoft sign-in
encrypted the same way: it has read-only access to their whole mailbox, not
just the folder they picked (Microsoft has no permission limited to one
folder), so anyone who can read both the database and the key can read
their mail until they disconnect and remove the app's access at Microsoft.
That's why the setup guide has the bank's alerts filed into a folder of
their own and the server reads only that folder. Alert emails are text
written by strangers: the server reads them as plain text, follows no link,
fetches no image, makes a line only from a mail that passed the mailbox
provider's own sender check, and never more than 50 lines in one check.
