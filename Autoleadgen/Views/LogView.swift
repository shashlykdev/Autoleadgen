import SwiftUI

struct LogView: View {
    @ObservedObject var loggingService: LoggingService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity Log")
                    .font(.headline)

                Spacer()

                Button(action: { loggingService.clear() }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear log")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(loggingService.entries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: loggingService.entries.count) {
                    if let lastEntry = loggingService.entries.last {
                        withAnimation {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.formattedTimestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Image(systemName: entry.level.icon)
                .foregroundColor(entry.level.color)
                .frame(width: 16)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(entry.level.color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
