import Foundation
import WebKit
import Combine
import SwiftUI

enum ViralPostsPhase: String {
    case idle = "Ready"
    case extractingContent = "Extracting Content"
    case generatingContent = "Generating Content"
    case scrapingEngagement = "Scraping Engagement"
    case connectingLeads = "Connecting with Leads"
}

enum ContentSourceTab: Int {
    case urls = 0
    case topics = 1
}

@MainActor
class ViralPostsViewModel: ObservableObject {

    // MARK: - Input State
    @Published var urlInput: String = ""
    @Published var topicsInput: String = ""
    @Published var selectedSourceTab: ContentSourceTab = .urls
    @Published var userVoiceStyle: String = ""

    // MARK: - Processing State
    @Published var currentPhase: ViralPostsPhase = .idle
    @Published var isProcessing: Bool = false
    @Published var statusMessage: String = ""
    @Published var progressCurrent: Int = 0
    @Published var progressTotal: Int = 0

    // MARK: - Data State
    @Published var posts: [ViralPost] = []
    @Published var selectedPost: ViralPost?
    @Published var engagers: [PostEngager] = []
    @Published var filteredEngagers: [PostEngager] = []
    @Published var selectedEngagers: Set<UUID> = []

    // MARK: - ICP Filter
    @Published var icpFilter: ICPFilter = ICPFilter()
    @Published var icpKeywordsText: String = ""
    @Published var icpExcludeKeywordsText: String = ""

    // MARK: - AI Settings (uses global model from MainViewModel)
    @AppStorage("globalSelectedModelId") private var selectedModelId: String = ""
    @AppStorage("viralUserVoice") private var storedUserVoice: String = ""

    // MARK: - Services
    private let contentScraperService = ContentScraperService()
    private let engagementService = LinkedInEngagementService()
    private let connectionService = LinkedInConnectionService()
    private let aiService = ViralContentAIService()

