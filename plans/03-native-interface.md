# 3 — Native interface

## Goal

Turn the functional client into a clean, modern, accessible macOS chat app.

## Work

- Build a dark three-area Native SDK view: saved-channel rail, selected-channel
  header/timeline, and persistent composer. Use a compact responsive layout
  for the minimum supported window width.
- Show signed-in identity, connection state, channel add/close controls,
  selected-tab state, unread counts, timestamps, sender colour, badges,
  replies, and inline connection/send errors.
- Provide keyboard-first interactions: focus composer, submit with Enter,
  newline with Shift+Enter, switch tabs, retry connection, and sign out. Give
  all controls descriptive accessibility labels and visible focus treatment.
- Keep Twitch login browser-only. The signed-out route should contain a single
  clear connect action and an explanation that anonymous chat is unavailable.
- Use the Native SDK automation server to capture reproducible snapshots and
  scripted interactions for signed-out, authenticating, connected, failed,
  and multi-tab states.

## Acceptance

- Automation verifies keyboard navigation, channel switching, unread state,
  message send feedback, and signed-out gating.
- Visual review confirms no clipped composer/timeline content at supported
  window sizes and no critical state relies on colour alone.

## Dependencies

Foundation and real-time chat; message decorations may use placeholders until
the emote plan lands.
