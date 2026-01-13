import SwiftUI

/// View for displaying scraped leads before adding to contacts
struct ScrapedResultsView: View {
    let leads: [ScrapedLead]
    let onOpenProfile: ((ScrapedLead) -> Void)?

    init(leads: [ScrapedLead], onOpenProfile: ((ScrapedLead) -> Void)? = nil) {
        self.leads = leads
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Scraped Leads")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(leads.count) leads")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Leads List
            if leads.isEmpty {
                emptyState
            } else {
                leadsList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "person.3")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("No leads scraped yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 20)
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Leads List

    private var leadsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(leads) { lead in
                    leadRow(lead)
                }
            }
        }
        .frame(maxHeight: 200)
    }

    private func leadRow(_ lead: ScrapedLead) -> some View {
        HStack {
            // Lead Info
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.fullName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let title = lead.title, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let company = lead.company, !company.isEmpty {
                    Text(company)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Open Profile Button
            if let url = URL(string: lead.linkedInURL) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.blue)
                }
                .help("Open LinkedIn profile")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .onTapGesture {
            onOpenProfile?(lead)
        }
    }
}

// MARK: - Summary Row

struct ScrapedResultsSummary: View {
    let newLeadsCount: Int
    let duplicatesSkipped: Int
    var savedToLeadsCount: Int = 0

    var body: some View {
        HStack(spacing: 16) {
            Label("\(newLeadsCount) new", systemImage: "person.badge.plus")
                .foregroundColor(.green)

            if savedToLeadsCount > 0 {
                Label("\(savedToLeadsCount) saved", systemImage: "square.and.arrow.down")
                    .foregroundColor(.blue)
            }

            Label("\(duplicatesSkipped) duplicates", systemImage: "doc.on.doc")
                .foregroundColor(.orange)

            Spacer()
        }
        .font(.subheadline)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ScrapedResultsView(leads: [
            ScrapedLead(
                firstName: "John",
                lastName: "Doe",
                linkedInURL: "https://linkedin.com/in/johndoe",
                title: "CEO at Tech Corp"
            ),
            ScrapedLead(
                firstName: "Jane",
                lastName: "Smith",
                linkedInURL: "https://linkedin.com/in/janesmith",
                title: "VP of Engineering",
                company: "StartupXYZ"
            )
        ])

        ScrapedResultsSummary(newLeadsCount: 15, duplicatesSkipped: 3)
    }
    .padding()
}
