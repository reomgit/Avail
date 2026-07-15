import SwiftUI

struct VoiceAndRateControls: View {
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
                ForEach(model.availableVoices) { voice in
                    Text("\(voice.name) — \(voice.languageCode)").tag(voice.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityHint("Uses only voices installed on this Mac.")
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
