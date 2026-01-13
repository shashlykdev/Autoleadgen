import Foundation
import WebKit
import Combine

@MainActor
class LeadFinderViewModel: ObservableObject {
    // Search parameters
    @Published var role: String = ""
    @Published var location: String = ""

    // Search state
    @Published var isSearching: Bool = false
    @Published var currentPage: Int = 0
    @Published var targetLeadsCount: Int = 50
    @Published var scrapedLeads: [ScrapedLead] = []
    @Published var newLeadsCount: Int = 0
    @Published var duplicatesSkipped: Int = 0
    @Published var statusMessage: String = ""
    @Published var seenURLsCount: Int = 0
    @Published var savedToLeadsCount: Int = 0

    private let scraperService = GoogleScraperService()
    private let deduplicationService = DeduplicationService()
    private let leadsService = LeadsManagementService()
    private var searchTask: Task<Void, Never>?

    private let maxPages = 50  // Safety limit

    init() {
        Task {
            await updateSeenCount()
        }
    }

    // MARK: - Computed Properties

    var canSearch: Bool {
        !role.isEmpty && !location.isEmpty && !isSearching
    }

    var searchQuery: SearchQuery {
        SearchQuery(role: role, location: location)
    }

    var searchURL: String {
        searchQuery.googleSearchURL
    }

    // MARK: - Search Control

    func startSearch(webView: WKWebView) {
        guard canSearch else { return }

        isSearching = true
        currentPage = 0
        scrapedLeads = []
        newLeadsCount = 0
        duplicatesSkipped = 0
        savedToLeadsCount = 0
        statusMessage = "Starting search..."

        searchTask = Task {
            await performSearch(webView: webView)
        }
    }

    func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        statusMessage = "Search stopped"
    }

    private func performSearch(webView: WKWebView) async {
        guard let url = URL(string: searchURL) else {
            statusMessage = "Invalid search URL"
            isSearching = false
            return
        }

        statusMessage = "Searching..."
        webView.load(URLRequest(url: url))

        // Wait for initial page load
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        var page = 0
        while page < maxPages && newLeadsCount < targetLeadsCount {
            if Task.isCancelled { break }

            currentPage = page + 1
            statusMessage = "Searching... (\(newLeadsCount)/\(targetLeadsCount) leads)"

            // Wait for page to fully load
            var waitCount = 0
            while webView.isLoading && waitCount < 20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                waitCount += 1
            }

            // Extra wait for dynamic content
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Scrape current page
            do {
                let pageLeads = try await scraperService.scrapeCurrentPage(webView: webView)

                // Filter duplicates using DeduplicationService
                var newOnThisPage = 0
                var leadsToSave: [Lead] = []

                for lead in pageLeads {
                    // Stop if we've reached the target
                    if newLeadsCount >= targetLeadsCount { break }

                    let isDupe = await deduplicationService.isDuplicate(lead)
                    if !isDupe {
                        scrapedLeads.append(lead)
                        await deduplicationService.markAsSeen(lead)
                        newOnThisPage += 1
                        newLeadsCount += 1

                        // Convert to Lead for persistence
                        let searchSource = "\(role) - \(location)"
                        leadsToSave.append(lead.toLead(source: searchSource))
                    } else {
                        duplicatesSkipped += 1
                    }
                }

                // Auto-save new leads to database
                if !leadsToSave.isEmpty {
                    let saved = await leadsService.addLeads(leadsToSave)
                    savedToLeadsCount += saved.count
                }

                statusMessage = "Found \(newLeadsCount) leads (+\(newOnThisPage) new)"

            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }

            // Check if we've reached the target
            if newLeadsCount >= targetLeadsCount {
                break
            }

            // Check for next page and navigate
            let hasNext = await scraperService.hasNextPage(webView: webView)
            if !hasNext {
                statusMessage = "No more results available"
                break
            }

            let clicked = await scraperService.goToNextPage(webView: webView)
            if !clicked {
                statusMessage = "Could not load more results"
                break
            }

            // Wait for navigation
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            page += 1
        }

        // Save seen URLs
        await deduplicationService.saveSeenURLs()
        await updateSeenCount()

        isSearching = false
        statusMessage = "Complete: \(newLeadsCount) leads found, \(savedToLeadsCount) saved, \(duplicatesSkipped) duplicates skipped"
    }

    // MARK: - Convert to Contacts

    func convertToContacts() -> [Contact] {
        scrapedLeads.enumerated().map { index, lead in
            // Message will be AI-generated later during automation
            return Contact(
                firstName: lead.firstName,
                lastName: lead.lastName.isEmpty ? nil : lead.lastName,
                linkedInURL: lead.linkedInURL,
                messageText: "",  // AI will generate this from profile data
                status: .pending,
                rowIndex: index + 1
            )
        }
    }

    // MARK: - Deduplication Management

    private func updateSeenCount() async {
        seenURLsCount = await deduplicationService.seenCount
    }

    func clearHistory() {
        Task {
            await deduplicationService.clearHistory()
            await updateSeenCount()
            statusMessage = "History cleared"
        }
    }

    func clearResults() {
        scrapedLeads = []
        newLeadsCount = 0
        duplicatesSkipped = 0
        savedToLeadsCount = 0
        statusMessage = ""
    }

    /// Import existing contacts to avoid duplicates
    func importExistingContacts(_ contacts: [Contact]) {
        Task {
            await deduplicationService.importFromContacts(contacts)
            await updateSeenCount()
        }
    }

    /// Import existing leads to avoid duplicates
    func importExistingLeads(_ leads: [Lead]) {
        Task {
            await deduplicationService.importFromLeads(leads)
            await updateSeenCount()
        }
    }
}
