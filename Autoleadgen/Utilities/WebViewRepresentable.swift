import SwiftUI
import WebKit

struct LinkedInWebView: NSViewRepresentable {
    let webView: WKWebView
    var onNavigationFinished: ((URL?) -> Void)?
    var onNavigationFailed: ((Error) -> Void)?
    var onTitleChanged: ((String?) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Updates handled by ViewModel
    }

    func makeCoordinator() -> WebViewCoordinator {
        let coordinator = WebViewCoordinator()
        coordinator.onNavigationFinished = onNavigationFinished
        coordinator.onNavigationFailed = onNavigationFailed
        coordinator.onTitleChanged = onTitleChanged
        return coordinator
    }
}

// Extension for WKWebView configuration
extension WKWebView {
    static func createLinkedInWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Enable JavaScript using the modern API
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        // Enable developer extras for debugging (optional)
        if #available(macOS 13.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }

        // Setup user content controller for message passing
        let contentController = WKUserContentController()
        configuration.userContentController = contentController

        // Set a desktop user agent to avoid mobile view
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        return webView
    }
}
