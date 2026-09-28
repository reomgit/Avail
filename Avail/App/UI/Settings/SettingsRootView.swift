import SwiftUI

struct SettingsRootView: View {
    @AppStorage("selectedSettingsTab") private var selectedTab = "library"

    var body: some View {
        TabView(selection: $selectedTab) {
            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag("library")
            VoicesSettingsView()
                .tabItem { Label("Voices", systemImage: "waveform") }
                .tag("voices")
            PrivacyView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag("privacy")
            LicensesView()
                .tabItem { Label("Licenses", systemImage: "doc.text") }
                .tag("licenses")
        }
        .frame(width: 620, height: 580)
        .safeAreaInset(edge: .top, spacing: 0) {
            NarrationActivityStrip()
        }
    }
}
