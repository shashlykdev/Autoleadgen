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

    // Apollo enrichment state (Phase 3)
    @Published var isEnrichingEmails: Bool = false
    @Published var currentEnrichmentIndex: Int = 0
    @Published var enrichedCount: Int = 0
    @Published var enrichmentErrors: Int = 0

    // Apollo settings (passed from view)
    var apolloEnabled: Bool = false
    var apolloApiKey: String = ""

    // AI Settings (read from AppStorage)
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("globalSelectedModelId") private var selectedModelId: String = ""
    @AppStorage("sampleMessage") private var sampleMessage: String = ""

    private let scraperService = GoogleScraperService()
    private let deduplicationService = DeduplicationService()
    private let leadsService = LeadsManagementService()
    private let profileScraperService = LinkedInProfileScraperService()
    private let aiService = AIMessageService()
    private let apolloService = ApolloEnrichmentService.shared
    private var searchTask: Task<Void, Never>?

    // Debug mode - show webview in window
    @Published var debugShowWebView: Bool = true
    private var debugWindow: NSWindow?

    // Callback for auto-adding to automation queue
    var onContactsReady: (([Lead]) -> Void)?

    // Callback for AI comparison results (sent to TestViewModel)
    var onComparisonResult: ((AIComparisonResult) -> Void)?

    // WebView for scraping (can be shown for debugging)
    private lazy var scrapingWebView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        return webView
    }()

    private func showDebugWindow() {
        guard debugShowWebView else { return }

        if debugWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Scraping Debug View"
            window.contentView = scrapingWebView
            window.isReleasedWhenClosed = false
            debugWindow = window
        }

        debugWindow?.makeKeyAndOrderFront(nil)
    }

    private func hideDebugWindow() {
        debugWindow?.orderOut(nil)
    }

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
        isSearching || isProcessingProfiles || isEnrichingEmails
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
        enrichedCount = 0
        enrichmentErrors = 0
        currentEnrichmentIndex = 0
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
        isEnrichingEmails = false
        statusMessage = "Search stopped"
        hideDebugWindow()
    }

    private func performSearch() async {
        guard let url = URL(string: searchURL) else {
            statusMessage = "Invalid search URL"
            isSearching = false
            return
        }

        let webView = scrapingWebView

        // Show debug window if enabled
        if debugShowWebView {
            showDebugWindow()
        }

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

        let webView = scrapingWebView
        let searchSource = "\(role) - \(location)"
        let totalLeads = scrapedLeads.count

        for (index, scrapedLead) in scrapedLeads.enumerated() {
            if Task.isCancelled { break }

            currentProfileIndex = index + 1
            statusMessage = "Phase 2: Processing profile \(currentProfileIndex)/\(totalLeads) - \(scrapedLead.fullName)"

            var generatedMessage: String? = nil
            var selectedModelMessage: String? = nil
            var selectedModelError: String? = nil
            var appleModelMessage: String? = nil
            var appleModelError: String? = nil
            var profileData: ProfileData? = nil

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
                    profileData = try await profileScraperService.scrapeProfile(webView: webView)

                    // Generate AI message if enabled
                    if aiEnabled && !selectedModelId.isEmpty, let profile = profileData {
                        // Generate with selected model
                        do {
                            selectedModelMessage = try await aiService.generateMessage(
                                modelId: selectedModelId,
                                profile: profile,
                                firstName: scrapedLead.firstName,
                                sampleMessage: sampleMessage.isEmpty ? nil : sampleMessage
                            )
                            generatedMessage = selectedModelMessage
                            statusMessage = "Phase 2: Generated message for \(scrapedLead.fullName)"
                        } catch {
                            selectedModelError = error.localizedDescription
                            statusMessage = "Phase 2: AI error for \(scrapedLead.fullName): \(error.localizedDescription)"
                        }

                        // Also generate with Apple Intelligence for comparison (if available and not already selected)
                        if AIMessageService.isAppleIntelligenceAvailable && !selectedModelId.contains("apple") {
                            do {
                                appleModelMessage = try await aiService.generateMessage(
                                    modelId: "apple-intelligence",
                                    profile: profile,
                                    firstName: scrapedLead.firstName,
                                    sampleMessage: sampleMessage.isEmpty ? nil : sampleMessage
                                )
                            } catch {
                                appleModelError = error.localizedDescription
                            }
                        } else if selectedModelId.contains("apple") {
                            // If Apple is the selected model, use its result for Apple column too
                            appleModelMessage = selectedModelMessage
                            appleModelError = selectedModelError
                        } else {
                            appleModelError = "Apple Intelligence not available"
                        }

                        // Send comparison result to TestViewModel
                        if let profile = profileData {
                            let result = AIComparisonResult(
                                leadName: scrapedLead.fullName,
                                linkedInURL: scrapedLead.linkedInURL,
                                profileData: ProfileDataSnapshot(from: profile),
                                selectedModelId: selectedModelId,
                                selectedModelMessage: selectedModelMessage,
                                selectedModelError: selectedModelError,
                                appleModelMessage: appleModelMessage,
                                appleModelError: appleModelError
                            )
                            onComparisonResult?(result)
                        }
                    }
                } catch {
                    statusMessage = "Phase 2: Scrape error for \(scrapedLead.fullName)"
                }

                // Small delay between profiles to avoid rate limiting
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            // Create Lead with generated message and profile data
            let lead = scrapedLead.toLead(source: searchSource, generatedMessage: generatedMessage, profileData: profileData)
            processedLeads.append(lead)
        }

        isProcessingProfiles = false

        // Phase 3: Apollo email enrichment (if enabled)
        print("🔷 [Apollo Check] apolloEnabled=\(apolloEnabled), apiKeyEmpty=\(apolloApiKey.isEmpty), leadsCount=\(processedLeads.count), cancelled=\(Task.isCancelled)")
        if apolloEnabled && !apolloApiKey.isEmpty && !processedLeads.isEmpty && !Task.isCancelled {
            print("🔷 [Apollo] Starting enrichment for \(processedLeads.count) leads")
            await enrichLeadsWithApollo()
        } else {
            print("🔷 [Apollo] Skipping enrichment - conditions not met")
        }

        // Save leads to database
        if !processedLeads.isEmpty {
            let saved = await leadsService.addLeads(processedLeads)
            savedToLeadsCount = saved.count
        }

        // Auto-add to automation queue
        if !processedLeads.isEmpty {
            onContactsReady?(processedLeads)
        }

        // Build completion message
        var completionParts = ["\(newLeadsCount) leads processed", "\(savedToLeadsCount) saved"]
        if duplicatesSkipped > 0 {
            completionParts.append("\(duplicatesSkipped) duplicates skipped")
        }
        if apolloEnabled && enrichedCount > 0 {
            completionParts.append("\(enrichedCount) emails found")
        }
        statusMessage = "Complete: \(completionParts.joined(separator: ", "))"

        // Hide debug window when complete
        hideDebugWindow()
    }

    // MARK: - Phase 3: Apollo Email Enrichment

    private func enrichLeadsWithApollo() async {
        isEnrichingEmails = true
        currentEnrichmentIndex = 0
        enrichedCount = 0
        enrichmentErrors = 0

        let totalLeads = processedLeads.count
        print("🔷 [Apollo Enrichment] Starting for \(totalLeads) leads with API key length: \(apolloApiKey.count)")

        for (index, lead) in processedLeads.enumerated() {
            if Task.isCancelled { break }

            currentEnrichmentIndex = index + 1
            statusMessage = "Phase 3: Enriching email \(currentEnrichmentIndex)/\(totalLeads) - \(lead.fullName)"

            do {
                let result = try await apolloService.enrichByLinkedIn(
                    linkedInURL: lead.linkedInURL,
                    firstName: lead.firstName,
                    lastName: lead.lastName,
                    apiKey: apolloApiKey
                )

                if result.wasFound {
                    // Update the lead with enriched data
                    var updatedLead = lead
                    if let email = result.email {
                        updatedLead.email = email
                        enrichedCount += 1
                    }
                    if let phone = result.phone {
                        updatedLead.phone = phone
                    }
                    // Optionally update other fields if we got better data
                    if updatedLead.company == nil || updatedLead.company?.isEmpty == true {
                        updatedLead.company = result.company
                    }
                    if updatedLead.location == nil || updatedLead.location?.isEmpty == true {
                        updatedLead.location = result.location
                    }

                    processedLeads[index] = updatedLead
                    statusMessage = "Phase 3: Found email for \(lead.fullName)"
                } else {
                    statusMessage = "Phase 3: No email found for \(lead.fullName)"
                }

                // Small delay between API calls to respect rate limits
                try? await Task.sleep(nanoseconds: 500_000_000)

            } catch {
                enrichmentErrors += 1
                statusMessage = "Phase 3: Error enriching \(lead.fullName): \(error.localizedDescription)"

                // If we hit rate limit or credits exhausted, stop enrichment
                if let apolloError = error as? ApolloError {
                    switch apolloError {
                    case .rateLimited, .insufficientCredits:
                        statusMessage = "Phase 3: Stopped - \(apolloError.localizedDescription)"
                        break
                    default:
                        break
                    }
                }

                // Continue with next lead
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        isEnrichingEmails = false
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
        enrichedCount = 0
        enrichmentErrors = 0
        currentEnrichmentIndex = 0
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
