import Foundation

/// Service for storing and retrieving API keys from cloud storage (Vercel)
actor CloudKeyStorageService {

    // MARK: - Configuration

    /// Set these values after deploying the Vercel API
    private let apiURL: String
    private let apiSecret: String
    private let deviceId: String

    static let shared = CloudKeyStorageService()

    private init() {
        // TODO: Replace with your Vercel deployment URL and secret
        // You can also load these from a plist or environment
        self.apiURL = UserDefaults.standard.string(forKey: "cloudApiURL") ?? ""
        self.apiSecret = UserDefaults.standard.string(forKey: "cloudApiSecret") ?? ""
        self.deviceId = Self.getOrCreateDeviceId()
    }

    /// Configure the service with API URL and secret
    func configure(apiURL: String, apiSecret: String) {
        UserDefaults.standard.set(apiURL, forKey: "cloudApiURL")
        UserDefaults.standard.set(apiSecret, forKey: "cloudApiSecret")
    }

    var isConfigured: Bool {
        !apiURL.isEmpty && !apiSecret.isEmpty
    }

    // MARK: - Device ID

    private static func getOrCreateDeviceId() -> String {
        let key = "autoleadgen_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - API Keys Model

    struct StoredKeys: Codable {
        var openai: String?
        var anthropic: String?
        var xai: String?
        var updatedAt: String?
    }

    // MARK: - Fetch Keys

    func fetchKeys() async throws -> StoredKeys {
        guard isConfigured else {
            throw CloudKeyError.notConfigured
        }

        guard let url = URL(string: "\(apiURL)/api/keys") else {
            throw CloudKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiSecret)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudKeyError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(FetchResponse.self, from: data)
            return result.keys
        case 401:
            throw CloudKeyError.unauthorized
        default:
            throw CloudKeyError.serverError(httpResponse.statusCode)
        }
    }

    private struct FetchResponse: Codable {
        let keys: StoredKeys
    }

    // MARK: - Store Keys

    func storeKeys(_ keys: StoredKeys) async throws {
        guard isConfigured else {
            throw CloudKeyError.notConfigured
        }

        guard let url = URL(string: "\(apiURL)/api/keys") else {
            throw CloudKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiSecret)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(keys)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudKeyError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return // Success
        case 401:
            throw CloudKeyError.unauthorized
        default:
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw CloudKeyError.serverMessage(errorResponse.error)
            }
            throw CloudKeyError.serverError(httpResponse.statusCode)
        }
    }

    /// Store a single key by provider
    func storeKey(provider: AIProvider, key: String) async throws {
        var keys = StoredKeys()
        switch provider {
        case .openai:
            keys.openai = key
        case .anthropic:
            keys.anthropic = key
        case .xai:
            keys.xai = key
        }
        try await storeKeys(keys)
    }

    // MARK: - Delete Keys

    func deleteAllKeys() async throws {
        guard isConfigured else {
            throw CloudKeyError.notConfigured
        }

        guard let url = URL(string: "\(apiURL)/api/keys") else {
            throw CloudKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiSecret)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudKeyError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw CloudKeyError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Health Check

    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(apiURL)/api/health") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private struct ErrorResponse: Codable {
        let error: String
    }
}

// MARK: - Errors

enum CloudKeyError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloud storage not configured. Set API URL and secret."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Unauthorized. Check API secret."
        case .serverError(let code):
            return "Server error: \(code)"
        case .serverMessage(let message):
            return message
        }
    }
}
