# Avail UI Guidance

This document records the Apple documentation consulted through Context7 before UI implementation and the project decisions derived from it.

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

Decisions:

- Use `NavigationSplitView` with explicit, stable selection and a native `.sidebar` list. Sidebar rows stay flat and concise; book metadata belongs in the content pane.
- Use the system `fileImporter` for both library-folder selection and multi-book EPUB/PDF import. Security-scoped URLs are opened only for the duration of import or bookmark creation.
- Expose Import, playback, and Open Zen through visible toolbar controls and scene commands with standard keyboard shortcuts.
- Use `ContentUnavailableView` for first run and empty collections, and `ProgressView` for copying/indexing without inventing custom progress chrome.
- Use semantic foreground styles, system selection, SF Symbols plus text, and accessibility values so state never depends on color alone.
- Keep the main window resizable with only minimum dimensions. Open the focused reader through a value-driven `WindowGroup` using `OpenWindowAction`.
