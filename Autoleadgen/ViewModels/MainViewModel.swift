import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject {
    // Child ViewModels
    @Published var browserVM: BrowserViewModel
    @Published var contactListVM: ContactListViewModel
    @Published var automationVM: AutomationViewModel
    @Published var loggingService: LoggingService
    @Published var leadsVM: LeadsViewModel
    @Published var leadFinderVM: LeadFinderViewModel
    @Published var testVM: TestViewModel
    @Published var viralPostsVM: ViralPostsViewModel

    // App State
    @Published var isLoggedIn: Bool = false
    @Published var showingFilePicker: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.browserVM = BrowserViewModel()
        self.contactListVM = ContactListViewModel()
        self.automationVM = AutomationViewModel()
        self.loggingService = LoggingService()
        self.leadsVM = LeadsViewModel()
        self.leadFinderVM = LeadFinderViewModel()
        self.testVM = TestViewModel()
        self.viralPostsVM = ViralPostsViewModel()

        setupBindings()
        setupCallbacks()
        loggingService.info("Autoleadgen started")
    }

    private func setupCallbacks() {
        // Wire up AI comparison results from Lead Finder to Test tab
        leadFinderVM.onComparisonResult = { [weak self] result in
            self?.testVM.addResult(result)
        }

        // Wire up leads from Viral Posts to automation queue
        viralPostsVM.onLeadsReady = { [weak self] leads in
            self?.addLeads(leads)
        }
    }

    private func setupBindings() {
        // Observe login state from browser
        browserVM.$isLoggedInToLinkedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoggedIn in
                let wasLoggedIn = self?.isLoggedIn ?? false
                self?.isLoggedIn = isLoggedIn
                if isLoggedIn && !wasLoggedIn {
                    self?.loggingService.info("Logged in to LinkedIn")
                }
            }
            .store(in: &cancellables)

        // Observe automation state changes
        automationVM.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .completed:
                    self?.loggingService.info("Automation completed")
                case .error(let message):
                    self?.loggingService.error("Automation error: \(message)")
                case .paused:
                    self?.loggingService.info("Automation paused")
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func loadExcelFile(from url: URL) async {
        loggingService.info("Loading Excel file: \(url.lastPathComponent)")

        do {
            try await contactListVM.loadLeads(from: url)
            loggingService.info("Loaded \(contactListVM.leads.count) leads")

            let pending = contactListVM.pendingLeads.count
            let sent = contactListVM.sentCount
            loggingService.info("Status: \(pending) pending, \(sent) already sent")
        } catch {
            loggingService.error("Failed to load Excel: \(error.localizedDescription)")
        }
    }

    var canStartAutomation: Bool {
        isLoggedIn &&
        !contactListVM.pendingLeads.isEmpty &&
        automationVM.currentState.canStart
    }

    func startAutomation() {
        guard canStartAutomation else {
            if !isLoggedIn {
                loggingService.warning("Cannot start: Not logged in to LinkedIn")
            } else if contactListVM.pendingLeads.isEmpty {
                loggingService.warning("Cannot start: No pending leads")
            }
            return
        }

        loggingService.info("Starting automation with \(contactListVM.pendingLeads.count) leads")

        automationVM.start(
            leads: contactListVM.pendingLeads,
            webView: browserVM.webView,
            onLeadStarted: { [weak self] lead in
                self?.contactListVM.markAsInProgress(lead)
                self?.loggingService.info("Processing: \(lead.displayName)")
            },
            onLeadCompleted: { [weak self] lead, result in
                switch result {
                case .success:
                    self?.contactListVM.markAsSent(lead)
                    self?.loggingService.info("Sent message to: \(lead.displayName)")
                case .failure(let error):
                    self?.contactListVM.markAsFailed(lead, error: error.localizedDescription)
                    self?.loggingService.error("Failed for \(lead.displayName): \(error.localizedDescription)")
                }
            }
        )
    }

    func pauseAutomation() {
        automationVM.pause()
        loggingService.info("Automation paused")
    }

    func resumeAutomation() {
        automationVM.resume()
        loggingService.info("Automation resumed")
    }

    func stopAutomation() {
        automationVM.stop()
        loggingService.info("Automation stopped")
    }

    // MARK: - Leads Management

    func addLeads(_ leads: [Lead]) {
        for lead in leads {
            // Check if lead already exists
            if !contactListVM.leads.contains(where: {
                $0.linkedInURL.lowercased() == lead.linkedInURL.lowercased()
            }) {
                contactListVM.leads.append(lead)
            }
        }
        loggingService.info("Added \(leads.count) leads to automation queue")
    }
}
