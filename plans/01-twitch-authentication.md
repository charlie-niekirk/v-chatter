# 1 — Twitch authentication

## Goal

Authenticate every user through Twitch in their default browser using the
public device-code flow. Anonymous reading or sending is never available.

## Prerequisites

- Register the public V Chatter application in the Twitch developer console.
- Supply its Client ID through the build configuration. Do not create or store
  a client secret because the application uses the public device-code flow.

## Work

- Request only `user:read:chat` and `user:write:chat` scopes. Start device
  authorization, open `verification_uri` with the OS browser, display the
  user code/progress in the app, and poll no faster than Twitch's interval.
- Exchange successful device authorization for an `AuthSession`, call Twitch
  token validation, and retrieve the authenticated user identity for display
  and sender IDs.
- Persist access and refresh tokens in Keychain. Serialize refresh attempts so
  a one-time-use refresh token is never consumed concurrently; atomically
  replace it with Twitch's returned token.
- On cancellation, denial, expiry, invalid token, or 401, clear Keychain
  credentials and return to the signed-out gate with an actionable retry
  state. Include explicit sign-out that revokes/clears local credentials.

## Acceptance

- No chat route, channel subscription, or composer is reachable without a
  valid authenticated session.
- Tests cover pending, success, denied, expired, refresh, validation failure,
  restart restoration, and redaction of sensitive values.
- UI automation verifies that authentication launches the external browser
  path and never embeds Twitch in a WebView.

## Dependencies

Foundation.
