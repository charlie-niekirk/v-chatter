# 2 — Real-time multi-channel chat

## Goal

Deliver live, signed-in Twitch chat across saved channel tabs.

## Work

- Resolve user-entered Twitch login names to broadcaster IDs; reject empty,
  duplicate, and unknown channels with inline errors. Persist the saved list
  and allow at most 10 simultaneously active tabs.
- Open one EventSub WebSocket session after sign-in. For each active tab,
  create a `channel.chat.message` subscription using the resolved broadcaster
  ID and the authenticated user ID; map notifications back to their tab.
- Handle welcome, keepalive, reconnect URL, duplicate-message protection,
  revocation, timeout/ban, connection loss, and exponential reconnect.
  Delete subscriptions when a tab closes and during orderly shutdown.
- Send selected-tab messages through Helix Send Chat Message. Use the signed-in
  user as `sender_id`; show pending, sent, held/AutoMod, failed, and rate-limit
  outcomes without inserting false successful messages.
- Keep only a bounded in-memory message timeline per active tab. Saved channels
  survive restart, but historical chat does not.

## Acceptance

- Mocked integration tests exercise subscription creation/cleanup, reconnect,
  ten-tab cap, persisted saved channels, send success, send rejection, and
  tab isolation.
- Network and authorization failures keep other tabs usable where possible and
  offer a clear recovery action.

## Dependencies

Twitch authentication.
