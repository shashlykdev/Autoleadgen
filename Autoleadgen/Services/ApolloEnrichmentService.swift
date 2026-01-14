import Foundation

/// Service for enriching leads with email/phone data using Apollo.io API
actor ApolloEnrichmentService {

    static let shared = ApolloEnrichmentService()

    private let baseURL = "https://api.apollo.io/api/v1"

    private init() {}

    // MARK: - Response Models

    struct PersonMatchResponse: Codable {
        let person: PersonData?
        let status: String?
    }

    struct PersonData: Codable {
        let id: String?
        let firstName: String?
        let lastName: String?
        let name: String?
        let email: String?
        let emailStatus: String?
        let title: String?
        let headline: String?
        let linkedinUrl: String?
        let organizationId: String?
        let organizationName: String?
        let city: String?
        let state: String?
        let country: String?
        let phoneNumbers: [PhoneNumber]?
        let personalEmails: [String]?

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case lastName = "last_name"
            case name
            case email
            case emailStatus = "email_status"
            case title
            case headline
            case linkedinUrl = "linkedin_url"
            case organizationId = "organization_id"
            case organizationName = "organization_name"
            case city
            case state
            case country
            case phoneNumbers = "phone_numbers"
            case personalEmails = "personal_emails"
        }
    }

    struct PhoneNumber: Codable {
        let rawNumber: String?
        let sanitizedNumber: String?
        let type: String?
        let position: Int?
        let status: String?

        enum CodingKeys: String, CodingKey {
            case rawNumber = "raw_number"
            case sanitizedNumber = "sanitized_number"
            case type
            case position
            case status
        }
    }

    // MARK: - Enrichment Result

    struct EnrichmentResult {
        let email: String?
        let phone: String?
        let title: String?
        let company: String?
        let location: String?
        let emailStatus: String?
        let wasFound: Bool
    }

    // MARK: - Credits Info

    struct CreditsInfo {
        let used: Int
        let total: Int
        let remaining: Int
    }

    /// Fetch current credits usage from Apollo
    func fetchCredits(apiKey: String) async throws -> CreditsInfo {
        guard let url = URL(string: "https://api.apollo.io/api/v1/auth/health") else {
            throw ApolloError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApolloError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw ApolloError.unauthorized
            }
            throw ApolloError.serverError(httpResponse.statusCode)
        }

        // Parse the response to get credits info
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApolloError.invalidResponse
        }

        // Apollo health endpoint returns current_credits_used and plan info
        let creditsUsed = json["current_credits_used"] as? Int ?? 0
        let creditsLimit = json["credits_limit"] as? Int ?? 0

        // If credits_limit is 0, try to get from plan
        var totalCredits = creditsLimit
        if totalCredits == 0, let plan = json["plan"] as? [String: Any] {
            totalCredits = plan["credits"] as? Int ?? 0
        }

        return CreditsInfo(
            used: creditsUsed,
            total: totalCredits,
            remaining: max(0, totalCredits - creditsUsed)
        )
    }

    // MARK: - API Methods

    /// Enrich a lead using their LinkedIn URL
    /// - Parameters:
    ///   - linkedInURL: The person's LinkedIn profile URL
    ///   - firstName: Optional first name for better matching
    ///   - lastName: Optional last name for better matching
    ///   - apiKey: Apollo API key
    /// - Returns: EnrichmentResult with email and phone if found
    func enrichByLinkedIn(
        linkedInURL: String,
        firstName: String? = nil,
        lastName: String? = nil,
        apiKey: String
    ) async throws -> EnrichmentResult {
        guard let url = URL(string: "\(baseURL)/people/match") else {
            throw ApolloError.invalidURL
        }

        // Build request body
        var body: [String: Any] = [
            "linkedin_url": linkedInURL,
            "reveal_personal_emails": true,
            "reveal_phone_number": true
        ]

        if let firstName = firstName, !firstName.isEmpty {
            body["first_name"] = firstName
        }
        if let lastName = lastName, !lastName.isEmpty {
            body["last_name"] = lastName
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApolloError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(PersonMatchResponse.self, from: data)

            guard let person = result.person else {
                return EnrichmentResult(
                    email: nil,
                    phone: nil,
                    title: nil,
                    company: nil,
                    location: nil,
                    emailStatus: nil,
                    wasFound: false
                )
            }

            // Get the best email (business email first, then personal)
            var email = person.email
            if email == nil || email?.isEmpty == true {
                email = person.personalEmails?.first
            }

            // Get the best phone number
            let phone = person.phoneNumbers?.first?.sanitizedNumber ?? person.phoneNumbers?.first?.rawNumber

            // Build location string
            var locationParts: [String] = []
            if let city = person.city { locationParts.append(city) }
            if let state = person.state { locationParts.append(state) }
            if let country = person.country { locationParts.append(country) }
            let location = locationParts.isEmpty ? nil : locationParts.joined(separator: ", ")

            return EnrichmentResult(
                email: email,
                phone: phone,
                title: person.title,
                company: person.organizationName,
                location: location,
                emailStatus: person.emailStatus,
                wasFound: true
            )

        case 401:
            throw ApolloError.unauthorized
        case 402:
            throw ApolloError.insufficientCredits
        case 422:
            throw ApolloError.invalidRequest
        case 429:
            throw ApolloError.rateLimited
        default:
            // Try to parse error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw ApolloError.serverMessage(message)
            }
            throw ApolloError.serverError(httpResponse.statusCode)
        }
    }

    /// Bulk enrich multiple leads (up to 10 at a time)
    /// - Parameters:
    ///   - leads: Array of tuples containing (linkedInURL, firstName, lastName)
    ///   - apiKey: Apollo API key
    /// - Returns: Dictionary mapping LinkedIn URLs to EnrichmentResults
    func bulkEnrich(
        leads: [(linkedInURL: String, firstName: String?, lastName: String?)],
        apiKey: String
    ) async throws -> [String: EnrichmentResult] {
        guard !leads.isEmpty else { return [:] }
        guard leads.count <= 10 else {
            throw ApolloError.tooManyRecords
        }

        guard let url = URL(string: "\(baseURL)/people/bulk_match") else {
            throw ApolloError.invalidURL
        }

        // Build details array
        var details: [[String: Any]] = []
        for lead in leads {
            var detail: [String: Any] = ["linkedin_url": lead.linkedInURL]
            if let firstName = lead.firstName, !firstName.isEmpty {
                detail["first_name"] = firstName
            }
            if let lastName = lead.lastName, !lastName.isEmpty {
                detail["last_name"] = lastName
            }
            details.append(detail)
        }

        let body: [String: Any] = [
            "details": details,
            "reveal_personal_emails": true,
            "reveal_phone_number": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApolloError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            // Parse bulk response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let matches = json["matches"] as? [[String: Any]] else {
                throw ApolloError.invalidResponse
            }

            var results: [String: EnrichmentResult] = [:]

            for match in matches {
                guard let linkedInURL = match["linkedin_url"] as? String else { continue }

                let email = match["email"] as? String
                let personalEmails = match["personal_emails"] as? [String]
                let phoneNumbers = match["phone_numbers"] as? [[String: Any]]
                let title = match["title"] as? String
                let company = match["organization_name"] as? String
                let city = match["city"] as? String
                let state = match["state"] as? String
                let country = match["country"] as? String
                let emailStatus = match["email_status"] as? String

                let finalEmail = email ?? personalEmails?.first
                let phone = phoneNumbers?.first?["sanitized_number"] as? String ?? phoneNumbers?.first?["raw_number"] as? String

                var locationParts: [String] = []
                if let city = city { locationParts.append(city) }
                if let state = state { locationParts.append(state) }
                if let country = country { locationParts.append(country) }
                let location = locationParts.isEmpty ? nil : locationParts.joined(separator: ", ")

                results[linkedInURL] = EnrichmentResult(
                    email: finalEmail,
                    phone: phone,
                    title: title,
                    company: company,
                    location: location,
                    emailStatus: emailStatus,
                    wasFound: finalEmail != nil || phone != nil
                )
            }

            return results

        case 401:
            throw ApolloError.unauthorized
        case 402:
            throw ApolloError.insufficientCredits
        case 422:
            throw ApolloError.invalidRequest
        case 429:
            throw ApolloError.rateLimited
        default:
            throw ApolloError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum ApolloError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case insufficientCredits
    case invalidRequest
    case rateLimited
    case tooManyRecords
    case serverError(Int)
    case serverMessage(String)
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Apollo API URL"
        case .invalidResponse:
            return "Invalid response from Apollo"
        case .unauthorized:
            return "Invalid Apollo API key"
        case .insufficientCredits:
            return "Insufficient Apollo credits"
        case .invalidRequest:
            return "Invalid request parameters"
        case .rateLimited:
            return "Apollo rate limit exceeded. Please wait and try again."
        case .tooManyRecords:
            return "Maximum 10 records per bulk request"
        case .serverError(let code):
            return "Apollo server error: \(code)"
        case .serverMessage(let message):
            return message
        case .noAPIKey:
            return "Apollo API key not configured. Add it in Settings."
        }
    }
}
