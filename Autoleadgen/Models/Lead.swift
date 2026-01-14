import Foundation
import SwiftUI

enum LeadStatus: String, Codable, CaseIterable {
    case new = "New"
    case contacted = "Contacted"
    case responded = "Responded"
    case converted = "Converted"
    case notInterested = "Not Interested"

    var color: String {
        switch self {
        case .new: return "blue"
        case .contacted: return "orange"
        case .responded: return "purple"
        case .converted: return "green"
        case .notInterested: return "gray"
        }
    }
}

struct Lead: Identifiable, Codable, Equatable {
    let id: UUID
    var firstName: String
    var lastName: String
    var linkedInURL: String
    var email: String?
    var phone: String?
    var company: String?
    var title: String?
    var location: String?
    var notes: String?
    var tags: [String]
    var status: LeadStatus
    var source: String?
    var generatedMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var lastContactedAt: Date?

    // Messaging automation fields
    var messageStatus: MessageStatus
    var messageText: String
    var lastAttemptDate: Date?
    var errorMessage: String?
    var rowIndex: Int

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        linkedInURL: String,
        email: String? = nil,
        phone: String? = nil,
        company: String? = nil,
        title: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        status: LeadStatus = .new,
        source: String? = nil,
        generatedMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastContactedAt: Date? = nil,
        messageStatus: MessageStatus = .pending,
        messageText: String = "",
        lastAttemptDate: Date? = nil,
        errorMessage: String? = nil,
        rowIndex: Int = 0
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.linkedInURL = linkedInURL
        self.email = email
        self.phone = phone
        self.company = company
        self.title = title
        self.location = location
        self.notes = notes
        self.tags = tags
        self.status = status
        self.source = source
        self.generatedMessage = generatedMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastContactedAt = lastContactedAt
        self.messageStatus = messageStatus
        self.messageText = messageText
        self.lastAttemptDate = lastAttemptDate
        self.errorMessage = errorMessage
        self.rowIndex = rowIndex
    }

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    var displayName: String {
        if !firstName.isEmpty {
            if !lastName.isEmpty {
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

    var normalizedURL: String {
        linkedInURL.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var isProcessable: Bool {
        messageStatus == .pending || messageStatus == .failed
    }

    /// Get the message to send - uses generatedMessage if available, otherwise messageText
    var effectiveMessage: String {
        if let generated = generatedMessage, !generated.isEmpty {
            return generated
        }
        return messageText
    }

    /// Personalize message text by replacing placeholders
    func personalizedMessage() -> String {
        var message = effectiveMessage
        message = message.replacingOccurrences(of: "{firstName}", with: firstName)
        message = message.replacingOccurrences(of: "{lastName}", with: lastName)
        message = message.replacingOccurrences(of: "{fullName}", with: fullName)
        message = message.replacingOccurrences(of: "{company}", with: company ?? "")
        message = message.replacingOccurrences(of: "{title}", with: title ?? "")
        message = message.replacingOccurrences(of: "  ", with: " ")
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
