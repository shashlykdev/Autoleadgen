import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class ViralContentAIService {

    private let cloudKeyService = CloudKeyStorageService.shared

    // MARK: - Content Generation

    func generateFromTopic(
        topic: String,
        userVoiceStyle: String?,
        modelId: String
    ) async throws -> String {
        let prompt = buildTopicPrompt(topic: topic, userVoiceStyle: userVoiceStyle)
        return try await generateContent(prompt: prompt, modelId: modelId)
    }

    func rewritePost(
        originalContent: String,
        userVoiceStyle: String?,
        modelId: String,
        topic: String? = nil
    ) async throws -> String {
        let prompt = buildRewritePrompt(
            originalContent: originalContent,
            userVoiceStyle: userVoiceStyle,
            topic: topic
        )
        return try await generateContent(prompt: prompt, modelId: modelId)
    }

    func generateReply(
        postContent: String,
        userVoiceStyle: String?,
        modelId: String
    ) async throws -> String {
        let prompt = buildReplyPrompt(postContent: postContent, userVoiceStyle: userVoiceStyle)
        return try await generateContent(prompt: prompt, modelId: modelId)
    }

    // MARK: - Private Methods

    private func generateContent(prompt: String, modelId: String) async throws -> String {
        guard !modelId.isEmpty else { throw AIError.modelNotConfigured }

        let provider = detectProvider(from: modelId)

        // Apple Intelligence doesn't need API key
        if provider == "apple" {
            return try await callApple(prompt: prompt)
        }

        // Fetch API key from cloud
        guard let apiKey = try await cloudKeyService.getAPIKey(for: provider),
              !apiKey.isEmpty else {
            throw AIError.noApiKey
        }

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

    private func detectProvider(from modelId: String) -> String {
        let lowercased = modelId.lowercased()
        if lowercased.contains("apple") || lowercased.contains("foundation") {
            return "apple"
        }
        if lowercased.contains("gpt") || lowercased.hasPrefix("o1") || lowercased.hasPrefix("o3") {
            return "openai"
        } else if lowercased.contains("claude") {
            return "anthropic"
        } else if lowercased.contains("grok") {
            return "xai"
        }
        return "openai"
    }

    // MARK: - Prompt Builders

    private func buildTopicPrompt(topic: String, userVoiceStyle: String?) -> String {
        var prompt = """
        Write an engaging LinkedIn post about the following topic:

        Topic: \(topic)

        Requirements:
        - Start with a compelling hook that stops the scroll
        - Share a unique perspective or insight on this topic
        - Use storytelling if appropriate
        - Keep it under 1300 characters (optimal for LinkedIn engagement)
        - Include line breaks for easy readability
        - End with a question or call to action to encourage engagement
        - Make it shareable and discussion-worthy
        - Avoid corporate jargon and buzzwords
        - Be authentic and relatable
        - Use a conversational tone
        """

        if let style = userVoiceStyle, !style.isEmpty {
            prompt += """


            IMPORTANT - Match this writing style and tone:
            ---
            \(style)
            ---
            """
        }

        prompt += "\n\nReturn ONLY the post text, nothing else."

        return prompt
    }

    private func buildRewritePrompt(originalContent: String, userVoiceStyle: String?, topic: String?) -> String {
        var prompt = """
        Rewrite the following viral LinkedIn post in a unique, authentic voice.
        The goal is to create engaging content that captures the same essence and insights
        but presents them in a fresh, original way.

        Original Post:
        ---
        \(originalContent.prefix(3000))
        ---

        Requirements:
        - Keep a similar length and structure to the original
        - Maintain the key insights and takeaways
        - Use conversational, engaging language
        - Include a hook in the first line
        - End with a call to action or thought-provoking question
        - Add appropriate line breaks for readability
        - Do NOT copy phrases directly from the original
        - Make it your own unique take on the topic
        """

        if let style = userVoiceStyle, !style.isEmpty {
            prompt += """


            IMPORTANT - Match this writing style and tone:
            ---
            \(style)
            ---
            """
        }

        if let topic = topic, !topic.isEmpty {
            prompt += "\n\nFocus the rewrite on this specific angle: \(topic)"
        }

        prompt += "\n\nReturn ONLY the post text, nothing else."

        return prompt
    }

    private func buildReplyPrompt(postContent: String, userVoiceStyle: String?) -> String {
        var prompt = """
        Write a thoughtful LinkedIn comment reply to this post:

        Post:
        ---
        \(postContent.prefix(2000))
        ---

        Requirements:
        - Be genuine and add value to the conversation
        - Keep it concise (2-3 sentences max)
        - Show that you've actually read and understood the post
        - Add a unique perspective or ask a thoughtful question
        - Avoid generic comments like "Great post!" or "So true!"
        - Don't be salesy or self-promotional
        - Be conversational and authentic
        """

        if let style = userVoiceStyle, !style.isEmpty {
            prompt += """


            Match this writing style:
            ---
            \(style)
            ---
            """
        }

        prompt += "\n\nReturn ONLY the comment text, nothing else."

        return prompt
    }

    // MARK: - API Calls

    private func callOpenAI(modelId: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let lowercased = modelId.lowercased()
        let isReasoningModel = lowercased.hasPrefix("o1") || lowercased.hasPrefix("o3") ||
                              (lowercased.contains("gpt-5") && !lowercased.contains("chat"))

        var body: [String: Any] = [
            "model": modelId,
            "messages": [["role": "user", "content": prompt]]
        ]

        if isReasoningModel {
            body["max_completion_tokens"] = 2000
        } else {
            body["max_tokens"] = 1500
            body["temperature"] = 0.8
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
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 1500,
            "temperature": 0.8
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
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 1500,
            "temperature": 0.8
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

    private func callApple(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                break
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

            let session = LanguageModelSession()
            try await session.prewarm()
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw AIError.appleIntelligenceUnavailable
    }
}
