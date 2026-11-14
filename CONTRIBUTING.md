# Contributing

Thanks for wanting to help. WalletWeather is a small personal project, so
please open an issue to talk a change through before sending a large pull
request.

## Licence of contributions

WalletWeather is MIT-licensed. By sending a pull request you agree that your
contribution is licensed under the same [MIT licence](LICENSE), and you
confirm that it's your own work or that you have the right to submit it.

- **No copied code** from projects under a copyleft licence (GPL, LGPL,
  AGPL, MPL), and nothing copied from a source whose licence you can't name.
- **New dependencies** need a permissive licence (MIT, BSD, Apache-2.0 or
  similar) and a line in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **AI-assisted changes are fine.** Say so in the pull request, and read and
  test what you send as you would your own code. Parts of WalletWeather were
  written with AI assistance.
- No company logos or other trademarks in the app or its sample data.

## Before you send it

- Run the tests (the README's **Tests** section has the one command).
- A new or changed API endpoint comes with tests.
- Add a line to `CHANGELOG.md` under `[Unreleased]`, written for the people
  who run the app.
- Never commit a secret or a real `.env` file.

## Security problems

Don't open a public issue for one. See [`SECURITY.md`](SECURITY.md).
