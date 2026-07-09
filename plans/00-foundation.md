# 0 — Foundation

## Goal

Replace the generated counter baseline with a maintainable Native SDK
application shell without yet calling Twitch.

## Work

- Establish Zig modules for `app_state`, `config`, `storage`, `twitch`,
  `chat`, and `ui`; preserve a thin `main.zig` that wires the Native SDK shell
  to the application model and message dispatcher.
- Define the stable application types: `AuthSession`, `AppConfig`,
  `SavedChannel`, `ActiveChannel`, `ChatMessage`, `MessageFragment`, and
  `ConnectionState`.
- Add a build-time `TWITCH_CLIENT_ID` option. Keep a development placeholder
  out of releases; document local invocation and configure the non-secret
  value as a GitHub Actions repository variable for production packaging.
- Implement a storage interface with two implementations: macOS Keychain for
  OAuth tokens and a local versioned preferences file for saved channels and
  presentation settings. No token may be written to preferences, logs, or
  crash messages.
- Update the manifest, app metadata, icon, accessibility labels, minimum
  window size, and app title for V Chatter. Keep macOS-specific code isolated
  behind the storage interface.

## Acceptance

- The app launches to a deterministic signed-out shell.
- Unit tests cover serialization/defaults/migrations and prove token values
  cannot flow into the preferences serializer.
- `native check`, `native test`, and `native build` pass locally and in CI.

## Dependencies

None. Complete before authentication work.
