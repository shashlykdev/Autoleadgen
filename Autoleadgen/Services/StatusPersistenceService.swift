import Foundation

actor StatusPersistenceService {
    private let statusFileName = "autoleadgen_status.json"

    struct ContactStatusData: Codable {
        var statuses: [String: StatusEntry]

        init(statuses: [String: StatusEntry] = [:]) {
            self.statuses = statuses
        }
    }

    struct StatusEntry: Codable {
        var status: String
        var lastUpdated: Date
        var errorMessage: String?

        init(status: String, lastUpdated: Date = Date(), errorMessage: String? = nil) {
            self.status = status
            self.lastUpdated = lastUpdated
            self.errorMessage = errorMessage
        }
    }

    func saveStatus(contacts: [Contact], excelPath: URL) async throws {
        let statusPath = getStatusFilePath(for: excelPath)

        var statusData = ContactStatusData()

        // Load existing if present
        if FileManager.default.fileExists(atPath: statusPath.path) {
            let data = try Data(contentsOf: statusPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            statusData = try decoder.decode(ContactStatusData.self, from: data)
        }

        // Update with current contacts
        for contact in contacts {
            statusData.statuses[contact.linkedInURL] = StatusEntry(
                status: contact.status.rawValue,
                lastUpdated: Date(),
                errorMessage: contact.errorMessage
            )
        }

        // Save
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(statusData)
        try data.write(to: statusPath)
    }

    func loadStatus(for excelPath: URL) async throws -> [String: StatusEntry] {
        let statusPath = getStatusFilePath(for: excelPath)

        guard FileManager.default.fileExists(atPath: statusPath.path) else {
            return [:]
        }

        let data = try Data(contentsOf: statusPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let statusData = try decoder.decode(ContactStatusData.self, from: data)
        return statusData.statuses
    }

    func updateContactStatus(_ contact: Contact, excelPath: URL) async throws {
        try await saveStatus(contacts: [contact], excelPath: excelPath)
    }

    private func getStatusFilePath(for excelPath: URL) -> URL {
        let directory = excelPath.deletingLastPathComponent()
        let baseName = excelPath.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(baseName)_status.json")
    }
}
