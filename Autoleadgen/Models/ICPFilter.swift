import Foundation

struct ICPFilter: Codable {
    var keywords: [String]
    var excludeKeywords: [String]
    var minConnectionDegree: Int?
    var requiredIndustries: [String]
    var excludedIndustries: [String]

    init(
        keywords: [String] = [],
        excludeKeywords: [String] = [],
        minConnectionDegree: Int? = nil,
        requiredIndustries: [String] = [],
        excludedIndustries: [String] = []
    ) {
        self.keywords = keywords
        self.excludeKeywords = excludeKeywords
        self.minConnectionDegree = minConnectionDegree
        self.requiredIndustries = requiredIndustries
        self.excludedIndustries = excludedIndustries
    }

    func matches(_ engager: PostEngager) -> Bool {
        let headline = engager.headline?.lowercased() ?? ""

        // Check exclude keywords first
        for excludeKeyword in excludeKeywords {
            if headline.contains(excludeKeyword.lowercased()) {
                return false
            }
        }

        // Check required keywords (if any specified, at least one must match)
        if !keywords.isEmpty {
            let hasMatch = keywords.contains { keyword in
                headline.contains(keyword.lowercased())
            }
            if !hasMatch {
                return false
            }
        }

        return true
    }
}
