import SwiftUI
import WebKit
import Combine

@MainActor
class AutomationViewModel: ObservableObject {
    @Published var currentState: AutomationState = .idle
    @Published var currentLeadIndex: Int = 0
    @Published var totalLeads: Int = 0
    @Published var delayRemaining: Int = 0
    @Published var messageDelayRemaining: Int = 0

    // Configuration - delay between leads
    @Published var minDelaySeconds: Int = 30
    @Published var maxDelaySeconds: Int = 90

    // Configuration - delay between typing message and sending (5-15 seconds)
    @Published var minMessageDelaySeconds: Int = 5
    @Published var maxMessageDelaySeconds: Int = 15

    // AI Settings (read from AppStorage)
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("selectedModelId") private var selectedModelId: String = ""
    @AppStorage("sampleMessage") private var sampleMessage: String = ""

    private var automationTask: Task<Void, Never>?
    private var isPaused: Bool = false
    private let delayService = DelayService()
    private let profileScraperService = LinkedInProfileScraperService()
    private let aiService = AIMessageService()

    var progress: Double {
        guard totalLeads > 0 else { return 0 }
        return Double(currentLeadIndex) / Double(totalLeads)
    }

    func start(
        leads: [Lead],
        webView: WKWebView,
        onLeadStarted: @escaping (Lead) -> Void,
        onLeadCompleted: @escaping (Lead, Result<Void, Error>) -> Void
    ) {
        guard currentState.canStart else { return }
        guard !leads.isEmpty else { return }

        totalLeads = leads.count
        currentLeadIndex = 0
        isPaused = false
        currentState = .running

        automationTask = Task { [weak self] in
            guard let self = self else { return }

            for (index, lead) in leads.enumerated() {
                // Check for pause
                while self.isPaused {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { return }
                }

                if Task.isCancelled { return }

                self.currentLeadIndex = index
                self.currentState = .processingContact(contactName: lead.displayName)
                onLeadStarted(lead)

                // Process the lead
                do {
                    try await self.processLead(lead, webView: webView)
                    onLeadCompleted(lead, .success(()))
                } catch {
                    onLeadCompleted(lead, .failure(error))
                }

                // Random delay before next lead (except for last one)
                if index < leads.count - 1 {
                    let delay = self.delayService.randomDelay(
                        min: self.minDelaySeconds,
                        max: self.maxDelaySeconds
                    )
                    await self.performDelay(seconds: delay)

                    if Task.isCancelled { return }
                }
            }

            self.currentLeadIndex = leads.count
            self.currentState = .completed
        }
    }

    private func processLead(_ lead: Lead, webView: WKWebView) async throws {
        // Step 1: Navigate to profile
        try await navigateToProfile(lead.linkedInURL, webView: webView)

        // Step 2: Determine the message to send
        let finalMessage: String

        // Check if lead already has a pre-generated message (from Lead Finder)
        if !lead.effectiveMessage.isEmpty {
            // Use pre-generated message - skip profile scraping and AI generation
            finalMessage = lead.personalizedMessage()
        } else {
            // No pre-generated message - scrape profile and generate on the fly
            let profileData = try await profileScraperService.scrapeProfile(webView: webView)

            if aiEnabled && !selectedModelId.isEmpty {
                // Use AI to generate message with cloud API keys
                do {
                    finalMessage = try await aiService.generateMessage(
                        modelId: selectedModelId,
                        profile: profileData,
                        firstName: lead.firstName.isEmpty ? "there" : lead.firstName,
                        sampleMessage: sampleMessage.isEmpty ? nil : sampleMessage
                    )
                } catch {
                    // Fallback to template-based personalization
                    finalMessage = personalizeMessage(lead, with: profileData)
                }
            } else {
                // Use template-based personalization
                finalMessage = personalizeMessage(lead, with: profileData)
            }
        }

        // Step 3: Find and click Message button
        try await clickMessageButton(webView: webView)

        // Step 4: Wait for message dialog
        try await waitForMessageDialog(webView: webView)

        // Step 5: Type message
        try await typeMessage(finalMessage, webView: webView)

        // Step 6: Wait 5-15 seconds before sending (random delay)
        let messageDelay = delayService.randomDelay(
            min: minMessageDelaySeconds,
            max: maxMessageDelaySeconds
        )
        await performMessageDelay(seconds: messageDelay)

        // Step 7: Click send
        try await clickSendButton(webView: webView)

        // Step 8: Verify message sent
        try await verifyMessageSent(webView: webView)
    }

