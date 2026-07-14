import AvailCore
import SwiftUI

struct ReadingContentView: View {
    let model: ZenViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.chunks) { chunk in
                        if let title = sectionTitle(startingAt: chunk) {
                            Text(title)
                                .font(.system(.title2, design: .serif, weight: .semibold))
                                .padding(.top, 18)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Text(attributedText(for: chunk))
                            .font(.system(size: 20, design: .serif))
                            .lineSpacing(8)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(chunk.id)
                            .accessibilityLabel(chunk.text)
                            .accessibilityValue(
                                model.highlightedSubstring(in: chunk).map { "Currently speaking: \($0)" } ?? ""
                            )
                    }
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 48)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1).onChanged { _ in model.userDidScroll() }
            )
            .overlay(alignment: .bottom) {
                if model.showsReturnToNarration {
                    Button("Return to Narration", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        model.returnToNarration(reduceMotion: reduceMotion)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .accessibilityHint("Re-enables automatic scrolling to the spoken text.")
                }
            }
            .onChange(of: model.playback.highlightedChunkID) {
                model.requestFollowScroll(reduceMotion: reduceMotion)
            }
            .onChange(of: model.scrollRequest) { _, request in
                guard let request else { return }
                if request.animated {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(request.chunkID, anchor: .center)
                    }
                } else {
                    proxy.scrollTo(request.chunkID, anchor: .center)
                }
            }
        }
    }

    private func sectionTitle(startingAt chunk: SpeechChunk) -> String? {
        guard let section = model.sections.first(where: { $0.id == chunk.sectionID }),
            section.chunkIDs.first == chunk.id
        else { return nil }
        return section.title
    }

    private func attributedText(for chunk: SpeechChunk) -> AttributedString {
        var attributed = AttributedString(chunk.text)
        guard let stringRange = model.highlightedStringRange(in: chunk),
            let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
            let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
        else {
            return attributed
        }
        attributed[lower..<upper].backgroundColor = .accentColor.opacity(0.18)
        attributed[lower..<upper].underlineStyle = Text.LineStyle(pattern: .solid, color: .accentColor)
        attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        return attributed
    }
}
