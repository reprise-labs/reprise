import SwiftUI
import AppKit
import UserNotifications
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Same pattern as StatusItemController.shared — SettingsView's About tab reaches the
    /// updater through this to trigger a manual check and drive its "Last checked" label.
    static var shared: AppDelegate?

    private let statusItemController = StatusItemController()

    /// Owns Sparkle's updater for the whole app's lifetime. `startingUpdater: true` makes it
    /// begin its own periodic background check immediately (interval set by
    /// SUScheduledCheckInterval in Info.plist) — replaces the hand-rolled GitHub-releases
    /// polling + custom progress UI that used to live in MonitorEngine/SettingsView (removed
    /// 11-10-2026). Sparkle's own native alerts (release notes, Skip/Remind Later/Install,
    /// download + relaunch progress) are what xACT and most other non-App-Store Mac apps use —
    /// this gets Reprise the same well-understood flow instead of a custom one buried in
    /// Settings that only checked when a user happened to go looking for it.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // SwiftUI sometimes automatically opens an empty window for the app's only
        // (Settings) Scene. Close it synchronously right away, before it becomes visible.
        NSApp.windows.forEach { $0.close() }

        // One-time ask so notify() can show a local banner alongside every Pushover push —
        // fire-and-forget: if denied, sendLocalNotification's UNUserNotificationCenter call
        // just quietly does nothing per-notification, Pushover still goes out regardless.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        guard Store.acquireSingleInstanceLock() else {
            // An instance is already running: stop immediately, never run two at once
            // (prevents one from overwriting the other's saved videos).
            NSApp.terminate(nil)
            return
        }
        let engine = MonitorEngine.shared
        statusItemController.setup()

        // Reprise is a menu-bar-only app (no Dock icon): on a normal launch nothing ever
        // pops up on screen, so a blocked permission would otherwise sit invisible behind
        // the menu bar icon until someone happens to click it. Force the window open right
        // away so a permission problem is impossible to miss.
        if engine.permissionWarnings["download-folder"] != nil || engine.permissionWarnings["cookie-access"] != nil
            || engine.permissionWarnings["external-tools"] != nil {
            statusItemController.showMainWindow()
        }
    }

    /// macOS calls this on "reopen" (among other things, when the app briefly becomes
    /// .regular to get keyboard focus). Without this function, SwiftUI falls back to its own
    /// default behavior: opening the only Scene (our empty Settings scene) when there's no
    /// visible window. Implementing it ourselves and showing our own window prevents that.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            statusItemController.showMainWindow()
        }
        return true
    }
}

// Build with install.sh, not a plain `swift build` + manual copy — it signs with the
// "Encore Local Signing" identity in the login keychain instead of an ad-hoc signature
// (kept that name from before the app was renamed to Reprise — it's an internal signing
// identity, never user-visible, so renaming it would just mean redoing the one-time
// keychain trust step for no real benefit). Ad-hoc signing hashes the binary's own
// content, so it changes on every rebuild and macOS resets Full Disk Access for what
// looks like a brand new app each time.
@main
struct RepriseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Without this, the standard app-menu "Settings…" item (and its Cmd+,
            // shortcut) opens the EmptyView() placeholder scene above instead of the
            // real settings window StatusItemController manages — a blank window with
            // no content. Redirects it to the same window the gear-icon button opens.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    StatusItemController.shared?.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
        }
    }
}

/// Wraps Sparkle's `canCheckForUpdates` publisher so the menu item disables itself while a
/// check is already in progress — Sparkle's own `CheckForUpdatesViewModel` pattern, just
/// inlined here since this is the only place that needs it.
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
