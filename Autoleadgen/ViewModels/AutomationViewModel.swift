import SwiftUI
import WebKit
import Combine

@MainActor
class AutomationViewModel: ObservableObject {
    @Published var currentState: AutomationState = .idle
    @Published var currentContactIndex: Int = 0
    @Published var totalContacts: Int = 0
    @Published var delayRemaining: Int = 0
    @Published var messageDelayRemaining: Int = 0

    // Configuration - delay between contacts
    @Published var minDelaySeconds: Int = 30
    @Published var maxDelaySeconds: Int = 90

    // Configuration - delay between typing message and sending (5-15 seconds)
    @Published var minMessageDelaySeconds: Int = 5
    @Published var maxMessageDelaySeconds: Int = 15

    // AI Settings (read from AppStorage)
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("aiProvider") private var aiProviderRaw: String = "OpenAI"
    @AppStorage("aiApiKey") private var aiApiKey: String = ""

    private var automationTask: Task<Void, Never>?
    private var isPaused: Bool = false
    private let delayService = DelayService()
    private let profileScraperService = LinkedInProfileScraperService()
    private let aiService = AIMessageService()

    var progress: Double {
        guard totalContacts > 0 else { return 0 }
        return Double(currentContactIndex) / Double(totalContacts)
    }

    func start(
        contacts: [Contact],
        webView: WKWebView,
        onContactStarted: @escaping (Contact) -> Void,
        onContactCompleted: @escaping (Contact, Result<Void, Error>) -> Void
    ) {
        guard currentState.canStart else { return }
        guard !contacts.isEmpty else { return }

        totalContacts = contacts.count
        currentContactIndex = 0
        isPaused = false
        currentState = .running

        automationTask = Task { [weak self] in
            guard let self = self else { return }

            for (index, contact) in contacts.enumerated() {
                // Check for pause
                while self.isPaused {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { return }
                }

                if Task.isCancelled { return }

                self.currentContactIndex = index
                self.currentState = .processingContact(contactName: contact.displayName)
                onContactStarted(contact)

                // Process the contact
                do {
                    try await self.processContact(contact, webView: webView)
                    onContactCompleted(contact, .success(()))
                } catch {
                    onContactCompleted(contact, .failure(error))
                }

                // Random delay before next contact (except for last one)
                if index < contacts.count - 1 {
                    let delay = self.delayService.randomDelay(
                        min: self.minDelaySeconds,
                        max: self.maxDelaySeconds
                    )
                    await self.performDelay(seconds: delay)

                    if Task.isCancelled { return }
                }
            }

            self.currentContactIndex = contacts.count
            self.currentState = .completed
        }
    }

    private func processContact(_ contact: Contact, webView: WKWebView) async throws {
        // Step 1: Navigate to profile
        try await navigateToProfile(contact.linkedInURL, webView: webView)

        // Step 2: Scrape profile data for personalization
        let profileData = try await profileScraperService.scrapeProfile(webView: webView)

        // Step 3: Generate or personalize message
        let finalMessage: String
        if aiEnabled && !aiApiKey.isEmpty {
            // Use AI to generate message
            do {
                let provider = AIProvider(rawValue: aiProviderRaw) ?? .openai
                finalMessage = try await aiService.generateMessage(
                    provider: provider,
                    apiKey: aiApiKey,
                    profile: profileData,
                    firstName: contact.firstName ?? "there"
                )
            } catch {
                // Fallback to template-based personalization
                finalMessage = personalizeMessage(contact, with: profileData)
            }
        } else {
            // Use template-based personalization
            finalMessage = personalizeMessage(contact, with: profileData)
        }

        // Step 4: Find and click Message button
        try await clickMessageButton(webView: webView)

        // Step 5: Wait for message dialog
        try await waitForMessageDialog(webView: webView)

        // Step 6: Type message
        try await typeMessage(finalMessage, webView: webView)

        // Step 7: Wait 5-15 seconds before sending (random delay)
        let messageDelay = delayService.randomDelay(
            min: minMessageDelaySeconds,
            max: maxMessageDelaySeconds
        )
        await performMessageDelay(seconds: messageDelay)

        // Step 8: Click send
        try await clickSendButton(webView: webView)

        // Step 9: Verify message sent
        try await verifyMessageSent(webView: webView)
    }

    private func personalizeMessage(_ contact: Contact, with profile: ProfileData) -> String {
        var message = contact.messageText

        // Replace contact placeholders
        message = message.replacingOccurrences(of: "{firstName}", with: contact.firstName ?? "")
        message = message.replacingOccurrences(of: "{lastName}", with: contact.lastName ?? "")
        message = message.replacingOccurrences(of: "{fullName}", with: contact.fullName)

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
