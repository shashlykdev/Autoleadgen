import Foundation

enum EngagementType: String, Codable, CaseIterable {
    case like = "Like"
    case comment = "Comment"
    case repost = "Repost"

    var icon: String {
        switch self {
        case .like: return "hand.thumbsup.fill"
        case .comment: return "bubble.left.fill"
        case .repost: return "arrow.2.squarepath"
        }
    }
}

enum ConnectionStatus: String, Codable {
    case notConnected = "Not Connected"
    case pending = "Pending"
    case connected = "Connected"
    case failed = "Failed"
}

struct PostEngager: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var headline: String?
    var linkedInURL: String
    var profileImageURL: String?
    var engagementType: EngagementType
    var commentText: String?
    var connectionDegree: String?
    var postId: UUID
    var scrapedAt: Date
    var matchesICP: Bool?
    var connectionStatus: ConnectionStatus

    init(
        id: UUID = UUID(),
        name: String,
        headline: String? = nil,
        linkedInURL: String,
        profileImageURL: String? = nil,
        engagementType: EngagementType,
        commentText: String? = nil,
        connectionDegree: String? = nil,
        postId: UUID,
        scrapedAt: Date = Date(),
        matchesICP: Bool? = nil,
        connectionStatus: ConnectionStatus = .notConnected
    ) {
        self.id = id
        self.name = name
        self.headline = headline
        self.linkedInURL = linkedInURL
        self.profileImageURL = profileImageURL
        self.engagementType = engagementType
        self.commentText = commentText
        self.connectionDegree = connectionDegree
        self.postId = postId
        self.scrapedAt = scrapedAt
        self.matchesICP = matchesICP
        self.connectionStatus = connectionStatus
    }

    func toLead(source: String) -> Lead {
        let nameParts = name.split(separator: " ")
        let firstName = nameParts.first.map(String.init) ?? name
        let lastName = nameParts.dropFirst().joined(separator: " ")

        return Lead(
            firstName: firstName,
            lastName: lastName,
            linkedInURL: linkedInURL,
            title: headline,
            status: .new,
            source: source,
            headline: headline,
            connectionDegree: connectionDegree
        )
    }
}
