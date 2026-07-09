# V Chatter

A native macOS Twitch chat client, built with the Native SDK. V Chatter will
require Twitch authentication in the user's browser; anonymous chat is not
supported.

The repository currently contains the Native SDK baseline. Product work is
tracked and delivered through pull requests only.

## Commands

```sh
npx @native-sdk/cli@0.4.1 dev . --yes     # build and run with hot reload
npx @native-sdk/cli@0.4.1 test . --yes    # run the test suite
npx @native-sdk/cli@0.4.1 build . --yes   # produce a ReleaseFast binary
npx @native-sdk/cli@0.4.1 check . --strict # validate markup and manifest
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the required branch and pull-request
workflow.
