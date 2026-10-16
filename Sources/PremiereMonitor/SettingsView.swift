import SwiftUI
import AppKit
import ServiceManagement
import Sparkle

struct SettingsView: View {
    @ObservedObject private var engine = MonitorEngine.shared

    @State private var checkLeadMinutes: Double
    @State private var vodWaitMinutes: Double
    @State private var failureCooldownMinutes: Double
    @State private var customDownloadPath: String
    @State private var lowDiskThresholdGB: Double
    @State private var showDockIcon: Bool
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var startAtLoginNote: String?
    @State private var minimalMenuBarIcon: Bool
    @State private var cookieBrowserPreference: String
    @State private var defaultQuality: VideoQuality
    @State private var pushoverToken: String
    @State private var pushoverUserKey: String
    @State private var showPushoverToken = false
    @State private var showPushoverUserKey = false

    @State private var newChannelURL = ""

    @State private var isTestingNotification = false
    @State private var notificationTestResult: String?
    @State private var notificationTestSucceeded = false

    @State private var isTestingCookies = false
    @State private var cookieTestResult: String?
    @State private var cookieTestSucceeded = false

    private enum SettingsTab: String, CaseIterable {
        case general = "General", monitoring = "Monitoring", channels = "Channels", cookies = "Cookies",
             quality = "Quality", notifications = "Notifications", about = "About"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .monitoring: return "clock"
            case .channels: return "person.2"
            case .cookies: return "globe"
            case .quality: return "slider.horizontal.3"
            case .notifications: return "bell"
            case .about: return "info.circle"
            }
        }
    }
    @State private var selectedTab: SettingsTab = .general

    @State private var logCopied = false
    @State private var automaticallyChecksForUpdates: Bool

    init() {
        let s = MonitorEngine.shared.settings
        _checkLeadMinutes = State(initialValue: s.checkLeadMinutes)
        _vodWaitMinutes = State(initialValue: s.vodWaitMinutes)
        _failureCooldownMinutes = State(initialValue: s.failureCooldownMinutes)
        _customDownloadPath = State(initialValue: s.customDownloadPath ?? "")
        _lowDiskThresholdGB = State(initialValue: s.lowDiskThresholdGB ?? 5)
        _showDockIcon = State(initialValue: s.showDockIcon ?? false)
        _minimalMenuBarIcon = State(initialValue: s.minimalMenuBarIcon ?? true)
        _cookieBrowserPreference = State(initialValue: s.cookieBrowserPreference ?? "auto")
        _defaultQuality = State(initialValue: s.defaultQualityResolved)
        _pushoverToken = State(initialValue: s.pushoverToken ?? "")
        _pushoverUserKey = State(initialValue: s.pushoverUserKey ?? "")
        _automaticallyChecksForUpdates = State(
            initialValue: AppDelegate.shared?.updaterController.updater.automaticallyChecksForUpdates ?? true
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 16)

            // A hand-rolled tab strip instead of SwiftUI's TabView: on macOS 26, TabView
            // tries to integrate tabs into the title bar and collapses into a hidden ">>"
            // overflow menu when that doesn't fit cleanly in a plain AppKit-hosted window
            // like this one — found 27-09-2026, the tabs were invisible except via that
            // chevron. A plain row of buttons has no such adaptive behavior to fight.
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15))
                            Text(tab.rawValue)
                                .font(.system(size: 12))
                                // Was wrapping "Notifications" onto its own second line once
                                // the Channels tab brought the total to 6 — each tab's share of
                                // the fixed-width strip got too narrow for its longest label at
                                // 12pt (01-10-2026). Shrinking instead of wrapping keeps every
                                // tab's label on one line regardless of how many tabs there are.
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .animation(.easeInOut(duration: 0.2), value: selectedTab)
                        // Without this, .buttonStyle(.plain) only makes the icon/text glyphs
                        // themselves clickable, not the padded/colored area around them —
                        // exactly the "have to click precisely on the icon" symptom.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .general: generalTab
                    case .monitoring: monitoringTab
                    case .channels: channelsTab
                    case .cookies: cookiesTab
                    case .quality: qualityTab
                    case .notifications: notificationsTab
                    case .about: aboutTab
                    }
                }
                // Without this, a tab whose content is all short Text/Button views (no
                // full-width TextField or Picker to stretch it) sizes to its own narrow
                // intrinsic width inside the ScrollView and then sits centered in the
                // leftover space — Monitoring and About looked "randomly centered"
                // while General/Channels/Cookies/Notifications looked fine purely by
                // accident, because something in each of those already happened to be
                // wide enough to fill the row (user feedback, 03-10-2026).
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            // Tried .scrollDisabled(selectedTab == .about) here (03-10-2026) to kill the
            // pointless rubber-band bounce on a tab that's supposed to always fit — but
            // disabling scroll doesn't just stop the bounce, it also removes the only way
            // to reach anything that doesn't quite fit. Content that's "supposed to fit"
            // isn't a hard guarantee (font rendering, a long update-available string,
            // whatever) — on this exact machine it turned out About's real content still
            // slightly exceeded 480pt once the window-height bug below was fixed, and with
            // scrolling off "Copy log to clipboard" became permanently unreachable with no
            // scrollbar to even hint it was there. Worse than the bounce it was meant to
            // fix, so reverted — scrolling stays enabled on every tab, always.

            Divider()
            HStack {
                Spacer()
                Button("Close") {
                    StatusItemController.shared?.closeSettingsWindow()
                }
                Button("Save") {
                    save()
                    StatusItemController.shared?.closeSettingsWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        // minWidth, not a flat width: the window itself is declared .resizable (see
        // showSettingsWindow) so a user can drag it wider — a flat width here fought that,
        // leaving the dragged-out window frame with dead empty space on the right while the
        // content stayed pinned at 460 (found during a UI audit, 11-10-2026). minWidth keeps
        // the original "was a flat 640 regardless of tab, short tabs left a dead gap above
        // Close/Save" fix (each tab's own ScrollView still caps comfortably at content size)
        // while letting the window actually use extra width if the user asks for it.
        .frame(minWidth: 460)
        .frame(maxHeight: 480)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Menu bar icon")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    iconLegendItem(color: .red, label: "Problem")
                    iconLegendItem(color: .blue, label: "Downloading")
                    iconLegendItem(color: minimalMenuBarIcon ? .primary : .green, label: "All good")
                }
                Toggle("Only color the icon for problems or downloads", isOn: $minimalMenuBarIcon)
                    .help("On (default): the icon blends into the menu bar when everything's fine, "
                        + "only turning red or blue when something needs attention. Off: always green "
                        + "when idle and healthy, like before.")
            }

            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .help("Off (default): menu bar only, no Dock icon. On: also keeps a permanent Dock icon, "
                    + "not just while a window happens to be open.")

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Start at login", isOn: $startAtLogin)
                    .help("Automatically launches Reprise in the background when you log in to your Mac.")
                    .onChange(of: startAtLogin) { _, wantsEnabled in setStartAtLogin(wantsEnabled) }
                if let startAtLoginNote {
                    Text(startAtLoginNote)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Download location")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack {
                    Text(customDownloadPath.isEmpty ? "Default: ~/Downloads/Reprise" : customDownloadPath)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                    if !customDownloadPath.isEmpty {
                        Button("Default") { customDownloadPath = "" }
                    }
                }
            }
        }
    }

    private var monitoringTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start checking (minutes before scheduled time)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Stepper(value: $checkLeadMinutes, in: 1...120, step: 1) {
                    Text("\(Int(checkLeadMinutes)) minutes")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Check interval while waiting for VOD (minutes)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Stepper(value: $vodWaitMinutes, in: 0.5...30, step: 0.5) {
                    Text("every \(vodWaitMinutes.formatted()) minutes")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Minimum time between failure notifications (minutes)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Stepper(value: $failureCooldownMinutes, in: 1...60, step: 1) {
                    Text("\(Int(failureCooldownMinutes)) minutes")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Warn when free disk space drops below (GB)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Stepper(value: $lowDiskThresholdGB, in: 1...100, step: 1) {
                    Text("\(Int(lowDiskThresholdGB)) GB")
                }
            }
        }
    }

    private var channelsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Watch a channel for new premieres")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text("Checked once a day. Found premieres show up in the main window for you "
                    + "to add with one click — no need to go find the URL on YouTube yourself.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Channel URL or @handle", text: $newChannelURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addChannel)
                    Button("Add", action: addChannel)
                        .disabled(newChannelURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if engine.channels.isEmpty {
                Text("No channels watched yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(engine.channels) { channel in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name ?? channel.url)
                                    .font(.system(size: 13, weight: .medium))
                                if let lastChecked = channel.lastChecked {
                                    Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not checked yet")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                engine.checkChannelNow(channel)
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .help("Check this channel now")
                            .accessibilityLabel("Check this channel now")
                            Button {
                                engine.removeChannel(channel)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .help("Stop watching this channel")
                            .accessibilityLabel("Stop watching this channel")
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
    }

    private func addChannel() {
        let trimmed = newChannelURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if engine.addChannel(url: trimmed) {
            newChannelURL = ""
        }
    }

    private var cookiesTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Read YouTube login cookies from")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Picker("", selection: $cookieBrowserPreference) {
                    Text("Automatic (Chrome, then Safari)").tag("auto")
                    Text("Chrome").tag("chrome")
                    Text("Safari").tag("safari")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Text("Only matters if you have both installed but are only logged into "
                    + "YouTube in one of them — Automatic always prefers Chrome.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostics")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await testCookies() }
                    } label: {
                        if isTestingCookies {
                            ProgressView().controlSize(.small).frame(width: 14, height: 14)
                        } else {
                            Text("Test YouTube login")
                        }
                    }
                    .disabled(isTestingCookies)

                    Button("Log in to YouTube again") {
                        engine.openYouTubeLogin()
                    }
                    .help("Opens YouTube in your cookie browser. Log in there, then run the "
                          + "test again.")
                }
                if let cookieTestResult {
                    Text(cookieTestResult)
                        .font(.system(size: 12))
                        .foregroundStyle(cookieTestSucceeded ? .green : .orange)
                }
            }
        }
    }

    private var qualityTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Default quality for new premieres")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Picker("", selection: $defaultQuality) {
                    if engine.settings.youtubePremiumConfirmed == true {
                        Text(VideoQuality.premium.displayName).tag(VideoQuality.premium)
                    }
                    ForEach(VideoQuality.allCases.filter { $0 != .premium }) { q in
                        Text(q.displayName).tag(q)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200)
                Text("Always changeable per premiere in the Add screen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("1080p Premium only appears on some videos, and only with a Premium "
                    + "account — picking it elsewhere just downloads as Best available.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The exact quality list only shows once a video is a finished VOD — "
                    + "before that, every option is offered and resolved for real at download time.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pushover credentials")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text("Optional — push notifications when you're away from this Mac. Get your "
                    + "keys at pushover.net.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Application token").font(.system(size: 12)).foregroundStyle(.secondary)
                    credentialField("Application token", text: $pushoverToken, revealed: $showPushoverToken)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("User key").font(.system(size: 12)).foregroundStyle(.secondary)
                    credentialField("User key", text: $pushoverUserKey, revealed: $showPushoverUserKey)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    testNotification()
                } label: {
                    if isTestingNotification {
                        ProgressView().controlSize(.small).frame(width: 14, height: 14)
                    } else {
                        Text("Send test notification")
                    }
                }
                .disabled(isTestingNotification)
                if let notificationTestResult {
                    Text(notificationTestResult)
                        .font(.system(size: 12))
                        .foregroundStyle(notificationTestSucceeded ? .green : .orange)
                }
            }
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reprise \(engine.currentVersion)")
                    .font(.system(size: 15, weight: .semibold))

                // Update checking/downloading/installing itself is entirely Sparkle's own
                // native UI from here (release notes, Skip/Remind Later/Install, download
                // progress, install + relaunch) — the same flow most non-App-Store Mac apps
                // use, replacing a hand-rolled GitHub-releases check + custom progress bar
                // that only ever ran when someone happened to open this tab and click a
                // button (switched 11-10-2026). This view only has to trigger the check and
                // offer the one toggle Sparkle doesn't put in its own dialogs.
                if let updater = AppDelegate.shared?.updaterController.updater {
                    Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                            updater.automaticallyChecksForUpdates = newValue
                        }
                    CheckForUpdatesView(updater: updater)
                    if let lastCheck = updater.lastUpdateCheckDate {
                        Text("Last checked \(lastCheck, style: .relative) ago")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Links")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Link("GitHub repository", destination: URL(string: "https://github.com/reprise-labs/reprise")!)
                    .font(.system(size: 12))
                Link("Release notes", destination: URL(string: "https://github.com/reprise-labs/reprise/releases")!)
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Troubleshooting")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Button {
                    copyLog()
                } label: {
                    Label(logCopied ? "Copied!" : "Copy log to clipboard", systemImage: logCopied ? "checkmark" : "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private func iconLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    /// A text field with an eye button to reveal/hide it. A plain SecureField
    /// hides both what's already saved AND what you're about to paste over
    /// it — you can't check you typed the right thing, or that you didn't
    /// accidentally touch the field you meant to leave alone. Defaults to
    /// hidden (it's a credential), but one click shows it in plain text.
    @ViewBuilder
    private func credentialField(_ title: String, text: Binding<String>, revealed: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Group {
                if revealed.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }
            .textFieldStyle(.roundedBorder)

            Button {
                revealed.wrappedValue.toggle()
            } label: {
                Image(systemName: revealed.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .help(revealed.wrappedValue ? "Hide" : "Show")
            .accessibilityLabel(revealed.wrappedValue ? "Hide \(title)" : "Show \(title)")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            customDownloadPath = url.path
        }
    }

    /// SMAppService.mainApp registers/unregisters Reprise as a Login Item without touching
    /// any plist by hand — the modern macOS 13+ replacement for the old LaunchAgent-file
    /// approach, and it shows up correctly in System Settings → General → Login Items.
    /// Registering can succeed but leave the item in .requiresApproval state (macOS wants
    /// the user to flip it on themselves in System Settings first) — surfaced here instead
    /// of silently doing nothing, since a toggle that looks "on" but isn't would be worse
    /// than not having the feature at all.
    private func setStartAtLogin(_ wantsEnabled: Bool) {
        startAtLoginNote = nil
        do {
            if wantsEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            startAtLoginNote = "Couldn't change this: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        startAtLogin = status == .enabled
        if wantsEnabled && status == .requiresApproval {
            startAtLoginNote = "Needs approval — open System Settings → General → Login Items and enable Reprise."
        }
    }

    private func testNotification() {
        isTestingNotification = true
        notificationTestResult = nil
        engine.sendTestNotification { ok, detail in
            isTestingNotification = false
            notificationTestSucceeded = ok
            notificationTestResult = ok ? "Sent — check your phone." : "Failed: \(detail)"
        }
    }

    private func testCookies() async {
        isTestingCookies = true
        cookieTestResult = nil
        // Apply the picker's current value before testing, not just on Save — otherwise
        // picking Safari and immediately hitting Test still tests against whatever browser
        // was saved before, which looks like the picker did nothing.
        engine.settings.cookieBrowserPreference = cookieBrowserPreference
        let (ok, message) = await engine.testCookies()
        isTestingCookies = false
        cookieTestSucceeded = ok
        cookieTestResult = message
    }


    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(engine.logLines.joined(separator: "\n"), forType: .string)
        logCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            logCopied = false
        }
    }

    private func save() {
        engine.settings.checkLeadMinutes = checkLeadMinutes
        engine.settings.vodWaitMinutes = vodWaitMinutes
        engine.settings.failureCooldownMinutes = failureCooldownMinutes
        engine.settings.customDownloadPath = customDownloadPath.isEmpty ? nil : customDownloadPath
        engine.settings.lowDiskThresholdGB = lowDiskThresholdGB
        engine.settings.showDockIcon = showDockIcon
        engine.settings.minimalMenuBarIcon = minimalMenuBarIcon
        engine.settings.cookieBrowserPreference = cookieBrowserPreference
        engine.settings.defaultQuality = defaultQuality.rawValue
        engine.settings.pushoverToken = pushoverToken.isEmpty ? nil : pushoverToken
        engine.settings.pushoverUserKey = pushoverUserKey.isEmpty ? nil : pushoverUserKey
        StatusItemController.shared?.refreshActivationPolicy()
        StatusItemController.shared?.refreshIcon()

        engine.log("Settings saved: check \(Int(checkLeadMinutes))min ahead, VOD interval \(vodWaitMinutes)min, notification cooldown \(Int(failureCooldownMinutes))min, download folder: \(customDownloadPath.isEmpty ? "default" : customDownloadPath), low disk warning: \(Int(lowDiskThresholdGB))GB")
    }
}
