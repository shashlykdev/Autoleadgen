import Foundation
import WebKit

enum EngagementError: Error, LocalizedError {
    case couldNotOpenModal
    case timeout
    case notOnPostPage

    var errorDescription: String? {
        switch self {
        case .couldNotOpenModal: return "Could not open reactions modal"
        case .timeout: return "Timed out loading engagements"
        case .notOnPostPage: return "Not on a LinkedIn post page"
        }
    }
}

actor LinkedInEngagementService {

    // MARK: - Engagement Scraping Scripts

    static let scrapeLikersScript = """
    (function() {
        const likers = [];
        const items = document.querySelectorAll('.social-details-reactors-tab-body-list-item') ||
                     document.querySelectorAll('[data-test-id="social-details-reactors-list-item"]');

        for (const item of items) {
            const nameEl = item.querySelector('.artdeco-entity-lockup__title') ||
                          item.querySelector('.scaffold-finite-scroll__content a span');
            const headlineEl = item.querySelector('.artdeco-entity-lockup__subtitle') ||
                              item.querySelector('.t-black--light');
            const linkEl = item.querySelector('a[href*="/in/"]');
            const degreeEl = item.querySelector('.artdeco-entity-lockup__degree') ||
                            item.querySelector('.dist-value');

            if (nameEl && linkEl) {
                likers.push({
                    name: nameEl.innerText?.trim() || '',
                    headline: headlineEl?.innerText?.trim() || null,
                    linkedInURL: linkEl.href.split('?')[0],
                    connectionDegree: degreeEl?.innerText?.trim() || null
                });
            }
        }

        return likers;
    })();
    """

    static let scrapeCommentersScript = """
    (function() {
        const commenters = [];
        const items = document.querySelectorAll('.comments-comment-item') ||
                     document.querySelectorAll('[data-test-id="comments-comment-item"]');

        for (const item of items) {
            const nameEl = item.querySelector('.comments-post-meta__name-text') ||
                          item.querySelector('.comments-comment-item__post-meta a');
            const headlineEl = item.querySelector('.comments-post-meta__headline') ||
                              item.querySelector('.comments-comment-item__post-meta-description');
            const linkEl = item.querySelector('a[href*="/in/"]');
            const commentText = item.querySelector('.comments-comment-item__main-content') ||
                               item.querySelector('.update-components-text');
            const degreeEl = item.querySelector('.dist-value');

            if (nameEl && linkEl) {
                commenters.push({
                    name: nameEl.innerText?.trim() || '',
                    headline: headlineEl?.innerText?.trim() || null,
                    linkedInURL: linkEl.href.split('?')[0],
                    commentText: commentText?.innerText?.trim() || null,
                    connectionDegree: degreeEl?.innerText?.trim() || null
                });
            }
        }

        return commenters;
    })();
    """

    static let openReactionsModalScript = """
    (function() {
        const reactionsBtn = document.querySelector('.social-details-social-counts__reactions-count') ||
                            document.querySelector('[data-control-name="reactions_detail"]') ||
                            document.querySelector('button[aria-label*="reactions"]');
        if (reactionsBtn) {
            reactionsBtn.click();
            return 'clicked';
        }
        return 'not_found';
    })();
    """

    static let scrollModalScript = """
    (function() {
        const modal = document.querySelector('.artdeco-modal__content') ||
                     document.querySelector('.social-details-reactors-modal') ||
                     document.querySelector('[role="dialog"] .scaffold-finite-scroll__content');
        if (modal) {
            modal.scrollTop = modal.scrollHeight;
            return 'scrolled';
        }
        return 'not_found';
    })();
    """

    static let closeModalScript = """
    (function() {
        const closeBtn = document.querySelector('.artdeco-modal__dismiss') ||
                        document.querySelector('[data-test-modal-close-btn]') ||
                        document.querySelector('[aria-label="Dismiss"]');
        if (closeBtn) {
            closeBtn.click();
            return 'closed';
        }
        return 'not_found';
    })();
    """

    static let expandCommentsScript = """
    (function() {
        // Click "Load more comments" button if present
        const loadMore = document.querySelector('.comments-comments-list__load-more-comments-button') ||
                        document.querySelector('[data-test-id="load-more-comments-button"]');
        if (loadMore) {
            loadMore.click();
            return 'clicked';
        }
        return 'not_found';
    })();
    """

    // MARK: - Scrape Methods

    @MainActor
    func scrapeLikers(postId: UUID, webView: WKWebView, maxCount: Int = 100) async throws -> [PostEngager] {
        // Open reactions modal
        let openResult = try await webView.evaluateJavaScript(Self.openReactionsModalScript) as? String
        guard openResult == "clicked" else {
            throw EngagementError.couldNotOpenModal
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)

        var allLikers: [[String: Any]] = []
        var previousCount = 0
        var scrollAttempts = 0
        let maxScrollAttempts = 20

        // Scroll to load more
        while allLikers.count < maxCount && scrollAttempts < maxScrollAttempts {
            let result = try await webView.evaluateJavaScript(Self.scrapeLikersScript)
            if let likers = result as? [[String: Any]] {
                allLikers = likers

                if allLikers.count == previousCount {
                    scrollAttempts += 1
                } else {
                    scrollAttempts = 0
                }
                previousCount = allLikers.count
            }

            _ = try? await webView.evaluateJavaScript(Self.scrollModalScript)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Close modal
        _ = try? await webView.evaluateJavaScript(Self.closeModalScript)

        return allLikers.prefix(maxCount).compactMap { dict -> PostEngager? in
            guard let name = dict["name"] as? String,
                  let linkedInURL = dict["linkedInURL"] as? String,
                  !name.isEmpty else {
                return nil
            }

            return PostEngager(
                name: name,
                headline: dict["headline"] as? String,
                linkedInURL: linkedInURL,
                engagementType: .like,
                connectionDegree: dict["connectionDegree"] as? String,
                postId: postId
            )
        }
    }

    @MainActor
    func scrapeCommenters(postId: UUID, webView: WKWebView, maxCount: Int = 100) async throws -> [PostEngager] {
        // Try to expand comments first
        for _ in 0..<5 {
            let expandResult = try? await webView.evaluateJavaScript(Self.expandCommentsScript) as? String
            if expandResult == "clicked" {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                break
            }
        }

        var allCommenters: [[String: Any]] = []
        var previousCount = 0
        var scrollAttempts = 0
        let maxScrollAttempts = 10

        while allCommenters.count < maxCount && scrollAttempts < maxScrollAttempts {
            let result = try await webView.evaluateJavaScript(Self.scrapeCommentersScript)
            if let commenters = result as? [[String: Any]] {
                allCommenters = commenters

                if allCommenters.count == previousCount {
                    scrollAttempts += 1
                } else {
                    scrollAttempts = 0
                }
                previousCount = allCommenters.count
            }

            // Scroll page to load more comments
            try await webView.evaluateJavaScript("window.scrollBy(0, 500);")
            try await Task.sleep(nanoseconds: 1_500_000_000)
        }

        return allCommenters.prefix(maxCount).compactMap { dict -> PostEngager? in
            guard let name = dict["name"] as? String,
                  let linkedInURL = dict["linkedInURL"] as? String,
                  !name.isEmpty else {
                return nil
            }

            return PostEngager(
                name: name,
                headline: dict["headline"] as? String,
                linkedInURL: linkedInURL,
                engagementType: .comment,
                commentText: dict["commentText"] as? String,
                connectionDegree: dict["connectionDegree"] as? String,
                postId: postId
            )
        }
    }
}
