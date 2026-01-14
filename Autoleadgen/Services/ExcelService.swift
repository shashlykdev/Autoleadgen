import Foundation

@MainActor
final class ExcelService {

    /// Loads leads from a CSV file
    /// Expected format: FirstName, LastName, LinkedIn URL, Message Text, Status (optional)
    /// First row is treated as header and skipped
    func loadLeads(from url: URL) async throws -> [Lead] {
        // Request access to the file
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "csv":
            return try await loadFromCSV(url: url)
        case "xlsx":
            throw AppError.invalidFileFormat("XLSX support requires CoreXLSX package. Please use CSV format.")
        default:
            throw AppError.invalidFileFormat("Unsupported file format: \(fileExtension). Use CSV files.")
        }
    }

    private func loadFromCSV(url: URL) async throws -> [Lead] {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppError.fileNotFound(url.path)
        }

        var leads: [Lead] = []
        let lines = content.components(separatedBy: .newlines)

        // Skip header row (index 0)
        for (index, line) in lines.enumerated() where index > 0 {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let columns = parseCSVLine(trimmedLine)

            // Expected format: FirstName, LastName, LinkedIn URL, Message, Status (optional)
            // Minimum 4 columns required (firstName, lastName, URL, message)
            guard columns.count >= 4 else { continue }

            let firstName = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let lastName = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let linkedInURL = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let messageText = columns[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let statusText = columns.count > 4 ? columns[4].trimmingCharacters(in: .whitespacesAndNewlines) : ""

            guard !linkedInURL.isEmpty else { continue }

            let messageStatus = MessageStatus(rawValue: statusText) ?? .pending

            let lead = Lead(
                firstName: firstName,
                lastName: lastName,
                linkedInURL: linkedInURL,
                source: "CSV Import",
                messageStatus: messageStatus,
                messageText: messageText,
                rowIndex: index + 1  // 1-based row number
            )
            leads.append(lead)
        }

        return leads
    }

    /// Parses a CSV line, handling quoted fields with commas
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)

        return result
    }
}
