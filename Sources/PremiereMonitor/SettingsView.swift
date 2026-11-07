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
    @State private var hasYouTubePremium: Bool
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

    /// Settings used to be spread across seven equally weighted mini-tabs. The two
    /// settings people need in the same moment — browser login and Premium quality —
    /// were especially easy to miss because they lived in different places. These
    /// sections mirror the app's main sidebar: a small number of clear destinations,
    /// with the YouTube workflow kept together.
    private enum SettingsSection: CaseIterable, Identifiable {
        case general, youtube, monitoring, channels, notifications, about

        var id: Self { self }

        var title: String {
            switch self {
            case .general: return "General"
            case .youtube: return "YouTube"
            case .monitoring: return "Monitoring"
            case .channels: return "Channels"
            case .notifications: return "Notifications"
            case .about: return "About & support"
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "Startup, appearance and downloads"
            case .youtube: return "Browser login and download quality"
            case .monitoring: return "When Reprise checks and alerts"
            case .channels: return "Discover upcoming premieres"
            case .notifications: return "Optional alerts when you are away"
            case .about: return "Version, updates and diagnostics"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .youtube: return "play.rectangle.fill"
            case .monitoring: return "clock"
            case .channels: return "dot.radiowaves.left.and.right"
            case .notifications: return "bell"
            case .about: return "questionmark.circle"
            }
        }
    }
    @State private var selectedSection: SettingsSection = .general

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
        _hasYouTubePremium = State(initialValue: s.youtubePremiumConfirmed ?? false)
        _pushoverToken = State(initialValue: s.pushoverToken ?? "")
        _pushoverUserKey = State(initialValue: s.pushoverUserKey ?? "")
        _automaticallyChecksForUpdates = State(
            initialValue: AppDelegate.shared?.updaterController.updater.automaticallyChecksForUpdates ?? true
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            VStack(spacing: 0) {
                // YouTube is a short, deliberate setup flow. Giving it a ScrollView
                // created the distracting elastic "empty page" bounce that made it feel
                // like there was more to discover below. The longer operational pages
                // keep scrolling so a smaller settings window can still reach everything.
                if selectedSection == .youtube {
                    settingsPageContent
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        settingsPageContent
                    }
                }

                Divider()
                HStack(spacing: 12) {
                    Text("Changes apply when you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Close") {
                        StatusItemController.shared?.closeSettingsWindow()
                    }
                    Button("Save changes") {
                        save()
                        StatusItemController.shared?.closeSettingsWindow()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var settingsPageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsPageHeader
            selectedContent
        }
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(30)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 14)

            Text("SET UP")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            settingsSidebarButton(.general)
            settingsSidebarButton(.youtube)

            Text("AUTOMATION")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 2)
            settingsSidebarButton(.monitoring)
            settingsSidebarButton(.channels)
            settingsSidebarButton(.notifications)

            Spacer()
            settingsSidebarButton(.about)
        }
        .padding(16)
        .frame(width: 190, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsSidebarButton(_ section: SettingsSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selectedSection == section ? Color.accentColor.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
    }

    private var settingsPageHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: selectedSection.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.title)
                    .font(.title2.weight(.semibold))
                Text(selectedSection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .general: generalTab
        case .youtube: youtubeTab
        case .monitoring: monitoringTab
        case .channels: channelsTab
        case .notifications: notificationsTab
        case .about: aboutTab
        }
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
                    Text(customDownloadPath.isEmpty ? "Default: ~/Downloads/reprise_new" : customDownloadPath)
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

    /// Browser access and the Premium choice are deliberately one page: a successful
    /// browser-login test proves that Reprise can read YouTube, but it does not prove
    /// that this particular account has Premium. Keeping the two steps together makes
    /// that distinction explicit instead of leaving a new install looking broken.
    private var youtubeTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(
                title: "YouTube account",
                subtitle: "Choose the browser where you are signed in to YouTube."
            ) {
                Picker("Browser", selection: $cookieBrowserPreference) {
                    Text("Automatic (Chrome, then Safari)").tag("auto")
                    Text("Chrome").tag("chrome")
                    Text("Safari").tag("safari")
                }
                .pickerStyle(.menu)

                HStack(spacing: 10) {
                    Button {
                        Task { await testCookies() }
                    } label: {
                        if isTestingCookies {
                            ProgressView().controlSize(.small).frame(width: 14, height: 14)
                        } else {
                            Label("Test YouTube login", systemImage: "checkmark.circle")
                        }
                    }
                    .disabled(isTestingCookies)

                    Button("Open YouTube") {
                        engine.openYouTubeLogin()
                    }
                }

                if let cookieTestResult {
                    Label(cookieTestResult, systemImage: cookieTestSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(cookieTestSucceeded ? .green : .orange)
                } else {
                    Text("Test the connection after choosing a browser. This confirms that YouTube accepts the saved login.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard(
                title: "Premium quality",
                subtitle: "This is separate from the login test above."
            ) {
                Toggle(isOn: $hasYouTubePremium) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("I have YouTube Premium")
                            .font(.body.weight(.medium))
                        Text("Adds 1080p Premium to the quality menu when you add a premiere.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: hasYouTubePremium) { _, enabled in
                    if !enabled, defaultQuality == .premium { defaultQuality = .best }
                }

                if hasYouTubePremium {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default for new premieres")
                                .font(.body.weight(.medium))
                            Text("You can still change this for each premiere.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Default quality", selection: $defaultQuality) {
                            Text(VideoQuality.premium.displayName).tag(VideoQuality.premium)
                            ForEach(VideoQuality.allCases.filter { $0 != .premium }) { q in
                                Text(q.displayName).tag(q)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                } else {
                    Label("Turn this on if the browser above is signed in to a YouTube Premium account.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Label("YouTube only provides the Premium track for eligible videos. If it is unavailable when the premiere is downloaded, Reprise uses Best available instead.", systemImage: "checkmark.shield")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pushover credentials")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text("Optional — push notifications when you're away from this Mac. Get your "
                    + "keys at pushover.net. You can test newly pasted keys immediately; saving first is not required.")
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
                Text("reprise_new \(engine.currentVersion)")
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

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
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
        // Match the YouTube test above: test exactly what is currently visible in
        // Settings, rather than only the last saved values. This also makes a first
        // Pushover setup testable without the confusing save → reopen → test detour.
        engine.settings.pushoverToken = pushoverToken.isEmpty ? nil : pushoverToken
        engine.settings.pushoverUserKey = pushoverUserKey.isEmpty ? nil : pushoverUserKey
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
        engine.settings.youtubePremiumConfirmed = hasYouTubePremium
        engine.settings.pushoverToken = pushoverToken.isEmpty ? nil : pushoverToken
        engine.settings.pushoverUserKey = pushoverUserKey.isEmpty ? nil : pushoverUserKey
        StatusItemController.shared?.refreshActivationPolicy()
        StatusItemController.shared?.refreshIcon()

        engine.log("Settings saved: check \(Int(checkLeadMinutes))min ahead, VOD interval \(vodWaitMinutes)min, notification cooldown \(Int(failureCooldownMinutes))min, download folder: \(customDownloadPath.isEmpty ? "default" : customDownloadPath), low disk warning: \(Int(lowDiskThresholdGB))GB")
    }
}
