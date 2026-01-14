import Foundation

/// Stores results from comparing different AI models
struct AIComparisonResult: Identifiable, Codable {
    let id: UUID
    let leadName: String
    let linkedInURL: String
    let profileData: ProfileDataSnapshot
    let selectedModelId: String
    let selectedModelMessage: String?
    let selectedModelError: String?
    let appleModelMessage: String?
    let appleModelError: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        leadName: String,
        linkedInURL: String,
        profileData: ProfileDataSnapshot,
        selectedModelId: String,
        selectedModelMessage: String? = nil,
        selectedModelError: String? = nil,
        appleModelMessage: String? = nil,
        appleModelError: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.leadName = leadName
        self.linkedInURL = linkedInURL
        self.profileData = profileData
        self.selectedModelId = selectedModelId
        self.selectedModelMessage = selectedModelMessage
        self.selectedModelError = selectedModelError
        self.appleModelMessage = appleModelMessage
        self.appleModelError = appleModelError
        self.timestamp = timestamp
    }
}

/// Snapshot of profile data for storage
struct ProfileDataSnapshot: Codable {
    let headline: String?
    let currentRole: String?
    let currentCompany: String?
    let location: String?
    let education: String?
    let about: String?
    let connectionDegree: String?
    let followerCount: String?

    init(from profile: ProfileData) {
        self.headline = profile.headline
        self.currentRole = profile.currentRole
        self.currentCompany = profile.currentCompany
        self.location = profile.location
        self.education = profile.education
        self.about = profile.about
        self.connectionDegree = profile.connectionDegree
        self.followerCount = profile.followerCount
    }

    init(
        headline: String? = nil,
        currentRole: String? = nil,
        currentCompany: String? = nil,
        location: String? = nil,
        education: String? = nil,
        about: String? = nil,
        connectionDegree: String? = nil,
        followerCount: String? = nil
    ) {
        self.headline = headline
        self.currentRole = currentRole
        self.currentCompany = currentCompany
        self.location = location
        self.education = education
        self.about = about
        self.connectionDegree = connectionDegree
        self.followerCount = followerCount
    }

    /// Returns true if any profile data was scraped
    var hasData: Bool {
        headline != nil || currentRole != nil || currentCompany != nil ||
        location != nil || education != nil || about != nil ||
        connectionDegree != nil || followerCount != nil
    }
}
