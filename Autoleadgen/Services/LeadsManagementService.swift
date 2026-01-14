import Foundation

@MainActor
final class LeadsManagementService {
    private var leads: [Lead] = []
    private let storageKey = "autoleadgen_leads"
    private let fileManager = FileManager.default

    private var leadsFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("leads.json")
    }

    // MARK: - Load & Save

    func loadLeads() async -> [Lead] {
        do {
            let data = try Data(contentsOf: leadsFileURL)
            leads = try JSONDecoder().decode([Lead].self, from: data)
        } catch {
            // Try loading from UserDefaults as fallback
            if let data = UserDefaults.standard.data(forKey: storageKey),
               let savedLeads = try? JSONDecoder().decode([Lead].self, from: data) {
                leads = savedLeads
            }
        }
        return leads
    }

    func saveLeads() async {
        do {
            let data = try JSONEncoder().encode(leads)
            try data.write(to: leadsFileURL)
            // Also save to UserDefaults as backup
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Silent fail - data will be in memory
        }
    }

    // MARK: - CRUD Operations

    func addLead(_ lead: Lead) async -> Lead {
        var newLead = lead
        newLead = Lead(
            id: UUID(),
            firstName: lead.firstName,
            lastName: lead.lastName,
            linkedInURL: lead.linkedInURL,
            email: lead.email,
            phone: lead.phone,
            company: lead.company,
            title: lead.title,
            location: lead.location,
            notes: lead.notes,
            tags: lead.tags,
            status: lead.status,
            source: lead.source,
            generatedMessage: lead.generatedMessage,
            createdAt: Date(),
            updatedAt: Date(),
            lastContactedAt: lead.lastContactedAt,
            headline: lead.headline,
            about: lead.about,
            education: lead.education,
            connectionDegree: lead.connectionDegree,
            followerCount: lead.followerCount
        )
        leads.append(newLead)
        await saveLeads()
        return newLead
    }

    func addLeads(_ newLeads: [Lead]) async -> [Lead] {
        var addedLeads: [Lead] = []
        for lead in newLeads {
            // Check for duplicates by normalized URL
            if !leads.contains(where: { $0.normalizedURL == lead.normalizedURL }) {
                let added = await addLead(lead)
                addedLeads.append(added)
            }
        }
        return addedLeads
    }

    func updateLead(_ lead: Lead) async {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            var updatedLead = lead
            updatedLead = Lead(
                id: lead.id,
                firstName: lead.firstName,
                lastName: lead.lastName,
                linkedInURL: lead.linkedInURL,
                email: lead.email,
                phone: lead.phone,
                company: lead.company,
                title: lead.title,
                location: lead.location,
                notes: lead.notes,
                tags: lead.tags,
                status: lead.status,
                source: lead.source,
                generatedMessage: lead.generatedMessage,
                createdAt: lead.createdAt,
                updatedAt: Date(),
                lastContactedAt: lead.lastContactedAt,
                headline: lead.headline,
                about: lead.about,
                education: lead.education,
                connectionDegree: lead.connectionDegree,
                followerCount: lead.followerCount
            )
            leads[index] = updatedLead
            await saveLeads()
        }
    }

    func deleteLead(_ lead: Lead) async {
        leads.removeAll { $0.id == lead.id }
        await saveLeads()
    }

    func deleteLeads(_ leadsToDelete: [Lead]) async {
        let idsToDelete = Set(leadsToDelete.map { $0.id })
        leads.removeAll { idsToDelete.contains($0.id) }
        await saveLeads()
    }

    // MARK: - Queries

    func getAllLeads() -> [Lead] {
        leads
    }

    func getLeadsByStatus(_ status: LeadStatus) -> [Lead] {
        leads.filter { $0.status == status }
    }

    func getLeadsByTag(_ tag: String) -> [Lead] {
        leads.filter { $0.tags.contains(tag) }
    }

    func searchLeads(query: String) -> [Lead] {
        let lowercasedQuery = query.lowercased()
        return leads.filter {
            $0.firstName.lowercased().contains(lowercasedQuery) ||
            $0.lastName.lowercased().contains(lowercasedQuery) ||
            ($0.company?.lowercased().contains(lowercasedQuery) ?? false) ||
            ($0.title?.lowercased().contains(lowercasedQuery) ?? false) ||
            ($0.email?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }

    func isDuplicate(url: String) -> Bool {
        let normalizedURL = url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return leads.contains { $0.normalizedURL == normalizedURL }
    }

    // MARK: - Tags

    func getAllTags() -> [String] {
        Array(Set(leads.flatMap { $0.tags })).sorted()
    }

    func addTag(_ tag: String, to lead: Lead) async {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            var updatedLead = leads[index]
            if !updatedLead.tags.contains(tag) {
                updatedLead = Lead(
                    id: updatedLead.id,
                    firstName: updatedLead.firstName,
                    lastName: updatedLead.lastName,
                    linkedInURL: updatedLead.linkedInURL,
                    email: updatedLead.email,
                    phone: updatedLead.phone,
                    company: updatedLead.company,
                    title: updatedLead.title,
                    location: updatedLead.location,
                    notes: updatedLead.notes,
                    tags: updatedLead.tags + [tag],
                    status: updatedLead.status,
                    source: updatedLead.source,
                    generatedMessage: updatedLead.generatedMessage,
                    createdAt: updatedLead.createdAt,
                    updatedAt: Date(),
                    lastContactedAt: updatedLead.lastContactedAt,
                    headline: updatedLead.headline,
                    about: updatedLead.about,
                    education: updatedLead.education,
                    connectionDegree: updatedLead.connectionDegree,
                    followerCount: updatedLead.followerCount
                )
                leads[index] = updatedLead
                await saveLeads()
            }
        }
    }

    // MARK: - Import/Export

    func exportToCSV() -> String {
        var csv = "FirstName,LastName,LinkedIn URL,Email,Phone,Company,Title,Location,Status,Tags,Notes\n"

        for lead in leads {
            let row = [
                escapeCSV(lead.firstName),
                escapeCSV(lead.lastName),
                escapeCSV(lead.linkedInURL),
                escapeCSV(lead.email ?? ""),
                escapeCSV(lead.phone ?? ""),
                escapeCSV(lead.company ?? ""),
                escapeCSV(lead.title ?? ""),
                escapeCSV(lead.location ?? ""),
                escapeCSV(lead.status.rawValue),
                escapeCSV(lead.tags.joined(separator: ";")),
                escapeCSV(lead.notes ?? "")
            ].joined(separator: ",")

            csv += row + "\n"
        }

        return csv
    }

    func importFromCSV(_ content: String) async -> [Lead] {
        var importedLeads: [Lead] = []
        let lines = content.components(separatedBy: .newlines)

        // Skip header
        for (index, line) in lines.enumerated() where index > 0 {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let columns = parseCSVLine(trimmedLine)
            guard columns.count >= 3 else { continue }

            let firstName = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let lastName = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let linkedInURL = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !linkedInURL.isEmpty else { continue }

            let lead = Lead(
                firstName: firstName,
                lastName: lastName,
                linkedInURL: linkedInURL,
                email: columns.count > 3 ? columns[3].trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                phone: columns.count > 4 ? columns[4].trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                company: columns.count > 5 ? columns[5].trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                title: columns.count > 6 ? columns[6].trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                location: columns.count > 7 ? columns[7].trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                status: columns.count > 8 ? LeadStatus(rawValue: columns[8]) ?? .new : .new,
                source: "CSV Import"
            )

            importedLeads.append(lead)
        }

        return await addLeads(importedLeads)
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

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

    // MARK: - Statistics

    func getStatistics() -> LeadsStatistics {
        LeadsStatistics(
            total: leads.count,
            new: leads.filter { $0.status == .new }.count,
            contacted: leads.filter { $0.status == .contacted }.count,
            responded: leads.filter { $0.status == .responded }.count,
            converted: leads.filter { $0.status == .converted }.count,
            notInterested: leads.filter { $0.status == .notInterested }.count
        )
    }
}

struct LeadsStatistics {
    let total: Int
    let new: Int
    let contacted: Int
    let responded: Int
    let converted: Int
    let notInterested: Int

    var conversionRate: Double {
        guard total > 0 else { return 0 }
        return Double(converted) / Double(total) * 100
    }

    var responseRate: Double {
        guard contacted > 0 else { return 0 }
        return Double(responded + converted) / Double(contacted) * 100
    }
}
