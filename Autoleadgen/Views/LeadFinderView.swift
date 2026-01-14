import SwiftUI

struct LeadFinderView: View {
    @ObservedObject var viewModel: LeadFinderViewModel
    let onAddContacts: ([Lead]) -> Void

    // AI Settings
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("selectedModelId") private var selectedModelId: String = ""
    @AppStorage("sampleMessage") private var sampleMessage: String = ""

    // Apollo Settings
    @AppStorage("apolloEnabled") private var apolloEnabled: Bool = false
    @State private var apolloApiKey: String = ""
    @State private var isLoadingApolloKey: Bool = false
    @State private var apolloKeyLoaded: Bool = false
    @State private var apolloTestResult: String?
    @State private var isTestingApollo: Bool = false

    // Models state
    @State private var availableModels: [CloudKeyStorageService.AIModel] = []
    @State private var isLoadingModels: Bool = false
    @State private var modelsError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("Lead Finder")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.seenURLsCount) in history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Search Fields
                searchFieldsSection

                // AI Model Selection
                aiModelSection

                // Apollo Email Enrichment
                apolloSettingsSection

                // Search Controls
                searchControlsSection

                // Progress
                if viewModel.isWorking {
                    progressSection
                }

                // Status
                if !viewModel.statusMessage.isEmpty {
                    statusSection
                }

                // Results Summary
                if !viewModel.scrapedLeads.isEmpty || viewModel.duplicatesSkipped > 0 {
                    ScrapedResultsSummary(
                        newLeadsCount: viewModel.newLeadsCount,
                        duplicatesSkipped: viewModel.duplicatesSkipped,
                        savedToLeadsCount: viewModel.savedToLeadsCount
                    )
                }

                // Scraped Leads Table
                if !viewModel.scrapedLeads.isEmpty {
                    ScrapedResultsView(leads: viewModel.scrapedLeads)
                }

                // Actions
                actionsSection
            }
            .padding()
        }
        .onAppear {
            // Set up callback for auto-adding contacts
            viewModel.onContactsReady = { contacts in
                onAddContacts(contacts)
            }

            if availableModels.isEmpty {
                loadModels()
            }
        }
    }

    // MARK: - Search Fields

    private var searchFieldsSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Role / Job Title")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., CEO, HR Director, Marketing Manager", text: $viewModel.role)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Location")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., Zurich, Switzerland, New York", text: $viewModel.location)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - AI Model Selection

    private var aiModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Message Generation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Toggle("", isOn: $aiEnabled)
                    .labelsHidden()
            }

            if aiEnabled {
                HStack(spacing: 12) {
                    // Model picker
                    if isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading models...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let error = modelsError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                loadModels()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        Picker("Model", selection: $selectedModelId) {
                            Text("Select a model").tag("")
                            ForEach(groupedModels, id: \.key) { provider, models in
                                Section(header: Text(provider.capitalized)) {
                                    ForEach(models) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 300)

                        // Status indicator
                        if !selectedModelId.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        Spacer()

                        Button {
                            loadModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Refresh models")
                    }
                }

                if !selectedModelId.isEmpty, let model = availableModels.first(where: { $0.id == selectedModelId }) {
                    Text("Using \(model.provider.capitalized) • \(model.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Sample message field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Message (for AI reference)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $sampleMessage)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80, maxHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    Text("Provide a sample message style for the AI to follow when generating personalized messages")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var groupedModels: [(key: String, value: [CloudKeyStorageService.AIModel])] {
        Dictionary(grouping: availableModels, by: { $0.provider })
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    private func loadModels() {
        isLoadingModels = true
        modelsError = nil

        Task {
            do {
                var models = try await CloudKeyStorageService.shared.fetchModels()

                // Add Apple Intelligence if available (on-device, no API key needed)
                if AIMessageService.isAppleIntelligenceAvailable {
                    let appleModel = CloudKeyStorageService.AIModel(
                        id: "apple-intelligence",
                        name: "Apple Intelligence (On-Device)",
                        provider: "apple"
                    )
                    models.insert(appleModel, at: 0)
                }

                await MainActor.run {
                    availableModels = models
                    isLoadingModels = false

                    // Auto-select Apple Intelligence if available and none selected
                    if selectedModelId.isEmpty {
                        if AIMessageService.isAppleIntelligenceAvailable {
                            selectedModelId = "apple-intelligence"
                        } else if let first = models.first {
                            selectedModelId = first.id
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    // Even on error, add Apple Intelligence if available
                    if AIMessageService.isAppleIntelligenceAvailable {
                        let appleModel = CloudKeyStorageService.AIModel(
                            id: "apple-intelligence",
                            name: "Apple Intelligence (On-Device)",
                            provider: "apple"
                        )
                        availableModels = [appleModel]
                        modelsError = nil
                    } else {
                        modelsError = error.localizedDescription
                    }
                    isLoadingModels = false
                }
            }
        }
    }

    // MARK: - Search Controls

    private var searchControlsSection: some View {
        HStack {
            Button(viewModel.isWorking ? "Stop" : "Find Leads") {
                if viewModel.isWorking {
                    viewModel.stopSearch()
                } else {
                    viewModel.startSearch()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isWorking ? .red : .blue)
            .disabled(!viewModel.canSearch && !viewModel.isWorking)

            Spacer()

            HStack(spacing: 4) {
                Text("Target:")
                Stepper("\(viewModel.targetLeadsCount) leads", value: $viewModel.targetLeadsCount, in: 10...500, step: 10)
                    .frame(width: 140)
            }
            .disabled(viewModel.isWorking)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            if viewModel.isSearching {
                // Phase 1: Google search progress
                ProgressView(value: Double(viewModel.newLeadsCount), total: Double(viewModel.targetLeadsCount))

                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Phase 1: Found \(viewModel.newLeadsCount) of \(viewModel.targetLeadsCount) leads...")
                        .font(.caption)
                    Spacer()
                }
            } else if viewModel.isProcessingProfiles {
                // Phase 2: Profile processing progress
                ProgressView(value: Double(viewModel.currentProfileIndex), total: Double(viewModel.scrapedLeads.count))

                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Phase 2: Processing profile \(viewModel.currentProfileIndex) of \(viewModel.scrapedLeads.count)...")
                        .font(.caption)
                    Spacer()
                }
            } else if viewModel.isEnrichingEmails {
                // Phase 3: Apollo email enrichment progress
                ProgressView(value: Double(viewModel.currentEnrichmentIndex), total: Double(viewModel.processedLeads.count))

                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Phase 3: Enriching emails \(viewModel.currentEnrichmentIndex) of \(viewModel.processedLeads.count)...")
                        .font(.caption)
                    if viewModel.enrichedCount > 0 {
                        Text("(\(viewModel.enrichedCount) found)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack {
            Image(systemName: viewModel.isWorking ? "magnifyingglass" : "checkmark.circle")
                .foregroundColor(viewModel.isWorking ? .blue : .green)
            Text(viewModel.statusMessage)
                .font(.caption)
            Spacer()
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack {
            Spacer()

            Button("Clear Results") {
                viewModel.clearResults()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.scrapedLeads.isEmpty || viewModel.isWorking)

            Button("Clear History") {
                viewModel.clearHistory()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isWorking)
        }
    }

    // MARK: - Apollo Settings

    private var apolloSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apollo Email Enrichment")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("100 free credits/month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)

                Spacer()

                Toggle("", isOn: $apolloEnabled)
                    .labelsHidden()
                    .disabled(!apolloKeyLoaded || apolloApiKey.isEmpty)
                    .onChange(of: apolloEnabled) { _, newValue in
                        viewModel.apolloEnabled = newValue
                        viewModel.apolloApiKey = apolloApiKey
                    }
            }

            if isLoadingApolloKey {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading Apollo API key...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if apolloKeyLoaded && !apolloApiKey.isEmpty {
                // Key loaded from cloud
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("API key loaded from cloud")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Test") {
                        testApolloConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTestingApollo)
                }

                // Test Result
                if let result = apolloTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("Success") ? .green : .red)
                }

                if apolloEnabled {
                    Text("Leads will be enriched with email addresses after scraping")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // No key configured
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Apollo API key not configured in Vercel")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Retry") {
                        loadApolloKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !apolloEnabled && apolloKeyLoaded && !apolloApiKey.isEmpty {
                Text("Enable to get email addresses for leads (bypasses LinkedIn DMs)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            if !apolloKeyLoaded {
                loadApolloKey()
            }
        }
    }

    private func loadApolloKey() {
        isLoadingApolloKey = true
        apolloTestResult = nil

        Task {
            do {
                if let key = try await CloudKeyStorageService.shared.getAPIKey(for: "apollo"), !key.isEmpty {
                    await MainActor.run {
                        apolloApiKey = key
                        apolloKeyLoaded = true
                        isLoadingApolloKey = false
                        viewModel.apolloApiKey = key
                        if apolloEnabled {
                            viewModel.apolloEnabled = true
                        }
                    }
                } else {
                    await MainActor.run {
                        apolloKeyLoaded = true
                        isLoadingApolloKey = false
                    }
                }
            } catch {
                await MainActor.run {
                    apolloKeyLoaded = true
                    isLoadingApolloKey = false
                }
            }
        }
    }

    private func testApolloConnection() {
        isTestingApollo = true
        apolloTestResult = nil

        Task {
            do {
                // Test with a sample LinkedIn URL
                let result = try await ApolloEnrichmentService.shared.enrichByLinkedIn(
                    linkedInURL: "https://www.linkedin.com/in/test",
                    firstName: "Test",
                    lastName: "User",
                    apiKey: apolloApiKey
                )
                await MainActor.run {
                    if result.wasFound {
                        apolloTestResult = "Success! API key valid. Email: \(result.email ?? "none found")"
                    } else {
                        apolloTestResult = "Success! API key valid (test profile not in Apollo DB)"
                    }
                    isTestingApollo = false
                }
            } catch let error as ApolloError {
                await MainActor.run {
                    apolloTestResult = "Error: \(error.localizedDescription)"
                    isTestingApollo = false
                }
            } catch {
                await MainActor.run {
                    apolloTestResult = "Error: \(error.localizedDescription)"
                    isTestingApollo = false
                }
            }
        }
    }
}
