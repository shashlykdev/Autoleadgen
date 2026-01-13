import Foundation

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case xai = "xAI"

    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-haiku-latest"
        case .xai: return "grok-2"
        }
    }

    var baseURL: URL {
        switch self {
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .xai: return URL(string: "https://api.x.ai/v1/chat/completions")!
        }
    }

    var authHeaderKey: String {
        switch self {
        case .openai, .xai: return "Authorization"
        case .anthropic: return "x-api-key"
        }
    }

    func authHeaderValue(apiKey: String) -> String {
        switch self {
        case .openai, .xai: return "Bearer \(apiKey)"
        case .anthropic: return apiKey
        }
    }
}
