import SwiftUI
import Combine

/// Manages the automation queue of leads for LinkedIn messaging
@MainActor
class ContactListViewModel: ObservableObject {
    @Published var leads: [Lead] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentExcelPath: URL?

    private let excelService = ExcelService()
    private let statusService = StatusPersistenceService()

    var pendingLeads: [Lead] {
        leads.filter { $0.messageStatus == .pending }
    }

    var processableLeads: [Lead] {
        leads.filter { $0.isProcessable }
    }

    var sentCount: Int {
        leads.filter { $0.messageStatus == .sent }.count
    }

    var failedCount: Int {
        leads.filter { $0.messageStatus == .failed }.count
    }

    var progressPercentage: Double {
        guard !leads.isEmpty else { return 0 }
        let processed = leads.filter {
            $0.messageStatus == .sent || $0.messageStatus == .failed || $0.messageStatus == .skipped
        }.count
        return Double(processed) / Double(leads.count)
    }

    func loadLeads(from url: URL) async throws {
        isLoading = true
        errorMessage = nil
        currentExcelPath = url

        do {
            // Load leads from Excel
            var loadedLeads = try await excelService.loadLeads(from: url)

            // Merge with saved status
            let savedStatuses = try await statusService.loadStatus(for: url)
            for i in loadedLeads.indices {
                if let savedStatus = savedStatuses[loadedLeads[i].linkedInURL] {
                    if let status = MessageStatus(rawValue: savedStatus.status) {
                        loadedLeads[i].messageStatus = status
                    }
                    loadedLeads[i].errorMessage = savedStatus.errorMessage
                    loadedLeads[i].lastAttemptDate = savedStatus.lastUpdated
                }
            }

            leads = loadedLeads
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func addLeads(_ newLeads: [Lead]) {
        leads.append(contentsOf: newLeads)
    }

    func markAsSent(_ lead: Lead) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        leads[index].messageStatus = .sent
        leads[index].lastAttemptDate = Date()
        leads[index].errorMessage = nil
        leads[index].status = .contacted
        leads[index].lastContactedAt = Date()
        saveStatus(for: leads[index])
    }

    func markAsFailed(_ lead: Lead, error: String) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        leads[index].messageStatus = .failed
        leads[index].lastAttemptDate = Date()
        leads[index].errorMessage = error
        saveStatus(for: leads[index])
    }

    func markAsInProgress(_ lead: Lead) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        leads[index].messageStatus = .inProgress
        saveStatus(for: leads[index])
    }

    func markAsSkipped(_ lead: Lead, reason: String) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        leads[index].messageStatus = .skipped
        leads[index].errorMessage = reason
        saveStatus(for: leads[index])
    }

    func resetLead(_ lead: Lead) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        leads[index].messageStatus = .pending
        leads[index].errorMessage = nil
        saveStatus(for: leads[index])
    }

    func resetAllFailed() {
        for i in leads.indices where leads[i].messageStatus == .failed {
            leads[i].messageStatus = .pending
            leads[i].errorMessage = nil
        }
        saveAllStatuses()
    }

    func clearLeads() {
        leads.removeAll()
    }

    private func saveStatus(for lead: Lead) {
        guard let path = currentExcelPath else { return }
        Task {
            try? await statusService.updateLeadStatus(lead, excelPath: path)
        }
    }

    private func saveAllStatuses() {
        guard let path = currentExcelPath else { return }
        Task {
            try? await statusService.saveStatus(leads: leads, excelPath: path)
        }
    }
}
