---
title: Set up email alerts
nav_order: 3
---

# Set up email alerts
{: .no_toc }

Your bank emails you about every purchase; WalletWeather reads those emails
and adds each one as a line, minutes after you pay.
{: .fs-6 .fw-300 }

You switch on "alert me for every transaction" at your bank, and WalletWeather
reads those alerts from one folder of your Microsoft 365 or Outlook.com
mailbox. It only reads: it never marks mail read, moves it or deletes it, and
it never sends mail.

{: .important }
> - **WalletWeather 1.74.0 or later** to have it check by itself (1.73.0 has Check now only). The version is in the app's footer.
> - **Not yet tried with a real Microsoft mailbox.** Email alerts are new in 1.73.0 and were tested only against a stand-in for Microsoft. Tell us if something doesn't work.
> - **The person who runs the server** registers a Microsoft app once and
>   switches email alerts on ([below](#for-the-person-who-runs-the-server)).
> - **Each person connects their own mailbox** and teaches it their bank's
>   alert once ([Connect your mailbox](#connect-your-mailbox)).
> - Gmail and other mailboxes come in a later version.

<details open markdown="block">
  <summary>On this page</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

## For the person who runs the server

WalletWeather signs in to Microsoft with an app you register yourself, free,
so no one else's app ever touches your users' mail.

### Register the app at Microsoft

1. Go to the [Microsoft Entra admin center](https://entra.microsoft.com) and
   open **App registrations** (under Identity → Applications), then **New
   registration**. You need a Microsoft Entra directory for this: a work or
   school Microsoft 365 account has one. If you only have a personal
   Outlook.com account and the portal asks you to create a directory or
   tenant first, a free Azure account gives you one.
2. **Name:** WalletWeather. **Supported account types:** "Accounts in any
   organizational directory and personal Microsoft accounts", so both
   Outlook.com and work mailboxes can connect. Leave **Redirect URI** empty
   for now and press **Register**.
3. On the app's **Authentication** page, under **Advanced settings**, set
   **Allow public client flows** to **Yes** and save. That's what lets people
   sign in with a code.
4. On **API permissions**, check that Microsoft Graph's **User.Read** is
   there, then **Add a permission → Microsoft Graph → Delegated permissions**
   and add **Mail.Read** and **offline_access**. Mail.Read is read-only.
5. Copy the **Application (client) ID** from the app's **Overview** page.

### Tell WalletWeather

Put the id in your server's `.env` and restart:

```
MS_CLIENT_ID=00001111-aaaa-2222-bbbb-3333cccc4444
```

```
docker compose up -d
```

Then, signed in as an admin, open **Admin → Email alerts** and switch it on.
It's off until you do. Admin's user list shows who has a mailbox connected.

### Optional: the Connect button

Signing in with a code works wherever your server is. If people reach your
server at an `https://` address (`APP_BASE_URL`), you can also offer a
**Connect with Microsoft** button that goes to Microsoft and straight back:

1. In the app's **Authentication** page, **Add a platform → Web**, with the
   redirect URI `APP_BASE_URL` followed by `/api/mail/microsoft/callback`, for
   example `https://wallet.example.com/api/mail/microsoft/callback`.
2. Under **Certificates & secrets**, make a **New client secret** and copy its
   **Value** (it's shown once).
3. Add it to `.env` as `MS_CLIENT_SECRET=` and restart. It's a secret: keep
   it out of git. Microsoft secrets expire (you pick when, up to two years);
   make a new one before then.

### Optional: only some accounts

`MS_TENANT` limits who may sign in: empty for anyone, `consumers` for
personal Microsoft accounts only, `organizations` for work or school only, or
your organization's tenant id. A work or school organization may ask its own
admin to approve the app the first time someone signs in.

## Connect your mailbox

### At your bank, and in your mailbox

1. In your bank's app or website, find its alerts and switch on an email
   alert for **every** transaction (often "purchases over $0.00" or "any
   amount"). Have it sent to your Microsoft 365 or Outlook.com address.
2. In Outlook, make a rule that moves mail from your bank's alert address
   into a folder of its own, for example "Bank alerts". WalletWeather then
   reads only that folder.

### In WalletWeather

1. Open **Settings → Email alerts** (the tab appears once an admin has
   switched email alerts on).
2. Press **Sign in with a code**. Go to the address shown, type the code, sign
   in to Microsoft and allow WalletWeather to read your mail. The tab notices
   by itself when you're done. (Or use **Connect with Microsoft** if your
   server offers it.) With two-factor sign-in on, WalletWeather asks for a
   code from your authenticator app first.
3. Pick the folder and the day to read alerts from (today, or up to 30 days
   back), and save.

### Teach it your bank's alert

1. Press **Teach a bank's alert** and pick one of your bank's alerts from the
   list.
2. The alert appears as plain text, with what WalletWeather thinks is the
   amount, the merchant, the date and the card's last four digits
   highlighted. If one is wrong or missing, select the right words in the
   alert and press **Amount**, **Merchant**, **Date** or **Card** under it.
   Only the amount is required. Without a date, the day the email arrived is
   used.
3. Say whether it's money out or money in, check the bank's name and the
   start of the subject (that's how WalletWeather tells this kind of alert
   apart from your bank's other mail), pick the account its lines go into
   (or, if the alert names a card, the account for that card), and save.
4. Teach a second kind the same way if your bank sends one, such as deposits.

Press **Check now** to bring alerts in. Each becomes a paid line, named after
the merchant, and your auto-tag rules run on it. An email is never brought in
twice.

### It checks by itself

Once a folder is chosen and a bank taught, WalletWeather looks at the folder
by itself, every **5, 15 or 60 minutes** as you choose next to the folder
(it starts at 5), so a purchase appears within minutes. The tab says when the
next check is due. If a check fails (Microsoft is busy, say), it tries again
at the same interval. If Microsoft no longer accepts the sign-in, checking
stops until you disconnect and connect again, and the Dashboard says so. The
Dashboard also warns when checks have been failing for more than a day or
when alerts couldn't be read.

The **Check log** lists every check that brought something in or failed,
newest first: when, whether it ran by itself or by Check now, how many lines
came in, were already there or couldn't be read, and any error. **Show lines**
lists what a check brought in. Checks that find nothing new aren't listed,
and entries go after 180 days (`AUDIT_RETENTION_DAYS`).

{: .note }
> Until a later version, an account takes lines from bank sync or from email
> alerts, not both: an account matched to a SimpleFIN bank account can't be
> picked for alerts.

## What if an alert doesn't come in

Alerts from a bank you've taught that didn't become lines are listed under
**Couldn't read**, with the reason:

| Reason | What to do |
| --- | --- |
| Couldn't find the values this alert was taught to have | The bank changed its wording. Press **Teach from this** and mark the values again. |
| Card ending … isn't matched to an account | Pick an account for that card under the bank's name. The alert comes in on the next check. |
| May not be from your bank | The email failed your mailbox's own check that it really came from the bank's domain. It's never brought in. If it was a real alert, add the line by hand. |
| Its account takes lines from bank sync | Pick another account, or wait for the version that joins alerts to bank sync. |

Microsoft's sign-in renews each time it's used and lapses after about 90 days
unused. If the tab says Microsoft no longer accepts the sign-in, disconnect
and connect again; what you taught is forgotten when you disconnect, so
you'll teach it again.

## Privacy

- The server reads only the folder you picked, and in it only mail from the
  senders you've taught. Other mail is never stored.
- It keeps, encrypted: what it read from each alert (date, amount, merchant,
  card digits), the sample you taught each bank from, and alerts it couldn't
  read so you can teach from them. Those go after 180 days (the audit log's
  `AUDIT_RETENTION_DAYS`) or when you dismiss them.
- Microsoft's sign-in is stored encrypted with the server's `ENCRYPTION_KEY`,
  never shown or logged, and goes into encrypted backups only, never into
  "Download my data".
- **Disconnect** forgets the sign-in, the senders taught and the couldn't-read
  list; the lines already brought in stay. To remove WalletWeather's access at
  Microsoft too, go to your Microsoft account's **Privacy → Apps and
  services** (personal) or **My Apps** (work or school) and remove it.

The [privacy policy](https://github.com/mkolakowski/WalletWeather/blob/main/PRIVACY.md#what-leaves-the-server)
says what leaves the server.
