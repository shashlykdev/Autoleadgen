import Foundation
import WebKit

enum ScraperError: Error, LocalizedError {
    case invalidURL
    case failedToParseContent
    case timeout
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL provided"
        case .failedToParseContent: return "Failed to parse page content"
        case .timeout: return "Page load timed out"
        case .notLoggedIn: return "Not logged in to LinkedIn"
        }
    }
}

actor ContentScraperService {

    // MARK: - LinkedIn Post Scraping

    static let linkedInPostScript = """
    (function() {
        const data = {};

        // Post content - try multiple selectors
        const postContent = document.querySelector('.feed-shared-update-v2__description') ||
                           document.querySelector('.update-components-text') ||
                           document.querySelector('[data-test-id="main-feed-activity-card__commentary"]') ||
                           document.querySelector('.feed-shared-inline-show-more-text');
        data.content = postContent?.innerText?.trim() || null;

        // Author info
        const authorName = document.querySelector('.update-components-actor__name span') ||
                          document.querySelector('.feed-shared-actor__name span') ||
                          document.querySelector('.update-components-actor__title span');
        data.authorName = authorName?.innerText?.trim() || null;

        const authorHeadline = document.querySelector('.update-components-actor__description') ||
                               document.querySelector('.feed-shared-actor__description') ||
                               document.querySelector('.update-components-actor__subtitle');
        data.authorHeadline = authorHeadline?.innerText?.trim() || null;

        const authorLink = document.querySelector('.update-components-actor__container-link') ||
                          document.querySelector('.feed-shared-actor__container-link') ||
                          document.querySelector('a[href*="/in/"]');
        data.authorProfileURL = authorLink?.href || null;

        // Engagement counts
        const reactions = document.querySelector('.social-details-social-counts__reactions-count') ||
                         document.querySelector('[data-test-id="social-actions__reactions"]');
        if (reactions) {
            const text = reactions.innerText || reactions.textContent || '';
            data.likeCount = parseInt(text.replace(/[^0-9]/g, '')) || 0;
        } else {
            data.likeCount = 0;
        }

        const comments = document.querySelector('.social-details-social-counts__comments') ||
                        document.querySelector('[data-test-id="social-actions__comments"]');
        if (comments) {
            const text = comments.innerText || comments.textContent || '';
            data.commentCount = parseInt(text.replace(/[^0-9]/g, '')) || 0;
        } else {
            data.commentCount = 0;
        }

        const reposts = document.querySelector('.social-details-social-counts__item--reposts span');
        if (reposts) {
            data.repostCount = parseInt(reposts.textContent.replace(/[^0-9]/g, '')) || 0;
        } else {
            data.repostCount = 0;
        }

        return data;
    })();
    """

    // MARK: - Twitter/X Post Scraping

    static let twitterPostScript = """
    (function() {
        const data = {};

        // Post content (tweet text)
        const tweetText = document.querySelector('[data-testid="tweetText"]');
        data.content = tweetText?.innerText?.trim() || null;

        // Author info
        const displayName = document.querySelector('[data-testid="User-Name"] div span');
        data.authorName = displayName?.innerText?.trim() || null;

        // Engagement (approximate from visible UI)
        const stats = document.querySelectorAll('[data-testid="app-text-transition-container"]');
        if (stats.length >= 3) {
            data.commentCount = parseInt(stats[0]?.textContent?.replace(/[^0-9]/g, '')) || 0;
            data.repostCount = parseInt(stats[1]?.textContent?.replace(/[^0-9]/g, '')) || 0;
            data.likeCount = parseInt(stats[2]?.textContent?.replace(/[^0-9]/g, '')) || 0;
        }

        return data;
    })();
    """

    // MARK: - Generic Website Content Scraping

    static let websiteContentScript = """
    (function() {
        const data = {};

        // Try to get main article/post content
        const article = document.querySelector('article') ||
                       document.querySelector('[role="main"]') ||
                       document.querySelector('.post-content') ||
                       document.querySelector('.article-content') ||
                       document.querySelector('.entry-content') ||
                       document.querySelector('main');

        if (article) {
            data.content = article.innerText?.substring(0, 5000).trim() || null;
        } else {
            // Fallback to body text
            data.content = document.body?.innerText?.substring(0, 3000).trim() || null;
        }

        // Try to get title
        data.title = document.querySelector('h1')?.innerText?.trim() ||
                    document.title || null;

        // Try to get author
        const authorEl = document.querySelector('[rel="author"]') ||
                        document.querySelector('.author') ||
                        document.querySelector('[itemprop="author"]') ||
                        document.querySelector('.byline');
        data.authorName = authorEl?.innerText?.trim() || null;

        return data;
    })();
    """

    // MARK: - Scrape Methods

    @MainActor
    func scrapeLinkedInPost(webView: WKWebView, url: String) async throws -> ViralPost {
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let result = try await webView.evaluateJavaScript(Self.linkedInPostScript)

        guard let dict = result as? [String: Any] else {
            throw ScraperError.failedToParseContent
        }

        return ViralPost(
            sourceURL: url,
            platform: .linkedin,
            originalContent: dict["content"] as? String ?? "",
            authorName: dict["authorName"] as? String,
            authorHeadline: dict["authorHeadline"] as? String,
            authorProfileURL: dict["authorProfileURL"] as? String,
            likeCount: dict["likeCount"] as? Int,
            commentCount: dict["commentCount"] as? Int,
            repostCount: dict["repostCount"] as? Int
        )
    }

    @MainActor
    func scrapeTwitterPost(webView: WKWebView, url: String) async throws -> ViralPost {
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let result = try await webView.evaluateJavaScript(Self.twitterPostScript)

        guard let dict = result as? [String: Any] else {
            throw ScraperError.failedToParseContent
        }

        return ViralPost(
            sourceURL: url,
            platform: .twitter,
            originalContent: dict["content"] as? String ?? "",
            authorName: dict["authorName"] as? String,
            likeCount: dict["likeCount"] as? Int,
            commentCount: dict["commentCount"] as? Int,
            repostCount: dict["repostCount"] as? Int
        )
    }

    @MainActor
    func scrapeWebsite(webView: WKWebView, url: String) async throws -> ViralPost {
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let result = try await webView.evaluateJavaScript(Self.websiteContentScript)

        guard let dict = result as? [String: Any] else {
            throw ScraperError.failedToParseContent
        }

        return ViralPost(
            sourceURL: url,
            platform: .website,
            originalContent: dict["content"] as? String ?? "",
            authorName: dict["authorName"] as? String
        )
    }

    @MainActor
    func scrapeContent(url: String, webView: WKWebView) async throws -> ViralPost {
        guard let pageURL = URL(string: url) else {
            throw ScraperError.invalidURL
        }

        // Load the URL
        webView.load(URLRequest(url: pageURL))

        // Wait for page load
        var waitCount = 0
        while webView.isLoading && waitCount < 60 {
            try await Task.sleep(nanoseconds: 500_000_000)
            waitCount += 1
        }

        if waitCount >= 60 {
            throw ScraperError.timeout
        }

        // Additional wait for dynamic content
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Detect platform and use appropriate scraper
        let platform = PostPlatform.detect(from: url)

        switch platform {
        case .linkedin:
            return try await scrapeLinkedInPost(webView: webView, url: url)
        case .twitter:
            return try await scrapeTwitterPost(webView: webView, url: url)
        case .website, .other, .topic:
            return try await scrapeWebsite(webView: webView, url: url)
        }
    }
}
