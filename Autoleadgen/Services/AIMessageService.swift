import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIError: Error, LocalizedError {
    case noApiKey
    case invalidResponse
    case apiError(String)
    case unsupportedProvider(String)
    case modelNotConfigured
    case appleIntelligenceUnavailable
    case appleIntelligenceNotEnabled
    case appleIntelligenceDeviceNotEligible
    case appleIntelligenceModelNotReady
    case appleIntelligenceError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No API key configured"
        case .invalidResponse: return "Invalid response from AI provider"
        case .apiError(let message): return "API Error: \(message)"
        case .unsupportedProvider(let provider): return "Unsupported provider: \(provider)"
        case .modelNotConfigured: return "No AI model selected"
        case .appleIntelligenceUnavailable: return "Apple Intelligence requires macOS 26.0+ with Apple Silicon"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is not enabled. Please enable it in System Settings > Apple Intelligence & Siri"
        case .appleIntelligenceDeviceNotEligible: return "This device is not eligible for Apple Intelligence (requires Apple Silicon Mac)"
        case .appleIntelligenceModelNotReady: return "Apple Intelligence model is not ready. Please wait for model assets to download in System Settings"
        case .appleIntelligenceError(let message): return "Apple Intelligence Error: \(message)"
        }
    }
}

@MainActor
final class AIMessageService {

    private let cloudKeyService = CloudKeyStorageService.shared

    /// Generate a message using the selected model from cloud configuration
    func generateMessage(
        modelId: String,
        profile: ProfileData,
        firstName: String,
        sampleMessage: String? = nil
    ) async throws -> String {
        guard !modelId.isEmpty else { throw AIError.modelNotConfigured }

        // Determine provider from model ID
        let provider = detectProvider(from: modelId)

        // Build prompt with optional sample message
        let prompt = buildPrompt(profile: profile, firstName: firstName, sampleMessage: sampleMessage)

        // Apple Intelligence doesn't need API key
        if provider == "apple" {
            return try await callApple(prompt: prompt)
        }

        // Fetch API key from cloud for other providers
        guard let apiKey = try await cloudKeyService.getAPIKey(for: provider),
              !apiKey.isEmpty else {
            throw AIError.noApiKey
        }

        // Call appropriate API
        switch provider {
        case "openai":
            return try await callOpenAI(modelId: modelId, apiKey: apiKey, prompt: prompt)
        case "anthropic":
            return try await callAnthropic(modelId: modelId, apiKey: apiKey, prompt: prompt)
        case "xai":
            return try await callXAI(modelId: modelId, apiKey: apiKey, prompt: prompt)
        default:
            throw AIError.unsupportedProvider(provider)
        }
    }

    /// Legacy method for backward compatibility
    func generateMessage(
        provider: AIProvider,
        apiKey: String,
        profile: ProfileData,
        firstName: String,
        customPrompt: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIError.noApiKey }

        let prompt = customPrompt ?? buildPrompt(profile: profile, firstName: firstName, sampleMessage: nil)

