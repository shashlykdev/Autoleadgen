import SwiftUI
import Combine

@MainActor
class LeadsViewModel: ObservableObject {
    @Published var leads: [Lead] = []
    @Published var filteredLeads: [Lead] = []
    @Published var selectedLeads: Set<UUID> = []
    @Published var searchQuery: String = ""
    @Published var selectedStatus: LeadStatus? = nil
    @Published var selectedTag: String? = nil
    @Published var isLoading: Bool = false
    @Published var statistics: LeadsStatistics?

    private let leadsService = LeadsManagementService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupSearchObserver()
    }

    private func setupSearchObserver() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.filterLeads()
            }
            .store(in: &cancellables)

        $selectedStatus
            .sink { [weak self] _ in
                self?.filterLeads()
            }
            .store(in: &cancellables)

        $selectedTag
            .sink { [weak self] _ in
                self?.filterLeads()
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    func loadLeads() async {
        isLoading = true
        leads = await leadsService.loadLeads()
        filterLeads()
        await updateStatistics()
        isLoading = false
    }

    // MARK: - CRUD

    func addLead(_ lead: Lead) async {
        let newLead = await leadsService.addLead(lead)
        leads.append(newLead)
        filterLeads()
        await updateStatistics()
    }

    func addLeads(_ newLeads: [Lead]) async -> Int {
        let added = await leadsService.addLeads(newLeads)
        leads.append(contentsOf: added)
        filterLeads()
        await updateStatistics()
        return added.count
    }

    func updateLead(_ lead: Lead) async {
        await leadsService.updateLead(lead)
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index] = lead
        }
        filterLeads()
        await updateStatistics()
    }

    func deleteLead(_ lead: Lead) async {
        await leadsService.deleteLead(lead)
        leads.removeAll { $0.id == lead.id }
        selectedLeads.remove(lead.id)
        filterLeads()
        await updateStatistics()
    }

    func deleteSelectedLeads() async {
        let leadsToDelete = leads.filter { selectedLeads.contains($0.id) }
        await leadsService.deleteLeads(leadsToDelete)
        leads.removeAll { selectedLeads.contains($0.id) }
        selectedLeads.removeAll()
        filterLeads()
        await updateStatistics()
    }

    // MARK: - Filtering

    private func filterLeads() {
        var result = leads

        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter {
                $0.firstName.lowercased().contains(query) ||
                $0.lastName.lowercased().contains(query) ||
                ($0.company?.lowercased().contains(query) ?? false) ||
                ($0.title?.lowercased().contains(query) ?? false) ||
                ($0.email?.lowercased().contains(query) ?? false)
            }
        }

        // Filter by status
        if let status = selectedStatus {
            result = result.filter { $0.status == status }
        }

        // Filter by tag
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        filteredLeads = result.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Selection

    func toggleSelection(_ lead: Lead) {
        if selectedLeads.contains(lead.id) {
            selectedLeads.remove(lead.id)
        } else {
            selectedLeads.insert(lead.id)
        }
    }

    func selectAll() {
        selectedLeads = Set(filteredLeads.map { $0.id })
    }

    func deselectAll() {
        selectedLeads.removeAll()
    }

    // MARK: - Status Update

    func updateStatus(_ status: LeadStatus, for leads: [Lead]) async {
        for lead in leads {
            var updatedLead = lead
            updatedLead = Lead(
                id: lead.id,
                firstName: lead.firstName,
                lastName: lead.lastName,
                linkedInURL: lead.linkedInURL,
                email: lead.email,
                phone: lead.phone,
                company: lead.company,
                title: lead.title,
                location: lead.location,
                notes: lead.notes,
                tags: lead.tags,
                status: status,
                source: lead.source,
                createdAt: lead.createdAt,
                updatedAt: Date(),
                lastContactedAt: status == .contacted ? Date() : lead.lastContactedAt
            )
            await updateLead(updatedLead)
        }
    }

    // MARK: - Tags

    var allTags: [String] {
        Array(Set(leads.flatMap { $0.tags })).sorted()
    }

    func addTag(_ tag: String, to lead: Lead) async {
        await leadsService.addTag(tag, to: lead)
        await loadLeads()
    }

    // MARK: - Import/Export

    func exportToCSV() async -> String {
        await leadsService.exportToCSV()
    }

    func importFromCSV(_ content: String) async -> Int {
        let imported = await leadsService.importFromCSV(content)
        leads.append(contentsOf: imported)
        filterLeads()
        await updateStatistics()
        return imported.count
    }

    // MARK: - Statistics

    func updateStatistics() async {
        statistics = await leadsService.getStatistics()
    }

    // MARK: - Convert to Contacts

    func convertToContacts(messageTemplate: String) -> [Contact] {
        let selectedLeadsList = leads.filter { selectedLeads.contains($0.id) }
        return selectedLeadsList.map { $0.toContact(messageTemplate: messageTemplate) }
    }

    func convertAllToContacts(messageTemplate: String) -> [Contact] {
        filteredLeads.map { $0.toContact(messageTemplate: messageTemplate) }
    }
}
