import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var showingFilePicker = false
    @State private var selectedTab: Int = 0

    var body: some View {
        HSplitView {
            // Left panel: Browser
            VStack(spacing: 0) {
                browserToolbar
                LinkedInWebView(webView: viewModel.browserVM.webView)
            }
            .frame(minWidth: 600)

            // Right panel: Controls and status
            VStack(spacing: 0) {
                // Tab selector
                Picker("", selection: $selectedTab) {
                    Text("Automation").tag(0)
                    Text("Lead Finder").tag(1)
                    Text("Leads").tag(2)
                    Text("Settings").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content
                TabView(selection: $selectedTab) {
                    // Tab 0: Automation
                    automationTab
                        .tag(0)

                    // Tab 1: Lead Finder
                    LeadFinderView(
                        viewModel: viewModel.leadFinderVM,
                        onAddContacts: { leads in
                            viewModel.addLeads(leads)
                        }
                    )
                    .tag(1)

                    // Tab 2: Leads Management
                    LeadsManagementView(
                        viewModel: viewModel.leadsVM,
                        onAddToContacts: { leads in
                            viewModel.addLeads(leads)
                        }
                    )
                    .tag(2)

                    // Tab 3: Settings
                    settingsTab
                        .tag(3)
                }
                .tabViewStyle(.automatic)
            }
            .frame(minWidth: 400, idealWidth: 500, maxWidth: 600)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv")!],
            onCompletion: handleFileSelection
        )
    }

    // MARK: - Browser Toolbar

    private var browserToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { viewModel.browserVM.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.browserVM.canGoBack)
            .buttonStyle(.borderless)

            Button(action: { viewModel.browserVM.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.browserVM.canGoForward)
            .buttonStyle(.borderless)

            Button(action: { viewModel.browserVM.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 16)

            if viewModel.browserVM.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }

            Text(viewModel.browserVM.pageTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("LinkedIn Home") {
                viewModel.browserVM.loadLinkedIn()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Login Status

    private var loginStatusSection: some View {
        HStack {
            Circle()
                .fill(viewModel.isLoggedIn ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Text(viewModel.isLoggedIn ? "Logged in to LinkedIn" : "Please log in to LinkedIn")
                .font(.headline)

            Spacer()

            if !viewModel.isLoggedIn {
                Text("Log in using the browser on the left")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - File Picker

    private var filePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contact File (CSV)")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.contactListVM.currentExcelPath?.lastPathComponent ?? "No file selected")
                        .foregroundColor(viewModel.contactListVM.currentExcelPath != nil ? .primary : .secondary)

                    if !viewModel.contactListVM.leads.isEmpty {
                        HStack(spacing: 16) {
                            Label("\(viewModel.contactListVM.leads.count) leads", systemImage: "person.2")
                            Label("\(viewModel.contactListVM.pendingLeads.count) pending", systemImage: "clock")
                            Label("\(viewModel.contactListVM.sentCount) sent", systemImage: "checkmark.circle")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Select File") {
                    showingFilePicker = true
                }
                .buttonStyle(.bordered)

                if !viewModel.contactListVM.leads.isEmpty {
                    Button("Reset Failed") {
                        viewModel.contactListVM.resetAllFailed()
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.contactListVM.failedCount == 0)
                }
            }

            if let error = viewModel.contactListVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - File Selection Handler

    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                await viewModel.loadExcelFile(from: url)
            }
        case .failure(let error):
            viewModel.loggingService.error("Failed to select file: \(error.localizedDescription)")
        }
    }

    // MARK: - Automation Tab

    private var automationTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                loginStatusSection
                filePickerSection
                ControlPanelView(
                    automationVM: viewModel.automationVM,
                    canStart: viewModel.canStartAutomation,
                    onStart: { viewModel.startAutomation() },
                    onPause: { viewModel.pauseAutomation() },
                    onResume: { viewModel.resumeAutomation() },
                    onStop: { viewModel.stopAutomation() }
                )
                ProgressSection(automationVM: viewModel.automationVM)
                ContactTableView(
                    leads: viewModel.contactListVM.leads,
                    onResetLead: { lead in
                        viewModel.contactListVM.resetLead(lead)
                    }
                )
                .frame(minHeight: 200, maxHeight: 300)
                LogView(loggingService: viewModel.loggingService)
                    .frame(minHeight: 150, maxHeight: 250)
            }
            .padding()
        }
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Message Delay Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Message Delay Settings")
                        .font(.headline)

                    HStack {
                        Text("Delay between paste and send:")
                        Spacer()
                        Text("\(viewModel.automationVM.minMessageDelaySeconds)-\(viewModel.automationVM.maxMessageDelaySeconds) seconds")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Min:")
                        Slider(value: Binding(
                            get: { Double(viewModel.automationVM.minMessageDelaySeconds) },
                            set: { viewModel.automationVM.minMessageDelaySeconds = Int($0) }
                        ), in: 1...30, step: 1)
                        Text("\(viewModel.automationVM.minMessageDelaySeconds)s")
                            .frame(width: 30)
                    }

                    HStack {
                        Text("Max:")
                        Slider(value: Binding(
                            get: { Double(viewModel.automationVM.maxMessageDelaySeconds) },
                            set: { viewModel.automationVM.maxMessageDelaySeconds = Int($0) }
                        ), in: 1...60, step: 1)
                        Text("\(viewModel.automationVM.maxMessageDelaySeconds)s")
                            .frame(width: 30)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Navigation Delay Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Navigation Delay Settings")
                        .font(.headline)

                    HStack {
                        Text("Delay between leads:")
                        Spacer()
                        Text("\(viewModel.automationVM.minDelaySeconds)-\(viewModel.automationVM.maxDelaySeconds) seconds")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Min:")
                        Slider(value: Binding(
                            get: { Double(viewModel.automationVM.minDelaySeconds) },
                            set: { viewModel.automationVM.minDelaySeconds = Int($0) }
                        ), in: 10...120, step: 5)
                        Text("\(viewModel.automationVM.minDelaySeconds)s")
                            .frame(width: 40)
                    }

                    HStack {
                        Text("Max:")
                        Slider(value: Binding(
                            get: { Double(viewModel.automationVM.maxDelaySeconds) },
                            set: { viewModel.automationVM.maxDelaySeconds = Int($0) }
                        ), in: 30...180, step: 5)
                        Text("\(viewModel.automationVM.maxDelaySeconds)s")
                            .frame(width: 40)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding()
        }
    }
}

#Preview {
    MainView()
}
