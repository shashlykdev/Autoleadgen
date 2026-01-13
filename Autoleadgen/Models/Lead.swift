import Foundation

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
    var createdAt: Date
    var updatedAt: Date
    var lastContactedAt: Date?

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
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastContactedAt: Date? = nil
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastContactedAt = lastContactedAt
    }

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    var normalizedURL: String {
        linkedInURL.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Convert to Contact for messaging automation
    func toContact(messageTemplate: String) -> Contact {
        let personalizedMessage = messageTemplate
            .replacingOccurrences(of: "{firstName}", with: firstName)
            .replacingOccurrences(of: "{lastName}", with: lastName)
            .replacingOccurrences(of: "{fullName}", with: fullName)
            .replacingOccurrences(of: "{company}", with: company ?? "")
            .replacingOccurrences(of: "{title}", with: title ?? "")

        return Contact(
            firstName: firstName,
            lastName: lastName,
            linkedInURL: linkedInURL,
            messageText: personalizedMessage,
            status: .pending,
            rowIndex: 0
        )
    }
}
