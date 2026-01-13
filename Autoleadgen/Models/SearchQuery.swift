import Foundation

/// Represents search parameters for lead finding
struct SearchQuery {
    var role: String
    var location: String

    init(role: String, location: String) {
        self.role = role
        self.location = location
    }

    /// Constructs the Google search URL for LinkedIn profiles
    var googleSearchURL: String {
        let query = "\(role) \(location) site:linkedin.com/in"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://www.google.com/search?q=\(query)"
    }

    /// Returns URL for a specific page (0-indexed)
    func paginatedURL(page: Int) -> String {
        let start = page * 10  // Google uses start=0, 10, 20...
        return "\(googleSearchURL)&start=\(start)"
    }

    /// Returns the search query string for display
    var displayQuery: String {
        "\(role) \(location) site:linkedin.com/in"
    }

    /// Validates that required fields are filled
    var isValid: Bool {
        !role.trimmingCharacters(in: .whitespaces).isEmpty &&
        !location.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
