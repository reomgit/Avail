import SwiftUI

struct LibraryDetailLayout<Content: View, Player: View>: View {
    private let content: Content
    private let player: Player

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder player: () -> Player
    ) {
        self.content = content()
        self.player = player()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            player
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
