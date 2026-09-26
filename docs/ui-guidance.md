# Avail macOS 26 UI Guidance

This document records the native macOS 26 structure used by the Xcode application target.

## Native library window — 2026-07-15

Sources:

- [Migrating to new navigation types](https://developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types)
- [SwiftUI fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3Aoncancellation%3A%29)
- [SwiftUI OpenWindowAction](https://developer.apple.com/documentation/swiftui/openwindowaction)
- [SwiftUI customizable toolbars](https://developer.apple.com/documentation/swiftui/view/toolbar%28id%3Acontent%3A%29)
- [HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [HIG: Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [HIG: Windows](https://developer.apple.com/design/human-interface-guidelines/windows)
- [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer)

Decisions:

- Use `NavigationSplitView` with explicit, stable selection and a native `.sidebar` list. Sidebar rows stay flat and concise; book metadata belongs in the content pane.
- Use the system `fileImporter` for both library-folder selection and multi-book EPUB/PDF import. Security-scoped URLs are opened only for the duration of import or bookmark creation.
- Keep a `NavigationStack` in the detail column so a cover pushes a Books-style page with the native Back action.
- Keep the application-wide player visible on collection and detail routes. Browsing never changes narration; only Listen, Continue, or a chapter action does.
- Let the native split view, sidebar, search, toolbar, sheets, menus, and inspector supply system glass. Use one custom `GlassEffectContainer` only for the player’s coherent metadata, transport, and progress cluster.
- Expose Import, playback, and Open Zen through visible toolbar controls and scene commands with standard keyboard shortcuts. Use `ToolbarSpacer` to preserve native grouping.
- Use `ContentUnavailableView` for first run and empty collections, and `ProgressView` for copying/indexing without inventing custom progress chrome.
- Use semantic foreground styles, system selection, SF Symbols plus text, and accessibility values so state never depends on color alone.
- Keep the main window resizable with only minimum dimensions. Open the focused reader through a value-driven `WindowGroup` using `OpenWindowAction`.

## Apple Books-style detail — 2026-07-16

Decisions:

- Lead with cover artwork, title, author, format/state, progress, Listen/Continue, Open Zen, and a standard More menu.
- Keep covers, chapter rows, and reading content on the content canvas. Custom glass is reserved for the primary actions and persistent transport surface.
- Use `backgroundExtensionEffect` only behind the constrained artwork hero; it must not determine page geometry.
- Show committed chapters during preparation and start narration at the selected chapter’s first speakable chunk.

## Zen window — 2026-07-16

Sources:

- [SwiftUI value-driven WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup/init%28_%3Afor%3Acontent%3A%29)
- [SwiftUI WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
- [SwiftUI focusedSceneValue](https://developer.apple.com/documentation/swiftui/view/focusedscenevalue%28_%3A_%3A%29)
- [HIG: Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)
- [HIG: Windows](https://developer.apple.com/design/human-interface-guidelines/windows)
- [HIG: Foundations](https://developer.apple.com/design/human-interface-guidelines/foundations)

Decisions:

- Define Zen as a value-driven `WindowGroup` keyed by the persistent book UUID so macOS can restore the window and its represented book.
- Implement the approved Option B layout with SwiftUI’s trailing `.inspector`: flexible long-form content on the left and native inspector presentation on the right.
- Preserve standard window chrome, resize behavior, system appearance, and state restoration. The reader is focused through hierarchy and typography, not a borderless or fixed dark theme.
- Use a system serif font for book text. Emphasize the spoken range with both a semantic background and an underline so the cue is not color-only.
- Put cover, metadata, chapter, progress, voice, speed, and shared playback controls in the inspector. Glass is limited to the transport cluster.
- Publish scene-wide playback actions with `focusedSceneValue`; keep the same actions available through visible standard controls. Closing Zen never stops playback.
- Automatic follow scrolls only while follow mode is active. A manual scroll suspends follow and reveals Return to Narration. Reduce Motion disables animated recentering.

## Settings and recovery — 2026-07-15

Sources:

- [SwiftUI Settings scene](https://developer.apple.com/documentation/swiftui/settings/init%28content%3A%29)
- [SwiftUI settings tabs and openSettings](https://developer.apple.com/documentation/swiftui/environmentvalues/opensettings)
- [SwiftUI fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3AonCancellation%3A%29)
- [HIG: Writing](https://developer.apple.com/design/human-interface-guidelines/writing)
- [HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)

Decisions:

- Keep Library, Voices, Privacy, and Licenses in the native Settings scene using a compact `TabView` and grouped forms.
- Explain failures with a specific title, plain-language cause, and one concrete recovery action. Show destructive removal only after confirmation, and always route managed files through Trash.
- State the local-only document and speech boundary directly. Disclose that a user-selected loopback TTS server receives passage text and independently controls its storage, logging, and network behavior. Mention the limited macOS Now Playing metadata handoff separately and only in the context of active playback.

## Local voices — 2026-09-24

Sources:

- [SwiftUI Settings scene](https://developer.apple.com/documentation/swiftui/settings/init%28content%3A%29)
- [SwiftUI fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3Aoncancellation%3A%29)
- [HIG: Writing](https://developer.apple.com/design/human-interface-guidelines/writing)

Decisions:

- Put linked models, managed model copies, and user-configured loopback servers in one Voices tab and the same per-book voice picker as system voices. Identify the source and availability of each voice in text, not color alone.
- Explain the difference between Link and Copy before selection. Use the system folder importer, keep linked-folder security scope as short as practical, and confirm before sending a managed copy to Trash. Removing a link removes only Avail's reference.
- Provide a short test using synthetic text, plus specific recovery actions for an incompatible folder, missing model, or unavailable server. A failed neural voice must preserve the reading position and offer a macOS voice.
- Show preparation and generation progress without blocking navigation or the persistent player. Neural narration emphasizes a phrase in Zen with semantic background and a non-color cue; system narration keeps word-range emphasis. Voice changes take effect at the next phrase boundary.
- Describe server setup as optional and local to this Mac. Before adding a server, say it receives passage text and that its privacy behavior is controlled outside Avail. Keep Now Playing disclosure separate.
