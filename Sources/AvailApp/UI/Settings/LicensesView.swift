import SwiftUI

struct LicensesView: View {
    var body: some View {
        Form {
            Section("Avail") {
                LabeledContent("License", value: "MIT")
                Text("Copyright © 2026 Avail contributors")
                    .foregroundStyle(.secondary)
            }
            Section("Open-Source Dependencies") {
                dependency(
                    "ZIPFoundation",
                    url: "https://github.com/weichsel/ZIPFoundation",
                    notice: "Copyright © 2017-2024 Thomas Zoechling and contributors — MIT License"
                )
                dependency(
                    "SwiftSoup",
                    url: "https://github.com/scinfu/SwiftSoup",
                    notice: "Copyright © 2016-2026 SwiftSoup contributors — MIT License"
                )
            }
            Section {
                Text("Complete license texts are included with the source repository and packaged application notices.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func dependency(_ name: String, url: String, notice: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Link(name, destination: URL(string: url)!)
            Text(notice)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
