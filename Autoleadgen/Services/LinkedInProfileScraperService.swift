import Foundation
import WebKit

struct ProfileData: Codable {
    var headline: String?
    var location: String?
    var about: String?
    var currentCompany: String?
    var currentRole: String?
    var education: String?
    var connectionDegree: String?
    var followerCount: String?

    init(
        headline: String? = nil,
        location: String? = nil,
        about: String? = nil,
        currentCompany: String? = nil,
        currentRole: String? = nil,
        education: String? = nil,
        connectionDegree: String? = nil,
        followerCount: String? = nil
    ) {
        self.headline = headline
        self.location = location
        self.about = about
        self.currentCompany = currentCompany
        self.currentRole = currentRole
        self.education = education
        self.connectionDegree = connectionDegree
        self.followerCount = followerCount
    }
}

actor LinkedInProfileScraperService {

    static let scrapeProfileScript = """
    (function() {
        const data = {};

        // Headline (under name)
        const headlineEl = document.querySelector('.text-body-medium.break-words');
        data.headline = headlineEl?.textContent?.trim() || null;

        // Location
        const locationEl = document.querySelector('.text-body-small.inline.t-black--light.break-words');
        data.location = locationEl?.textContent?.trim() || null;

        // About section (first 200 chars)
        const aboutSection = document.querySelector('#about');
        if (aboutSection) {
            const aboutText = aboutSection.closest('section')?.querySelector('.display-flex.full-width')?.textContent;
            data.about = aboutText?.trim()?.substring(0, 200) || null;
        }

        // Current experience
        const experienceSection = document.querySelector('#experience');
        if (experienceSection) {
            const firstExp = experienceSection.closest('section')?.querySelector('.display-flex.flex-column.full-width');
            if (firstExp) {
                const roleEl = firstExp.querySelector('.display-flex.align-items-center.mr1.t-bold span');
                const companyEl = firstExp.querySelector('.t-14.t-normal span');
                data.currentRole = roleEl?.textContent?.trim() || null;
                data.currentCompany = companyEl?.textContent?.trim()?.split(' · ')[0] || null;
            }
        }

        // Education
        const educationSection = document.querySelector('#education');
        if (educationSection) {
            const firstEdu = educationSection.closest('section')?.querySelector('.display-flex.flex-column.full-width');
            if (firstEdu) {
                const schoolEl = firstEdu.querySelector('.display-flex.align-items-center.mr1.hoverable-link-text.t-bold span');
                const degreeEl = firstEdu.querySelector('.t-14.t-normal span');
                const school = schoolEl?.textContent?.trim() || '';
                const degree = degreeEl?.textContent?.trim() || '';
                data.education = [school, degree].filter(s => s).join(' - ') || null;
            }
        }

        // Connection degree
        const connectionEl = document.querySelector('.dist-value');
        data.connectionDegree = connectionEl?.textContent?.trim() || null;

        // Follower count
        const allSpans = document.querySelectorAll('span.t-bold');
        for (const span of allSpans) {
            if (span.nextElementSibling?.textContent?.includes('follower')) {
                data.followerCount = span.textContent?.trim();
                break;
            }
        }

        return data;
    })();
    """

    @MainActor
    func scrapeProfile(webView: WKWebView) async throws -> ProfileData {
        // Wait for profile to fully load
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let result = try await webView.evaluateJavaScript(Self.scrapeProfileScript)

        guard let dict = result as? [String: Any] else {
            return ProfileData()
        }

        return ProfileData(
            headline: dict["headline"] as? String,
            location: dict["location"] as? String,
            about: dict["about"] as? String,
            currentCompany: dict["currentCompany"] as? String,
            currentRole: dict["currentRole"] as? String,
            education: dict["education"] as? String,
            connectionDegree: dict["connectionDegree"] as? String,
            followerCount: dict["followerCount"] as? String
        )
    }
}
