import Foundation

/// Service for tracking and preventing duplicate LinkedIn profile contacts
actor DeduplicationService {
    private var seenURLs: Set<String> = []
    private let storageKey = "seen_linkedin_urls"

    init() {
        // Load synchronously using nonisolated helper
        seenURLs = Self.loadStoredURLs(forKey: storageKey)
    }

    // MARK: - Persistence

    /// Load previously seen URLs from UserDefaults (nonisolated for init)
    private nonisolated static func loadStoredURLs(forKey key: String) -> Set<String> {
        if let data = UserDefaults.standard.data(forKey: key),
           let urls = try? JSONDecoder().decode(Set<String>.self, from: data) {
            return urls
        }
        return []
    }

    /// Normalize a LinkedIn URL for deduplication
    private func normalizeURL(_ url: String) -> String {
        url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Save seen URLs to UserDefaults
    func saveSeenURLs() {
        if let data = try? JSONEncoder().encode(seenURLs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Duplicate Checking

    /// Check if a lead's URL has already been seen
    func isDuplicate(_ lead: ScrapedLead) -> Bool {
        seenURLs.contains(normalizeURL(lead.linkedInURL))
    }

    /// Check if a normalized URL has already been seen
    func isDuplicate(normalizedURL: String) -> Bool {
        seenURLs.contains(normalizedURL)
    }

    // MARK: - Marking as Seen

    /// Mark a single lead as seen
    func markAsSeen(_ lead: ScrapedLead) {
        seenURLs.insert(normalizeURL(lead.linkedInURL))
    }

    /// Mark multiple leads as seen and persist
    func markAsSeen(_ leads: [ScrapedLead]) {
        for lead in leads {
            seenURLs.insert(normalizeURL(lead.linkedInURL))
        }
        saveSeenURLs()
    }

    /// Mark a normalized URL as seen
    func markAsSeen(normalizedURL: String) {
        seenURLs.insert(normalizedURL)
    }

    // MARK: - Filtering

    /// Filter out duplicates from a list of leads
    func filterDuplicates(_ leads: [ScrapedLead]) -> [ScrapedLead] {
        leads.filter { !isDuplicate($0) }
    }

    /// Filter leads and return both new leads and duplicate count
    func filterWithStats(_ leads: [ScrapedLead]) -> (newLeads: [ScrapedLead], duplicateCount: Int) {
        var newLeads: [ScrapedLead] = []
        var duplicateCount = 0

        for lead in leads {
            if isDuplicate(lead) {
                duplicateCount += 1
            } else {
                newLeads.append(lead)
            }
        }

        return (newLeads, duplicateCount)
    }

    // MARK: - Management

    /// Clear all seen URL history
    func clearHistory() {
        seenURLs.removeAll()
        saveSeenURLs()
    }

    /// Get the count of seen URLs
    var seenCount: Int {
        seenURLs.count
    }

    /// Check if a URL exists in history (for external use)
    func contains(_ normalizedURL: String) -> Bool {
        seenURLs.contains(normalizedURL)
    }

    /// Add a URL directly (useful for importing existing contacts)
    func addURL(_ normalizedURL: String) {
        seenURLs.insert(normalizedURL)
    }

    /// Bulk import URLs from existing leads
    func importFromLeads(_ leads: [Lead]) {
        for lead in leads {
            seenURLs.insert(normalizeURL(lead.linkedInURL))
        }
        saveSeenURLs()
    }
}
