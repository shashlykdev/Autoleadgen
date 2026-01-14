import Foundation
import WebKit
import Combine
import SwiftUI

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

    // Profile processing state (Phase 2)
    @Published var isProcessingProfiles: Bool = false
    @Published var currentProfileIndex: Int = 0
    @Published var processedLeads: [Lead] = []

    // AI Settings (read from AppStorage)
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("selectedModelId") private var selectedModelId: String = ""
    @AppStorage("sampleMessage") private var sampleMessage: String = ""

    private let scraperService = GoogleScraperService()
    private let deduplicationService = DeduplicationService()
    private let leadsService = LeadsManagementService()
    private let profileScraperService = LinkedInProfileScraperService()
    private let aiService = AIMessageService()
    private var searchTask: Task<Void, Never>?

    // Callback for auto-adding to automation queue
    var onContactsReady: (([Lead]) -> Void)?

    // Hidden WebView for background scraping
    private lazy var hiddenWebView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }()

    private let maxPages = 50  // Safety limit

    init() {
        Task {
            await updateSeenCount()
        }
    }

    // MARK: - Computed Properties

    var canSearch: Bool {
        !role.isEmpty && !location.isEmpty && !isSearching && !isProcessingProfiles
    }

    var searchQuery: SearchQuery {
        SearchQuery(role: role, location: location)
    }

    var searchURL: String {
        searchQuery.googleSearchURL
    }

    var isWorking: Bool {
        isSearching || isProcessingProfiles
    }

    // MARK: - Search Control

    func startSearch() {
        guard canSearch else { return }

        isSearching = true
        currentPage = 0
        scrapedLeads = []
        newLeadsCount = 0
        duplicatesSkipped = 0
        savedToLeadsCount = 0
        processedLeads = []
        currentProfileIndex = 0
        statusMessage = "Starting search..."

        searchTask = Task {
            await performSearch()
        }
    }

    func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        isProcessingProfiles = false
        statusMessage = "Search stopped"
    }

    private func performSearch() async {
        guard let url = URL(string: searchURL) else {
            statusMessage = "Invalid search URL"
            isSearching = false
            return
        }

        let webView = hiddenWebView
        statusMessage = "Searching..."
        webView.load(URLRequest(url: url))

        // Wait for initial page load
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        var page = 0
        while page < maxPages && newLeadsCount < targetLeadsCount {
            if Task.isCancelled { break }

            currentPage = page + 1
            statusMessage = "Phase 1: Searching... (\(newLeadsCount)/\(targetLeadsCount) leads)"

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

                for lead in pageLeads {
                    // Stop if we've reached the target
                    if newLeadsCount >= targetLeadsCount { break }

                    let isDupe = await deduplicationService.isDuplicate(lead)
                    if !isDupe {
                        scrapedLeads.append(lead)
                        await deduplicationService.markAsSeen(lead)
                        newOnThisPage += 1
                        newLeadsCount += 1
                    } else {
                        duplicatesSkipped += 1
                    }
                }

                statusMessage = "Phase 1: Found \(newLeadsCount) leads (+\(newOnThisPage) new)"

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

        // Phase 2: Process profiles and generate messages
        if !scrapedLeads.isEmpty && !Task.isCancelled {
            await processProfilesAndGenerateMessages()
        } else {
            statusMessage = "Complete: \(newLeadsCount) leads found, \(duplicatesSkipped) duplicates skipped"
        }
    }

    // MARK: - Phase 2: Profile Processing & AI Message Generation

    private func processProfilesAndGenerateMessages() async {
        isProcessingProfiles = true
        currentProfileIndex = 0
        processedLeads = []

        let webView = hiddenWebView
        let searchSource = "\(role) - \(location)"
        let totalLeads = scrapedLeads.count

        for (index, scrapedLead) in scrapedLeads.enumerated() {
            if Task.isCancelled { break }

            currentProfileIndex = index + 1
            statusMessage = "Phase 2: Processing profile \(currentProfileIndex)/\(totalLeads) - \(scrapedLead.fullName)"

            var generatedMessage: String? = nil

            // Navigate to LinkedIn profile
            if let profileURL = URL(string: scrapedLead.linkedInURL) {
                webView.load(URLRequest(url: profileURL))

                // Wait for page load
                var waitCount = 0
                while webView.isLoading && waitCount < 30 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    waitCount += 1
                }

                // Extra wait for dynamic content
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // Scrape profile data
                do {
                    let profileData = try await profileScraperService.scrapeProfile(webView: webView)

                    // Generate AI message if enabled
                    if aiEnabled && !selectedModelId.isEmpty {
                        do {
                            generatedMessage = try await aiService.generateMessage(
                                modelId: selectedModelId,
                                profile: profileData,
                                firstName: scrapedLead.firstName,
                                sampleMessage: sampleMessage.isEmpty ? nil : sampleMessage
                            )
                            statusMessage = "Phase 2: Generated message for \(scrapedLead.fullName)"
                        } catch {
                            statusMessage = "Phase 2: AI error for \(scrapedLead.fullName): \(error.localizedDescription)"
                            // Continue without AI message
                        }
                    }
                } catch {
                    statusMessage = "Phase 2: Scrape error for \(scrapedLead.fullName)"
                }

                // Small delay between profiles to avoid rate limiting
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            // Create Lead with generated message
            let lead = scrapedLead.toLead(source: searchSource, generatedMessage: generatedMessage)
            processedLeads.append(lead)
        }

        // Save leads to database
        if !processedLeads.isEmpty {
            let saved = await leadsService.addLeads(processedLeads)
            savedToLeadsCount = saved.count
        }

        isProcessingProfiles = false

        // Auto-add to automation queue
        if !processedLeads.isEmpty {
            onContactsReady?(processedLeads)
        }

        statusMessage = "Complete: \(newLeadsCount) leads processed, \(savedToLeadsCount) saved, \(duplicatesSkipped) duplicates skipped"
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
        processedLeads = []
        newLeadsCount = 0
        duplicatesSkipped = 0
        savedToLeadsCount = 0
        currentProfileIndex = 0
        statusMessage = ""
    }

    /// Import existing leads to avoid duplicates
    func importExistingLeads(_ leads: [Lead]) {
        Task {
            await deduplicationService.importFromLeads(leads)
            await updateSeenCount()
        }
    }
}
