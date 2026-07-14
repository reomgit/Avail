import SwiftUI

struct ZenReaderView: View {
    @Environment(AppEnvironment.self) private var environment
    let bookID: UUID
    @State private var model: ZenViewModel?

    var body: some View {
        Group {
            if let model {
                HSplitView {
                    ReadingContentView(model: model)
                        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                    PlaybackInspectorView(model: model)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420, maxHeight: .infinity)
                }
                .focusedSceneValue(\.zenCommandActions, model.commandActions)
            } else {
                ProgressView("Opening book…")
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .navigationTitle(model?.book?.title ?? "Zen")
        .task(id: bookID) {
            guard let libraryStore = environment.libraryStore,
                let indexStore = environment.indexStore,
                let playback = environment.playbackCoordinator
            else { return }
            let created = ZenViewModel(
                bookID: bookID,
                libraryStore: libraryStore,
                indexStore: indexStore,
                playback: playback
            )
            model = created
            await created.load()
        }
        .onDisappear {
            model?.windowWillClose()
        }
    }
}
