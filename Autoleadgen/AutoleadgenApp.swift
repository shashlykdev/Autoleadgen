//
//  AutoleadgenApp.swift
//  Autoleadgen
//
//  Created by Cuong Pham on 13.01.2026.
//

import SwiftUI
import AppKit

@main
struct AutoleadgenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}

// MARK: - App Delegate for Background Execution

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable background execution - app continues running when minimized
        NSApp.setActivationPolicy(.regular)

        // Disable App Nap to prevent system from suspending the app
        ProcessInfo.processInfo.disableAutomaticTermination("Automation in progress")
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "LinkedIn automation running"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false to keep app running when window is closed
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
