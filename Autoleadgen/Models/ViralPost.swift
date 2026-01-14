import Foundation

enum PostPlatform: String, Codable, CaseIterable {
    case linkedin = "LinkedIn"
    case twitter = "Twitter"
    case website = "Website"
    case topic = "Topic"
    case other = "Other"

    static func detect(from url: String) -> PostPlatform {
        let lowercased = url.lowercased()
        if lowercased.contains("linkedin.com") {
            return .linkedin
        } else if lowercased.contains("twitter.com") || lowercased.contains("x.com") {
            return .twitter
        } else if lowercased.hasPrefix("http") {
            return .website
        }
        return .other
    }
}

enum ContentGenerationType: String, Codable {
    case rewrite = "Rewrite"
    case original = "Original"
}

struct ViralPost: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceURL: String
    var platform: PostPlatform
    var originalContent: String
    var authorName: String?
    var authorHeadline: String?
    var authorProfileURL: String?
    var likeCount: Int?
    var commentCount: Int?
    var repostCount: Int?
    var scrapedAt: Date
    var generatedContent: String?
    var generationType: ContentGenerationType?
    var userVoiceStyle: String?
    var topic: String?

    init(
        id: UUID = UUID(),
        sourceURL: String = "",
        platform: PostPlatform = .other,
        originalContent: String = "",
        authorName: String? = nil,
        authorHeadline: String? = nil,
        authorProfileURL: String? = nil,
        likeCount: Int? = nil,
        commentCount: Int? = nil,
        repostCount: Int? = nil,
        scrapedAt: Date = Date(),
        generatedContent: String? = nil,
        generationType: ContentGenerationType? = nil,
        userVoiceStyle: String? = nil,
        topic: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.platform = platform
        self.originalContent = originalContent
        self.authorName = authorName
        self.authorHeadline = authorHeadline
        self.authorProfileURL = authorProfileURL
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.scrapedAt = scrapedAt
        self.generatedContent = generatedContent
        self.generationType = generationType
        self.userVoiceStyle = userVoiceStyle
        self.topic = topic
    }

    var isLinkedInPost: Bool {
        platform == .linkedin
    }

    var isFromTopic: Bool {
        platform == .topic
    }

    var engagementScore: Int {
        (likeCount ?? 0) + (commentCount ?? 0) * 3 + (repostCount ?? 0) * 5
    }

    var hasEngagementData: Bool {
        likeCount != nil || commentCount != nil || repostCount != nil
    }

    var displayTitle: String {
        if let topic = topic, !topic.isEmpty {
            return "Topic: \(topic)"
        } else if let author = authorName {
            return author
        } else if !sourceURL.isEmpty {
            return String(sourceURL.prefix(50))
        }
        return "Generated Post"
    }
}
