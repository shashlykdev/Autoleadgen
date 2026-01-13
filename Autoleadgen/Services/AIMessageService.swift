import Foundation

enum AIError: Error, LocalizedError {
    case noApiKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No API key configured"
        case .invalidResponse: return "Invalid response from AI provider"
        case .apiError(let message): return "API Error: \(message)"
        }
    }
}

actor AIMessageService {

    func generateMessage(
        provider: AIProvider,
        apiKey: String,
        profile: ProfileData,
        firstName: String,
        customPrompt: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIError.noApiKey }

        let prompt = customPrompt ?? buildDefaultPrompt(profile: profile, firstName: firstName)

        switch provider {
        case .openai, .xai:
            return try await callOpenAICompatible(provider: provider, apiKey: apiKey, prompt: prompt)
        case .anthropic:
            return try await callAnthropic(apiKey: apiKey, prompt: prompt)
        }
    }

    // MARK: - OpenAI / xAI (Compatible API)

    private func callOpenAICompatible(provider: AIProvider, apiKey: String, prompt: String) async throws -> String {
        var request = URLRequest(url: provider.baseURL)
        request.httpMethod = "POST"
        request.setValue(provider.authHeaderValue(apiKey: apiKey), forHTTPHeaderField: provider.authHeaderKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": provider.defaultModel,
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

    // MARK: - Anthropic

    private func callAnthropic(apiKey: String, prompt: String) async throws -> String {
        var request = URLRequest(url: AIProvider.anthropic.baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": AIProvider.anthropic.defaultModel,
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

    // MARK: - Prompt Builder

    private func buildDefaultPrompt(profile: ProfileData, firstName: String) -> String {
        """
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

        Return ONLY the message text, nothing else.
        """
    }
}
