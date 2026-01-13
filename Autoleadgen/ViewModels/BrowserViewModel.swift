import SwiftUI
import WebKit
import Combine

@MainActor
class BrowserViewModel: ObservableObject {
    @Published var webView: WKWebView
    @Published var currentURL: URL?
    @Published var isLoading: Bool = false
    @Published var isLoggedInToLinkedIn: Bool = false
    @Published var pageTitle: String = ""
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    private var loginCheckTimer: Timer?
    private var observation: NSKeyValueObservation?

    init() {
        self.webView = WKWebView.createLinkedInWebView()
        setupObservations()
        loadLinkedIn()
        startLoginCheck()
    }

    private func setupObservations() {
        // Observe loading state
        observation = webView.observe(\.isLoading) { [weak self] webView, _ in
            Task { @MainActor in
                self?.isLoading = webView.isLoading
                self?.canGoBack = webView.canGoBack
                self?.canGoForward = webView.canGoForward
                self?.currentURL = webView.url
                self?.pageTitle = webView.title ?? ""
            }
        }
    }

    func loadLinkedIn() {
        let linkedInURL = URL(string: "https://www.linkedin.com/login")!
        webView.load(URLRequest(url: linkedInURL))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    private func startLoginCheck() {
        loginCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkLoginStatus()
            }
        }
    }

    private func checkLoginStatus() async {
        let js = """
            (function() {
                // Check for various logged-in indicators
                const feed = document.querySelector('.feed-shared-update-v2');
                const navProfile = document.querySelector('.global-nav__me-photo');
                const navMe = document.querySelector('.global-nav__me');
                const profilePhoto = document.querySelector('img.global-nav__me-photo');
                const loginForm = document.querySelector('.login__form');
                const loginButton = document.querySelector('[data-id="sign-in-form__submit-btn"]');

                if (feed || navProfile || navMe || profilePhoto) return 'logged_in';
                if (loginForm || loginButton) return 'not_logged_in';
                return 'unknown';
            })();
        """

        do {
            let result = try await webView.evaluateJavaScript(js) as? String
            isLoggedInToLinkedIn = (result == "logged_in")
        } catch {
            // Keep previous state on error
        }
    }

    func navigateToProfile(_ profileURL: String) async throws {
        guard let url = URL(string: profileURL) else {
            throw AppError.invalidURL(profileURL)
        }
        webView.load(URLRequest(url: url))
        try await waitForPageLoad()
    }

    func waitForPageLoad(timeout: TimeInterval = 30) async throws {
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

    deinit {
        loginCheckTimer?.invalidate()
        observation?.invalidate()
    }
}
