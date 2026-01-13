import SwiftUI
import WebKit

struct LeadFinderView: View {
    @ObservedObject var viewModel: LeadFinderViewModel
    let webView: WKWebView
    let onAddContacts: ([Contact]) -> Void

    // AI Settings
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("aiProvider") private var providerRaw: String = "OpenAI"
    @AppStorage("aiApiKey") private var apiKey: String = ""

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
                if viewModel.isSearching {
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
                    // Provider picker
                    Picker("", selection: $providerRaw) {
                        ForEach(AIProvider.allCases, id: \.rawValue) { p in
                            Text(p.rawValue).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)

                    // API Key
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)

                    // Status indicator
                    if !apiKey.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.orange)
                    }
                }

                Text("Messages will be AI-generated from scraped profile data (headline, experience, education)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Search Controls

    private var searchControlsSection: some View {
        HStack {
            Button(viewModel.isSearching ? "Stop" : "Find Leads") {
                if viewModel.isSearching {
                    viewModel.stopSearch()
                } else {
                    viewModel.startSearch(webView: webView)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isSearching ? .red : .blue)
            .disabled(!viewModel.canSearch && !viewModel.isSearching)

            Spacer()

            HStack(spacing: 4) {
                Text("Target:")
                Stepper("\(viewModel.targetLeadsCount) leads", value: $viewModel.targetLeadsCount, in: 10...500, step: 10)
                    .frame(width: 140)
            }
            .disabled(viewModel.isSearching)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(viewModel.newLeadsCount), total: Double(viewModel.targetLeadsCount))

            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Found \(viewModel.newLeadsCount) of \(viewModel.targetLeadsCount) leads...")
                    .font(.caption)
                Spacer()
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack {
            Image(systemName: viewModel.isSearching ? "magnifyingglass" : "checkmark.circle")
                .foregroundColor(viewModel.isSearching ? .blue : .green)
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
            if !viewModel.scrapedLeads.isEmpty && !viewModel.isSearching {
                Button("Add \(viewModel.scrapedLeads.count) Leads to Contacts") {
                    let contacts = viewModel.convertToContacts()
                    onAddContacts(contacts)
                    viewModel.clearResults()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            Spacer()

            Button("Clear Results") {
                viewModel.clearResults()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.scrapedLeads.isEmpty)

            Button("Clear History") {
                viewModel.clearHistory()
            }
            .buttonStyle(.bordered)
        }
    }
}
