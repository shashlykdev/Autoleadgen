import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var automationVM: AutomationViewModel
    let canStart: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Automation Controls")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canStart)

                Button(action: onPause) {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .disabled(!automationVM.currentState.canPause)

                Button(action: onResume) {
                    Label("Resume", systemImage: "play.fill")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .disabled(!automationVM.currentState.canResume)

                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!automationVM.currentState.canStop)
            }

            Divider()

            // Delay settings
            VStack(alignment: .leading, spacing: 8) {
                Text("Delay Between Messages")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Min:")
                    TextField("", value: $automationVM.minDelaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("sec")

                    Spacer().frame(width: 20)

                    Text("Max:")
                    TextField("", value: $automationVM.maxDelaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("sec")
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
