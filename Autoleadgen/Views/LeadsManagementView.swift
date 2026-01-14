import SwiftUI
import UniformTypeIdentifiers

struct LeadsManagementView: View {
    @ObservedObject var viewModel: LeadsViewModel
    @State private var showingAddLead = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingClearConfirmation = false
    @State private var editingLead: Lead?
    let onAddToContacts: ([Lead]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Statistics
            if let stats = viewModel.statistics {
                statisticsSection(stats)
            }

            // Filters
            filterSection

            // Leads Table
            leadsTable

            // Actions
            actionsSection
        }
        .sheet(isPresented: $showingAddLead) {
            LeadEditSheet(lead: nil, onSave: { lead in
                Task { await viewModel.addLead(lead) }
            })
        }
        .sheet(item: $editingLead) { lead in
            LeadEditSheet(lead: lead, onSave: { updatedLead in
                Task { await viewModel.updateLead(updatedLead) }
            })
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText],
            onCompletion: handleImport
        )
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: ""),
            contentType: .commaSeparatedText,
            defaultFilename: "leads_export.csv"
        ) { result in
            // Handle export result
        }
        .task {
            await viewModel.loadLeads()
        }
        .alert("Clear All Leads", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                Task { await viewModel.clearAllLeads() }
            }
        } message: {
            Text("Are you sure you want to delete all \(viewModel.leads.count) leads? This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Leads Management")
                .font(.headline)

            Spacer()

            Text("\(viewModel.filteredLeads.count) leads")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { showingAddLead = true }) {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Import CSV") { showingImporter = true }
                Button("Export CSV") {
                    let csv = viewModel.exportToCSV()
                    // Save to clipboard or file
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(csv, forType: .string)
                }
                Divider()
                Button("Clear All Leads", role: .destructive) {
                    showingClearConfirmation = true
                }
                .disabled(viewModel.leads.isEmpty)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Statistics

    private func statisticsSection(_ stats: LeadsStatistics) -> some View {
        HStack(spacing: 16) {
            statBadge("Total", value: stats.total, color: .primary)
            statBadge("New", value: stats.new, color: .blue)
            statBadge("Contacted", value: stats.contacted, color: .orange)
            statBadge("Responded", value: stats.responded, color: .purple)
            statBadge("Converted", value: stats.converted, color: .green)

            Spacer()

            if stats.total > 0 {
                Text("Conversion: \(String(format: "%.1f", stats.conversionRate))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func statBadge(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Filters

    private var filterSection: some View {
        HStack {
            TextField("Search...", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Picker("Status", selection: $viewModel.selectedStatus) {
                Text("All Statuses").tag(nil as LeadStatus?)
                ForEach(LeadStatus.allCases, id: \.self) { status in
                    Text(status.rawValue).tag(status as LeadStatus?)
                }
            }
            .frame(width: 140)

            if !viewModel.allTags.isEmpty {
                Picker("Tag", selection: $viewModel.selectedTag) {
                    Text("All Tags").tag(nil as String?)
                    ForEach(viewModel.allTags, id: \.self) { tag in
                        Text(tag).tag(tag as String?)
                    }
                }
                .frame(width: 120)
            }

            Spacer()

            if !viewModel.selectedLeads.isEmpty {
                Text("\(viewModel.selectedLeads.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Deselect All") {
                    viewModel.deselectAll()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Leads Table

    private var leadsTable: some View {
        List(viewModel.filteredLeads, selection: $viewModel.selectedLeads) { lead in
            LeadRowView(
                lead: lead,
                isSelected: viewModel.selectedLeads.contains(lead.id),
                onToggleSelect: { viewModel.toggleSelection(lead) },
                onEdit: { editingLead = lead },
                onDelete: { Task { await viewModel.deleteLead(lead) } }
            )
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack {
            if !viewModel.selectedLeads.isEmpty {
                Menu("Update Status") {
                    ForEach(LeadStatus.allCases, id: \.self) { status in
                        Button(status.rawValue) {
                            let selectedLeadsList = viewModel.leads.filter {
                                viewModel.selectedLeads.contains($0.id)
                            }
                            Task {
                                await viewModel.updateStatus(status, for: selectedLeadsList)
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Delete Selected") {
                    Task { await viewModel.deleteSelectedLeads() }
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()

                Button("Add to Automation") {
                    let selectedLeadsList = viewModel.leads.filter {
                        viewModel.selectedLeads.contains($0.id)
                    }
                    onAddToContacts(selectedLeadsList)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Import Handler

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }

                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let count = await viewModel.importFromCSV(content)
                    print("Imported \(count) leads")
                } catch {
                    print("Import error: \(error)")
                }
            }
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }
}

// MARK: - Lead Row View

struct LeadRowView: View {
    let lead: Lead
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(lead.fullName)
                    .font(.headline)

                HStack(spacing: 8) {
                    if let title = lead.title {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let company = lead.company {
                        Text("@ \(company)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Tags
            HStack(spacing: 4) {
                ForEach(lead.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            // Status badge
            Text(lead.status.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor(lead.status).opacity(0.2))
                .foregroundColor(statusColor(lead.status))
                .cornerRadius(4)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: LeadStatus) -> Color {
        switch status {
        case .new: return .blue
        case .contacted: return .orange
        case .responded: return .purple
        case .converted: return .green
        case .notInterested: return .gray
        }
    }
}

// MARK: - Lead Edit Sheet

struct LeadEditSheet: View {
    let lead: Lead?
    let onSave: (Lead) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var linkedInURL: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var company: String = ""
    @State private var title: String = ""
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var status: LeadStatus = .new
    @State private var tagsText: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(lead == nil ? "Add Lead" : "Edit Lead")
                .font(.headline)

            Form {
                Section("Basic Info") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("LinkedIn URL", text: $linkedInURL)
                }

                Section("Contact") {
                    TextField("Email", text: $email)
                    TextField("Phone", text: $phone)
                }

                Section("Professional") {
                    TextField("Company", text: $company)
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                }

                Section("Status & Tags") {
                    Picker("Status", selection: $status) {
                        ForEach(LeadStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    TextField("Tags (comma separated)", text: $tagsText)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    let tags = tagsText.split(separator: ",").map {
                        String($0).trimmingCharacters(in: .whitespaces)
                    }

                    let newLead = Lead(
                        id: lead?.id ?? UUID(),
                        firstName: firstName,
                        lastName: lastName,
                        linkedInURL: linkedInURL,
                        email: email.isEmpty ? nil : email,
                        phone: phone.isEmpty ? nil : phone,
                        company: company.isEmpty ? nil : company,
                        title: title.isEmpty ? nil : title,
                        location: location.isEmpty ? nil : location,
                        notes: notes.isEmpty ? nil : notes,
                        tags: tags,
                        status: status,
                        source: lead?.source,
                        createdAt: lead?.createdAt ?? Date(),
                        updatedAt: Date(),
                        lastContactedAt: lead?.lastContactedAt
                    )
                    onSave(newLead)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(firstName.isEmpty || linkedInURL.isEmpty)
            }
            .padding()
        }
        .padding()
        .frame(width: 500, height: 600)
        .onAppear {
            if let lead = lead {
                firstName = lead.firstName
                lastName = lead.lastName
                linkedInURL = lead.linkedInURL
                email = lead.email ?? ""
                phone = lead.phone ?? ""
                company = lead.company ?? ""
                title = lead.title ?? ""
                location = lead.location ?? ""
                notes = lead.notes ?? ""
                status = lead.status
                tagsText = lead.tags.joined(separator: ", ")
            }
        }
    }
}

// MARK: - CSV Document for Export

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}
