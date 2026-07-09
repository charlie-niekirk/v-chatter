# V Chatter implementation roadmap

Implement these documents in order. Each numbered document should be delivered
as one or more focused `codex/<topic>` pull requests; no direct pushes to
`master` are permitted.

| Order | Plan | Outcome |
| --- | --- | --- |
| 0 | [Foundation](00-foundation.md) | Application structure, configuration, secure local storage boundary |
| 1 | [Twitch authentication](01-twitch-authentication.md) | Browser-based signed-in session with no anonymous mode |
| 2 | [Real-time chat](02-realtime-chat.md) | Saved multi-channel EventSub/Helix chat client |
| 3 | [Native interface](03-native-interface.md) | Polished macOS chat experience |
| 4 | [Emotes and badges](04-emotes-and-badges.md) | Twitch, 7TV, BTTV, and FFZ message rendering |
| 5 | [Quality and releases](05-quality-and-releases.md) | Automation, required checks, and unsigned GitHub releases |

Before starting a plan, load the current Native SDK `core --full` guidance and,
where UI verification is involved, its `automation` guidance. Keep the Native
SDK CLI version consistent with CI unless intentionally updating it in a
dedicated PR.
