import Foundation

enum AutomationState: Equatable {
    case idle
    case waitingForLogin
    case running
    case paused
    case waitingForDelay(secondsRemaining: Int)
    case processingContact(contactName: String)
    case completed
    case error(message: String)

    var canStart: Bool {
        switch self {
        case .idle, .paused, .completed, .error:
            return true
        default:
            return false
        }
    }

    var canPause: Bool {
        switch self {
        case .running, .waitingForDelay, .processingContact:
            return true
        default:
            return false
        }
    }

    var canResume: Bool {
        self == .paused
    }

    var canStop: Bool {
        switch self {
        case .running, .paused, .waitingForDelay, .processingContact:
            return true
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .waitingForLogin:
            return "Waiting for LinkedIn login..."
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .waitingForDelay(let seconds):
            return "Next message in \(seconds)s"
        case .processingContact(let name):
            return "Processing: \(name)"
        case .completed:
            return "Completed"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var statusColor: String {
        switch self {
        case .idle:
            return "gray"
        case .waitingForLogin:
            return "orange"
        case .running, .processingContact:
            return "blue"
        case .paused:
            return "yellow"
        case .waitingForDelay:
            return "orange"
        case .completed:
            return "green"
        case .error:
            return "red"
        }
    }
}
