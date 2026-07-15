import SwiftUI

struct ChapterMenu: View {
    let model: ZenViewModel

    var body: some View {
        LabeledContent("Chapter") {
            Menu(model.currentChapterTitle ?? "Choose Chapter") {
                ForEach(model.sections) { section in
                    Button {
                        model.selectChapter(section.id)
                    } label: {
                        if section.id == model.currentSectionID {
                            Label(section.title ?? "Chapter \(section.ordinal + 1)", systemImage: "checkmark")
                        } else {
                            Text(section.title ?? "Chapter \(section.ordinal + 1)")
                        }
                    }
                    .disabled(section.chunkIDs.isEmpty)
                }
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Chapter")
            .accessibilityValue(model.currentChapterTitle ?? "Not selected")
        }
    }
}
