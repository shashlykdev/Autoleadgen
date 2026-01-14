import SwiftUI

struct ContactTableView: View {
    let leads: [Lead]
    var onResetLead: ((Lead) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Automation Queue")
                    .font(.headline)
                Spacer()
                Text("\(leads.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if leads.isEmpty {
                VStack {
                    Spacer()
                    Text("No leads in queue")
                        .foregroundColor(.secondary)
                    Text("Load a CSV file or add leads from Lead Finder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Table(leads) {
                    TableColumn("Status") { lead in
                        HStack(spacing: 4) {
                            Image(systemName: lead.messageStatus.systemImage)
                                .foregroundColor(lead.messageStatus.displayColor)
                            Text(lead.messageStatus.rawValue)
                                .font(.caption)
                        }
                        .frame(width: 80, alignment: .leading)
                    }
                    .width(90)

                    TableColumn("LinkedIn Profile") { lead in
                        Text(lead.displayName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(lead.linkedInURL)
                    }
                    .width(min: 100, ideal: 150)

                    TableColumn("Message Preview") { lead in
                        Text(lead.effectiveMessage)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(.secondary)
                            .help(lead.effectiveMessage)
                    }
                    .width(min: 100, ideal: 200)

                    TableColumn("") { lead in
                        if lead.messageStatus == .failed {
                            Button("Retry") {
                                onResetLead?(lead)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .width(50)
                }
                .tableStyle(.bordered)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct AutomationQueueRowView: View {
    let lead: Lead
    var onReset: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: lead.messageStatus.systemImage)
                .foregroundColor(lead.messageStatus.displayColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(lead.displayName)
                    .lineLimit(1)

                if let error = lead.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(lead.messageStatus.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)

            if lead.messageStatus == .failed, let onReset = onReset {
                Button("Retry") {
                    onReset()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
