import SwiftUI

struct TestView: View {
    @ObservedObject var viewModel: TestViewModel
    @AppStorage("selectedModelId") private var selectedModelId: String = ""
    @AppStorage("sampleMessage") private var sampleMessage: String = ""

    // Manual test inputs
    @State private var testFirstName: String = "John"
    @State private var testHeadline: String = "Software Engineer at Apple"
    @State private var testCompany: String = "Apple"
    @State private var testRole: String = "Software Engineer"
    @State private var testLocation: String = "Cupertino, CA"

    // Batch test state
    @State private var isRunningBatchTest: Bool = false
    @State private var batchTestResults: [String: String] = [:]
    @State private var showBatchResults: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("AI Model Comparison")
                        .font(.headline)
                    Spacer()

                    appleIntelligenceStatusView
                }

                // Batch Test Section
                batchTestSection

                Divider()

                // Manual Test Section
                manualTestSection

                Divider()

                // Results Section
                resultsSection
            }
            .padding()
        }
    }

    // MARK: - Apple Intelligence Status

    @ViewBuilder
    private var appleIntelligenceStatusView: some View {
        let status = AIMessageService.appleIntelligenceStatus
        if status.available {
            Label("Apple Intelligence Ready", systemImage: "apple.logo")
                .font(.caption)
                .foregroundColor(.green)
        } else if AIMessageService.isAppleIntelligenceAvailable {
            // API available but model not ready
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text(status.reason ?? "Apple Intelligence not ready")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .help(status.reason ?? "Apple Intelligence is not available")
        } else {
            Label("Apple Intelligence Unavailable", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
                .help("Requires macOS 26.0+ with Apple Silicon")
        }
    }

    // MARK: - Batch Test Section

    private var batchTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Batch Model Test")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    runBatchTest()
                } label: {
                    if isRunningBatchTest {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Testing...")
                    } else {
                        Label("Test All Models", systemImage: "testtube.2")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRunningBatchTest)
            }

            Text("Tests a simulated profile against all available AI models to verify API parameters")
                .font(.caption)
                .foregroundColor(.secondary)

            if showBatchResults && !batchTestResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(batchTestResults.keys.sorted()), id: \.self) { modelId in
                        HStack(alignment: .top) {
                            Text(modelId)
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(width: 180, alignment: .leading)

                            Text(batchTestResults[modelId] ?? "")
                                .font(.caption)
                                .foregroundColor(batchTestResults[modelId]?.hasPrefix("✅") == true ? .green :
                                               batchTestResults[modelId]?.hasPrefix("❌") == true ? .red : .orange)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func runBatchTest() {
        isRunningBatchTest = true
        showBatchResults = false
        batchTestResults = [:]

        Task {
            // Test models from each provider
            let testModels = [
                // OpenAI GPT-5 (no temperature)
                "gpt-5-mini",
                "gpt-5-nano",
                // OpenAI GPT-4.1 (with temperature)
                "gpt-4.1-mini-2025-04-14",
                // Anthropic Claude
                "claude-3-5-haiku-20241022",
                // xAI Grok
                "grok-3-mini"
            ]

            let results = await viewModel.runBatchTest(
                models: testModels,
                sampleMessage: sampleMessage.isEmpty ? nil : sampleMessage
            )

            await MainActor.run {
                batchTestResults = results
                showBatchResults = true
                isRunningBatchTest = false
            }
        }
    }

    // MARK: - Manual Test Section

    private var manualTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Test")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("First Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("First name", text: $testFirstName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Role")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Job title", text: $testRole)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Company")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Company name", text: $testCompany)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Location", text: $testLocation)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Headline")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("LinkedIn headline", text: $testHeadline)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Selected Model: \(selectedModelId.isEmpty ? "None" : selectedModelId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    runManualTest()
                } label: {
                    if viewModel.isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Generating...")
                    } else {
                        Label("Generate & Compare", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGenerating || selectedModelId.isEmpty)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func runManualTest() {
        let profile = ProfileData(
            headline: testHeadline.isEmpty ? nil : testHeadline,
            location: testLocation.isEmpty ? nil : testLocation,
            about: nil,
            currentCompany: testCompany.isEmpty ? nil : testCompany,
            currentRole: testRole.isEmpty ? nil : testRole,
            education: nil,
            connectionDegree: nil,
            followerCount: nil
        )

        Task {
            await viewModel.generateComparison(
                leadName: testFirstName,
                profile: profile,
                selectedModelId: selectedModelId,
                sampleMessage: sampleMessage.isEmpty ? nil : sampleMessage
            )
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comparison Results")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(viewModel.comparisonResults.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Clear All") {
                    viewModel.clearResults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.comparisonResults.isEmpty)
            }

            if viewModel.comparisonResults.isEmpty {
                VStack {
                    Spacer()
                    Text("No comparison results yet")
                        .foregroundColor(.secondary)
                    Text("Results from Lead Finder scraping and manual tests will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(viewModel.comparisonResults) { result in
                    ComparisonResultCard(result: result) {
                        viewModel.deleteResult(result)
                    }
                }
            }
        }
    }
}

// MARK: - Comparison Result Card

struct ComparisonResultCard: View {
    let result: AIComparisonResult
    let onDelete: () -> Void

    @State private var isExpanded: Bool = true
    @State private var showProfileInfo: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(result.leadName)
                            .font(.headline)

                        if !result.linkedInURL.isEmpty, let url = URL(string: result.linkedInURL) {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        if let role = result.profileData.currentRole {
                            Text(role)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let company = result.profileData.currentCompany {
                            Text("@ \(company)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Text(result.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    showProfileInfo.toggle()
                } label: {
                    Image(systemName: showProfileInfo ? "person.fill" : "person")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("Show profile info")

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }

            // Profile Info Section (expandable)
            if showProfileInfo {
                ProfileInfoSection(profile: result.profileData)
            }

            if isExpanded {
                Divider()

                HStack(alignment: .top, spacing: 16) {
                    // Selected Model Result
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(.blue)
                            Text(result.selectedModelId)
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        if let message = result.selectedModelMessage {
                            Text(message)
                                .font(.system(.body, design: .rounded))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                        } else if let error = result.selectedModelError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Apple Intelligence Result
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "apple.logo")
                                .foregroundColor(.purple)
                            Text("Apple Intelligence")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        if let message = result.appleModelMessage {
                            Text(message)
                                .font(.system(.body, design: .rounded))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(6)
                        } else if let error = result.appleModelError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Profile Info Section

struct ProfileInfoSection: View {
    let profile: ProfileDataSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile Data Scraped from LinkedIn")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            if !profile.hasData {
                Text("No profile data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .topLeading),
                    GridItem(.flexible(), alignment: .topLeading)
                ], spacing: 8) {
                    ProfileField(label: "Headline", value: profile.headline)
                    ProfileField(label: "Location", value: profile.location)
                    ProfileField(label: "Current Role", value: profile.currentRole)
                    ProfileField(label: "Company", value: profile.currentCompany)
                    ProfileField(label: "Education", value: profile.education)
                    ProfileField(label: "Connection", value: profile.connectionDegree)
                    ProfileField(label: "Followers", value: profile.followerCount)
                }

                if let about = profile.about, !about.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("About")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(about)
                            .font(.caption)
                            .lineLimit(3)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(6)
    }
}

struct ProfileField: View {
    let label: String
    let value: String?

    var body: some View {
        if let value = value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}
