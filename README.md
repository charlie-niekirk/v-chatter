# V Chatter

A native macOS Twitch chat client, built with the Native SDK. V Chatter will
require Twitch authentication in the user's browser; anonymous chat is not
supported.

The repository currently contains the Native SDK baseline. Product work is
tracked and delivered through pull requests only.

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for the required branch and pull-request
workflow.
