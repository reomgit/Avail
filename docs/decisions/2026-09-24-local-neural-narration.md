# Local neural narration

Date: 2026-09-24
Status: Approved by the maintainer's implementation request

## User and problem

Readers who prefer a local neural voice cannot currently use their own model with Avail. The maintainer specifically requested support for local LLM voice models, including Fish Audio, and for users to import custom models. No broader demand or usability research is claimed.

Today, Avail narrates with installed macOS voices. A user who wants a neural voice must listen outside Avail and loses its reading position, Zen synchronization, and shared playback controls. The narrow useful outcome is to let the same book and player use a user-supplied local voice while keeping system voices as the default and preserving Avail's offline core.

## Decision

- Offer Link and Copy for supported model folders. Start direct loading with Fish Audio S2 Pro MLX on Apple Silicon through a separately signed arm64 helper. Link stores an app-scoped bookmark; Copy installs into Avail's managed Models folder with interruption-safe atomic completion. Neither path downloads or bundles weights.
- Offer a user-configured OpenAI-compatible `/v1/audio/speech` endpoint on a literal loopback address. Reject remote hosts and redirects, and store optional credentials in Keychain. This requires the app's network-client entitlement even though system and imported-model speech need no network connection.
- Show both sources alongside macOS voices in the per-book picker. Qualify new voice IDs by provider while resolving existing macOS IDs. Keep generation in bounded phrases; record the active phrase and audio frame for exact audible resume, with stable text-position fallback after an index rebuild. Neural voices highlight a phrase; system voices retain word-range highlighting.
- Keep generated phrase WAV files in Application Support so a saved frame can resume after relaunch. Prune older clips when the cache grows past about 512 MiB; if a referenced clip is absent, regenerate that phrase from its start.
- Preserve the 450-word progressive playback threshold, application-wide playback across windows, and the existing narrow Now Playing metadata handoff. Failure to reach a server or model must leave the reading position intact and offer reconnect or a system voice.
- Add a Voices Settings tab for setup, a synthetic-text test, status, and removal. Removing a link deletes only its bookmark. Confirm removal of a managed copy and send its files to Trash.

## Privacy, constraints, and alternatives

The app declares `NSAllowsLocalNetworking` so macOS App Transport Security permits HTTP to local IP addresses for this explicit server integration. The request builder still accepts only literal `127.0.0.1` or `::1` endpoints and does not follow redirects. Apple documents this key as allowing unqualified domains, `.local` domains, and IPv4/IPv6 addresses; it does not enable arbitrary remote HTTP: [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Passage text stays on this Mac when Avail uses a model in its own helper. If a reader selects a local-server voice, Avail sends the phrase to that separate server on this Mac. The server controls its own storage, logging, and network behavior; Avail cannot make a privacy promise on its behalf. The UI must disclose this before connection and the README must state it. Avail continues to have no accounts, analytics, uploads, remote TTS endpoints, or automatic model downloads.

A single in-process model loader would add Apple Silicon dependencies to the universal app and risk playback and UI responsiveness. A helper confines native model loading to arm64. A server-only design would exclude readers who want to import a model folder directly; an importer-only design would exclude already installed local TTS servers. Automatic downloads would broaden privacy, licensing, and storage responsibilities, so they remain outside this release.

Fish Audio model materials have a separate [research license](https://github.com/fishaudio/fish-speech/blob/main/LICENSE), including commercial restrictions and attribution. Avail supplies no model weights and surfaces the license in third-party notices. [MLX Audio Swift v0.1.3](https://github.com/Blaizzy/mlx-audio-swift/releases/tag/v0.1.3) is pinned for the helper; its bundled dependencies and notices require review at release time.

## Acceptance and recovery

- A compatible linked or copied folder and a configured loopback server can be tested and selected for a book on Apple Silicon; incompatible folders and non-loopback addresses are rejected with actionable explanations. Intel Macs retain system voices.
- Pause, relaunch, index rebuild, cancellation, and a voice change preserve the audible position or use the stable text fallback. Browsing and opening or closing Zen do not interrupt the active session.
- Missing linked folders, interrupted copies, missing managed models, stopped servers, and failed synthesis keep source books and progress safe and present reconnect or system-voice recovery.
- Voice setup and playback remain usable with keyboard and VoiceOver, in light and dark appearance, increased contrast, reduced transparency and motion, and compact player and Zen layouts.

Model training, voice cloning from recordings, arbitrary checkpoint conversion, OCR, DRM support, remote endpoints, and automatic weight downloads are outside this decision. Validate with synthetic or public-domain fixtures; do not put user books or paths in tests or logs.
