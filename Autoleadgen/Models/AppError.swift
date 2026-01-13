import Foundation

enum AppError: LocalizedError {
    case fileNotFound(String)
    case invalidURL(String)
    case invalidFileFormat(String)
    case timeout(String)
    case elementNotFound(String)
    case messageSendFailed(String)
    case notLoggedIn
    case rateLimited
    case networkError(Error)
    case excelParseError(String)
    case automationError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidFileFormat(let details):
            return "Invalid file format: \(details)"
        case .timeout(let operation):
            return "Timeout: \(operation)"
        case .elementNotFound(let element):
            return "Element not found: \(element)"
        case .messageSendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .notLoggedIn:
            return "Not logged in to LinkedIn"
        case .rateLimited:
            return "Rate limited by LinkedIn. Please wait and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .excelParseError(let details):
            return "Excel parse error: \(details)"
        case .automationError(let details):
            return "Automation error: \(details)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Please select a valid Excel file."
        case .invalidURL:
            return "Check the LinkedIn URL format in your Excel file."
        case .timeout:
            return "Try again. If the issue persists, check your internet connection."
        case .elementNotFound:
            return "LinkedIn's page structure may have changed. The automation may need updating."
        case .notLoggedIn:
            return "Please log in to LinkedIn in the browser first."
        case .rateLimited:
            return "Wait 15-30 minutes before trying again."
        default:
            return nil
        }
    }
}
