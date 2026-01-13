import SwiftUI

struct ProgressSection: View {
    @ObservedObject var automationVM: AutomationViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Progress")
                .font(.headline)

            ProgressView(value: automationVM.progress)
                .progressViewStyle(.linear)

            HStack {
                Text("\(automationVM.currentContactIndex) / \(automationVM.totalContacts)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(automationVM.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            statusView
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var statusView: some View {
        switch automationVM.currentState {
        case .idle:
            Label("Ready to start", systemImage: "circle")
                .foregroundColor(.gray)

        case .waitingForLogin:
            Label("Waiting for LinkedIn login...", systemImage: "person.badge.clock")
                .foregroundColor(.orange)

        case .running:
            Label("Running", systemImage: "arrow.triangle.2.circlepath")
                .foregroundColor(.blue)

        case .waitingForDelay(let seconds):
            HStack {
                Image(systemName: "timer")
                Text("Next message in \(seconds) seconds")
            }
            .foregroundColor(.orange)

        case .processingContact(let name):
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Processing: \(name)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundColor(.blue)

        case .paused:
            Label("PAUSED", systemImage: "pause.circle.fill")
                .foregroundColor(.yellow)
                .font(.headline)

        case .completed:
            Label("COMPLETED", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.headline)

        case .error(let message):
            VStack(alignment: .leading) {
                Label("Error", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
    }
}
