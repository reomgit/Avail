import SwiftUI

struct ZenReaderView: View {
    @Environment(AppEnvironment.self) private var environment
    let bookID: UUID
    @State private var model: ZenViewModel?
    @State private var showsInspector = true

    var body: some View {
        Group {
            if let model {
                ReadingContentView(model: model)
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                    .inspector(isPresented: $showsInspector) {
                        PlaybackInspectorView(model: model)
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(
                                showsInspector ? "Hide Inspector" : "Show Inspector",
                                systemImage: "sidebar.trailing"
                            ) {
                                showsInspector.toggle()
                            }
                            .help(showsInspector ? "Hide playback inspector" : "Show playback inspector")
                        }
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
