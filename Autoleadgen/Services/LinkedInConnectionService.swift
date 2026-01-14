import Foundation
import WebKit

enum ConnectionResult {
    case sent
    case alreadyConnected
    case pending
}

enum ConnectionError: Error, LocalizedError {
    case invalidURL
    case connectButtonNotFound
    case sendFailed
    case timeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid profile URL"
        case .connectButtonNotFound: return "Connect button not found"
        case .sendFailed: return "Failed to send connection request"
        case .timeout: return "Timed out loading profile"
        case .unknown: return "Unknown error occurred"
        }
    }
}

actor LinkedInConnectionService {

    // MARK: - Connection Scripts

    static let clickConnectScript = """
    (function() {
        // Try multiple selectors for Connect button
        const selectors = [
            'button[aria-label*="Connect"]',
            'button[aria-label*="connect"]',
            '.pv-s-profile-actions button[aria-label*="Connect"]',
            '.pvs-profile-actions button[aria-label*="Connect"]',
            'button.artdeco-button--primary'
        ];

        for (const selector of selectors) {
            try {
                const buttons = document.querySelectorAll(selector);
                for (const btn of buttons) {
                    const label = btn.getAttribute('aria-label')?.toLowerCase() || '';
                    const text = btn.innerText?.toLowerCase() || '';
                    if (label.includes('connect') || text.includes('connect')) {
                        btn.click();
                        return 'clicked';
                    }
                }
            } catch(e) {}
        }

        // Direct button search
        const allButtons = document.querySelectorAll('button');
        for (const btn of allButtons) {
            if (btn.innerText?.trim().toLowerCase() === 'connect') {
                btn.click();
                return 'clicked';
            }
        }

        // Check if already connected
        const messageBtn = document.querySelector('button[aria-label*="Message"]');
        if (messageBtn) return 'already_connected';

        // Check if pending
        const pendingBtn = document.querySelector('button[aria-label*="Pending"]');
        if (pendingBtn) return 'pending';

        return 'not_found';
    })();
    """

    static let addConnectionNoteScript = """
    (function() {
        // Click "Add a note" button
        const addNoteBtn = document.querySelector('button[aria-label*="Add a note"]') ||
                          document.querySelector('.artdeco-modal button.artdeco-button--secondary');

        if (addNoteBtn) {
            addNoteBtn.click();
            return 'add_note_clicked';
        }
        return 'no_add_note_btn';
    })();
    """

    static func typeNoteScript(note: String) -> String {
        let escapedNote = note
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        return """
        (function() {
            const textarea = document.querySelector('#custom-message') ||
                            document.querySelector('textarea[name="message"]') ||
                            document.querySelector('.connect-button-send-invite__custom-message') ||
                            document.querySelector('.artdeco-modal textarea');

            if (textarea) {
                textarea.focus();
                textarea.value = '\(escapedNote)';

                // Trigger events
                const inputEvent = new Event('input', { bubbles: true });
                textarea.dispatchEvent(inputEvent);
                const changeEvent = new Event('change', { bubbles: true });
                textarea.dispatchEvent(changeEvent);

                return 'typed';
            }
            return 'not_found';
        })();
        """
    }

    static let sendConnectionScript = """
    (function() {
        const sendBtn = document.querySelector('button[aria-label*="Send"]') ||
                       document.querySelector('.artdeco-modal button[aria-label*="Send now"]') ||
                       document.querySelector('.artdeco-modal button.artdeco-button--primary');

        if (sendBtn && !sendBtn.disabled) {
            const text = sendBtn.innerText?.toLowerCase() || '';
            const label = sendBtn.getAttribute('aria-label')?.toLowerCase() || '';
            if (text.includes('send') || label.includes('send')) {
                sendBtn.click();
                return 'sent';
            }
        }
        return 'not_found';
    })();
    """

    // MARK: - Connection Methods

    @MainActor
    func sendConnectionRequest(
        profileURL: String,
        note: String?,
        webView: WKWebView
    ) async throws -> ConnectionResult {
        // Navigate to profile
        guard let url = URL(string: profileURL) else {
            throw ConnectionError.invalidURL
        }

        webView.load(URLRequest(url: url))
        try await waitForPageLoad(webView: webView)

        // Click Connect
        let connectResult = try await webView.evaluateJavaScript(Self.clickConnectScript) as? String

        switch connectResult {
        case "already_connected":
            return .alreadyConnected
        case "pending":
            return .pending
        case "not_found":
            throw ConnectionError.connectButtonNotFound
        case "clicked":
            break
        default:
            throw ConnectionError.unknown
        }

        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Add note if provided
        if let note = note, !note.isEmpty {
            _ = try await webView.evaluateJavaScript(Self.addConnectionNoteScript)
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let typeResult = try await webView.evaluateJavaScript(Self.typeNoteScript(note: note)) as? String
            if typeResult != "typed" {
                // Proceed without note if typing failed
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Send
        let sendResult = try await webView.evaluateJavaScript(Self.sendConnectionScript) as? String
        if sendResult == "sent" {
            return .sent
        }

        throw ConnectionError.sendFailed
    }

    @MainActor
    private func waitForPageLoad(webView: WKWebView, timeout: TimeInterval = 30) async throws {
        let startTime = Date()

        while webView.isLoading {
            if Date().timeIntervalSince(startTime) > timeout {
                throw ConnectionError.timeout
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Wait for dynamic content
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }
}