    // MARK: - WebView for scraping
    private lazy var scrapingWebView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
    }()

    // Debug window
    @Published var debugShowWebView: Bool = true
    private var debugWindow: NSWindow?

    private var processingTask: Task<Void, Never>?

    // Callbacks
    var onLeadsReady: (([Lead]) -> Void)?

    init() {
        userVoiceStyle = storedUserVoice
    }

    // MARK: - Computed Properties

    var canExtractURLs: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    var canGenerateFromTopics: Bool {
        !topicsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing && !selectedModelId.isEmpty
    }

    var canRewrite: Bool {
        selectedPost != nil && !selectedPost!.originalContent.isEmpty && !isProcessing && !selectedModelId.isEmpty
    }

    var canScrapeEngagement: Bool {
        selectedPost?.isLinkedInPost == true && !isProcessing
    }

    var hasEngagers: Bool {
        !engagers.isEmpty
    }

    // MARK: - Phase 1A: Extract Content from URLs

    func extractContent() {
        guard canExtractURLs else { return }

        let urls = parseURLs(from: urlInput)
        guard !urls.isEmpty else {
            statusMessage = "No valid URLs found"
            return
        }

        isProcessing = true
        currentPhase = .extractingContent
        progressCurrent = 0
        progressTotal = urls.count

        processingTask = Task {
            if debugShowWebView { showDebugWindow() }

            for (index, url) in urls.enumerated() {
                if Task.isCancelled { break }

                progressCurrent = index + 1
                statusMessage = "Extracting \(index + 1)/\(urls.count): \(url.prefix(50))..."

                do {
                    let post = try await contentScraperService.scrapeContent(url: url, webView: scrapingWebView)
                    posts.append(post)
                    statusMessage = "Extracted: \(post.displayTitle)"
                } catch {
                    statusMessage = "Error extracting \(url): \(error.localizedDescription)"
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            hideDebugWindow()
            isProcessing = false
            currentPhase = .idle

            if posts.isEmpty {
                statusMessage = "No content could be extracted"
            } else {
                statusMessage = "Extracted \(posts.count) posts"
                selectedPost = posts.first
            }
        }
    }

    // MARK: - Phase 1B: Generate Content from Topics

    func generateFromTopics() {
        guard canGenerateFromTopics else { return }

        let topics = parseTopics(from: topicsInput)
        guard !topics.isEmpty else {
            statusMessage = "No topics found"
            return
        }

        isProcessing = true
        currentPhase = .generatingContent
        progressCurrent = 0
        progressTotal = topics.count

        processingTask = Task {
            for (index, topic) in topics.enumerated() {
                if Task.isCancelled { break }

                progressCurrent = index + 1
                statusMessage = "Generating \(index + 1)/\(topics.count): \(topic.prefix(30))..."

                do {
                    let content = try await aiService.generateFromTopic(
                        topic: topic,
                        userVoiceStyle: userVoiceStyle.isEmpty ? nil : userVoiceStyle,
                        modelId: selectedModelId
                    )

                    let newPost = ViralPost(
                        platform: .topic,
                        originalContent: "",
                        generatedContent: content,
                        generationType: .original,
                        userVoiceStyle: userVoiceStyle.isEmpty ? nil : userVoiceStyle,
                        topic: topic
                    )
                    posts.insert(newPost, at: 0)
                    statusMessage = "Generated post for: \(topic)"
                } catch {
                    statusMessage = "Error generating for '\(topic)': \(error.localizedDescription)"
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            isProcessing = false
            currentPhase = .idle

            if !posts.isEmpty {
                selectedPost = posts.first
                statusMessage = "Generated \(progressCurrent) posts from topics"
            }
        }
    }

    // MARK: - Phase 2: AI Content Generation (Rewrite/Regenerate)

    func rewriteSelected() async {
        guard let post = selectedPost, !post.originalContent.isEmpty else { return }

        isProcessing = true
        currentPhase = .generatingContent
        statusMessage = "Rewriting content..."

        do {
            let generated = try await aiService.rewritePost(
                originalContent: post.originalContent,
                userVoiceStyle: userVoiceStyle.isEmpty ? nil : userVoiceStyle,
                modelId: selectedModelId
            )

            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index].generatedContent = generated
                posts[index].generationType = .rewrite
                selectedPost = posts[index]
            }

            statusMessage = "Rewrite generated successfully"
        } catch {
            statusMessage = "Generation error: \(error.localizedDescription)"
        }

        isProcessing = false
        currentPhase = .idle
    }

    func regenerateSelected() async {
        guard let post = selectedPost else { return }

        isProcessing = true
        currentPhase = .generatingContent
        statusMessage = "Regenerating content..."

        do {
            let generated: String
            if post.isFromTopic, let topic = post.topic {
                generated = try await aiService.generateFromTopic(
                    topic: topic,
                    userVoiceStyle: userVoiceStyle.isEmpty ? nil : userVoiceStyle,
                    modelId: selectedModelId
                )
            } else if !post.originalContent.isEmpty {
                generated = try await aiService.rewritePost(
                    originalContent: post.originalContent,
                    userVoiceStyle: userVoiceStyle.isEmpty ? nil : userVoiceStyle,
                    modelId: selectedModelId
                )
            } else {
                statusMessage = "No content to regenerate"
                isProcessing = false
                currentPhase = .idle
                return
            }

            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index].generatedContent = generated
                selectedPost = posts[index]
            }

            statusMessage = "Content regenerated successfully"
        } catch {
            statusMessage = "Regeneration error: \(error.localizedDescription)"
        }

        isProcessing = false
        currentPhase = .idle
    }

    func generateReply() async {
        guard let post = selectedPost else { return }

        let contentToReplyTo = post.generatedContent ?? post.originalContent
        guard !contentToReplyTo.isEmpty else {
            statusMessage = "No content to reply to"
            return
        }

        isProcessing = true
        statusMessage = "Generating reply..."

        do {
            let reply = try await aiService.generateReply(
                postContent: contentToReplyTo,
                userVoiceStyle: userVoiceStyle.isEmpty ? nil : userVoiceStyle,
                modelId: selectedModelId
            )

            // Copy to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(reply, forType: .string)
            statusMessage = "Reply copied to clipboard"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    // MARK: - Phase 3: Engagement Scraping

    func scrapeEngagement() {
        guard let post = selectedPost, post.isLinkedInPost else {
            statusMessage = "Select a LinkedIn post first"
            return
        }

        isProcessing = true
        currentPhase = .scrapingEngagement
        engagers = []
        statusMessage = "Scraping engagement..."

        processingTask = Task {
            if debugShowWebView { showDebugWindow() }

            // Navigate to post
            if let url = URL(string: post.sourceURL) {
                scrapingWebView.load(URLRequest(url: url))
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }

            // Scrape likers
            statusMessage = "Scraping likers..."
            do {
                let likers = try await engagementService.scrapeLikers(
                    postId: post.id,
                    webView: scrapingWebView,
                    maxCount: 100
                )
                engagers.append(contentsOf: likers)
                statusMessage = "Found \(likers.count) likers"
            } catch {
                statusMessage = "Error scraping likers: \(error.localizedDescription)"
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Scrape commenters
            statusMessage = "Scraping commenters..."
            do {
                let commenters = try await engagementService.scrapeCommenters(
                    postId: post.id,
                    webView: scrapingWebView,
                    maxCount: 50
                )
                engagers.append(contentsOf: commenters)
                statusMessage = "Found \(commenters.count) commenters"
            } catch {
                statusMessage = "Error scraping commenters: \(error.localizedDescription)"
            }

            hideDebugWindow()
            applyICPFilter()

            isProcessing = false
            currentPhase = .idle
            statusMessage = "Found \(engagers.count) engagers, \(filteredEngagers.count) match ICP"
        }
    }

    // MARK: - Phase 4: Lead Connection

    func connectWithSelected(note: String?) {
        let selectedList = engagers.filter { selectedEngagers.contains($0.id) }
        guard !selectedList.isEmpty else {
            statusMessage = "No engagers selected"
            return
        }

        isProcessing = true
        currentPhase = .connectingLeads
        progressCurrent = 0
        progressTotal = selectedList.count

        processingTask = Task {
            if debugShowWebView { showDebugWindow() }

            var successCount = 0
            var failCount = 0

            for (index, engager) in selectedList.enumerated() {
                if Task.isCancelled { break }

                progressCurrent = index + 1
                statusMessage = "Connecting \(index + 1)/\(selectedList.count): \(engager.name)"

                do {
                    let result = try await connectionService.sendConnectionRequest(
                        profileURL: engager.linkedInURL,
                        note: note,
                        webView: scrapingWebView
                    )

                    if let idx = engagers.firstIndex(where: { $0.id == engager.id }) {
                        switch result {
                        case .sent:
                            engagers[idx].connectionStatus = .pending
                            successCount += 1
                        case .alreadyConnected:
                            engagers[idx].connectionStatus = .connected
                        case .pending:
                            engagers[idx].connectionStatus = .pending
                        }
                    }
                } catch {
                    if let idx = engagers.firstIndex(where: { $0.id == engager.id }) {
                        engagers[idx].connectionStatus = .failed
                    }
                    failCount += 1
                }

                // Random delay between connections (30-90 seconds)
                let delay = Int.random(in: 30...90)
                for remaining in stride(from: delay, through: 1, by: -1) {
                    if Task.isCancelled { break }
                    statusMessage = "Waiting \(remaining)s before next..."
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            hideDebugWindow()
            selectedEngagers.removeAll()
            applyICPFilter()

            isProcessing = false
            currentPhase = .idle
            statusMessage = "Connected: \(successCount), Failed: \(failCount)"
        }
    }

    func addSelectedToLeads() {
        let selectedList = engagers.filter { selectedEngagers.contains($0.id) }
        guard !selectedList.isEmpty else {
            statusMessage = "No engagers selected"
            return
        }

        let source = selectedPost?.sourceURL.isEmpty == false ? selectedPost!.sourceURL : "Viral Post Engagement"
        let leads = selectedList.map { $0.toLead(source: source) }

        onLeadsReady?(leads)
        statusMessage = "Added \(leads.count) leads"
    }

    // MARK: - ICP Filtering

    func updateICPFilter() {
        icpFilter.keywords = icpKeywordsText.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        icpFilter.excludeKeywords = icpExcludeKeywordsText.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        applyICPFilter()
    }

    private func applyICPFilter() {
        if icpFilter.keywords.isEmpty && icpFilter.excludeKeywords.isEmpty {
            filteredEngagers = engagers
            for i in engagers.indices {
                engagers[i].matchesICP = nil
            }
        } else {
            for i in engagers.indices {
                engagers[i].matchesICP = icpFilter.matches(engagers[i])
            }
            filteredEngagers = engagers.filter { $0.matchesICP == true }
        }
    }

    // MARK: - Selection

    func toggleEngagerSelection(_ engager: PostEngager) {
        if selectedEngagers.contains(engager.id) {
            selectedEngagers.remove(engager.id)
        } else {
            selectedEngagers.insert(engager.id)
        }
    }

    func selectAllFiltered() {
        selectedEngagers = Set(filteredEngagers.map { $0.id })
    }

    func deselectAll() {
        selectedEngagers.removeAll()
    }

    // MARK: - Utility

    private func parseURLs(from input: String) -> [String] {
        return input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    private func parseTopics(from input: String) -> [String] {
        return input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func saveUserVoice() {
        storedUserVoice = userVoiceStyle
        statusMessage = "Writing style saved"
    }

    func copyToClipboard() {
        guard let content = selectedPost?.generatedContent ?? selectedPost?.originalContent else {
            statusMessage = "No content to copy"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        statusMessage = "Content copied to clipboard"
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        currentPhase = .idle
        statusMessage = "Stopped"
        hideDebugWindow()
    }

    func clearAll() {
        posts = []
        selectedPost = nil
        engagers = []
        filteredEngagers = []
        selectedEngagers = []
        urlInput = ""
        topicsInput = ""
        statusMessage = ""
    }

    func deletePost(_ post: ViralPost) {
        posts.removeAll { $0.id == post.id }
        if selectedPost?.id == post.id {
            selectedPost = posts.first
        }
    }

    // MARK: - Debug Window

    private func showDebugWindow() {
        guard debugShowWebView else { return }

        if debugWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Viral Posts - Scraping"
            window.contentView = scrapingWebView
            window.isReleasedWhenClosed = false
            debugWindow = window
        }

        debugWindow?.makeKeyAndOrderFront(nil)
    }

    private func hideDebugWindow() {
        debugWindow?.orderOut(nil)
    }
}
