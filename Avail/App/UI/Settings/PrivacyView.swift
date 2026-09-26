import SwiftUI

struct PrivacyView: View {
    var body: some View {
        Form {
            Section("Local by Design") {
                LabeledContent("Books") {
                    Label("Stay on this Mac", systemImage: "checkmark.shield")
                }
                LabeledContent("Speech") {
                    Label("Generated on this Mac", systemImage: "waveform")
                }
                LabeledContent("Network") {
                    Label("No internet service or analytics", systemImage: "network.slash")
                }
            }
            Section("Optional Local TTS Server") {
                Text(
                    "If you add a TTS server in Voices settings, Avail sends passage text and the selected voice request only to the loopback server address on this Mac. The separate server controls its own privacy behavior, including any logging or network access. Check its settings before connecting."
                )
                .foregroundStyle(.secondary)
            }
            Section("System Integration") {
                Text(
                    "While a book is playing, Avail shares its title, author, chapter, artwork, and playback position with macOS Now Playing so media keys and Control Center work. Avail clears this state when playback ends."
                )
                .foregroundStyle(.secondary)
            }
            Section("Your Folder") {
                Text("Avail accesses only the library folder and book files you choose through macOS security-scoped permissions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
