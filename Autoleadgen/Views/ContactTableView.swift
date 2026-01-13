import SwiftUI

struct ContactTableView: View {
    let contacts: [Contact]
    var onResetContact: ((Contact) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Contacts")
                    .font(.headline)
                Spacer()
                Text("\(contacts.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if contacts.isEmpty {
                VStack {
                    Spacer()
                    Text("No contacts loaded")
                        .foregroundColor(.secondary)
                    Text("Select an Excel file to load contacts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Table(contacts) {
                    TableColumn("Status") { contact in
                        HStack(spacing: 4) {
                            Image(systemName: contact.status.systemImage)
                                .foregroundColor(contact.status.displayColor)
                            Text(contact.status.rawValue)
                                .font(.caption)
                        }
                        .frame(width: 80, alignment: .leading)
                    }
                    .width(90)

                    TableColumn("LinkedIn Profile") { contact in
                        Text(contact.displayName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(contact.linkedInURL)
                    }
                    .width(min: 100, ideal: 150)

                    TableColumn("Message Preview") { contact in
                        Text(contact.messageText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(.secondary)
                            .help(contact.messageText)
                    }
                    .width(min: 100, ideal: 200)

                    TableColumn("") { contact in
                        if contact.status == .failed {
                            Button("Retry") {
                                onResetContact?(contact)
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

struct ContactRowView: View {
    let contact: Contact
    var onReset: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: contact.status.systemImage)
                .foregroundColor(contact.status.displayColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .lineLimit(1)

                if let error = contact.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(contact.status.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)

            if contact.status == .failed, let onReset = onReset {
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
