import SwiftUI
import Combine

@MainActor
class TestViewModel: ObservableObject {
    @Published var comparisonResults: [AIComparisonResult] = []
    @Published var isGenerating: Bool = false
    @Published var testLeadName: String = ""
    @Published var testProfile: ProfileDataSnapshot = ProfileDataSnapshot()

    private let aiService = AIMessageService()
    private let storageKey = "ai_comparison_results"

    init() {
        loadResults()
    }

    // MARK: - Add Result

    func addResult(_ result: AIComparisonResult) {
        comparisonResults.insert(result, at: 0)
        saveResults()
    }

    // MARK: - Manual Test

    func generateComparison(
        leadName: String,
        profile: ProfileData,
        selectedModelId: String,
        sampleMessage: String?
    ) async {
        isGenerating = true

        var selectedMessage: String?
        var selectedError: String?
        var appleMessage: String?
        var appleError: String?

        // Generate with selected model
        do {
            selectedMessage = try await aiService.generateMessage(
                modelId: selectedModelId,
                profile: profile,
                firstName: leadName.components(separatedBy: " ").first ?? leadName,
                sampleMessage: sampleMessage
            )
        } catch {
            selectedError = error.localizedDescription
        }

        // Generate with Apple Intelligence if available
        if AIMessageService.isAppleIntelligenceAvailable {
            do {
                appleMessage = try await aiService.generateMessage(
                    modelId: "apple-intelligence",
                    profile: profile,
                    firstName: leadName.components(separatedBy: " ").first ?? leadName,
                    sampleMessage: sampleMessage
                )
            } catch {
                appleError = error.localizedDescription
            }
        } else {
            appleError = "Apple Intelligence not available"
        }

        let result = AIComparisonResult(
            leadName: leadName,
            linkedInURL: "",
            profileData: ProfileDataSnapshot(from: profile),
            selectedModelId: selectedModelId,
            selectedModelMessage: selectedMessage,
            selectedModelError: selectedError,
            appleModelMessage: appleMessage,
            appleModelError: appleError
        )

        addResult(result)
        isGenerating = false
    }

    // MARK: - Batch Test All Models

    /// Test all available models with a simulated profile
    /// This validates that API parameters are correctly configured for each model
    func runBatchTest(models: [String], sampleMessage: String?) async -> [String: String] {
        var results: [String: String] = [:]

        let testProfile = ProfileData(
            headline: "Senior Software Engineer at Tech Company",
            location: "San Francisco, CA",
            about: "Passionate about building scalable systems and mentoring junior developers.",
            currentCompany: "Tech Company Inc.",
            currentRole: "Senior Software Engineer",
            education: "Stanford University - Computer Science",
            connectionDegree: "2nd",
            followerCount: "1,234"
        )
        let testFirstName = "Alex"

        for modelId in models {
            do {
                let message = try await aiService.generateMessage(
                    modelId: modelId,
                    profile: testProfile,
                    firstName: testFirstName,
                    sampleMessage: sampleMessage
                )
                results[modelId] = "✅ Success: \(message.prefix(50))..."
            } catch {
                results[modelId] = "❌ Error: \(error.localizedDescription)"
            }

            // Small delay between API calls
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Test Apple Intelligence separately
        if AIMessageService.isAppleIntelligenceAvailable {
            do {
                let message = try await aiService.generateMessage(
                    modelId: "apple-intelligence",
                    profile: testProfile,
                    firstName: testFirstName,
                    sampleMessage: sampleMessage
                )
                results["apple-intelligence"] = "✅ Success: \(message.prefix(50))..."
            } catch {
                results["apple-intelligence"] = "❌ Error: \(error.localizedDescription)"
            }
        } else {
            results["apple-intelligence"] = "⚠️ Not available on this device"
        }

        return results
    }

    // MARK: - Clear

    func clearResults() {
        comparisonResults.removeAll()
        saveResults()
    }

    func deleteResult(_ result: AIComparisonResult) {
        comparisonResults.removeAll { $0.id == result.id }
        saveResults()
    }

    // MARK: - Persistence

    private func saveResults() {
        if let data = try? JSONEncoder().encode(comparisonResults) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadResults() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let results = try? JSONDecoder().decode([AIComparisonResult].self, from: data) {
            comparisonResults = results
        }
    }
}
