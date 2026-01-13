import Foundation
import WebKit

actor GoogleScraperService {

    /// JavaScript to extract LinkedIn results from Google search page
    static let scrapeScript = """
    (function() {
        const results = [];

        // Find all search result links
        const links = document.querySelectorAll('a[href*="linkedin.com/in/"]');

        for (const link of links) {
            const href = link.href;

            // Skip if not a profile link
            if (!href.includes('linkedin.com/in/')) continue;

            // Extract clean LinkedIn URL
            let linkedInURL = href;
            if (href.includes('google.com/url')) {
                const urlParams = new URLSearchParams(href.split('?')[1]);
                linkedInURL = urlParams.get('url') || urlParams.get('q') || href;
            }

            // Find the title element (contains name)
            const titleEl = link.querySelector('h3') || link.closest('div')?.querySelector('h3');
            if (!titleEl) continue;

            const titleText = titleEl.textContent || '';

            // Parse name: "Kristof Terryn - Chief Executive Officer..."
            // or "LinkedIn · Kristof Terryn"
            let name = titleText;
            if (name.includes(' - ')) {
                name = name.split(' - ')[0];
            }
            if (name.includes(' · ')) {
                name = name.split(' · ').pop();
            }
            name = name.replace('LinkedIn', '').trim();

            // Split into first/last name
            const nameParts = name.split(' ').filter(p => p.length > 0);
            if (nameParts.length < 1) continue;

            const firstName = nameParts[0];
            const lastName = nameParts.length > 1 ? nameParts.slice(1).join(' ') : '';

            // Extract title/company from description
            const parentDiv = link.closest('div')?.parentElement;
            const descEl = parentDiv?.querySelector('[data-sncf]') ||
                          parentDiv?.querySelector('.VwiC3b') ||
                          parentDiv?.querySelector('span:not(h3 span)');
            const description = descEl?.textContent || '';

            results.push({
                firstName: firstName,
                lastName: lastName,
                linkedInURL: linkedInURL.split('?')[0], // Remove tracking params
                title: description.substring(0, 150),
                scrapedAt: new Date().toISOString()
            });
        }

        // Remove duplicates by URL
        const seen = new Set();
        return results.filter(r => {
            const normalized = r.linkedInURL.toLowerCase();
            if (seen.has(normalized)) return false;
            seen.add(normalized);
            return true;
        });
    })();
    """

    /// Check if "Next" button exists
    static let hasNextPageScript = """
    (function() {
        const nextLink = document.querySelector('a#pnnext') ||
                         document.querySelector('a[aria-label="Next page"]') ||
                         document.querySelector('a[aria-label="Next"]') ||
                         document.querySelector('td.d6cvqb a:last-child');
        return nextLink ? 'yes' : 'no';
    })();
    """

    /// Click "Next" to go to next page
    static let clickNextScript = """
    (function() {
        const nextLink = document.querySelector('a#pnnext') ||
                         document.querySelector('a[aria-label="Next page"]') ||
                         document.querySelector('a[aria-label="Next"]') ||
                         document.querySelector('td.d6cvqb a:last-child');
        if (nextLink) {
            nextLink.click();
            return 'clicked';
        }
        return 'not_found';
    })();
    """

    /// Scrape current Google search page
    @MainActor
    func scrapeCurrentPage(webView: WKWebView) async throws -> [ScrapedLead] {
        let result = try await webView.evaluateJavaScript(Self.scrapeScript)

        guard let jsonArray = result as? [[String: Any]] else {
            return []
        }

        return jsonArray.compactMap { dict -> ScrapedLead? in
            guard let firstName = dict["firstName"] as? String,
                  let linkedInURL = dict["linkedInURL"] as? String,
                  !linkedInURL.isEmpty else {
                return nil
            }

            return ScrapedLead(
                id: UUID(),
                firstName: firstName,
                lastName: dict["lastName"] as? String ?? "",
                linkedInURL: linkedInURL,
                title: dict["title"] as? String,
                company: nil,
                scrapedAt: Date()
            )
        }
    }

    /// Check if next page exists
    @MainActor
    func hasNextPage(webView: WKWebView) async -> Bool {
        do {
            let result = try await webView.evaluateJavaScript(Self.hasNextPageScript) as? String
            return result == "yes"
        } catch {
            return false
        }
    }

    /// Navigate to next page
    @MainActor
    func goToNextPage(webView: WKWebView) async -> Bool {
        do {
            let result = try await webView.evaluateJavaScript(Self.clickNextScript) as? String
            return result == "clicked"
        } catch {
            return false
        }
    }
}
