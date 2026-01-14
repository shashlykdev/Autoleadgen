import Foundation

enum AIError: Error, LocalizedError {
    case noApiKey
    case invalidResponse
    case apiError(String)
    case unsupportedProvider(String)
    case modelNotConfigured

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No API key configured"
        case .invalidResponse: return "Invalid response from AI provider"
        case .apiError(let message): return "API Error: \(message)"
        case .unsupportedProvider(let provider): return "Unsupported provider: \(provider)"
        case .modelNotConfigured: return "No AI model selected"
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

        // Fetch API key from cloud
        guard let apiKey = try await cloudKeyService.getAPIKey(for: provider),
              !apiKey.isEmpty else {
            throw AIError.noApiKey
        }

        // Build prompt with optional sample message
        let prompt = buildPrompt(profile: profile, firstName: firstName, sampleMessage: sampleMessage)

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
        if modelId.contains("gpt") || modelId.contains("o1") || modelId.contains("o3") {
            return "openai"
        } else if modelId.contains("claude") {
            return "anthropic"
        } else if modelId.contains("grok") {
            return "xai"
        }
        // Default to openai for unknown models
        return "openai"
    }

    // MARK: - OpenAI API

    /// Check if the model is an o1/o3 reasoning model (uses different parameters)
    private func isReasoningModel(_ modelId: String) -> Bool {
        let lowercased = modelId.lowercased()
        return lowercased.contains("o1") || lowercased.contains("o3")
    }

    private func callOpenAI(modelId: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body based on model type
        var body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        // o1/o3 models use max_completion_tokens and don't support temperature
        if isReasoningModel(modelId) {
            body["max_completion_tokens"] = 300
        } else {
            body["max_tokens"] = 300
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

    private func callAnthropic(modelId: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 300
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

    private func callXAI(modelId: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
