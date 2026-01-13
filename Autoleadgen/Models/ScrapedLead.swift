import Foundation

/// Represents a lead scraped from Google search results
struct ScrapedLead: Identifiable, Codable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var linkedInURL: String
    var title: String?
    var company: String?
    var scrapedAt: Date

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        linkedInURL: String,
        title: String? = nil,
        company: String? = nil,
        scrapedAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.linkedInURL = linkedInURL
        self.title = title
        self.company = company
        self.scrapedAt = scrapedAt
    }

    var fullName: String {
        if lastName.isEmpty {
            return firstName
        }
        return "\(firstName) \(lastName)"
    }

    /// For deduplication - normalize LinkedIn URL
    var normalizedURL: String {
        linkedInURL.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Convert to Contact for messaging automation
    func toContact(withMessage message: String, rowIndex: Int) -> Contact {
        Contact(
            firstName: firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            linkedInURL: linkedInURL,
            messageText: message,
            status: .pending,
            rowIndex: rowIndex
        )
    }

    /// Personalize a message template with this lead's data
    func personalizeMessage(_ template: String) -> String {
        template
            .replacingOccurrences(of: "{firstName}", with: firstName)
            .replacingOccurrences(of: "{lastName}", with: lastName)
            .replacingOccurrences(of: "{fullName}", with: fullName)
            .replacingOccurrences(of: "{title}", with: title ?? "")
            .replacingOccurrences(of: "{company}", with: company ?? "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convert to Lead for persistence in Leads database
    func toLead(source: String = "Google Search") -> Lead {
        Lead(
            firstName: firstName,
            lastName: lastName,
            linkedInURL: linkedInURL,
            company: company,
            title: title,
            status: .new,
            source: source
        )
    }
}
