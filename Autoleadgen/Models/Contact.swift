import Foundation

struct Contact: Identifiable, Codable, Equatable {
    let id: UUID
    var firstName: String?
    var lastName: String?
    var linkedInURL: String
    var messageText: String
    var status: MessageStatus
    var lastAttemptDate: Date?
    var errorMessage: String?
    var rowIndex: Int

    init(
        id: UUID = UUID(),
        firstName: String? = nil,
        lastName: String? = nil,
        linkedInURL: String,
        messageText: String,
        status: MessageStatus = .pending,
        lastAttemptDate: Date? = nil,
        errorMessage: String? = nil,
        rowIndex: Int
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.linkedInURL = linkedInURL
        self.messageText = messageText
        self.status = status
        self.lastAttemptDate = lastAttemptDate
        self.errorMessage = errorMessage
        self.rowIndex = rowIndex
    }

    var fullName: String {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? displayName : parts.joined(separator: " ")
    }

    var displayName: String {
        if let firstName = firstName, !firstName.isEmpty {
            if let lastName = lastName, !lastName.isEmpty {
                return "\(firstName) \(lastName)"
            }
            return firstName
        }
        if let url = URL(string: linkedInURL),
           let lastComponent = url.pathComponents.last,
           lastComponent != "/" {
            return lastComponent
        }
        return linkedInURL
    }

    var isProcessable: Bool {
        status == .pending || status == .failed
    }

    /// Personalize message text by replacing placeholders
    func personalizedMessage() -> String {
        var message = messageText
        message = message.replacingOccurrences(of: "{firstName}", with: firstName ?? "")
        message = message.replacingOccurrences(of: "{lastName}", with: lastName ?? "")
        message = message.replacingOccurrences(of: "{fullName}", with: fullName)
        // Clean up extra spaces
        message = message.replacingOccurrences(of: "  ", with: " ")
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
