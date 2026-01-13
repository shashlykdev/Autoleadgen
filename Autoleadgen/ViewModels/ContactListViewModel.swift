import SwiftUI
import Combine

@MainActor
class ContactListViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentExcelPath: URL?

    private let excelService = ExcelService()
    private let statusService = StatusPersistenceService()

    var pendingContacts: [Contact] {
        contacts.filter { $0.status == .pending }
    }

    var processableContacts: [Contact] {
        contacts.filter { $0.isProcessable }
    }

    var sentCount: Int {
        contacts.filter { $0.status == .sent }.count
    }

    var failedCount: Int {
        contacts.filter { $0.status == .failed }.count
    }

    var progressPercentage: Double {
        guard !contacts.isEmpty else { return 0 }
        let processed = contacts.filter { $0.status == .sent || $0.status == .failed || $0.status == .skipped }.count
        return Double(processed) / Double(contacts.count)
    }

    func loadContacts(from url: URL) async throws {
        isLoading = true
        errorMessage = nil
        currentExcelPath = url

        do {
            // Load contacts from Excel
            var loadedContacts = try await excelService.loadContacts(from: url)

            // Merge with saved status
            let savedStatuses = try await statusService.loadStatus(for: url)
            for i in loadedContacts.indices {
                if let savedStatus = savedStatuses[loadedContacts[i].linkedInURL] {
                    if let status = MessageStatus(rawValue: savedStatus.status) {
                        loadedContacts[i].status = status
                    }
                    loadedContacts[i].errorMessage = savedStatus.errorMessage
                    loadedContacts[i].lastAttemptDate = savedStatus.lastUpdated
                }
            }

            contacts = loadedContacts
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func markAsSent(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].status = .sent
        contacts[index].lastAttemptDate = Date()
        contacts[index].errorMessage = nil
        saveStatus(for: contacts[index])
    }

    func markAsFailed(_ contact: Contact, error: String) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].status = .failed
        contacts[index].lastAttemptDate = Date()
        contacts[index].errorMessage = error
        saveStatus(for: contacts[index])
    }

    func markAsInProgress(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].status = .inProgress
        saveStatus(for: contacts[index])
    }

    func markAsSkipped(_ contact: Contact, reason: String) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].status = .skipped
        contacts[index].errorMessage = reason
        saveStatus(for: contacts[index])
    }

    func resetContact(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].status = .pending
        contacts[index].errorMessage = nil
        saveStatus(for: contacts[index])
    }

    func resetAllFailed() {
        for i in contacts.indices where contacts[i].status == .failed {
            contacts[i].status = .pending
            contacts[i].errorMessage = nil
        }
        saveAllStatuses()
    }

    private func saveStatus(for contact: Contact) {
        guard let path = currentExcelPath else { return }
        Task {
            try? await statusService.updateContactStatus(contact, excelPath: path)
        }
    }

    private func saveAllStatuses() {
        guard let path = currentExcelPath else { return }
        Task {
            try? await statusService.saveStatus(contacts: contacts, excelPath: path)
        }
    }
}
