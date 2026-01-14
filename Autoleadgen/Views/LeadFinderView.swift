import SwiftUI

struct LeadFinderView: View {
    @ObservedObject var viewModel: LeadFinderViewModel
    let onAddContacts: ([Lead]) -> Void

    // AI Settings
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("selectedModelId") private var selectedModelId: String = ""
    @AppStorage("sampleMessage") private var sampleMessage: String = ""

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
                let models = try await CloudKeyStorageService.shared.fetchModels()
                await MainActor.run {
                    availableModels = models
                    isLoadingModels = false

                    // Auto-select first model if none selected
                    if selectedModelId.isEmpty, let first = models.first {
                        selectedModelId = first.id
                    }
                }
            } catch {
                await MainActor.run {
                    modelsError = error.localizedDescription
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
}
