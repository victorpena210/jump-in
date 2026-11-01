import SwiftUI

private enum CoachingMode: String, CaseIterable, Identifiable {
    case upwork = "Upwork clients"
    case interview = "Job interviews"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .upwork:
            return "Prepare for client conversations about requirements, scope, pricing, and timelines."
        case .interview:
            return "Prepare for interview questions using your experience and the role's requirements."
        }
    }
}

struct ContentView: View {
    @State private var selectedMode: CoachingMode = .upwork

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 64, height: 64)
                    .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Jump In")
                        .font(.largeTitle.bold())
                    Text("Your conversation coach")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a coaching mode")
                    .font(.headline)

                Picker("Coaching mode", selection: $selectedMode) {
                    ForEach(CoachingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(selectedMode.description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .topLeading)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Label("Starter project ready", systemImage: "checkmark.circle")
                    .font(.headline)
                Text("Next: connect meeting audio and private headphone playback.")
                Text("Audio capture and AI coaching are not connected yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 420)
    }
}

#Preview {
    ContentView()
}
