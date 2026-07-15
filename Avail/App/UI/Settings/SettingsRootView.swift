import SwiftUI

struct SettingsRootView: View {
    @AppStorage("selectedSettingsTab") private var selectedTab = "library"

    var body: some View {
        TabView(selection: $selectedTab) {
            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag("library")
            PrivacyView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag("privacy")
            LicensesView()
                .tabItem { Label("Licenses", systemImage: "doc.text") }
                .tag("licenses")
        }
        .frame(width: 560, height: 380)
    }
}
