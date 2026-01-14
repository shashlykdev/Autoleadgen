import Foundation

/// Service for fetching API keys and models from cloud storage (Vercel)
actor CloudKeyStorageService {

    // MARK: - Configuration

    private let apiURL = "https://vercel-api-keys.vercel.app"
    private let apiSecret = "0baeb073f327622477f162809ceca22e5045f9e8d17d54c820fceac2be3aa860"

    static let shared = CloudKeyStorageService()

    private init() {}

    // MARK: - Models

    struct AIModel: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let provider: String
    }

    struct ModelsResponse: Codable {
        let models: [AIModel]
    }

    /// Fetch available AI models from all configured providers
    func fetchModels() async throws -> [AIModel] {
        guard let url = URL(string: "\(apiURL)/api/models") else {
            throw CloudKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiSecret)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudKeyError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return result.models
        case 401:
            throw CloudKeyError.unauthorized
        default:
            throw CloudKeyError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - API Keys

    struct AIKeys: Codable {
        let openai: String?
        let anthropic: String?
        let xai: String?
    }

    /// Fetch API keys from cloud storage
    func fetchAPIKeys() async throws -> AIKeys {
        guard let url = URL(string: "\(apiURL)/api/ai-keys") else {
            throw CloudKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiSecret)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudKeyError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(AIKeys.self, from: data)
        case 401:
            throw CloudKeyError.unauthorized
        default:
            throw CloudKeyError.serverError(httpResponse.statusCode)
        }
    }

    /// Get API key for a specific provider
    func getAPIKey(for provider: String) async throws -> String? {
        let keys = try await fetchAPIKeys()
        switch provider {
        case "openai":
            return keys.openai
        case "anthropic":
            return keys.anthropic
        case "xai":
            return keys.xai
        default:
            return nil
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
            return "Cloud storage not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Unauthorized"
        case .serverError(let code):
            return "Server error: \(code)"
        case .serverMessage(let message):
            return message
        }
    }
}
