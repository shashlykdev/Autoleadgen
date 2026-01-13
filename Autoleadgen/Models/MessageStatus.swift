import SwiftUI

enum MessageStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case sent = "Sent"
    case failed = "Failed"
    case skipped = "Skipped"

    var displayColor: Color {
        switch self {
        case .pending: return .gray
        case .inProgress: return .blue
        case .sent: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .sent: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "forward.fill"
        }
    }
}
