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

        setupBindings()
        loggingService.info("Autoleadgen started")
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
            try await contactListVM.loadContacts(from: url)
            loggingService.info("Loaded \(contactListVM.contacts.count) contacts")

            let pending = contactListVM.pendingContacts.count
            let sent = contactListVM.sentCount
            loggingService.info("Status: \(pending) pending, \(sent) already sent")
        } catch {
            loggingService.error("Failed to load Excel: \(error.localizedDescription)")
        }
    }

    var canStartAutomation: Bool {
        isLoggedIn &&
        !contactListVM.pendingContacts.isEmpty &&
        automationVM.currentState.canStart
    }

    func startAutomation() {
        guard canStartAutomation else {
            if !isLoggedIn {
                loggingService.warning("Cannot start: Not logged in to LinkedIn")
            } else if contactListVM.pendingContacts.isEmpty {
                loggingService.warning("Cannot start: No pending contacts")
            }
            return
        }

        loggingService.info("Starting automation with \(contactListVM.pendingContacts.count) contacts")

        automationVM.start(
            contacts: contactListVM.pendingContacts,
            webView: browserVM.webView,
            onContactStarted: { [weak self] contact in
                self?.contactListVM.markAsInProgress(contact)
                self?.loggingService.info("Processing: \(contact.displayName)")
            },
            onContactCompleted: { [weak self] contact, result in
                switch result {
                case .success:
                    self?.contactListVM.markAsSent(contact)
                    self?.loggingService.info("Sent message to: \(contact.displayName)")
                case .failure(let error):
                    self?.contactListVM.markAsFailed(contact, error: error.localizedDescription)
                    self?.loggingService.error("Failed for \(contact.displayName): \(error.localizedDescription)")
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

    func addLeadsToContacts(_ contacts: [Contact]) {
        for contact in contacts {
            // Check if contact already exists
            if !contactListVM.contacts.contains(where: {
                $0.linkedInURL.lowercased() == contact.linkedInURL.lowercased()
            }) {
                contactListVM.contacts.append(contact)
            }
        }
        loggingService.info("Added \(contacts.count) leads to contacts")
    }
}