        switch provider {
        case .openai:
            return try await callOpenAI(modelId: provider.defaultModel, apiKey: apiKey, prompt: prompt)
        case .anthropic:
            return try await callAnthropic(modelId: provider.defaultModel, apiKey: apiKey, prompt: prompt)
        case .xai:
            return try await callXAI(modelId: provider.defaultModel, apiKey: apiKey, prompt: prompt)
        }
    }

    // MARK: - Provider Detection

    private func detectProvider(from modelId: String) -> String {
        let lowercased = modelId.lowercased()
        // Apple Intelligence (on-device)
        if lowercased.contains("apple") || lowercased.contains("foundation") {
            return "apple"
        }
        // OpenAI: GPT models and o1/o3 reasoning models
        if lowercased.contains("gpt") || lowercased.hasPrefix("o1") || lowercased.hasPrefix("o3") {
            return "openai"
        } else if lowercased.contains("claude") {
            return "anthropic"
        } else if lowercased.contains("grok") {
            return "xai"
        }
        // Default to openai for unknown models
        return "openai"
    }

    // MARK: - OpenAI API

    /// Model parameter configuration based on official OpenAI documentation
    /// Source: https://platform.openai.com/docs/api-reference/chat
    /// Source: https://community.openai.com/t/temperature-in-gpt-5-models/1337133
    private struct OpenAIModelConfig {
        let useMaxCompletionTokens: Bool
        let supportsTemperature: Bool

        /// Get configuration for a specific model
        static func forModel(_ modelId: String) -> OpenAIModelConfig {
            let lowercased = modelId.lowercased()

            // GPT-5 reasoning models (gpt-5, gpt-5-mini, gpt-5-nano) - NO temperature support
            // These are reasoning models that don't support temperature parameter
            if lowercased.contains("gpt-5") {
                // gpt-5-chat variants support temperature
                if lowercased.contains("chat") {
                    return OpenAIModelConfig(useMaxCompletionTokens: true, supportsTemperature: true)
                }
                // All other gpt-5 variants (gpt-5, gpt-5-mini, gpt-5-nano) don't support temperature
                return OpenAIModelConfig(useMaxCompletionTokens: true, supportsTemperature: false)
            }

            // GPT-4.1 models (gpt-4.1, gpt-4.1-mini, gpt-4.1-nano) - temperature supported
            if lowercased.contains("gpt-4.1") {
                return OpenAIModelConfig(useMaxCompletionTokens: true, supportsTemperature: true)
            }

            // o1/o3 reasoning models - NO temperature support
            if lowercased.hasPrefix("o1") || lowercased.hasPrefix("o3") {
                return OpenAIModelConfig(useMaxCompletionTokens: true, supportsTemperature: false)
            }

            // Legacy models (gpt-4, gpt-4-turbo, gpt-3.5-turbo) - use max_tokens
            return OpenAIModelConfig(useMaxCompletionTokens: false, supportsTemperature: true)
        }
    }

    private func callOpenAI(modelId: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get model-specific configuration
        let config = OpenAIModelConfig.forModel(modelId)

        // Build request body based on model type
        var body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        // Set token parameter based on model
        // Note: GPT-5 reasoning models need higher limits because they use internal reasoning tokens
        // GPT-5-mini used 384 reasoning tokens + 48 output tokens for a simple message
        if config.useMaxCompletionTokens {
            // Reasoning models need more tokens (reasoning + output)
            body["max_completion_tokens"] = config.supportsTemperature ? 300 : 1000
        } else {
            body["max_tokens"] = 300
        }

        // Only add temperature if the model supports it
        if config.supportsTemperature {
            body["temperature"] = 0.7
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.apiError(message)
            }
            throw AIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic API

    /// Anthropic API parameters based on official documentation
    /// Source: https://docs.anthropic.com/en/api/messages
    /// - max_tokens: Required, maximum tokens to generate
    /// - temperature: Optional (0.0-1.0), default 1.0
    ///   - Use 0.0 for analytical/deterministic tasks
    ///   - Use 1.0 for creative/generative tasks
    private func callAnthropic(modelId: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Anthropic API parameters:
        // - max_tokens: Required
        // - temperature: Optional, range 0.0-1.0 (NOT 0-2 like OpenAI)
        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 300,
            "temperature": 0.7  // Within Anthropic's 0.0-1.0 range
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.apiError(message)
            }
            throw AIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AIError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - xAI API

    /// xAI Grok API parameters based on official documentation
    /// Source: https://docs.x.ai/docs/overview
    /// Source: https://docs.x.ai/docs/guides/reasoning
    /// - max_tokens: Supported for all models
    /// - temperature: Supported (0-2 range, similar to OpenAI)
    /// - reasoning_effort: Only supported by grok-3-mini (not grok-3, grok-4, or grok-4-fast-reasoning)
    /// - Non-reasoning models also support: presence_penalty, frequency_penalty, stop
    private func callXAI(modelId: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // xAI uses OpenAI-compatible API format
        // All Grok models support temperature and max_tokens
        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 300,
            "temperature": 0.7
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.apiError(message)
            }
            throw AIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Apple Foundation Models

    /// Check if Apple Intelligence API is available on this device (macOS 26+)
    static var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Check if Apple Intelligence is ready to use (model assets downloaded and enabled)
    static var appleIntelligenceStatus: (available: Bool, reason: String?) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return (true, nil)
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return (false, "Apple Intelligence is not enabled. Enable it in System Settings > Apple Intelligence & Siri")
                case .deviceNotEligible:
                    return (false, "This device is not eligible for Apple Intelligence")
                case .modelNotReady:
                    return (false, "Model assets are not ready. Please wait for download to complete in System Settings")
                @unknown default:
                    return (false, "Apple Intelligence is unavailable")
                }
            }
        }
        #endif
        return (false, "Requires macOS 26.0+ with Apple Silicon")
    }

    private func callApple(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            // Check model availability before attempting to use it
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                break // Model is ready, continue
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    throw AIError.appleIntelligenceNotEnabled
                case .deviceNotEligible:
                    throw AIError.appleIntelligenceDeviceNotEligible
                case .modelNotReady:
                    throw AIError.appleIntelligenceModelNotReady
                @unknown default:
                    throw AIError.appleIntelligenceError("Unknown unavailability reason")
                }
            }

            do {
                let session = LanguageModelSession()
                // Prewarm the model to reduce latency
                try await session.prewarm()
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as LanguageModelSession.GenerationError {
                throw AIError.appleIntelligenceError(error.localizedDescription)
            }
        }
        #endif
        throw AIError.appleIntelligenceUnavailable
    }

    // MARK: - Prompt Builder

    private func buildPrompt(profile: ProfileData, firstName: String, sampleMessage: String?) -> String {
        var prompt = """
        Write a short, personalized LinkedIn connection message (under 100 words).

        Recipient information:
        - First Name: \(firstName)
        - Current Role: \(profile.currentRole ?? "not specified")
        - Company: \(profile.currentCompany ?? "not specified")
        - Location: \(profile.location ?? "not specified")
        - Headline: \(profile.headline ?? "not specified")
        - Education: \(profile.education ?? "not specified")

        Requirements:
        - Start with "Hi \(firstName),"
        - Be friendly but professional
        - Reference their role or company naturally (if available)
        - Keep it genuine, not salesy
        - End with a clear reason to connect
        - Avoid generic phrases like "I hope this finds you well"
        - Do NOT include a subject line
        """

        // Add sample message for style reference if provided
        if let sample = sampleMessage, !sample.isEmpty {
            prompt += """


        IMPORTANT: Use this sample message as a style and tone reference. Match the writing style, length, and approach:
        ---
        \(sample)
        ---
        """
        }

        prompt += "\n\nReturn ONLY the message text, nothing else."

        return prompt
    }
}