    private func personalizeMessage(_ lead: Lead, with profile: ProfileData) -> String {
        var message = lead.messageText

        // Replace lead placeholders
        message = message.replacingOccurrences(of: "{firstName}", with: lead.firstName)
        message = message.replacingOccurrences(of: "{lastName}", with: lead.lastName)
        message = message.replacingOccurrences(of: "{fullName}", with: lead.fullName)

        // Replace profile placeholders
        message = message.replacingOccurrences(of: "{headline}", with: profile.headline ?? "")
        message = message.replacingOccurrences(of: "{location}", with: profile.location ?? "")
        message = message.replacingOccurrences(of: "{about}", with: profile.about ?? "")
        message = message.replacingOccurrences(of: "{currentCompany}", with: profile.currentCompany ?? "")
        message = message.replacingOccurrences(of: "{currentRole}", with: profile.currentRole ?? "")
        message = message.replacingOccurrences(of: "{education}", with: profile.education ?? "")

        // Clean up extra spaces
        message = message.replacingOccurrences(of: "  ", with: " ")
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performMessageDelay(seconds: Int) async {
        for remaining in stride(from: seconds, through: 1, by: -1) {
            if Task.isCancelled { return }
            messageDelayRemaining = remaining
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        messageDelayRemaining = 0
    }

    private func performDelay(seconds: Int) async {
        for remaining in stride(from: seconds, through: 1, by: -1) {
            if isPaused {
                currentState = .paused
                while isPaused {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { return }
                }
            }

            if Task.isCancelled { return }

            delayRemaining = remaining
            currentState = .waitingForDelay(secondsRemaining: remaining)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        delayRemaining = 0
    }

    func pause() {
        guard currentState.canPause else { return }
        isPaused = true
        currentState = .paused
    }

    func resume() {
        guard currentState.canResume else { return }
        isPaused = false
        currentState = .running
    }

    func stop() {
        automationTask?.cancel()
        automationTask = nil
        isPaused = false
        currentState = .idle
        delayRemaining = 0
    }

    // MARK: - LinkedIn Automation Steps

    private func navigateToProfile(_ url: String, webView: WKWebView) async throws {
        guard let profileURL = URL(string: url) else {
            throw AppError.invalidURL(url)
        }
        webView.load(URLRequest(url: profileURL))
        try await waitForPageLoad(webView: webView)
    }

    private func waitForPageLoad(webView: WKWebView, timeout: TimeInterval = 30) async throws {
        let startTime = Date()

        while webView.isLoading {
            if Date().timeIntervalSince(startTime) > timeout {
                throw AppError.timeout("Page load timeout")
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Additional wait for dynamic content
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    private func clickMessageButton(webView: WKWebView) async throws {
        let js = """
            (function() {
                // Try multiple selectors for Message button
                const selectors = [
                    'button[aria-label*="Message"]',
                    'a[aria-label*="Message"]',
                    '.message-anywhere-button',
                    '.pv-s-profile-actions button[aria-label*="Message"]',
                    '.pv-top-card-v2-ctas button:has(span:contains("Message"))',
                    'button.artdeco-button--primary span.artdeco-button__text'
                ];

                for (const selector of selectors) {
                    try {
                        const elements = document.querySelectorAll(selector);
                        for (const el of elements) {
                            if (el.textContent && el.textContent.toLowerCase().includes('message')) {
                                el.click();
                                return 'clicked';
                            }
                            if (el.getAttribute('aria-label') && el.getAttribute('aria-label').toLowerCase().includes('message')) {
                                el.click();
                                return 'clicked';
                            }
                        }
                    } catch(e) {}
                }

                // Direct button search
                const allButtons = document.querySelectorAll('button');
                for (const btn of allButtons) {
                    if (btn.textContent && btn.textContent.trim().toLowerCase() === 'message') {
                        btn.click();
                        return 'clicked';
                    }
                }

                return 'not_found';
            })();
        """

        let result = try await webView.evaluateJavaScript(js) as? String
        if result != "clicked" {
            throw AppError.elementNotFound("Message button")
        }

        // Wait for dialog animation
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    private func waitForMessageDialog(webView: WKWebView) async throws {
        let js = """
            (function() {
                const selectors = [
                    '.msg-form__contenteditable',
                    '.msg-form__message-texteditor',
                    '[role="textbox"][aria-label*="message"]',
                    '.msg-form__textarea'
                ];

                for (const selector of selectors) {
                    if (document.querySelector(selector)) return 'found';
                }
                return 'not_found';
            })();
        """

        for _ in 0..<15 {
            let result = try await webView.evaluateJavaScript(js) as? String
            if result == "found" { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw AppError.timeout("Message dialog did not appear")
    }

    private func typeMessage(_ message: String, webView: WKWebView) async throws {
        // Escape special characters for JavaScript
        let escapedMessage = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")

        let js = """
            (function() {
                const selectors = [
                    '.msg-form__contenteditable',
                    '.msg-form__message-texteditor',
                    '[role="textbox"][aria-label*="message"]',
                    '.msg-form__textarea'
                ];

                let editor = null;
                for (const selector of selectors) {
                    editor = document.querySelector(selector);
                    if (editor) break;
                }

                if (!editor) return 'not_found';

                // Focus the editor
                editor.focus();

                // Set content - try different methods
                if (editor.tagName === 'DIV' || editor.getAttribute('contenteditable') === 'true') {
                    editor.innerHTML = '<p>\(escapedMessage)</p>';
                } else {
                    editor.value = '\(escapedMessage)';
                }

                // Trigger input event for React to detect the change
                const inputEvent = new Event('input', { bubbles: true, cancelable: true });
                editor.dispatchEvent(inputEvent);

                // Also trigger change event
                const changeEvent = new Event('change', { bubbles: true, cancelable: true });
                editor.dispatchEvent(changeEvent);

                // Trigger keyup for good measure
                const keyEvent = new KeyboardEvent('keyup', { bubbles: true, cancelable: true });
                editor.dispatchEvent(keyEvent);

                return 'typed';
            })();
        """

        let result = try await webView.evaluateJavaScript(js) as? String
        if result != "typed" {
            throw AppError.elementNotFound("Message editor")
        }

        // Wait for UI to update
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    private func clickSendButton(webView: WKWebView) async throws {
        let js = """
            (function() {
                const selectors = [
                    '.msg-form__send-button',
                    'button[type="submit"].msg-form__send-button',
                    'button.msg-form__send-btn',
                    'button[aria-label="Send"]'
                ];

                for (const selector of selectors) {
                    const sendBtn = document.querySelector(selector);
                    if (sendBtn && !sendBtn.disabled) {
                        sendBtn.click();
                        return 'clicked';
                    }
                }

                // Fallback: find button with "Send" text
                const allButtons = document.querySelectorAll('button');
                for (const btn of allButtons) {
                    if (btn.textContent && btn.textContent.trim().toLowerCase() === 'send' && !btn.disabled) {
                        btn.click();
                        return 'clicked';
                    }
                }

                return 'not_found';
            })();
        """

        let result = try await webView.evaluateJavaScript(js) as? String
        if result != "clicked" {
            throw AppError.elementNotFound("Send button")
        }
    }

    private func verifyMessageSent(webView: WKWebView) async throws {
        // Wait for the message to send
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let js = """
            (function() {
                // Check if editor is empty (message was sent)
                const editor = document.querySelector('.msg-form__contenteditable');
                if (editor) {
                    const content = editor.textContent || editor.innerText || '';
                    if (content.trim() === '') {
                        return 'sent';
                    }
                }

                // Check for error indicators
                const error = document.querySelector('.msg-form__error');
                if (error && error.textContent) {
                    return 'error:' + error.textContent;
                }

                // Check for success toast/notification
                const toast = document.querySelector('.artdeco-toast-item--success');
                if (toast) return 'sent';

                return 'unknown';
            })();
        """

        let result = try await webView.evaluateJavaScript(js) as? String ?? "unknown"

        if result.starts(with: "error:") {
            let errorMessage = String(result.dropFirst(6))
            throw AppError.messageSendFailed(errorMessage)
        }

        // We'll accept 'sent' or 'unknown' (LinkedIn might have closed the dialog)
    }
}
