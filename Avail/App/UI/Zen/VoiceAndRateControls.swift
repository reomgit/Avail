import SwiftUI

struct VoiceAndRateControls: View {
    @Environment(AppEnvironment.self) private var environment
    let model: ZenViewModel

    private let rates: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Speed", selection: rateBinding) {
                ForEach(rates, id: \.self) { rate in
                    Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "×")
                        .tag(rate)
                }
            }
            .pickerStyle(.menu)
            .accessibilityValue("\(model.book?.narrationRate ?? 1) times")

            Picker("Voice", selection: voiceBinding) {
                Text("Automatic").tag("")
                Section("macOS System Voices") {
                    ForEach(model.availableVoices.filter { !$0.id.hasPrefix("neural:") }) { voice in
                        Text("\(voice.name) — \(voice.languageCode)").tag(voice.id)
                    }
                }
                if environment.supportsLocalNeuralNarration {
                    let groups = VoicePickerGroups(entries: environment.voiceModelCatalog?.entries ?? [])
                    if !groups.imported.isEmpty {
                        Section("Fish Audio Models · Built with Fish Audio") {
                            ForEach(groups.imported) { entry in
                                Text("\(entry.name) — \(entry.source == .linked ? "Linked" : "Copied")")
                                    .tag(entry.providerVoiceID)
                            }
                        }
                    }
                    if !groups.servers.isEmpty {
                        Section("Local TTS Servers") {
                            ForEach(groups.servers) { entry in
                                Text(entry.name).tag(entry.providerVoiceID)
                            }
                        }
                    }
                }
                if let selected = model.book?.voiceIdentifier, !selected.isEmpty {
                    let isSavedCustomVoice =
                        environment.voiceModelCatalog?.entries.contains {
                            $0.providerVoiceID == selected
                        } == true
                    if isSavedCustomVoice && !environment.supportsLocalNeuralNarration {
                        Text("Custom voice unavailable on this Mac")
                            .tag(selected)
                    } else if let savedSystemVoice = model.availableVoices.first(where: { $0.id == "system:\(selected)" }) {
                        Text("\(savedSystemVoice.name) — Saved macOS Voice")
                            .tag(selected)
                    } else if !model.availableVoices.contains(where: { $0.id == selected }),
                        !(environment.voiceModelCatalog?.entries.contains(where: { $0.providerVoiceID == selected }) ?? false)
                    {
                        Text("Unavailable voice · Choose another")
                            .tag(selected)
                    }
                }
            }
            .pickerStyle(.menu)
            .accessibilityHint("Choose a macOS voice, a Fish Audio model, or a TTS server running on this Mac.")
        }
    }

    private var rateBinding: Binding<Double> {
        Binding(
            get: { model.book?.narrationRate ?? 1 },
            set: { model.setRate($0) }
        )
    }

    private var voiceBinding: Binding<String> {
        Binding(
            get: { model.book?.voiceIdentifier ?? "" },
            set: { model.setVoiceIdentifier($0.isEmpty ? nil : $0) }
        )
    }
}
