import SwiftUI

struct AISettingsView: View {
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("aiProvider") private var providerRaw: String = "OpenAI"
    @AppStorage("aiApiKey") private var apiKey: String = ""

    @State private var showApiKey = false
    @State private var testResult: String?
    @State private var isTesting = false

    private var provider: AIProvider {
        get { AIProvider(rawValue: providerRaw) ?? .openai }
        set { providerRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with toggle
            HStack {
                Text("AI Message Generation")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $aiEnabled)
                    .labelsHidden()
            }

            if aiEnabled {
                // Provider Selection
                Picker("Provider", selection: $providerRaw) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { p in
                        Text(p.rawValue).tag(p.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                // API Key Input
                HStack {
                    Group {
                        if showApiKey {
                            TextField("API Key", text: $apiKey)
                        } else {
                            SecureField("API Key", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button(showApiKey ? "Hide" : "Show") {
                        showApiKey.toggle()
                    }
                    .buttonStyle(.borderless)
                }

                // Model Info
                HStack {
                    Text("Model: \(provider.defaultModel)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Test Button
                    Button("Test") {
                        testConnection()
                    }
                    .disabled(apiKey.isEmpty || isTesting)
                    .buttonStyle(.bordered)
                }

                // Test Result
                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("Success") ? .green : .red)
                        .lineLimit(2)
                }

                // Help Links
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get API Keys:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 16) {
                        Link("OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        Link("Anthropic", destination: URL(string: "https://console.anthropic.com/")!)
                        Link("xAI", destination: URL(string: "https://console.x.ai/")!)
                    }
                    .font(.caption)
                }
            } else {
                Text("Enable AI to generate personalized messages based on LinkedIn profile data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let service = AIMessageService()
            let testProfile = ProfileData(
                headline: "Software Engineer",
                location: "San Francisco",
                currentCompany: "Tech Corp",
                currentRole: "Senior Developer"
            )

            do {
                let message = try await service.generateMessage(
                    provider: provider,
                    apiKey: apiKey,
                    profile: testProfile,
                    firstName: "Test"
                )
                await MainActor.run {
                    testResult = "Success! Generated \(message.count) chars"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Error: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    AISettingsView()
        .frame(width: 400)
        .padding()
}
