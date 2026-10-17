import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var engine = MonitorEngine.shared

    /// Which half of the (formerly single, now tabbed) top pane is showing — split out
    /// 01-10-2026 because the old single "Found on watched channels" banner pushed the
    /// tracked list down every time a channel found something, instead of living in its
    /// own clearly-separate place.
    private enum MainSection { case tracked, upcoming }
    @State private var selectedSection: MainSection = .tracked
    @State private var isRefreshingUpcoming = false

    private var sortedVideos: [MonitoredVideo] {
        engine.videos.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    @ViewBuilder
    private func sectionTabButton(_ section: MainSection, title: String, badgeCount: Int?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.title2).bold()
                    .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
                    // Without this, the badge capsule crowding the HStack made "Upcoming"
                    // wrap onto two lines instead of staying on one (found 11-10-2026,
                    // live-testing the discovered-channel Add flow) — fixedSize keeps it at
                    // its natural single-line width regardless of how tight the row gets.
                    .fixedSize()
                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var isBlockedByPermissions: Bool {
        engine.permissionWarnings["download-folder"] != nil || engine.permissionWarnings["cookie-access"] != nil
            || engine.permissionWarnings["external-tools"] != nil
    }

    /// The video list pane used to have a flat .frame(minHeight: 260) regardless of how
    /// many premieres were tracked — with just 1-2, that left a big blank gap below the
    /// last row before the log section started (28-09-2026 feedback). Capping its max
    /// height to roughly what the current rows actually need means VSplitView gives any
    /// leftover window height to the log pane below instead, which can always use more
    /// room. Still grows normally up to the cap once there's enough content to fill it.
    ///
    /// The cap itself was 260 (~3 rows) until 17-10-2026: with several premieres queued
    /// up via channel watching, that meant scrolling inside a cramped ~3-row box even
    /// though the window itself had room to grow — annoying enough on its own, worse
    /// over a remote-desktop connection where trackpad/mouse scroll events don't always
    /// land cleanly in a small inner scroll area (user report + screenshots, several
    /// tracked premieres queued at once). Raised to 440 (~6 rows) so a realistic queue
    /// is visible without scrolling at all; still only grows as large as the content
    /// actually needs for the small-list case the original fix was about.
    ///
    /// Based on the larger of the two tabs' row counts, not just whichever is currently
    /// selected — using only the active tab's count meant switching between Tracked and
    /// Upcoming visibly resized this pane (and shifted the log below it) purely because
    /// the two tabs happened to hold a different number of items, which read as broken
    /// rather than intentional (user feedback, 03-10-2026, screenshots of the two tabs
    /// at different heights with the log line landing in a different spot on each).
    private var videoListMaxHeight: CGFloat {
        let header: CGFloat = 56
        let approxRowHeight: CGFloat = 72
        let rowCount = max(sortedVideos.count, engine.discoveredVideos.count)
        let content = header + CGFloat(max(rowCount, 1)) * approxRowHeight
        return min(max(content, 160), 440)
    }

    var body: some View {
        if isBlockedByPermissions {
            PermissionGateView()
                .frame(minWidth: 620, minHeight: 480)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    sectionTabButton(.tracked, title: "Tracked", badgeCount: nil)
                    sectionTabButton(.upcoming, title: "Upcoming", badgeCount: engine.discoveredVideos.count)
                    Spacer()

                    if selectedSection == .upcoming {
                        // .refreshable (pull-to-refresh) used to live on the Upcoming list
                        // for exactly this — checking now instead of waiting up to a day —
                        // but in a popover this short, macOS's refresh spinner had nowhere
                        // proper to draw itself and rendered as a small clipped glitch, with
                        // a stray scrollbar appearing even on the empty, nothing-to-scroll
                        // state (user screenshot, 04-10-2026). A plain button sidesteps both.
                        Button {
                            guard !isRefreshingUpcoming else { return }
                            isRefreshingUpcoming = true
                            Task {
                                await engine.checkChannels(force: true)
                                isRefreshingUpcoming = false
                            }
                        } label: {
                            if isRefreshingUpcoming {
                                ProgressView().controlSize(.small).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshingUpcoming)
                        .contentShape(Rectangle())
                        .help("Check watched channels now")
                        .accessibilityLabel("Check watched channels now")
                    }

                    Button {
                        engine.openDownloadFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .contentShape(Rectangle())
                    .help("Open download folder")
                    .accessibilityLabel("Open download folder")

                    Button {
                        confirmClearHistory()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!engine.videos.contains { $0.status == .done })
                    .contentShape(Rectangle())
                    .help("Clear completed premieres from the list (downloaded files stay put)")
                    .accessibilityLabel("Clear completed premieres")

                    Button {
                        StatusItemController.shared?.showSettingsWindow()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .contentShape(Rectangle())
                    .help("Settings")
                    .accessibilityLabel("Settings")

                    Button {
                        StatusItemController.shared?.showAddWindow()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .contentShape(Rectangle())

                    Button {
                        confirmQuit()
                    } label: {
                        Image(systemName: "power")
                    }
                    .contentShape(Rectangle())
                    .help("Quit Reprise")
                    .accessibilityLabel("Quit Reprise")
                }
                .padding([.horizontal, .top])

                if !engine.permissionWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(engine.permissionWarnings.keys.sorted()), id: \.self) { key in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(engine.permissionWarnings[key] ?? "")
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                if selectedSection == .tracked {
                    if sortedVideos.isEmpty {
                        ContentUnavailableView(
                            "No premieres yet",
                            systemImage: "video.badge.plus",
                            description: Text("Click Add to track a YouTube premiere.")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(sortedVideos) { video in
                                    VideoRow(video: video, onDelete: { confirmDelete(video) })
                                    Divider()
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        }
                    }
                } else {
                    if engine.discoveredVideos.isEmpty {
                        ContentUnavailableView(
                            "No new premieres found",
                            systemImage: "antenna.radiowaves.left.and.right",
                            // Used to also say "— use the refresh button above to check now."
                            // here, but that extra clause wrapped to a line more than this
                            // pane has room for — invisible with auto-hiding scrollbars, but
                            // ContentUnavailableView apparently scrolls internally when its
                            // content doesn't fit, so with "Always show scroll bars" (common
                            // with an external mouse, e.g. a MacBook docked at a desk) that
                            // extra line showed up as a persistent scrollbar on a view with
                            // nothing meaningful to scroll (user report + screenshot,
                            // 04-10-2026). The refresh button has its own tooltip; it doesn't
                            // need explaining here too.
                            description: Text("Reprise checks your watched channels once a day.")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(engine.discoveredVideos) { discovered in
                                    HStack(alignment: .center, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(discovered.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .lineLimit(1)
                                            Text(discovered.channelName)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        // Same bordered-button family as Cancel/Add in the Add
                                        // dialog — a plain-text "Dismiss" next to a solid "Add"
                                        // read as mismatched weight and, top-aligned against a
                                        // two-line title block, looked like it was floating
                                        // above the row instead of belonging to it (user
                                        // feedback, 16-10-2026).
                                        Button("Dismiss") {
                                            engine.dismissDiscovered(discovered)
                                        }
                                        .controlSize(.small)
                                        Button("Add") {
                                            StatusItemController.shared?.showAddWindow(discovered: discovered)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                    .padding(.vertical, 8)
                                    Divider()
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedSection)
            .animation(.easeInOut(duration: 0.2), value: engine.permissionWarnings.isEmpty)
            // idealHeight AND layoutPriority, not just min/maxHeight: VSplitView turned out
            // to favor the *log* pane below for any extra window height — even with this
            // pane's own maxHeight raised and an idealHeight added, confirmed 17-10-2026 by
            // measuring the actual rendered panes (list stayed ~238px, log grew to ~261px,
            // despite the list's new 440 cap) — the log pane has no maxHeight of its own, and
            // VSplitView apparently treats that as implicit priority. layoutPriority(1) here
            // (log pane stays at the SwiftUI default, 0) makes this pane's own min/ideal/max
            // win that tug-of-war instead.
            .frame(minHeight: 160, idealHeight: videoListMaxHeight, maxHeight: videoListMaxHeight)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 0) {
                Text("Log")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 6)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(engine.logLines.enumerated()), id: \.offset) { idx, line in
                                // ⚠️/❌ zijn al de bestaande markering voor "dit is geen
                                // routineregel" door de hele log heen (schrijftest, cookies,
                                // verouderde yt-dlp, noodformaat, enz.) — vet + kleur maakt
                                // ze ook visueel meteen te onderscheiden van de vele gewone
                                // Check/download-regels eromheen, i.p.v. ze te moeten lezen
                                // om te zien dat het geen routine was (gebruikersfeedback,
                                // 11-10-2026, specifiek over de noodformaat-regel).
                                let isWaarschuwing = line.contains("⚠️") || line.contains("❌")
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .fontWeight(isWaarschuwing ? .bold : .regular)
                                    .foregroundStyle(isWaarschuwing ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                                    .id(idx)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: engine.logLines.count) { _, _ in
                        if let last = engine.logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 120)
            .background(Color(nsColor: .textBackgroundColor))
        }
        // minHeight raised from 480 alongside videoListMaxHeight's bump to 440 (see that
        // property's comment) — without this the window's own floor would still squeeze
        // the list pane back down below its new cap whenever it opens at minimum size.
        .frame(minWidth: 620, minHeight: 560)
    }

    private func confirmDelete(_ video: MonitoredVideo) {
        let alert = NSAlert()
        alert.messageText = "Delete premiere?"
        alert.informativeText = "\"\(video.label)\" will no longer be tracked."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            engine.removeVideo(video)
        }
    }

    private func confirmClearHistory() {
        let doneCount = engine.videos.filter { $0.status == .done }.count
        guard doneCount > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Clear completed premieres?"
        alert.informativeText = "Removes \(doneCount) finished premiere\(doneCount == 1 ? "" : "s") from the list. "
            + "Downloaded files themselves are not touched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            engine.clearCompleted()
        }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Reprise?"
        alert.informativeText = "Automatic checking and downloading will stop until you open the app again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            StatusItemController.shared?.quit()
        }
    }
}

struct VideoRow: View {
    let video: MonitoredVideo
    let onDelete: () -> Void
    @ObservedObject private var engine = MonitorEngine.shared

    private var isBusy: Bool {
        video.status == .downloadingLive || video.status == .downloadingVod
    }

    // Flat gray the whole "waiting" stretch (which can be days) made it hard to tell
    // whether anything was actually close to happening — user feedback, 03-10-2026.
    // Active checking only starts checkLeadMinutes before the scheduled time (15 min
    // by default), but this just nudges the row's color in the last hour so it reads
    // as "getting close" well before that. Orange, matching "Waiting for VOD" — tried
    // teal first to keep the two visually distinct (different kind of "waiting"), but
    // user feedback the same day preferred one shared color for every "something's
    // about to happen" state instead.
    private var isSoon: Bool {
        guard video.status == .waiting else { return false }
        let secondsUntil = video.scheduledDate.timeIntervalSinceNow
        return secondsUntil > 0 && secondsUntil <= 3600
    }

    private var fileSizeText: String? {
        guard video.status == .done, let path = video.finalFilePath,
              let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var body: some View {
        HStack {
            AsyncImage(url: video.thumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.2), value: video.status)

            VStack(alignment: .leading, spacing: 2) {
                // Without a line limit, a title just a bit longer than the others eats into
                // the Spacer below and nudges the icon buttons out of column with every other
                // row — truncating keeps every row's trailing icons at the exact same x.
                Text(video.label)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(video.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Only shown for the non-default choice — the common case (Best) needs
                // no extra label, same reasoning as the vega/side-dish badges elsewhere.
                if let quality = video.quality, quality != .best {
                    Text(quality.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                // Same proof shown in the push notification/log, now visible without
                // digging into either — only shown once the VOD is actually done, and
                // only when there was something real to compare against (nil means no
                // ceiling was known for this video, not a silent "assume it's fine").
                if video.status == .done, let confirmed = video.qualityConfirmed {
                    HStack(spacing: 3) {
                        Image(systemName: confirmed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        Text(confirmed ? "Confirmed best available" : "Lower than available")
                    }
                    .font(.caption2)
                    .foregroundStyle(confirmed ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.orange))
                }
                if video.status == .waiting {
                    // SwiftUI's built-in relative style ticks down on its own — no timer needed.
                    Text("in \(video.scheduledDate, style: .relative)")
                        .font(.caption2)
                        .fontWeight(isSoon ? .semibold : .regular)
                        .foregroundStyle(isSoon ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                }
                if let lastChecked = video.lastChecked {
                    Text("Last checked \(lastChecked, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if isBusy, let progress = engine.downloadProgress[video.id] {
                    Text(progress)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
                if let fileSizeText {
                    Text(fileSizeText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                MonitorEngine.shared.checkNow(video)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .contentShape(Rectangle())
            .help("Check now")
            .accessibilityLabel("Check now")

            Button {
                MonitorEngine.shared.runPreflightCheckNow(video)
            } label: {
                Image(systemName: "checkmark.shield")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Run pre-flight check now (yt-dlp, access, disk space, link)")
            .accessibilityLabel("Run pre-flight check")

            Button {
                StatusItemController.shared?.showAddWindow(editing: video)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .contentShape(Rectangle())
            .help("Edit")
            .accessibilityLabel("Edit")

            Button {
                MonitorEngine.shared.revealFile(video)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(isBusy)
            .contentShape(Rectangle())
            .help(isBusy ? "Can't delete while downloading" : "Delete")
            .accessibilityLabel("Delete")

            HStack(spacing: 4) {
                if video.status == .done {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isSoon ? "Soon" : video.status.displayName)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 66)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: video.status)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if isSoon { return .orange }
        switch video.status {
        case .waiting: return .gray
        case .downloadingLive: return .red
        case .vodPending: return .orange
        case .downloadingVod: return .blue
        case .done: return .green
        }
    }
}
