# V Chatter

A native macOS Twitch chat client, built with the Native SDK. V Chatter will
require Twitch authentication in the user's browser; anonymous chat is not
supported.

The app uses Twitch's public device-code flow: it opens the verification URL
in the default browser, never embeds Twitch in a WebView, and requests only
`user:read:chat` and `user:write:chat`. Tokens live in macOS Keychain, not the
preferences file. Product work is tracked and delivered through pull requests
only.

## Commands

```sh
npm ci
npx --no-install native dev . --yes                     # build and run with hot reload
npx --no-install native test . --yes                    # run the test suite
npx --no-install native build . --yes                   # produce a ReleaseFast binary
npx --no-install native check . --strict                # validate markup and manifest
npx --no-install native build . --yes -DTWITCH_CLIENT_ID=<public-client-id>
```

`TWITCH_CLIENT_ID` is a public Twitch application identifier, not a secret.
Never put a Twitch client secret, access token, or refresh token in source,
GitHub Actions variables, or the preferences file.

Before a signed build can authenticate, register V Chatter as a public client
in the Twitch developer console and provide that Client ID at build time. A
Client ID is intentionally omitted from this repository, so development builds
show an actionable configuration message instead of attempting anonymous chat.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the required branch and pull-request
workflow.
