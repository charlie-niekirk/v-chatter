# 4 — Emotes and badges

## Goal

Render chat in a way that feels native to Twitch communities while degrading
gracefully when provider services are unavailable.

## Work

- Render Twitch EventSub message fragments, using Twitch's CDN template for
  emotes and the official global/channel badge endpoints for badge artwork.
- Add provider clients for 7TV, BetterTTV, and FrankerFaceZ. Load global and
  channel catalogs lazily, cache them in memory, and refresh without blocking
  message delivery.
- Tokenize text fragments against the active channel catalog. For matching
  third-party names use deterministic precedence: 7TV, then BTTV, then FFZ.
  Twitch fragments remain authoritative for native Twitch emotes.
- Constrain image dimensions, decode off the UI path, provide alt text, and
  render source text when an image/catalog request fails.

## Acceptance

- Unit tests cover fragment preservation, provider precedence, cache expiry,
  failed provider fetches, and duplicate names.
- Snapshot tests cover mixed text, Twitch emotes, third-party emotes, badges,
  replies, and offline fallbacks.

## Dependencies

Real-time chat and native interface.
