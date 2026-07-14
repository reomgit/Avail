import SwiftUI

struct SettingsRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            LabeledContent("Library Location", value: "Not selected")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .disabled(environment.launchState == .loading)
    }
}
