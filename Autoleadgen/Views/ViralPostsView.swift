import SwiftUI

struct ViralPostsView: View {
    @ObservedObject var viewModel: ViralPostsViewModel
    let onAddToContacts: ([Lead]) -> Void

    @State private var connectionNote: String = ""
    @State private var showConnectionNoteSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                contentSourceSection
                if !viewModel.posts.isEmpty {
                    postsListSection
                }
                if viewModel.selectedPost != nil {
                    contentGenerationSection
                }
                if viewModel.selectedPost?.isLinkedInPost == true {
                    engagementSection
                }
                if viewModel.hasEngagers {
                    engagersSection
                }
                if !viewModel.statusMessage.isEmpty {
                    statusSection
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.onLeadsReady = onAddToContacts
        }
        .sheet(isPresented: $showConnectionNoteSheet) {
            connectionNoteSheet
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Viral Posts")
                    .font(.headline)
                Text(viewModel.currentPhase.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)

                Button("Stop") {
                    viewModel.stop()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Button("Clear All") {
                viewModel.clearAll()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isProcessing)
        }
    }

    // MARK: - Content Source Section (Tabs)

    private var contentSourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 1: Content Source")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("", selection: $viewModel.selectedSourceTab) {
                Text("From URLs").tag(ContentSourceTab.urls)
                Text("From Topics").tag(ContentSourceTab.topics)
            }
            .pickerStyle(.segmented)

            if viewModel.selectedSourceTab == .urls {
                urlInputSection
            } else {
                topicsInputSection
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste URLs (one per line)")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $viewModel.urlInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            Text("Supports: LinkedIn posts, Twitter/X, any website")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Extract Content") {
                    viewModel.extractContent()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExtractURLs)

                Spacer()

                if viewModel.currentPhase == .extractingContent {
                    Text("\(viewModel.progressCurrent)/\(viewModel.progressTotal)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var topicsInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter topics to generate posts about (one per line)")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $viewModel.topicsInput)
                .font(.system(.body))
                .frame(minHeight: 80, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            Text("Examples: AI in sales, leadership lessons, startup growth tips")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Generate Posts") {
                    viewModel.generateFromTopics()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canGenerateFromTopics)

                Spacer()

                if viewModel.currentPhase == .generatingContent {
                    Text("\(viewModel.progressCurrent)/\(viewModel.progressTotal)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Posts List Section

    private var postsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Posts (\(viewModel.posts.count))")
                .font(.subheadline)
                .fontWeight(.medium)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.posts) { post in
                        PostCard(
                            post: post,
                            isSelected: viewModel.selectedPost?.id == post.id,
                            onSelect: { viewModel.selectedPost = post },
                            onDelete: { viewModel.deletePost(post) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Content Generation Section

    private var contentGenerationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 2: Generate & Refine Content")
                .font(.subheadline)
                .fontWeight(.medium)

            // User Voice Style
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Writing Style (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $viewModel.userVoiceStyle)
                    .font(.system(.body))
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                HStack {
                    Text("Paste a sample of your writing for the AI to match your tone")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Save Style") {
                        viewModel.saveUserVoice()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            // Action Buttons
            HStack {
                if viewModel.canRewrite {
                    Button("Rewrite") {
                        Task { await viewModel.rewriteSelected() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Regenerate") {
                    Task { await viewModel.regenerateSelected() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedPost == nil || viewModel.isProcessing)

                Button("Generate Reply") {
                    Task { await viewModel.generateReply() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedPost == nil || viewModel.isProcessing)

                Spacer()

                Button("Copy") {
                    viewModel.copyToClipboard()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedPost?.generatedContent == nil && viewModel.selectedPost?.originalContent.isEmpty != false)
            }

            // Content Preview
            if let post = viewModel.selectedPost {
                VStack(alignment: .leading, spacing: 8) {
                    if let generated = post.generatedContent {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Generated Content")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(generated.count) chars")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(generated)
                                .font(.body)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }

                    if !post.originalContent.isEmpty && post.generatedContent != nil {
                        DisclosureGroup("Original Content") {
                            Text(post.originalContent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                        }
                    } else if !post.originalContent.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Original Content")
                                .font(.caption)
                                .fontWeight(.medium)

                            Text(post.originalContent)
                                .font(.body)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Engagement Section

    private var engagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 3: Scrape Engagement (LinkedIn only)")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                Button("Scrape Likers & Commenters") {
                    viewModel.scrapeEngagement()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canScrapeEngagement)

                Spacer()

                if viewModel.currentPhase == .scrapingEngagement {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // ICP Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("ICP Filter (optional)")
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include keywords:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextField("CEO, Founder, Director...", text: $viewModel.icpKeywordsText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.icpKeywordsText) { _, _ in
                                viewModel.updateICPFilter()
                            }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exclude keywords:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextField("Student, Intern...", text: $viewModel.icpExcludeKeywordsText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.icpExcludeKeywordsText) { _, _ in
                                viewModel.updateICPFilter()
                            }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Engagers Section

    private var engagersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Step 4: Connect with Engagers")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(viewModel.filteredEngagers.count) of \(viewModel.engagers.count) match ICP")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Select All Matching") {
                    viewModel.selectAllFiltered()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Deselect All") {
                    viewModel.deselectAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if !viewModel.selectedEngagers.isEmpty {
                    Text("\(viewModel.selectedEngagers.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.filteredEngagers) { engager in
                        EngagerRow(
                            engager: engager,
                            isSelected: viewModel.selectedEngagers.contains(engager.id),
                            onToggle: { viewModel.toggleEngagerSelection(engager) }
                        )
                    }
                }
            }
            .frame(maxHeight: 250)

            HStack {
                Button("Add to Leads") {
                    viewModel.addSelectedToLeads()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedEngagers.isEmpty)

                Button("Connect with Selected") {
                    showConnectionNoteSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedEngagers.isEmpty || viewModel.isProcessing)

                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack {
            Image(systemName: viewModel.isProcessing ? "hourglass" : "checkmark.circle")
                .foregroundColor(viewModel.isProcessing ? .blue : .green)

            Text(viewModel.statusMessage)
                .font(.caption)

            if viewModel.isProcessing && viewModel.progressTotal > 0 {
                Spacer()
                ProgressView(value: Double(viewModel.progressCurrent), total: Double(viewModel.progressTotal))
                    .frame(width: 100)
            }

            Spacer()
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }

    // MARK: - Connection Note Sheet

    private var connectionNoteSheet: some View {
        VStack(spacing: 16) {
            Text("Connection Request Note")
                .font(.headline)

            Text("Add a personalized note to your connection requests (optional)")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $connectionNote)
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            Text("LinkedIn limits notes to 300 characters")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") {
                    showConnectionNoteSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Start Connecting") {
                    showConnectionNoteSheet = false
                    viewModel.connectWithSelected(note: connectionNote.isEmpty ? nil : connectionNote)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Post Card

struct PostCard: View {
    let post: ViralPost
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(post.platform.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(platformColor.opacity(0.2))
                    .foregroundColor(platformColor)
                    .cornerRadius(4)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Text(post.displayTitle)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            if post.hasEngagementData {
                HStack(spacing: 6) {
                    if let likes = post.likeCount, likes > 0 {
                        Label("\(likes)", systemImage: "hand.thumbsup")
                            .font(.caption2)
                    }
                    if let comments = post.commentCount, comments > 0 {
                        Label("\(comments)", systemImage: "bubble.left")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)
            }

            Text((post.generatedContent ?? post.originalContent).prefix(60) + "...")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if post.generatedContent != nil {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Generated")
                        .foregroundColor(.green)
                }
                .font(.caption2)
            }
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture(perform: onSelect)
    }

    private var platformColor: Color {
        switch post.platform {
        case .linkedin: return .blue
        case .twitter: return .cyan
        case .website: return .orange
        case .topic: return .purple
        case .other: return .gray
        }
    }
}

// MARK: - Engager Row

struct EngagerRow: View {
    let engager: PostEngager
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(engager.name)
                        .font(.caption)
                        .fontWeight(.medium)

                    Image(systemName: engager.engagementType.icon)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let degree = engager.connectionDegree {
                        Text(degree)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let headline = engager.headline {
                    Text(headline)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let matches = engager.matchesICP {
                Image(systemName: matches ? "checkmark.seal.fill" : "xmark")
                    .foregroundColor(matches ? .green : .red)
                    .font(.caption)
            }

            Text(engager.connectionStatus.rawValue)
                .font(.caption2)
                .foregroundColor(connectionStatusColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(4)
    }

    private var connectionStatusColor: Color {
        switch engager.connectionStatus {
        case .notConnected: return .secondary
        case .pending: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }
}
